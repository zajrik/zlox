//! A wrapper around a given `Tokenizer` to facilitate iterating over source
//! tokens via loop payload captures.
//!
//! ```zig
//! var tokenizer = Tokenizer.init("var a = 123;");
//! const tokens = TokenIterator.init(&tokenizer);
//!
//! while (tokens.next()) |token| {
//!     std.debug.print("{f}\n", .{token});
//! }
//! ```

const std = @import("std");
const zlox = @import("../.lib.zig");

const Token = zlox.compiler.Token;
const Tokenizer = zlox.compiler.Tokenizer;

// ============================================================================

const TokenIterator: type = @This();

/// Pointer to a `Tokenizer` instance from which to iterate produced tokens.
tokenizer: *Tokenizer,

/// Initialize a new `TokenIterator` on the stack.
pub fn init(tokenizer: *Tokenizer) TokenIterator {
    return .{ .tokenizer = tokenizer };
}

/// Returns the next `Token` from the `tokenizer`, or `null` if we've reached
/// the end of the tokenizer input.
pub fn next(self: *const TokenIterator) ?Token {
    if (self.tokenizer.isAtEnd()) return null;
    return self.tokenizer.consumeToken();
}
