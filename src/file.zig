const std = @import("std");
const config_mod = @import("config.zig");

/// Supported config file types.
pub const ConfigType = enum {
    yaml,
    toml,
};

/// Parse simple YAML content into an EntryMap.
///
/// Supports the simple key-value subset used by config files:
///   key: value
///   nested:
///     child_key: child_value
///   deeply:
///     nested:
///       key: value
///
/// Rules:
/// - Each line is either a "key: value" pair or a "key:" section header.
/// - 2-space indentation defines nesting level.
/// - Nested keys are stored with dot notation: "database.host" = "localhost".
/// - Leading/trailing whitespace on values is trimmed.
/// - Empty lines and comment lines (starting with #) are skipped.
/// - Inline comments are NOT supported (to keep parser simple).
pub fn parseSimpleYaml(content: []const u8, map: *config_mod.EntryMap) void {
    // Stack of parent key prefixes at each indent level.
    // Index = indent level (0 = root, 1 = 2-space indent, 2 = 4-space, etc.)
    const MAX_DEPTH = 16;
    var prefix_stack: [MAX_DEPTH][config_mod.MAX_KEY_LEN]u8 = undefined;
    var prefix_stack_lens: [MAX_DEPTH]usize = [_]usize{0} ** MAX_DEPTH;

    var line_start: usize = 0;
    while (line_start < content.len) {
        // Find end of line.
        var line_end = line_start;
        while (line_end < content.len and content[line_end] != '\n') {
            line_end += 1;
        }

        const line = content[line_start..line_end];
        line_start = line_end + 1;

        // Skip empty lines and comments.
        const trimmed = trimLeft(line);
        if (trimmed.len == 0) continue;
        if (trimmed[0] == '#') continue;

        // Count leading spaces to determine indent level.
        const indent_spaces = line.len - trimmed.len;
        const indent_level = indent_spaces / 2;

        // Find the colon separator.
        const colon_pos = std.mem.indexOf(u8, trimmed, ":") orelse continue;
        const key_part = trim(trimmed[0..colon_pos]);
        if (key_part.len == 0) continue;

        // Check what follows the colon.
        const after_colon = if (colon_pos + 1 < trimmed.len) trim(trimmed[colon_pos + 1 ..]) else "";

        if (after_colon.len == 0) {
            // Section header (no value) — push onto prefix stack.
            if (indent_level < MAX_DEPTH) {
                const full_key = buildFullKey(&prefix_stack, &prefix_stack_lens, indent_level, key_part);
                if (full_key.len > 0 and full_key.len <= config_mod.MAX_KEY_LEN) {
                    @memcpy(prefix_stack[indent_level][0..full_key.len], full_key);
                    prefix_stack_lens[indent_level] = full_key.len;
                    // Clear deeper levels.
                    var d = indent_level + 1;
                    while (d < MAX_DEPTH) : (d += 1) {
                        prefix_stack_lens[d] = 0;
                    }
                }
            }
        } else {
            // Key-value pair — build the full dotted key and store.
            const full_key = buildFullKey(&prefix_stack, &prefix_stack_lens, indent_level, key_part);
            if (full_key.len > 0) {
                map.set(full_key, after_colon) catch {};
            }
        }
    }
}

/// Build a full dotted key from the prefix stack and the current key part.
/// Returns a slice into a static buffer (valid until next call).
var full_key_buf: [config_mod.MAX_KEY_LEN]u8 = undefined;

fn buildFullKey(
    prefix_stack: *[16][config_mod.MAX_KEY_LEN]u8,
    prefix_stack_lens: *[16]usize,
    indent_level: usize,
    key_part: []const u8,
) []const u8 {
    var pos: usize = 0;

    // Find the nearest ancestor prefix (the one at indent_level - 1, or deeper if available).
    if (indent_level > 0) {
        // Walk from the closest parent down.
        var level: usize = indent_level - 1;
        // We need the immediate parent, which should be the prefix at (indent_level - 1).
        // But the parent might actually be at a higher level if levels were skipped.
        // Find the highest non-empty prefix at or below (indent_level - 1).
        var found_level: ?usize = null;
        while (true) {
            if (prefix_stack_lens[level] > 0) {
                found_level = level;
                break;
            }
            if (level == 0) break;
            level -= 1;
        }

        if (found_level) |fl| {
            const prefix = prefix_stack[fl][0..prefix_stack_lens[fl]];
            if (pos + prefix.len >= config_mod.MAX_KEY_LEN) return "";
            @memcpy(full_key_buf[pos .. pos + prefix.len], prefix);
            pos += prefix.len;
            if (pos >= config_mod.MAX_KEY_LEN) return "";
            full_key_buf[pos] = '.';
            pos += 1;
        }
    }

    if (pos + key_part.len > config_mod.MAX_KEY_LEN) return "";
    @memcpy(full_key_buf[pos .. pos + key_part.len], key_part);
    pos += key_part.len;

    return full_key_buf[0..pos];
}

/// Trim leading whitespace from a slice.
fn trimLeft(s: []const u8) []const u8 {
    var i: usize = 0;
    while (i < s.len and (s[i] == ' ' or s[i] == '\t')) {
        i += 1;
    }
    return s[i..];
}

/// Trim leading and trailing whitespace from a slice.
fn trim(s: []const u8) []const u8 {
    var start: usize = 0;
    while (start < s.len and (s[start] == ' ' or s[start] == '\t')) {
        start += 1;
    }
    var end: usize = s.len;
    while (end > start and (s[end - 1] == ' ' or s[end - 1] == '\t')) {
        end -= 1;
    }
    return s[start..end];
}

/// Parse simple TOML content into an EntryMap.
///
/// Supports the subset used by config files:
///   key = "string_value"
///   key = 123
///   key = true
///   [section]
///   [section.subsection]
///   # comments
///
/// Rules:
/// - Each line is a key = value pair or a [section] header.
/// - Section headers create dot-notation prefixes: [inference] + model → inference.model.
/// - Dotted section headers work: [inference.providers.anthropic] → deeper nesting.
/// - String values in double quotes have quotes stripped.
/// - Bare values (integers, booleans) are stored as-is.
/// - Inline comments after bare values are stripped.
/// - Empty lines and comment lines (starting with #) are skipped.
pub fn parseSimpleToml(content: []const u8, map: *config_mod.EntryMap) void {
    var current_section: [config_mod.MAX_KEY_LEN]u8 = undefined;
    var current_section_len: usize = 0;

    var line_start: usize = 0;
    while (line_start < content.len) {
        var line_end = line_start;
        while (line_end < content.len and content[line_end] != '\n') {
            line_end += 1;
        }

        const line = content[line_start..line_end];
        line_start = line_end + 1;

        const trimmed = trim(line);
        if (trimmed.len == 0) continue;
        if (trimmed[0] == '#') continue;

        // Section header: [section] or [section.subsection]
        if (trimmed[0] == '[' and trimmed.len > 2 and trimmed[trimmed.len - 1] == ']') {
            const section = trim(trimmed[1 .. trimmed.len - 1]);
            if (section.len > 0 and section.len <= config_mod.MAX_KEY_LEN) {
                @memcpy(current_section[0..section.len], section);
                current_section_len = section.len;
            }
            continue;
        }

        // Key = value pair
        const eq_pos = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
        const key_part = trim(trimmed[0..eq_pos]);
        if (key_part.len == 0) continue;

        var value_part: []const u8 = if (eq_pos + 1 < trimmed.len) trim(trimmed[eq_pos + 1 ..]) else "";

        // Handle quoted strings vs bare values
        if (value_part.len >= 2 and value_part[0] == '"') {
            // Find closing quote
            if (std.mem.indexOfScalar(u8, value_part[1..], '"')) |close_pos| {
                value_part = value_part[1 .. 1 + close_pos];
            }
        } else {
            // Bare value — strip inline comments
            if (std.mem.indexOfScalar(u8, value_part, '#')) |hash_pos| {
                value_part = trim(value_part[0..hash_pos]);
            }
        }

        // Build full key: section.key or just key
        var key_buf: [config_mod.MAX_KEY_LEN]u8 = undefined;
        var key_len: usize = 0;

        if (current_section_len > 0) {
            if (current_section_len + 1 + key_part.len > config_mod.MAX_KEY_LEN) continue;
            @memcpy(key_buf[0..current_section_len], current_section[0..current_section_len]);
            key_len = current_section_len;
            key_buf[key_len] = '.';
            key_len += 1;
        }

        if (key_len + key_part.len > config_mod.MAX_KEY_LEN) continue;
        @memcpy(key_buf[key_len .. key_len + key_part.len], key_part);
        key_len += key_part.len;

        map.set(key_buf[0..key_len], value_part) catch {};
    }
}

// =============================================================================
// Tests
// =============================================================================

const testing = std.testing;

test "parseSimpleToml: simple key-value" {
    var m = config_mod.EntryMap{};
    parseSimpleToml(
        \\name = "myapp"
        \\port = 8080
        \\debug = true
    , &m);
    try testing.expectEqualStrings("myapp", m.get("name").?);
    try testing.expectEqualStrings("8080", m.get("port").?);
    try testing.expectEqualStrings("true", m.get("debug").?);
}

test "parseSimpleToml: sections" {
    var m = config_mod.EntryMap{};
    parseSimpleToml(
        \\[inference]
        \\provider = "anthropic"
        \\model = "claude-sonnet-4-6"
        \\
        \\[output]
        \\format = "human"
    , &m);
    try testing.expectEqualStrings("anthropic", m.get("inference.provider").?);
    try testing.expectEqualStrings("claude-sonnet-4-6", m.get("inference.model").?);
    try testing.expectEqualStrings("human", m.get("output.format").?);
}

test "parseSimpleToml: nested sections" {
    var m = config_mod.EntryMap{};
    parseSimpleToml(
        \\[inference.providers.anthropic]
        \\api_key_env = "ANTHROPIC_API_KEY"
        \\model = "claude-sonnet-4-6"
    , &m);
    try testing.expectEqualStrings("ANTHROPIC_API_KEY", m.get("inference.providers.anthropic.api_key_env").?);
    try testing.expectEqualStrings("claude-sonnet-4-6", m.get("inference.providers.anthropic.model").?);
}

test "parseSimpleToml: comments and blank lines" {
    var m = config_mod.EntryMap{};
    parseSimpleToml(
        \\# This is a comment
        \\name = "myapp"
        \\
        \\# Another comment
        \\port = 8080
    , &m);
    try testing.expectEqualStrings("myapp", m.get("name").?);
    try testing.expectEqualStrings("8080", m.get("port").?);
}

test "parseSimpleToml: inline comments on bare values" {
    var m = config_mod.EntryMap{};
    parseSimpleToml(
        \\max_size = 1024 # megabytes
        \\enabled = true # toggle
    , &m);
    try testing.expectEqualStrings("1024", m.get("max_size").?);
    try testing.expectEqualStrings("true", m.get("enabled").?);
}

test "parseSimpleToml: mixed top-level and sections" {
    var m = config_mod.EntryMap{};
    parseSimpleToml(
        \\version = "0.1.0"
        \\
        \\[inference]
        \\provider = "anthropic"
        \\
        \\[cache]
        \\max_size_mb = 1024
    , &m);
    try testing.expectEqualStrings("0.1.0", m.get("version").?);
    try testing.expectEqualStrings("anthropic", m.get("inference.provider").?);
    try testing.expectEqualStrings("1024", m.get("cache.max_size_mb").?);
}

test "parseSimpleToml: empty quoted string" {
    var m = config_mod.EntryMap{};
    parseSimpleToml(
        \\name = ""
    , &m);
    try testing.expectEqualStrings("", m.get("name").?);
}

test "parseSimpleYaml: simple key-value" {
    var m = config_mod.EntryMap{};
    parseSimpleYaml("host: localhost\nport: 5432\n", &m);
    try testing.expectEqualStrings("localhost", m.get("host").?);
    try testing.expectEqualStrings("5432", m.get("port").?);
}

test "parseSimpleYaml: nested keys" {
    var m = config_mod.EntryMap{};
    parseSimpleYaml(
        \\database:
        \\  host: localhost
        \\  port: 5432
        \\server:
        \\  timeout: 30
    , &m);
    try testing.expectEqualStrings("localhost", m.get("database.host").?);
    try testing.expectEqualStrings("5432", m.get("database.port").?);
    try testing.expectEqualStrings("30", m.get("server.timeout").?);
}

test "parseSimpleYaml: deeply nested" {
    var m = config_mod.EntryMap{};
    parseSimpleYaml(
        \\app:
        \\  database:
        \\    primary:
        \\      host: db1.example.com
        \\      port: 5432
    , &m);
    try testing.expectEqualStrings("db1.example.com", m.get("app.database.primary.host").?);
    try testing.expectEqualStrings("5432", m.get("app.database.primary.port").?);
}

test "parseSimpleYaml: comments and blank lines" {
    var m = config_mod.EntryMap{};
    parseSimpleYaml(
        \\# This is a comment
        \\host: localhost
        \\
        \\# Another comment
        \\port: 8080
    , &m);
    try testing.expectEqualStrings("localhost", m.get("host").?);
    try testing.expectEqualStrings("8080", m.get("port").?);
}

test "parseSimpleYaml: mixed flat and nested" {
    var m = config_mod.EntryMap{};
    parseSimpleYaml(
        \\name: myapp
        \\database:
        \\  host: localhost
        \\debug: true
    , &m);
    try testing.expectEqualStrings("myapp", m.get("name").?);
    try testing.expectEqualStrings("localhost", m.get("database.host").?);
    try testing.expectEqualStrings("true", m.get("debug").?);
}
