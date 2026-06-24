const std = @import("std");
const printf = std.debug.print;

// ============================================================================

/// Represents a lox value.
pub const Value: type = f32;

/// Prints the given `value`.
pub fn print(value: Value) void {
    printf("{any}", .{value});
}
