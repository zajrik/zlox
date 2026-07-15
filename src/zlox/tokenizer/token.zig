//! A token scanned from lox source text.

const std = @import("std");
const zlox = @import("../.lib.zig");

const TokenType = zlox.tokenizer.TokenType;

const Writer = std.Io.Writer;

// ============================================================================

const Token: type = @This();

/// The type of this token.
type: TokenType,

/// The lexeme of this token, sliced from the source text.
lexeme: []const u8,

/// The line number of this token in the source text.
line: u16,

/// The column number of this token in the source text.
column: u16,

/// Initializes a new `Token` on the stack with the given `type`, `lexeme`, and
/// source text location (`line`/`column`).
pub fn init(@"type": TokenType, lexeme: []const u8, line: u16, column: u16) Token {
    return .{
        .type = @"type",
        .lexeme = lexeme,
        .line = line,
        .column = column,
    };
}

/// Returns whether this token is of the given `type`.
pub fn is(self: Token, @"type": TokenType) bool {
    return self.type == @"type";
}

/// Returns whether this token is *not* of the given `type`.
pub fn isNot(self: Token, @"type": TokenType) bool {
    return self.type != @"type";
}

/// Returns whether this token is a discard token (`_`).
pub fn isDiscard(self: Token) bool {
    return self.lexeme.len == 1 and self.lexeme[0] == '_';
}

/// Returns whether this token is equal to `other`.
///
/// Tokens are equal if their types and lexemes are equal.
pub fn equals(self: Token, other: Token) bool {
    return self.type == other.type and std.mem.eql(u8, self.lexeme, other.lexeme);
}

/// Custom formatter for `Token` values.
pub fn format(self: Token, writer: *Writer) Writer.Error!void {
    try writer.writeAll("Token { ");
    try writer.print(".token_type = {}, ", .{self.type});
    try writer.print(".lexeme = '{s}', ", .{self.lexeme});
    try writer.print(".line = {d}, ", .{self.line});
    try writer.print(".column = {d} ", .{self.column});
    try writer.writeAll("}");
}
