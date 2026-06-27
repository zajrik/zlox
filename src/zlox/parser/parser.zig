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

const Token = zlox.tokenizer.Token;
const Tokenizer = zlox.tokenizer.Tokenizer;
const TokenType = zlox.tokenizer.TokenType;

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
        if (token.isNot(.@"error")) break;

        self.errorAtNext(token.lexeme);
    }
}

/// Consume a token of the given `type` from the tokenizer.
///
/// Emits error `msg` if a token of the given type is not found.
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

// Error management ===========================================================

/// Output error `msg` at the given `token`.
pub fn errorAt(self: *Parser, token: Token, msg: []const u8) void {
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

/// Output error `msg` at the current token being parsed.
pub fn @"error"(self: *Parser, msg: []const u8) void {
    self.errorAt(self.current, msg);
}

/// Output error `msg` at the next token to be parsed.
pub fn errorAtNext(self: *Parser, msg: []const u8) void {
    self.errorAt(self.next, msg);
}

/// Synchronize parser to the next valid statement boundary after encountering
/// an error.
pub fn synchronize(self: *Parser) void {
    self.panic_mode = false;

    while (!self.nextIs(.eof)) : (self.advance()) {
        if (self.currentIs(.semicolon)) return;

        // zig fmt: off
        switch (self.nextType()) {
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

/// Indicates the level of precedence with which to parse an expression.
///
/// Enum member order is significant here and reflects the actual grammar rule
/// precedence.
const Precedence = enum(u8) {
    none,
    assignment,
    @"or",
    @"and",
    equality,
    comparison,
    term,
    factor,
    unary,
    call,
    primary,

    _,

    pub fn lessThan(self: Precedence, other: Precedence) bool {
        return @intFromEnum(self) < @intFromEnum(other);
    }
};

/// Represents a specific expression grammar rule, used to signal to the compiler
/// how it should compile a given expression.
const Rule = enum {
    grouping,
    call,
    dot,
    unary,
    binary,
    nilish,
    variable,
    string,
    number,
    literal,
    andExpr,
    orExpr,
    funExpr,
    thisExpr,
};

/// Holds rules for how a given token should be parsed as part of an expression
/// based on its position and precedence.
const ParseStrategy = struct {
    token: TokenType,
    prefix: ?Rule,
    infix: ?Rule,
    precedence: Precedence,

    fn strat(comptime token: TokenType, prefix: ?Rule, infix: ?Rule, precedence: Precedence) ParseStrategy {
        return .{
            .token = token,
            .prefix = prefix,
            .infix = infix,
            .precedence = precedence,
        };
    }
};

const token_count: u8 = std.enums.values(TokenType).len;

// zig fmt: off
const strategies = [token_count]ParseStrategy{
    .strat(.paren_left,      .grouping,      null,         .call             ),
    .strat(.paren_right,     null,           null,         .none             ),
    .strat(.brace_left,      null,           null,         .none             ),
    .strat(.brace_right,     null,           null,         .none             ),
    .strat(.comma,           null,           null,         .none             ),
    .strat(.dot,             null,           null,         .call             ),
    .strat(.semicolon,       null,           null,         .none             ),
    .strat(.question,        null,           null,         .none             ),
    .strat(.colon,           null,           null,         .none             ),

    .strat(.minus,           .unary,         .binary,      .term             ),
    .strat(.plus,            null,           .binary,      .term             ),
    .strat(.slash,           null,           .binary,      .factor           ),
    .strat(.star,            null,           .binary,      .factor           ),

    // Multi-character token rules
    .strat(.bang,            .unary,         null,         .none             ),
    .strat(.bang_equal,      null,           null,         .none             ),
    .strat(.equal,           null,           null,         .none             ),
    .strat(.equal_equal,     null,           null,         .none             ),
    .strat(.greater,         null,           null,         .none             ),
    .strat(.greater_equal,   null,           null,         .none             ),
    .strat(.less,            null,           null,         .none             ),
    .strat(.less_equal,      null,           null,         .none             ),
    .strat(.plus_equal,      null,           null,         .none             ),
    .strat(.minus_equal,     null,           null,         .none             ),
    .strat(.star_equal,      null,           null,         .none             ),
    .strat(.slash_equal,     null,           null,         .none             ),
    .strat(.arrow,           null,           null,         .none             ),
    .strat(.nilish,          null,           null,         .none             ),
    .strat(.nilish_equal,    null,           null,         .none             ),

    // Literals
    .strat(.identifier,      null,           null,         .none             ),
    .strat(.string,          null,           null,         .none             ),
    .strat(.number,          null,           null,         .none             ),

    // Keywords
    .strat(.keyword_and,     null,           null,         .none             ),
    .strat(.keyword_case,    null,           null,         .none             ),
    .strat(.keyword_class,   null,           null,         .none             ),
    .strat(.keyword_default, null,           null,         .none             ),
    .strat(.keyword_else,    null,           null,         .none             ),
    .strat(.keyword_false,   null,           null,         .none             ),
    .strat(.keyword_for,     null,           null,         .none             ),
    .strat(.keyword_fun,     null,           null,         .none             ),
    .strat(.keyword_if,      null,           null,         .none             ),
    .strat(.keyword_nil,     null,           null,         .none             ),
    .strat(.keyword_or,      null,           null,         .none             ),
    .strat(.keyword_print,   null,           null,         .none             ),
    .strat(.keyword_return,  null,           null,         .none             ),
    .strat(.keyword_super,   null,           null,         .none             ),
    .strat(.keyword_switch,  null,           null,         .none             ),
    .strat(.keyword_this,    null,           null,         .none             ),
    .strat(.keyword_true,    null,           null,         .none             ),
    .strat(.keyword_var,     null,           null,         .none             ),
    .strat(.keyword_while,   null,           null,         .none             ),

    // Special
    .strat(.@"error",        null,           null,         .none             ),
    .strat(.eof,             null,           null,         .none             ),

};
// zig fmt: on

pub fn getStrategyFor(token: TokenType) void {
    return strategies[@intFromEnum(token)];
}

// Verify parsing strategies are correctly ordered for indexing by token
// and that none are missing from the table
comptime {
    for (strategies, 0..) |strat, actual_index| {
        const expected_index: u8 = @intFromEnum(strat.token);

        if (actual_index == expected_index) continue;

        const msg: []const u8 = std.fmt.comptimePrint(
            "Parsing strategy '{s}' out of order. Expected {d}, got {d}",
            .{ @tagName(strat.token), expected_index, actual_index },
        );
        @compileError(msg);
    }
}
