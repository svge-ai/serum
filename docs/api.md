# API Reference

## Config

The main configuration type. Zero-allocation, fixed-size buffers.

```zig
const Config = struct {
    pub fn init() Config;

    // Setters
    pub fn setDefault(self: *Config, key: []const u8, value: []const u8) void;
    pub fn set(self: *Config, key: []const u8, value: []const u8) void;
    pub fn setFlag(self: *Config, key: []const u8, value: []const u8) void;

    // Getters (respect precedence chain)
    pub fn get(self: *const Config, key: []const u8) ?[]const u8;
    pub fn getString(self: *const Config, key: []const u8) []const u8;  // "" if missing
    pub fn getInt(self: *const Config, key: []const u8) ?i64;
    pub fn getBool(self: *const Config, key: []const u8) ?bool;
    pub fn isSet(self: *const Config, key: []const u8) bool;

    // Environment variables
    pub fn bindEnv(self: *Config, key: []const u8, env_var: []const u8) void;
    pub fn setEnvPrefix(self: *Config, prefix: []const u8) void;
    pub fn automaticEnv(self: *Config) void;

    // Config file
    pub fn setConfigName(self: *Config, name: []const u8) void;
    pub fn setConfigType(self: *Config, config_type: ConfigType) void;
    pub fn addConfigPath(self: *Config, path: []const u8) void;
    pub fn readConfig(self: *Config, content: []const u8) void;
};
```

## ConfigType

```zig
const ConfigType = enum {
    yaml,
    toml,
};
```

## EntryMap

Low-level fixed-capacity key-value store used internally.

```zig
const EntryMap = struct {
    pub fn set(self: *EntryMap, key: []const u8, value: []const u8) !void;
    pub fn get(self: *const EntryMap, key: []const u8) ?[]const u8;
    pub fn contains(self: *const EntryMap, key: []const u8) bool;
};
```

## Boolean parsing

`getBool()` recognizes these values:

| True | False |
|------|-------|
| `"true"` | `"false"` |
| `"1"` | `"0"` |
| `"yes"` | `"no"` |

Anything else returns `null`.

## Static limits

| Resource | Limit |
|----------|-------|
| Max entries per layer | 256 |
| Max key length | 128 bytes |
| Max value length | 512 bytes |
| Max config search paths | 16 |
| Key delimiter | `.` (configurable) |
