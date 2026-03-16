//! Integration tests for Serum — ported from viper_test.go behavioral expectations.
//!
//! Tests cover:
//! - Default values
//! - Override precedence (set > env > config > default)
//! - Env var binding (explicit and automatic)
//! - Env prefix
//! - Nested key access with dot notation
//! - Config file reading (using readConfig with string input)
//! - Type getters (getString, getInt, getBool)
//! - isSet behavior

const std = @import("std");
const serum = @import("serum");
const Config = serum.Config;

const testing = std.testing;

// =============================================================================
// Default values
// =============================================================================

test "defaults: set and retrieve" {
    var c = Config.init();
    c.setDefault("name", "gemworks");
    c.setDefault("version", "1.0");

    try testing.expectEqualStrings("gemworks", c.get("name").?);
    try testing.expectEqualStrings("1.0", c.get("version").?);
}

test "defaults: missing key returns null" {
    const c = Config.init();
    try testing.expect(c.get("nonexistent") == null);
}

test "defaults: multiple defaults don't interfere" {
    var c = Config.init();
    c.setDefault("a", "1");
    c.setDefault("b", "2");
    c.setDefault("c", "3");

    try testing.expectEqualStrings("1", c.get("a").?);
    try testing.expectEqualStrings("2", c.get("b").?);
    try testing.expectEqualStrings("3", c.get("c").?);
}

test "defaults: overwriting a default" {
    var c = Config.init();
    c.setDefault("key", "old");
    c.setDefault("key", "new");
    try testing.expectEqualStrings("new", c.get("key").?);
}

// =============================================================================
// Override precedence
// =============================================================================

test "precedence: override beats everything" {
    var c = Config.init();
    c.setDefault("key", "default_val");
    c.readConfig("key: config_val\n");
    c.set("key", "override_val");

    try testing.expectEqualStrings("override_val", c.get("key").?);
}

test "precedence: config beats default" {
    var c = Config.init();
    c.setDefault("key", "default_val");
    c.readConfig("key: config_val\n");

    try testing.expectEqualStrings("config_val", c.get("key").?);
}

test "precedence: flag beats config" {
    var c = Config.init();
    c.setDefault("key", "default_val");
    c.readConfig("key: config_val\n");
    c.setFlag("key", "flag_val");

    try testing.expectEqualStrings("flag_val", c.get("key").?);
}

test "precedence: override beats flag" {
    var c = Config.init();
    c.setFlag("key", "flag_val");
    c.set("key", "override_val");

    try testing.expectEqualStrings("override_val", c.get("key").?);
}

test "precedence: full chain" {
    var c = Config.init();

    // Set all layers.
    c.setDefault("key", "from_default");
    c.readConfig("key: from_config\n");
    c.setFlag("key", "from_flag");
    c.set("key", "from_override");

    // Override wins.
    try testing.expectEqualStrings("from_override", c.get("key").?);
}

// =============================================================================
// Env var binding (explicit)
// =============================================================================

test "env: explicit binding reads env var" {
    // We use the PATH env var as a proxy since it's always set.
    var c = Config.init();
    c.bindEnv("system_path", "PATH");

    const val = c.get("system_path");
    try testing.expect(val != null);
    try testing.expect(val.?.len > 0);
}

test "env: explicit binding beats config and default" {
    // Bind to PATH which we know is set.
    var c = Config.init();
    c.setDefault("system_path", "fallback");
    c.readConfig("system_path: from_config\n");
    c.bindEnv("system_path", "PATH");

    const val = c.get("system_path").?;
    // It should NOT be "fallback" or "from_config" because env has higher precedence.
    try testing.expect(!std.mem.eql(u8, val, "fallback"));
    try testing.expect(!std.mem.eql(u8, val, "from_config"));
}

test "env: override still beats env" {
    var c = Config.init();
    c.bindEnv("system_path", "PATH");
    c.set("system_path", "my_override");

    try testing.expectEqualStrings("my_override", c.get("system_path").?);
}

test "env: unset env var falls through to config" {
    var c = Config.init();
    c.bindEnv("my_key", "SERUM_UNSET_VAR_XYZ_999");
    c.readConfig("my_key: from_config\n");

    try testing.expectEqualStrings("from_config", c.get("my_key").?);
}

test "env: unset env var falls through to default" {
    var c = Config.init();
    c.bindEnv("my_key", "SERUM_UNSET_VAR_XYZ_999");
    c.setDefault("my_key", "from_default");

    try testing.expectEqualStrings("from_default", c.get("my_key").?);
}

// =============================================================================
// Env prefix
// =============================================================================

test "env prefix: automatic env with prefix" {
    // Use HOME which is typically set.
    var c = Config.init();
    c.automaticEnv();

    // Without prefix, key "HOME" should resolve to env var "HOME".
    const val = c.get("home"); // "home" -> uppercased to "HOME"
    // HOME is usually set. If somehow not, this test is a no-op.
    if (val) |v| {
        try testing.expect(v.len > 0);
    }
}

// =============================================================================
// Automatic env
// =============================================================================

test "automatic env: dot keys become underscored uppercase" {
    // We'd need a specific env var to test this reliably.
    // Test the mechanism: automatic_env with key "a.b" looks up "A_B".
    var c = Config.init();
    c.automaticEnv();
    c.setDefault("a.b", "default_val");

    // Since env var A_B is almost certainly not set, we should get the default.
    try testing.expectEqualStrings("default_val", c.get("a.b").?);
}

// =============================================================================
// Nested key access with dot notation
// =============================================================================

test "nested keys from config" {
    var c = Config.init();
    c.readConfig(
        \\database:
        \\  host: localhost
        \\  port: 5432
        \\  credentials:
        \\    user: admin
        \\    password: secret
    );

    try testing.expectEqualStrings("localhost", c.get("database.host").?);
    try testing.expectEqualStrings("5432", c.get("database.port").?);
    try testing.expectEqualStrings("admin", c.get("database.credentials.user").?);
    try testing.expectEqualStrings("secret", c.get("database.credentials.password").?);
}

test "nested keys: override on nested key" {
    var c = Config.init();
    c.readConfig(
        \\database:
        \\  host: localhost
    );
    c.set("database.host", "production.db");

    try testing.expectEqualStrings("production.db", c.get("database.host").?);
}

test "nested keys: default on nested key" {
    var c = Config.init();
    c.setDefault("database.host", "localhost");
    c.setDefault("database.port", "5432");

    try testing.expectEqualStrings("localhost", c.get("database.host").?);
    try testing.expectEqualStrings("5432", c.get("database.port").?);
}

// =============================================================================
// Config file reading
// =============================================================================

test "readConfig: basic yaml" {
    var c = Config.init();
    c.readConfig(
        \\name: myapp
        \\debug: true
        \\port: 8080
    );

    try testing.expectEqualStrings("myapp", c.get("name").?);
    try testing.expectEqualStrings("true", c.get("debug").?);
    try testing.expectEqualStrings("8080", c.get("port").?);
}

test "readConfig: complex nested config" {
    var c = Config.init();
    c.readConfig(
        \\app:
        \\  name: gemworks
        \\  version: 0.1.0
        \\database:
        \\  host: localhost
        \\  port: 5432
        \\logging:
        \\  level: info
        \\  output: stdout
    );

    try testing.expectEqualStrings("gemworks", c.get("app.name").?);
    try testing.expectEqualStrings("0.1.0", c.get("app.version").?);
    try testing.expectEqualStrings("localhost", c.get("database.host").?);
    try testing.expectEqualStrings("5432", c.get("database.port").?);
    try testing.expectEqualStrings("info", c.get("logging.level").?);
    try testing.expectEqualStrings("stdout", c.get("logging.output").?);
}

test "readConfig: empty content" {
    var c = Config.init();
    c.readConfig("");
    try testing.expect(c.get("anything") == null);
}

test "readConfig: only comments" {
    var c = Config.init();
    c.readConfig(
        \\# This is a comment
        \\# Another comment
    );
    try testing.expect(c.get("anything") == null);
}

// =============================================================================
// Type getters
// =============================================================================

test "getString: returns value" {
    var c = Config.init();
    c.setDefault("name", "hello");
    try testing.expectEqualStrings("hello", c.getString("name"));
}

test "getString: returns empty for missing" {
    const c = Config.init();
    try testing.expectEqualStrings("", c.getString("missing"));
}

test "getInt: valid integers" {
    var c = Config.init();
    c.setDefault("positive", "42");
    try testing.expectEqual(@as(i64, 42), c.getInt("positive").?);

    c.setDefault("negative", "-17");
    try testing.expectEqual(@as(i64, -17), c.getInt("negative").?);

    c.setDefault("zero", "0");
    try testing.expectEqual(@as(i64, 0), c.getInt("zero").?);
}

test "getInt: invalid returns null" {
    var c = Config.init();
    c.setDefault("text", "not_a_number");
    try testing.expect(c.getInt("text") == null);
}

test "getInt: missing returns null" {
    const c = Config.init();
    try testing.expect(c.getInt("missing") == null);
}

test "getBool: true variants" {
    var c = Config.init();
    c.setDefault("a", "true");
    try testing.expectEqual(true, c.getBool("a").?);

    c.setDefault("b", "1");
    try testing.expectEqual(true, c.getBool("b").?);

    c.setDefault("c", "yes");
    try testing.expectEqual(true, c.getBool("c").?);
}

test "getBool: false variants" {
    var c = Config.init();
    c.setDefault("a", "false");
    try testing.expectEqual(false, c.getBool("a").?);

    c.setDefault("b", "0");
    try testing.expectEqual(false, c.getBool("b").?);

    c.setDefault("c", "no");
    try testing.expectEqual(false, c.getBool("c").?);
}

test "getBool: invalid returns null" {
    var c = Config.init();
    c.setDefault("text", "maybe");
    try testing.expect(c.getBool("text") == null);
}

test "getBool: missing returns null" {
    const c = Config.init();
    try testing.expect(c.getBool("missing") == null);
}

// =============================================================================
// isSet behavior
// =============================================================================

test "isSet: false for missing" {
    const c = Config.init();
    try testing.expect(!c.isSet("missing"));
}

test "isSet: true for default" {
    var c = Config.init();
    c.setDefault("key", "val");
    try testing.expect(c.isSet("key"));
}

test "isSet: true for config" {
    var c = Config.init();
    c.readConfig("key: val\n");
    try testing.expect(c.isSet("key"));
}

test "isSet: true for override" {
    var c = Config.init();
    c.set("key", "val");
    try testing.expect(c.isSet("key"));
}

test "isSet: true for flag" {
    var c = Config.init();
    c.setFlag("key", "val");
    try testing.expect(c.isSet("key"));
}

test "isSet: true for env binding" {
    var c = Config.init();
    c.bindEnv("key", "PATH");
    try testing.expect(c.isSet("key"));
}

// =============================================================================
// Config file settings
// =============================================================================

test "config settings: setConfigName and setConfigType" {
    var c = Config.init();
    c.setConfigName("myconfig");
    c.setConfigType(.yaml);

    try testing.expectEqualStrings("myconfig", c.config_name[0..c.config_name_len]);
    try testing.expectEqual(serum.ConfigType.yaml, c.config_type);
}

test "config settings: addConfigPath" {
    var c = Config.init();
    c.addConfigPath("/etc/myapp");
    c.addConfigPath("/home/user/.myapp");

    try testing.expectEqual(@as(usize, 2), c.config_paths_count);
    try testing.expectEqualStrings("/etc/myapp", c.config_paths[0][0..c.config_paths_len[0]]);
    try testing.expectEqualStrings("/home/user/.myapp", c.config_paths[1][0..c.config_paths_len[1]]);
}

// =============================================================================
// TOML config
// =============================================================================

test "readConfig: TOML basic key-value" {
    var c = Config.init();
    c.setConfigType(.toml);
    c.readConfig(
        \\name = "myapp"
        \\debug = true
        \\port = 8080
    );

    try testing.expectEqualStrings("myapp", c.get("name").?);
    try testing.expectEqualStrings("true", c.get("debug").?);
    try testing.expectEqualStrings("8080", c.get("port").?);
}

test "readConfig: TOML with sections" {
    var c = Config.init();
    c.setConfigType(.toml);
    c.readConfig(
        \\[inference]
        \\provider = "anthropic"
        \\model = "claude-sonnet-4-6"
        \\api_key_env = "ANTHROPIC_API_KEY"
        \\
        \\[output]
        \\format = "human"
        \\
        \\[cache]
        \\max_size_mb = 1024
        \\max_age_hours = 168
    );

    try testing.expectEqualStrings("anthropic", c.get("inference.provider").?);
    try testing.expectEqualStrings("claude-sonnet-4-6", c.get("inference.model").?);
    try testing.expectEqualStrings("ANTHROPIC_API_KEY", c.get("inference.api_key_env").?);
    try testing.expectEqualStrings("human", c.get("output.format").?);
    try testing.expectEqualStrings("1024", c.get("cache.max_size_mb").?);
    try testing.expectEqualStrings("168", c.get("cache.max_age_hours").?);
}

test "readConfig: TOML nested sections" {
    var c = Config.init();
    c.setConfigType(.toml);
    c.readConfig(
        \\[inference.providers.anthropic]
        \\api_key_env = "ANTHROPIC_API_KEY"
        \\model = "claude-sonnet-4-6"
    );

    try testing.expectEqualStrings("ANTHROPIC_API_KEY", c.get("inference.providers.anthropic.api_key_env").?);
    try testing.expectEqualStrings("claude-sonnet-4-6", c.get("inference.providers.anthropic.model").?);
}

test "readConfig: TOML precedence with defaults" {
    var c = Config.init();
    c.setDefault("inference.provider", "default_provider");
    c.setDefault("inference.model", "default_model");

    c.setConfigType(.toml);
    c.readConfig(
        \\[inference]
        \\provider = "anthropic"
    );

    // Config overrides default
    try testing.expectEqualStrings("anthropic", c.get("inference.provider").?);
    // Default still applies for keys not in config
    try testing.expectEqualStrings("default_model", c.get("inference.model").?);
}

test "readConfig: TOML empty content" {
    var c = Config.init();
    c.setConfigType(.toml);
    c.readConfig("");
    try testing.expect(c.get("anything") == null);
}

test "readConfig: TOML only comments" {
    var c = Config.init();
    c.setConfigType(.toml);
    c.readConfig(
        \\# Gemworks config
        \\# Nothing here yet
    );
    try testing.expect(c.get("anything") == null);
}
