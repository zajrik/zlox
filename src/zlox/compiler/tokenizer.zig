//! Encapsulates the process of converting raw lox source code into a series of
//! tokens to be parsed and compiled into lox bytecode.

const std = @import("std");
const zlox = @import("../.lib.zig");

const Token = zlox.compiler.Token;
const TokenType = zlox.compiler.TokenType;

// ============================================================================

const Tokenizer: type = @This();

/// The source code to be tokenized.
source: []const u8,

/// Pointer to the current character to be processed.
///
/// - Call `consume()` to advance the tokenizer and return this character.
/// - Call `discard()` to advance the tokenizer without returning this character.
current: [*]const u8,

/// Column number of the current character to be processed.
column: u16,

/// Line number of the current character to be processed.
line: u16,

/// Pointer to the start of the currently-processing token lexeme.
///
/// This is updated whenever we begin processing a new token.
start: [*]const u8,

/// Line at which the currently-processing token lexeme begins.
///
/// This is updated whenever we begin processing a new token.
start_line: u16,

/// Column at which the currently-processing token lexeme begins.
///
/// This is updated whenever we begin processing a new token.
start_column: u16,

/// Initialize a new `Tokenizer` on the stack with the given source code string.
pub fn init(source: []const u8) Tokenizer {
    return .{
        .source = source,
        .current = source.ptr,
        .column = 1,
        .line = 1,
        .start = source.ptr,
        .start_line = 1,
        .start_column = 1,
    };
}

/// Consumes and returns the next `Token` from the source input, or `null` if
/// we've reached the end of the source input.
pub fn next(self: *Tokenizer) ?Token {
    if (self.isAtEnd()) return null;
    return self.consumeToken();
}

/// Advance the tokenizer, moving past the currently-processing character to the
/// next character to be processed.
///
/// Returns the currently-processing character.
fn consume(self: *Tokenizer) u8 {
    defer self.column += 1;
    defer self.current += 1;
    return self.peek();
}

/// Advance the tokenizer, moving past the currently-processing character to the
/// next character to be processed.
///
/// The currently-processing character will not be returned.
fn advance(self: *Tokenizer) void {
    _ = self.consume();
}

/// Advance the tokenizer, discarding characters until we see any non-whitespace
/// character.
fn discardWhitespace(self: *Tokenizer) void {
    while (true) switch (self.peek()) {
        ' ', '\r', '\t' => self.advance(),

        // Increment line count and reset column on newlines
        '\n' => {
            self.advance();
            self.line += 1;
            self.column = 1;
        },

        // Skip comments or return on single slash
        '/' => {
            if (self.peekNext() != '/') break;

            while (self.peek() != '\n' and !self.isAtEnd()) {
                self.advance();
            }
        },

        else => break,
    };
}

/// Create and return a `Token` with the given `token_type` using the characters
/// that have been consumed/discarded since `start` as the token lexeme.
fn createToken(self: *Tokenizer, token_type: TokenType) Token {
    const token_len: usize = self.current - self.start;
    return Token.init(
        token_type,
        self.start[0..token_len],
        self.start_line,
        self.start_column,
    );
}

/// Create and return an error token with the given `err` string as the token lexeme.
fn errorToken(self: *Tokenizer, err: []const u8) Token {
    return Token.init(
        .err,
        err,
        self.line,
        self.start_column,
    );
}

/// Peek at the current character being processed.
///
/// Returns the peeked character without advancing the tokenizer.
fn peek(self: *Tokenizer) u8 {
    return self.current[0];
}

/// Peek at the character after the current character being processed.
///
/// Returns the peeked character without advancing the tokenizer.
fn peekNext(self: *Tokenizer) u8 {
    return self.current[1];
}

/// Returns whether the tokenizer has reached the end of the source code.
pub fn isAtEnd(self: *Tokenizer) bool {
    return self.peek() == 0;
}

/// Peek at the current character being processed and return whether it matches
/// `expected`.
///
/// If the character matches, the tokenizer will advance.
fn match(self: *Tokenizer, expected: u8) bool {
    if (self.isAtEnd()) return false;
    if (self.peek() != expected) return false;

    self.advance();
    return true;
}

/// Check if the remainder of the currently-processing token lexeme after `offset`
/// matches the given partial token text.
///
/// Returns the given `token_type` if it matches, otherwise returns `TokenType.identifier`.
///
/// ```zig
/// // Assume the input text is "class" and we've already checked 'c' and 'l'
/// _ = checkPartial(2, "ass", .keyword_class);
/// //               ^  ^
/// //               |  `--remainder of the keyword "class" text after offset
/// //               |
/// //               `--offset by 2 because 'c' and 'l' have already been checked
/// ```
fn checkPartial(
    self: *Tokenizer,
    offset: u32,
    rest: []const u8,
    token_type: TokenType,
) TokenType {
    const token_len: usize = self.current - self.start;
    const keyword_len: usize = offset + rest.len;

    if (token_len != keyword_len) return .identifier;

    // Compare `rest` to the remaining token characters
    if (std.mem.eql(u8, self.start[offset..token_len], rest)) return token_type;

    return .identifier;
}

/// Determine if the currently-processing token lexeme is a keyword or an identifier.
///
/// Returns the keyword token type, or `TokenType.token_identifier` if no keyword
/// is matched.
fn identifierType(self: *Tokenizer) TokenType {
    const token_len: usize = self.current - self.start;

    return switch (self.start[0]) {
        'a' => self.checkPartial(1, "nd", .keyword_and),
        'c' => if (token_len > 1) switch (self.start[1]) {
            'l' => self.checkPartial(2, "ass", .keyword_class),
            'a' => self.checkPartial(2, "se", .keyword_case),
            else => .identifier,
        } else .identifier,

        'd' => self.checkPartial(1, "efault", .keyword_default),
        'e' => self.checkPartial(1, "lse", .keyword_else),
        'i' => self.checkPartial(1, "f", .keyword_if),

        'f' => if (token_len > 1) switch (self.start[1]) {
            'a' => self.checkPartial(2, "lse", .keyword_false),
            'o' => self.checkPartial(2, "r", .keyword_for),
            'u' => self.checkPartial(2, "n", .keyword_fun),
            else => .identifier,
        } else .identifier,

        'n' => self.checkPartial(1, "il", .keyword_nil),
        'o' => self.checkPartial(1, "r", .keyword_or),
        'p' => self.checkPartial(1, "rint", .keyword_print),
        'r' => self.checkPartial(1, "eturn", .keyword_return),

        's' => if (token_len > 1) switch (self.start[1]) {
            'u' => self.checkPartial(2, "per", .keyword_super),
            'w' => self.checkPartial(2, "itch", .keyword_switch),
            else => .identifier,
        } else .identifier,

        't' => if (token_len > 1) switch (self.start[1]) {
            'h' => self.checkPartial(2, "is", .keyword_this),
            'r' => self.checkPartial(2, "ue", .keyword_true),
            else => .identifier,
        } else .identifier,

        'v' => self.checkPartial(1, "ar", .keyword_var),
        'w' => self.checkPartial(1, "hile", .keyword_while),

        else => .identifier,
    };
}

/// Consume an identifier from source.
///
/// Returns the tokenized identifier.
fn consumeIdentifier(self: *Tokenizer) Token {
    while (isAlphaNumeric(self.peek())) self.advance();
    return self.createToken(self.identifierType());
}

/// Consumes a number literal from source.
///
/// Returns the tokenized number literal.
fn consumeNumber(self: *Tokenizer) Token {
    while (isDigit(self.peek())) self.advance();

    // Consume floating point digits if present
    if (self.peek() == '.' and isDigit(self.peekNext())) {
        self.advance();
        while (isDigit(self.peek())) self.advance();
    }

    return self.createToken(.number);
}

/// Consumes a string literal from source.
///
/// Returns the tokenized string literal.
fn consumeString(self: *Tokenizer) Token {
    while (self.peek() != '"' and !self.isAtEnd()) {
        // Increment line count and reset column after advancing on new line
        if (self.peek() == '\n') {
            defer self.line += 1;
            defer self.column = 1;
        }

        self.advance();
    }

    if (self.isAtEnd()) return self.errorToken("Unterminated string.");

    // Consume closing quote
    self.advance();

    return self.createToken(.string);
}

/// Consume the next token from the source text.
///
/// Returns the consumed token.
fn consumeToken(self: *Tokenizer) Token {
    self.discardWhitespace();

    // Set token lexeme start location within source
    self.start = self.current;
    self.start_line = self.line;
    self.start_column = self.column;

    if (self.isAtEnd()) return self.createToken(.eof);

    const char: u8 = self.consume();

    if (isAlpha(char)) return self.consumeIdentifier();
    if (isDigit(char)) return self.consumeNumber();

    return switch (char) {
        '(' => self.createToken(.paren_left),
        ')' => self.createToken(.paren_right),
        '{' => self.createToken(.brace_left),
        '}' => self.createToken(.brace_right),
        ':' => self.createToken(.colon),
        ';' => self.createToken(.semicolon),
        ',' => self.createToken(.comma),
        '.' => self.createToken(.dot),

        '*' => self.createToken(if (self.match('=')) .star_equal else .star),
        '/' => self.createToken(if (self.match('=')) .slash_equal else .slash),
        '-' => self.createToken(if (self.match('=')) .minus_equal else .minus),
        '+' => self.createToken(if (self.match('=')) .plus_equal else .plus),

        '?' => self.createToken(token: {
            if (!self.match('?')) break :token .question;
            if (self.match('=')) break :token .nilish_equal;
            break :token .nilish;
        }),

        '!' => self.createToken(if (self.match('=')) .bang_equal else .bang),
        '<' => self.createToken(if (self.match('=')) .less_equal else .less),
        '>' => self.createToken(if (self.match('=')) .greater_equal else .greater),
        '=' => switch (self.peek()) {
            '=' => do(self.advance(), self.createToken(.equal_equal)),
            '>' => do(self.advance(), self.createToken(.arrow)),
            else => self.createToken(.equal),
        },

        '"' => self.consumeString(),

        else => self.errorToken("Unexpected character."),
    };
}

/// Return whether the given `char` is a digit character.
fn isDigit(char: u8) bool {
    return char >= '0' and char <= '9';
}

/// Return whether the given `char` is an alpha character.
fn isAlpha(char: u8) bool {
    // zig fmt: off
    return (char >= 'a' and char <= 'z')
        or (char >= 'A' and char <= 'Z')
        or char == '_';
    // zig fmt: on
}

/// Return whether the given `char` is an alphanumeric character.
fn isAlphaNumeric(char: u8) bool {
    return isAlpha(char) or isDigit(char);
}

/// Inline block expression to clean up switch cases that return a value but
/// also need to evaluate an additional expression for its side-effects.
///
/// Discards the first given expression, returns the second.
inline fn do(_: anytype, result: anytype) @TypeOf(result) {
    return result;
}
