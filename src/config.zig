const std = @import("std");
const env_mod = @import("env.zig");
const file_mod = @import("file.zig");

/// Maximum entries per storage layer (defaults, overrides, config, env bindings).
pub const MAX_ENTRIES = 256;
/// Maximum length for a key.
pub const MAX_KEY_LEN = 128;
/// Maximum length for a value.
pub const MAX_VALUE_LEN = 512;

/// A key-value entry stored in a fixed-size buffer.
pub const Entry = struct {
    key: [MAX_KEY_LEN]u8 = [_]u8{0} ** MAX_KEY_LEN,
    key_len: usize = 0,
    value: [MAX_VALUE_LEN]u8 = [_]u8{0} ** MAX_VALUE_LEN,
    value_len: usize = 0,

    pub fn keySlice(self: *const Entry) []const u8 {
        return self.key[0..self.key_len];
    }

    pub fn valueSlice(self: *const Entry) []const u8 {
        return self.value[0..self.value_len];
    }
};

/// A fixed-capacity map of string key-value pairs.
pub const EntryMap = struct {
    entries: [MAX_ENTRIES]Entry = [_]Entry{.{}} ** MAX_ENTRIES,
    len: usize = 0,

    /// Set a key-value pair. If the key already exists, update the value.
    /// Returns error if key or value is too long, or if the map is full.
    pub fn set(self: *EntryMap, key: []const u8, value: []const u8) error{ KeyTooLong, ValueTooLong, MapFull }!void {
        if (key.len > MAX_KEY_LEN) return error.KeyTooLong;
        if (value.len > MAX_VALUE_LEN) return error.ValueTooLong;

        // Check if key already exists — update in place.
        for (self.entries[0..self.len]) |*entry| {
            if (entry.key_len == key.len and std.mem.eql(u8, entry.key[0..entry.key_len], key)) {
                @memcpy(entry.value[0..value.len], value);
                entry.value_len = value.len;
                return;
            }
        }

        // New entry.
        if (self.len >= MAX_ENTRIES) return error.MapFull;
        var entry = &self.entries[self.len];
        @memcpy(entry.key[0..key.len], key);
        entry.key_len = key.len;
        @memcpy(entry.value[0..value.len], value);
        entry.value_len = value.len;
        self.len += 1;
    }

    /// Get a value by key. Returns null if not found.
    pub fn get(self: *const EntryMap, key: []const u8) ?[]const u8 {
        for (self.entries[0..self.len]) |*entry| {
            if (entry.key_len == key.len and std.mem.eql(u8, entry.key[0..entry.key_len], key)) {
                return entry.value[0..entry.value_len];
            }
        }
        return null;
    }

    /// Check if a key exists.
    pub fn contains(self: *const EntryMap, key: []const u8) bool {
        return self.get(key) != null;
    }
};

/// Environment variable binding entry.
pub const EnvBinding = struct {
    key: [MAX_KEY_LEN]u8 = [_]u8{0} ** MAX_KEY_LEN,
    key_len: usize = 0,
    env_var: [MAX_KEY_LEN]u8 = [_]u8{0} ** MAX_KEY_LEN,
    env_var_len: usize = 0,

    pub fn keySlice(self: *const EnvBinding) []const u8 {
        return self.key[0..self.key_len];
    }

    pub fn envVarSlice(self: *const EnvBinding) []const u8 {
        return self.env_var[0..self.env_var_len];
    }
};

/// Serum Config — a prioritized configuration registry.
///
/// Precedence (highest to lowest):
/// 1. overrides (set via `set`)
/// 2. flags (reserved for CLI flag binding)
/// 3. env vars (bound explicitly or via automaticEnv)
/// 4. config file (loaded via readConfig)
/// 5. defaults (set via `setDefault`)
pub const Config = struct {
    // Storage layers
    defaults: EntryMap = .{},
    config_file: EntryMap = .{},
    overrides: EntryMap = .{},
    flags: EntryMap = .{},

    // Environment bindings
    env_bindings: [MAX_ENTRIES]EnvBinding = [_]EnvBinding{.{}} ** MAX_ENTRIES,
    env_bindings_len: usize = 0,

    env_prefix: [MAX_KEY_LEN]u8 = [_]u8{0} ** MAX_KEY_LEN,
    env_prefix_len: usize = 0,

    automatic_env: bool = false,

    // Config file settings
    config_name: [MAX_KEY_LEN]u8 = [_]u8{0} ** MAX_KEY_LEN,
    config_name_len: usize = 0,

    config_type: file_mod.ConfigType = .yaml,

    config_paths: [16][MAX_VALUE_LEN]u8 = [_][MAX_VALUE_LEN]u8{[_]u8{0} ** MAX_VALUE_LEN} ** 16,
    config_paths_len: [16]usize = [_]usize{0} ** 16,
    config_paths_count: usize = 0,

    /// Key delimiter for nested access.
    key_delim: u8 = '.',

    /// Create a new Config with defaults.
    pub fn init() Config {
        return .{};
    }

    // =========================================================================
    // Setters
    // =========================================================================

    /// Set a default value for a key (lowest precedence).
    pub fn setDefault(self: *Config, key: []const u8, value: []const u8) void {
        self.defaults.set(key, value) catch {};
    }

    /// Set an override value for a key (highest precedence).
    pub fn set(self: *Config, key: []const u8, value: []const u8) void {
        self.overrides.set(key, value) catch {};
    }

    /// Set a flag value for a key (second highest precedence, after overrides).
    pub fn setFlag(self: *Config, key: []const u8, value: []const u8) void {
        self.flags.set(key, value) catch {};
    }

    // =========================================================================
    // Getters — respecting precedence
    // =========================================================================

    /// Get a value by key, respecting the full precedence chain.
    /// Returns null if the key is not found at any level.
    pub fn get(self: *const Config, key: []const u8) ?[]const u8 {
        // 1. Overrides (highest)
        if (self.overrides.get(key)) |v| return v;

        // 2. Flags
        if (self.flags.get(key)) |v| return v;

        // 3. Env vars
        if (self.getEnvValue(key)) |v| return v;

        // 4. Config file
        if (self.config_file.get(key)) |v| return v;

        // 5. Defaults (lowest)
        if (self.defaults.get(key)) |v| return v;

        return null;
    }

    /// Get a string value, returning empty string if not found.
    pub fn getString(self: *const Config, key: []const u8) []const u8 {
        return self.get(key) orelse "";
    }

    /// Get a value parsed as an integer. Returns null if not found or not parseable.
    pub fn getInt(self: *const Config, key: []const u8) ?i64 {
        const raw = self.get(key) orelse return null;
        return std.fmt.parseInt(i64, raw, 10) catch null;
    }

    /// Get a value parsed as a boolean. Returns null if not found or not parseable.
    /// Recognizes: "true"/"1"/"yes" -> true, "false"/"0"/"no" -> false.
    pub fn getBool(self: *const Config, key: []const u8) ?bool {
        const raw = self.get(key) orelse return null;
        if (std.mem.eql(u8, raw, "true") or std.mem.eql(u8, raw, "1") or std.mem.eql(u8, raw, "yes")) {
            return true;
        }
        if (std.mem.eql(u8, raw, "false") or std.mem.eql(u8, raw, "0") or std.mem.eql(u8, raw, "no")) {
            return false;
        }
        return null;
    }

    /// Check if a key is set at any precedence level (including env).
    pub fn isSet(self: *const Config, key: []const u8) bool {
        return self.get(key) != null;
    }

    // =========================================================================
    // Environment variable support
    // =========================================================================

    /// Bind a config key to a specific environment variable name.
    pub fn bindEnv(self: *Config, key: []const u8, env_var: []const u8) void {
        if (self.env_bindings_len >= MAX_ENTRIES) return;
        if (key.len > MAX_KEY_LEN or env_var.len > MAX_KEY_LEN) return;

        var binding = &self.env_bindings[self.env_bindings_len];
        @memcpy(binding.key[0..key.len], key);
        binding.key_len = key.len;
        @memcpy(binding.env_var[0..env_var.len], env_var);
        binding.env_var_len = env_var.len;
        self.env_bindings_len += 1;
    }

    /// Set a prefix for automatic env var lookup.
    /// E.g., prefix "GEMWORKS" makes key "port" look up "GEMWORKS_PORT".
    pub fn setEnvPrefix(self: *Config, prefix: []const u8) void {
        if (prefix.len > MAX_KEY_LEN) return;
        @memcpy(self.env_prefix[0..prefix.len], prefix);
        self.env_prefix_len = prefix.len;
    }

    /// Enable automatic environment variable lookup for all keys.
    /// Key "database.host" looks up "DATABASE_HOST" (dots become underscores, uppercased).
    /// If a prefix is set, it's prepended: "GEMWORKS_DATABASE_HOST".
    pub fn automaticEnv(self: *Config) void {
        self.automatic_env = true;
    }

    /// Internal: resolve a config key to its environment variable value.
    /// Checks explicit bindings first, then automatic env if enabled.
    fn getEnvValue(self: *const Config, key: []const u8) ?[]const u8 {
        // Check explicit bindings first.
        for (self.env_bindings[0..self.env_bindings_len]) |*binding| {
            if (binding.key_len == key.len and std.mem.eql(u8, binding.key[0..binding.key_len], key)) {
                const env_name = binding.env_var[0..binding.env_var_len];
                return env_mod.getEnv(env_name);
            }
        }

        // If automatic env is enabled, derive the env var name from the key.
        if (self.automatic_env) {
            var env_name_buf: [MAX_KEY_LEN + MAX_KEY_LEN + 1]u8 = undefined;
            const env_name_len = self.buildEnvVarName(key, &env_name_buf);
            if (env_name_len > 0) {
                return env_mod.getEnv(env_name_buf[0..env_name_len]);
            }
        }

        return null;
    }

    /// Build the environment variable name for a given key.
    /// Dots become underscores, lowercased letters become uppercased.
    /// If prefix is set, prepend "PREFIX_".
    fn buildEnvVarName(self: *const Config, key: []const u8, buf: *[MAX_KEY_LEN + MAX_KEY_LEN + 1]u8) usize {
        var pos: usize = 0;

        // Add prefix if set.
        if (self.env_prefix_len > 0) {
            const prefix = self.env_prefix[0..self.env_prefix_len];
            for (prefix) |c| {
                if (pos >= buf.len) return 0;
                buf[pos] = std.ascii.toUpper(c);
                pos += 1;
            }
            if (pos >= buf.len) return 0;
            buf[pos] = '_';
            pos += 1;
        }

        // Add key, replacing dots with underscores, uppercasing.
        for (key) |c| {
            if (pos >= buf.len) return 0;
            if (c == '.') {
                buf[pos] = '_';
            } else {
                buf[pos] = std.ascii.toUpper(c);
            }
            pos += 1;
        }

        return pos;
    }

    // =========================================================================
    // Config file support
    // =========================================================================

    /// Set the name of the config file (without extension).
    pub fn setConfigName(self: *Config, name: []const u8) void {
        if (name.len > MAX_KEY_LEN) return;
        @memcpy(self.config_name[0..name.len], name);
        self.config_name_len = name.len;
    }

    /// Set the config file type.
    pub fn setConfigType(self: *Config, config_type: file_mod.ConfigType) void {
        self.config_type = config_type;
    }

    /// Add a path to search for config files.
    pub fn addConfigPath(self: *Config, path: []const u8) void {
        if (self.config_paths_count >= 16) return;
        if (path.len > MAX_VALUE_LEN) return;
        @memcpy(self.config_paths[self.config_paths_count][0..path.len], path);
        self.config_paths_len[self.config_paths_count] = path.len;
        self.config_paths_count += 1;
    }

    /// Read configuration from a string (useful for testing without filesystem).
    /// Parses the content based on the configured type and merges into the config layer.
    pub fn readConfig(self: *Config, content: []const u8) void {
        switch (self.config_type) {
            .yaml => file_mod.parseSimpleYaml(content, &self.config_file),
            .toml => file_mod.parseSimpleToml(content, &self.config_file),
        }
    }
};

// =============================================================================
// Tests
// =============================================================================

const testing = std.testing;

test "Config.init creates empty config" {
    const c = Config.init();
    try testing.expect(c.get("anything") == null);
}

test "setDefault and get" {
    var c = Config.init();
    c.setDefault("host", "localhost");
    try testing.expectEqualStrings("localhost", c.get("host").?);
}

test "set overrides default" {
    var c = Config.init();
    c.setDefault("host", "localhost");
    c.set("host", "production.example.com");
    try testing.expectEqualStrings("production.example.com", c.get("host").?);
}

test "getString returns empty for missing key" {
    const c = Config.init();
    try testing.expectEqualStrings("", c.getString("missing"));
}

test "getInt parses integers" {
    var c = Config.init();
    c.setDefault("port", "5432");
    try testing.expectEqual(@as(i64, 5432), c.getInt("port").?);
}

test "getInt returns null for non-integer" {
    var c = Config.init();
    c.setDefault("name", "hello");
    try testing.expect(c.getInt("name") == null);
}

test "getBool parses booleans" {
    var c = Config.init();
    c.setDefault("debug", "true");
    try testing.expectEqual(true, c.getBool("debug").?);
    c.setDefault("verbose", "false");
    try testing.expectEqual(false, c.getBool("verbose").?);
    c.setDefault("enabled", "1");
    try testing.expectEqual(true, c.getBool("enabled").?);
    c.setDefault("disabled", "0");
    try testing.expectEqual(false, c.getBool("disabled").?);
    c.setDefault("on", "yes");
    try testing.expectEqual(true, c.getBool("on").?);
    c.setDefault("off", "no");
    try testing.expectEqual(false, c.getBool("off").?);
}

test "getBool returns null for non-boolean" {
    var c = Config.init();
    c.setDefault("name", "hello");
    try testing.expect(c.getBool("name") == null);
}

test "isSet returns true for existing keys" {
    var c = Config.init();
    try testing.expect(!c.isSet("key"));
    c.setDefault("key", "value");
    try testing.expect(c.isSet("key"));
}

test "precedence: override > flag > config > default" {
    var c = Config.init();
    c.setDefault("key", "default");
    try testing.expectEqualStrings("default", c.get("key").?);

    c.readConfig("key: from_config\n");
    try testing.expectEqualStrings("from_config", c.get("key").?);

    c.setFlag("key", "from_flag");
    try testing.expectEqualStrings("from_flag", c.get("key").?);

    c.set("key", "from_override");
    try testing.expectEqualStrings("from_override", c.get("key").?);
}

test "EntryMap set and get" {
    var m = EntryMap{};
    try m.set("hello", "world");
    try testing.expectEqualStrings("world", m.get("hello").?);
    try testing.expect(m.get("missing") == null);
}

test "EntryMap update existing key" {
    var m = EntryMap{};
    try m.set("key", "value1");
    try m.set("key", "value2");
    try testing.expectEqualStrings("value2", m.get("key").?);
    try testing.expectEqual(@as(usize, 1), m.len);
}

test "EntryMap contains" {
    var m = EntryMap{};
    try m.set("key", "val");
    try testing.expect(m.contains("key"));
    try testing.expect(!m.contains("other"));
}
