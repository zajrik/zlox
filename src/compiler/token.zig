//! A token scanned from lox source text.

const std = @import("std");

const TokenType = @import("token_type.zig").TokenType;

const Writer = std.Io.Writer;

// ============================================================================

pub const Token: type = @This();

/// The type of this token.
token_type: TokenType,

/// The lexeme of this token, sliced from the source text.
lexeme: []const u8,

/// The line number of this token in the source text.
line: u16,

/// The column number of this token in the source text.
column: u16,

/// Initializes a new `Token` on the stack with the given `token_type`, `lexeme`,
/// and source text position (`line`/`column`).
pub fn init(token_type: TokenType, lexeme: []const u8, line: u16, column: u16) Token {
    return .{
        .token_type = token_type,
        .lexeme = lexeme,
        .line = line,
        .column = column,
    };
}

/// Custom formatter for `Token` values.
pub fn format(self: Token, writer: *Writer) !void {
    try writer.writeAll("Token { ");
    try writer.print(".token_type = {}, ", .{self.token_type});
    try writer.print(".lexeme = '{s}', ", .{self.lexeme});
    try writer.print(".line = {d}, ", .{self.line});
    try writer.print(".column = {d} ", .{self.column});
    try writer.writeAll("}");
}
