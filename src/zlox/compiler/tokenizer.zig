//! Processes given lox source code into individual tokens to be parsed and compiled
//! into lox bytecode.

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
        .token_error,
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
/// Returns the given `token_type` if it matches, otherwise returns
/// `TokenType.token_identifier`.
///
/// ```zig
/// // Assume the input text is "class" and we've already checked 'c' and 'l'
/// _ = checkKeyword(2, "ass", .token_class);
/// //               ^  ^
/// //               |  `--remainder of the keyword "class" after offset
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

    if (token_len != keyword_len) return .token_identifier;

    // Compare `rest` to the remaining token characters
    if (std.mem.eql(u8, self.start[offset..token_len], rest)) return token_type;

    return .token_identifier;
}

/// Determine if the currently-processing token lexeme is a keyword or an identifier.
///
/// Returns the keyword token type, or `TokenType.token_identifier` if no keyword
/// is matched.
fn identifierType(self: *Tokenizer) TokenType {
    const token_len: usize = self.current - self.start;

    return switch (self.start[0]) {
        'a' => self.checkPartial(1, "nd", .token_and),
        'c' => if (token_len > 1) switch (self.start[1]) {
            'l' => self.checkPartial(2, "ass", .token_class),
            'a' => self.checkPartial(2, "se", .token_case),
            else => .token_identifier,
        } else .token_identifier,

        'd' => self.checkPartial(1, "efault", .token_default),
        'e' => self.checkPartial(1, "lse", .token_else),
        'i' => self.checkPartial(1, "f", .token_if),

        'f' => if (token_len > 1) switch (self.start[1]) {
            'a' => self.checkPartial(2, "lse", .token_false),
            'o' => self.checkPartial(2, "r", .token_for),
            'u' => self.checkPartial(2, "n", .token_fun),
            else => .token_identifier,
        } else .token_identifier,

        'n' => self.checkPartial(1, "il", .token_nil),
        'o' => self.checkPartial(1, "r", .token_or),
        'p' => self.checkPartial(1, "rint", .token_print),
        'r' => self.checkPartial(1, "eturn", .token_return),

        's' => if (token_len > 1) switch (self.start[1]) {
            'u' => self.checkPartial(2, "per", .token_super),
            'w' => self.checkPartial(2, "itch", .token_switch),
            else => .token_identifier,
        } else .token_identifier,

        't' => if (token_len > 1) switch (self.start[1]) {
            'h' => self.checkPartial(2, "is", .token_this),
            'r' => self.checkPartial(2, "ue", .token_true),
            else => .token_identifier,
        } else .token_identifier,

        'v' => self.checkPartial(1, "ar", .token_var),
        'w' => self.checkPartial(1, "hile", .token_while),

        else => .token_identifier,
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

    return self.createToken(.token_number);
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

    return self.createToken(.token_string);
}

/// Consume the next token from the source text.
///
/// Returns the consumed token.
pub fn consumeToken(self: *Tokenizer) Token {
    self.discardWhitespace();

    // Set token lexeme start location within source
    self.start = self.current;
    self.start_line = self.line;
    self.start_column = self.column;

    if (self.isAtEnd()) return self.createToken(.token_eof);

    const char: u8 = self.consume();

    if (isAlpha(char)) return self.consumeIdentifier();
    if (isDigit(char)) return self.consumeNumber();

    return switch (char) {
        '(' => self.createToken(.token_left_paren),
        ')' => self.createToken(.token_right_paren),
        '{' => self.createToken(.token_left_brace),
        '}' => self.createToken(.token_right_brace),
        ':' => self.createToken(.token_colon),
        ';' => self.createToken(.token_semicolon),
        ',' => self.createToken(.token_comma),
        '.' => self.createToken(.token_dot),

        '*' => self.createToken(if (self.match('=')) .token_star_equal else .token_star),
        '/' => self.createToken(if (self.match('=')) .token_slash_equal else .token_slash),
        '-' => self.createToken(if (self.match('=')) .token_minus_equal else .token_minus),
        '+' => self.createToken(if (self.match('=')) .token_plus_equal else .token_plus),

        '?' => self.createToken(
            if (self.match('?'))
                (if (self.match('=')) .token_nilish_equal else .token_nilish)
            else
                .token_question,
        ),

        '!' => self.createToken(if (self.match('=')) .token_bang_equal else .token_bang),
        '<' => self.createToken(if (self.match('=')) .token_less_equal else .token_less),
        '>' => self.createToken(if (self.match('=')) .token_greater_equal else .token_greater),
        '=' => switch (self.peek()) {
            '=' => do(self.advance(), self.createToken(.token_equal_equal)),
            '>' => do(self.advance(), self.createToken(.token_arrow)),
            else => self.createToken(.token_equal),
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
