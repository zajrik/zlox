//! Encapsulates the process of fetching tokens from the `Tokenizer`, bridging
//! the gap between tokenization and compilation.
//!
//! The compiler will use the parser both for obtaining lox tokens from source
//! and for reporting errors related to parsing and compiling those tokens.
//!
//! Lox programs are compiled in a single pass, with each bit of source code passing
//! through the tokenizer, to the parser, and finally to the compiler, so all
//! errors encountered during tokenization and parsing are treated as compilation
//! errors.

const std = @import("std");
const zlox = @import("../.lib.zig");

const mem = zlox.mem;

const ParseStrategy = zlox.parser.ParseStrategy;
const Precedence = zlox.parser.Precedence;

const Token = zlox.tokenizer.Token;
const Tokenizer = zlox.tokenizer.Tokenizer;
const TokenType = zlox.tokenizer.TokenType;

const printf = std.debug.print;

// ============================================================================

const Parser: type = @This();

/// Tokenizer instance. Not owned by the parser.
tokenizer: *Tokenizer,

/// The token currently being parsed for compilation.
current: Token = undefined,

/// The next token to be parsed for compilation.
next: Token = undefined,

/// Whether we encountered at least one (1) error while parsing/compiling.
had_error: bool = false,

/// Whether the parser is panicking.
///
/// While panicking, we'll skip tokens until we find a valid token boundary to
/// synchronize to so that we can return to parsing the remainder of the input
/// to find any other errors to report, if any.
panic_mode: bool = false,

/// Allocate a new `Parser` instance on the heap, returning a pointer to it.
///
/// The caller owns the returned pointer and is responsible for freeing it.
pub fn create(tokenizer: *Tokenizer) !*Parser {
    const parser: *Parser = try mem.createStruct(Parser, .{
        .tokenizer = tokenizer,
    });

    // Load the first token into `next`
    parser.advance();

    return parser;
}

/// Destroy this `Parser`, freeing its owned resources.
pub fn destroy(self: *Parser) void {
    mem.destroy(self);
}

/// Advance this parser, fetching the next token from the tokenizer.
pub fn advance(self: *Parser) void {
    self.current = self.next;

    while (self.tokenizer.next()) |token| {
        self.next = token;
        if (token.isNot(.@"error")) break;

        self.errAtNext(token.lexeme);
    }
}

/// Consume a token of the given `type` from the tokenizer.
///
/// Emits error `msg` if a token of the given type is not found.
pub fn consume(self: *Parser, @"type": TokenType, msg: []const u8) void {
    if (self.next.is(@"type")) return self.advance();
    self.errAtNext(msg);
}

/// Returns whether the next token to be parsed is of `type`.
///
/// If it is, the token will be consumed and the next token will be fetched from
/// the tokenizer.
pub fn match(self: *Parser, @"type": TokenType) bool {
    if (self.next.isNot(@"type")) return false;
    self.advance();
    return true;
}

/// Returns whether a currently-parsing list of comma-separated items has ended.
///
/// An end is found when a non-comma token or the given `end_token` is encountered.
///
/// Call this at the end of every loop after encountering a comma. Dangling commas
/// are allowed and will be consumed. The given end token will not be consumed.
pub fn listEnd(self: *Parser, end_token: TokenType) bool {
    return !self.match(.comma) or self.next.is(end_token);
}

/// Returns whether a currently parsing block has ended.
///
/// An end is found when `end_token` is encountered, or we hit `.eof`.
///
/// `.eof` will be consumed if encountered, `end_token` will not.
pub fn blockEnd(self: *Parser, end_token: TokenType) bool {
    return self.match(.eof) or self.next.is(end_token);
}

/// Returns the strategy for how the given `token` is parsed/compiled.
pub fn strategy(_: *const Parser, token: Token) ParseStrategy {
    return ParseStrategy.forToken(token);
}

// Error management ===========================================================

/// Output error `msg` at the given `token`.
pub fn errAt(self: *Parser, token: Token, msg: []const u8) void {
    printf("[line {d}:{d}] Error", .{ token.line, token.column });

    if (token.is(.eof)) {
        printf(" at end", .{});
    } else if (token.is(.@"error")) {
        // No extra message needed for error tokens
    } else {
        printf(" at '{s}'", .{token.lexeme});
    }

    printf(": {s}\n", .{msg});
    self.had_error = true;
}

/// Output error `msg` at the current token being parsed.
pub fn err(self: *Parser, msg: []const u8) void {
    self.errAt(self.current, msg);
}

/// Output error `msg` at the next token to be parsed.
pub fn errAtNext(self: *Parser, msg: []const u8) void {
    self.errAt(self.next, msg);
}

/// Synchronize parser to the next valid statement boundary after encountering
/// an error.
pub fn synchronize(self: *Parser) void {
    self.panic_mode = false;

    while (self.next.isNot(.eof)) : (self.advance()) {
        if (self.current.is(.semicolon)) return;

        // zig fmt: off
        switch (self.next.type) {
            .keyword_class,
            .keyword_fun,
            .keyword_var,
            .keyword_for,
            .keyword_if,
            .keyword_switch,
            .keyword_while,
            .keyword_print,
            .keyword_return => return,
            else => break,
        }
        // zig fmt: on
    }
}
