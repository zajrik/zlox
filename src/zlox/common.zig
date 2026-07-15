pub const U8_MAX = 255;
pub const U8_SIZE = U8_MAX + 1;

pub const U16_MAX = 65535;
pub const U16_SIZE = U16_MAX + 1;

pub const FRAME_MAX = 64;
pub const STACK_MAX = FRAME_MAX * U8_SIZE;

/// Inline block expression to clean up switch cases that return a value but
/// also need to evaluate an additional expression for its side-effects.
///
/// Discards the first given expression, returns the second.
pub inline fn do(_: anytype, result: anytype) @TypeOf(result) {
    return result;
}

/// Split the given unsigned integer into two 8-bit integers.
///
/// Given integers larger than 16-bits will be truncated.
pub fn splitBytes(int: usize) struct { u8, u8 } {
    return .{ @as(u8, @truncate(int >> 8)), @as(u8, @truncate(int)) };
}
