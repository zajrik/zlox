//! Reads through a given lox source code string and produces tokens to be parsed
//! and compiled into lox bytecode.

const std = @import("std");

const Token = @import("./token.zig").Token;

// ============================================================================

const Tokenizer: type = @This();

/// The source code to be tokenized.
chars: []const u8,

/// The current character being processed.
current: [*]const u8,

/// The column number of the current character being processed.
column: u16,

/// The line number of the current character being processed.
line: u16,

/// Initializes a new `Tokenizer` on the stack with the given source code string.
pub fn init(chars: []const u8) Tokenizer {
    return Tokenizer{
        .chars = chars,
        .current = chars.ptr,
        .column = 1,
        .line = 1,
    };
}

/// Returns whether the tokenizer has reached the end of the source code.
pub fn isAtEnd(self: *Tokenizer) bool {
    return self.peek() == 0;
}

/// Consume the current character being processed and advance the tokenizer.
///
/// Returns the consumed character.
pub fn advance(self: *Tokenizer) u8 {
    defer self.current += 1;
    return self.current[0];
}

/// Peek at the current character being processed.
///
/// Returns the peeked character without advancing the tokenizer.
pub fn peek(self: *Tokenizer) u8 {
    return self.current[0];
}

/// Peek at the character after the current character being processed.
///
/// Returns the peeked character without advancing the tokenizer.
pub fn peekNext(self: *Tokenizer) u8 {
    return self.current[1];
}
