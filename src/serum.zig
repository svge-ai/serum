//! Serum -- Zig Configuration Library
//!
//! A Zig-idiomatic port of Go's spf13/viper.
//! Provides prioritized configuration from defaults, config files, env vars, flags, and overrides.

pub const config = @import("config.zig");
pub const env = @import("env.zig");
pub const file = @import("file.zig");

// Re-export primary types at the top level for convenience.
pub const Config = config.Config;
pub const EntryMap = config.EntryMap;
pub const Entry = config.Entry;
pub const ConfigType = file.ConfigType;

test {
    // Pull in tests from sub-modules.
    _ = @import("config.zig");
    _ = @import("env.zig");
    _ = @import("file.zig");
    // Integration tests live in tests/ — run via build.zig test targets
}
