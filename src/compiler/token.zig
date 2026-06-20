//! A token scanned from lox source text.

const TokenType = @import("token_type.zig").TokenType;

// ============================================================================

const Token: type = @This();

/// The type of this token.
token_type: TokenType,

/// The lexeme of this token, sliced from the source text.
lexeme: []const u8,

/// The line number of this token in the source text.
line: u16,

/// The column number of this token in the source text.
column: u16,

/// Initializes a new `Token` with the given `token_type`, `lexeme`, and source text position.
pub fn init(token_type: TokenType, lexeme: []const u8, line: u16, column: u16) Token {
    return Token{
        .token_type = token_type,
        .lexeme = lexeme,
        .line = line,
        .column = column,
    };
}
