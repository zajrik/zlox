//! A token scanned from lox source text.

const std = @import("std");
const zlox = @import("../.lib.zig");

const TokenType = zlox.tokenizer.TokenType;

const Writer = std.Io.Writer;

// =================================================================================================

const Self: type = @This();

/// The type of this token.
type: TokenType,

/// The lexeme of this token, sliced from the source text.
lexeme: []const u8,

/// The line number of this token in the source text.
line: u16,

/// The column number of this token in the source text.
column: u16,

/// Initializes a new `Token` on the stack with the given type `T`, `lexeme`, and
/// source text location (`line`/`column`).
pub fn init(T: TokenType, lexeme: []const u8, line: u16, column: u16) Self {
    return .{
        .type = T,
        .lexeme = lexeme,
        .line = line,
        .column = column,
    };
}

/// Create a synthetic identifier token with the given lexeme.
///
/// Tokens are considered equal if their lexemes match, so this can be used for
/// easily matching reserved identifiers.
pub fn identifier(lexeme: []const u8) Self {
    return Self.init(.identifier, lexeme, 0, 0);
}

/// Returns whether this token is of the given type `T`.
pub fn is(self: Self, T: TokenType) bool {
    return self.type == T;
}

/// Returns whether this token is *not* of the given type `T`.
pub fn isNot(self: Self, T: TokenType) bool {
    return self.type != T;
}

/// Returns whether this token is a discard token (`_`).
pub fn isDiscard(self: Self) bool {
    return self.lexeme.len == 1 and self.lexeme[0] == '_';
}

/// Returns whether this token is equal to `other`.
///
/// Tokens are considered equal if their lexemes are equal.
pub fn equals(self: Self, other: Self) bool {
    return std.mem.eql(u8, self.lexeme, other.lexeme);
}

/// Custom formatter for `Token` values.
pub fn format(self: Self, writer: *Writer) !void {
    try writer.print(
        "Token{{ .type = {}, .lexeme = '{s}', .line = {d}, .column = {d} }}",
        .{ self.type, self.lexeme, self.line, self.column },
    );
}
