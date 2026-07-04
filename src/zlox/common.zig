pub const U8_MAX = 255;
pub const U8_SIZE = U8_MAX + 1;

pub const FRAME_MAX = 64;
pub const STACK_MAX = FRAME_MAX * U8_SIZE;

/// Inline block expression to clean up switch cases that return a value but
/// also need to evaluate an additional expression for its side-effects.
///
/// Discards the first given expression, returns the second.
pub inline fn do(_: anytype, result: anytype) @TypeOf(result) {
    return result;
}
