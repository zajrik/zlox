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

const Token = zlox.compiler.Token;
const Tokenizer = zlox.compiler.Tokenizer;
const TokenType = zlox.compiler.TokenType;

const printf = std.debug.print;

// ============================================================================

const Parser: type = @This();

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
    const parser: *Parser = try mem.createStruct(Parser, .{ .tokenizer = tokenizer });

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
        if (token.type == .@"error") break;
        // self.parser.errorAtNext();
    }
}

/// Consume a token of the given `type` from the tokenizer
pub fn consume(self: *Parser, @"type": TokenType, msg: []const u8) void {
    if (self.nextIs(@"type")) return self.advance();
    self.errorAtNext(msg);
}

/// Returns the `TokenType` of the current token to be parsed.
pub fn currentType(self: *Parser) TokenType {
    return self.current.type;
}

/// Returns whether the current token to be parsed is of `type`.
pub fn currentIs(self: *Parser, @"type": TokenType) bool {
    return self.currentType() == @"type";
}

/// Returns the `TokenType` of the next token to be parsed.
pub fn nextType(self: *Parser) TokenType {
    return self.next.type;
}

/// Returns whether the next token to be parsed is of `type`.
pub fn nextIs(self: *Parser, @"type": TokenType) bool {
    return self.nextType() == @"type";
}

/// Returns whether the next token to be parsed is of `type`.
///
/// If it is, the token will be consumed and the next token will be fetched from
/// the tokenizer.
pub fn nextMatches(self: *Parser, @"type": TokenType) bool {
    if (!self.nextIs(@"type")) return false;
    self.advance();
    return true;
}

/// Returns whether the given tokens have the same identifier lexemes.
pub fn identifiersEqual(a: Token, b: Token) bool {
    return std.mem.eql(u8, a.lexeme, b.lexeme);
}

pub fn @"error"(self: *Parser, msg: []const u8) void {
    self.errorAt(self.current, msg);
}

pub fn errorAt(self: *Parser, token: *Token, msg: []const u8) void {
    printf("[line {d}:{d}] Error", .{ token.line, token.column });

    if (token.is(.eof)) {
        printf(" at end", .{});
    } else if (token.is(.@"error")) {
        // No extra message needed for errors
    } else {
        printf(" at '{s}'", .{token.lexeme});
    }

    printf(": {s}\n", .{msg});
    self.had_error = true;
}
