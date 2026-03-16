const std = @import("std");

/// Maximum length for an environment variable value we can capture.
const MAX_ENV_VALUE_LEN = 4096;

/// Thread-local buffer for returning env var values as slices.
/// We need this because std.posix.getenv returns a null-terminated C string
/// but we want a Zig slice, and the value must outlive the function call scope.
/// This is safe because we only support single-threaded access (like Viper).
var env_value_buf: [MAX_ENV_VALUE_LEN]u8 = undefined;

/// Look up an environment variable by name.
/// Returns a slice into a static buffer, or null if the variable is not set.
///
/// WARNING: The returned slice is invalidated by the next call to getEnv.
/// This is acceptable for Serum's use case where we immediately copy or compare.
pub fn getEnv(name: []const u8) ?[]const u8 {
    // Build null-terminated name for the C interface.
    var name_buf: [256]u8 = undefined;
    if (name.len >= name_buf.len) return null;
    @memcpy(name_buf[0..name.len], name);
    name_buf[name.len] = 0;

    const name_z: [*:0]const u8 = @ptrCast(name_buf[0..name.len :0]);

    // Use std.posix.getenv which returns a [*:0]const u8 or null.
    const result = std.c.getenv(name_z);
    if (result == null) return null;

    // Convert to a Zig slice by finding the length.
    const c_str: [*:0]const u8 = @ptrCast(result.?);
    const len = std.mem.len(c_str);
    if (len > MAX_ENV_VALUE_LEN) return null;

    @memcpy(env_value_buf[0..len], c_str[0..len]);
    return env_value_buf[0..len];
}

// =============================================================================
// Tests
// =============================================================================

const testing = std.testing;

test "getEnv returns null for unset variable" {
    const result = getEnv("SERUM_TEST_DEFINITELY_NOT_SET_12345");
    try testing.expect(result == null);
}

test "getEnv returns value for set variable" {
    // PATH is almost always set on any system.
    const result = getEnv("PATH");
    // PATH should be non-null and non-empty.
    try testing.expect(result != null);
    try testing.expect(result.?.len > 0);
}
