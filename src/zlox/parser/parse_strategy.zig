//! Indicates how a given token is to be treated depending on its position in
//! an expression (prefix or infix).
//!
//! Links the compiler methods for compiling an expression beginning with that
//! token in that position.

const std = @import("std");
const zlox = @import("../.lib.zig");

const Compiler = zlox.compiler.Compiler;
const ExprFn = zlox.compiler.ExprFn;

const grouping = Compiler.grouping;
const string = Compiler.string;
const number = Compiler.number;
const literal = Compiler.literal;
const variable = Compiler.variable;
const unary = Compiler.unary;
const binary = Compiler.binary;
const orExpr = Compiler.orExpr;
const andExpr = Compiler.andExpr;
const switchExpr = Compiler.switchExpr;
const funExpr = Compiler.funExpr;
const call = Compiler.call;

const Token = zlox.tokenizer.Token;
const TokenType = zlox.tokenizer.TokenType;
const Precedence = zlox.parser.Precedence;

// ============================================================================

const ParseStrategy: type = @This();

token: TokenType,
prefix: ?ExprFn,
infix: ?ExprFn,
precedence: Precedence,

/// Creates a `ParseStrategy` from the given parameters.
fn strat(
    comptime token: TokenType,
    comptime prefix: ?ExprFn,
    comptime infix: ?ExprFn,
    comptime precedence: Precedence,
) ParseStrategy {
    return .{
        .token = token,
        .prefix = prefix,
        .infix = infix,
        .precedence = precedence,
    };
}

/// Returns the `ParseStrategy` for the given `token`.
pub fn forToken(token: Token) ParseStrategy {
    return strategies[@intFromEnum(token.type)];
}

// zig fmt: off
const token_count: u8 = std.enums.values(TokenType).len;
const strategies: [token_count]ParseStrategy = .{
    strat(.paren_left,       grouping,   call,     .call      ),
    strat(.paren_right,      null,       null,     .none      ),
    strat(.brace_left,       null,       null,     .none      ),
    strat(.brace_right,      null,       null,     .none      ),
    strat(.comma,            null,       null,     .none      ),
    strat(.dot,              null,       null,     .call      ),
    strat(.semicolon,        null,       null,     .none      ),
    strat(.question,         null,       null,     .none      ),
    strat(.colon,            null,       null,     .none      ),

    strat(.minus,            unary,      binary,   .term      ),
    strat(.plus,             null,       binary,   .term      ),
    strat(.slash,            null,       binary,   .factor    ),
    strat(.star,             null,       binary,   .factor    ),

    // Multi-character token rules
    strat(.bang,             unary,      null,     .none      ),
    strat(.bang_equal,       null,       binary,   .equality  ),
    strat(.equal,            null,       null,     .none      ),
    strat(.equal_equal,      null,       binary,   .equality  ),
    strat(.greater,          null,       binary,   .comparison),
    strat(.greater_equal,    null,       binary,   .comparison),
    strat(.less,             null,       binary,   .comparison),
    strat(.less_equal,       null,       binary,   .comparison),
    strat(.plus_equal,       null,       null,     .none      ),
    strat(.minus_equal,      null,       null,     .none      ),
    strat(.star_equal,       null,       null,     .none      ),
    strat(.slash_equal,      null,       null,     .none      ),
    strat(.arrow,            null,       null,     .none      ),
    strat(.nilish,           null,       null,     .none      ),
    strat(.nilish_equal,     null,       null,     .none      ),

    // Literals
    strat(.identifier,       variable,   null,     .none      ),
    strat(.string,           string,     null,     .none      ),
    strat(.number,           number,     null,     .none      ),

    // Keywords
    strat(.keyword_and,      null,       andExpr,  .@"and"    ),
    strat(.keyword_break,    null,       null,     .none      ),
    strat(.keyword_case,     null,       null,     .none      ),
    strat(.keyword_class,    null,       null,     .none      ),
    strat(.keyword_default,  null,       null,     .none      ),
    strat(.keyword_else,     null,       null,     .none      ),
    strat(.keyword_false,    literal,    null,     .none      ),
    strat(.keyword_for,      null,       null,     .none      ),
    strat(.keyword_fun,      funExpr,    null,     .none      ),
    strat(.keyword_if,       null,       null,     .none      ),
    strat(.keyword_nil,      literal,    null,     .none      ),
    strat(.keyword_or,       null,       orExpr,   .@"or"     ),
    strat(.keyword_print,    null,       null,     .none      ),
    strat(.keyword_return,   null,       null,     .none      ),
    strat(.keyword_super,    null,       null,     .none      ),
    strat(.keyword_switch,   switchExpr, null,     .none      ),
    strat(.keyword_this,     null,       null,     .none      ),
    strat(.keyword_true,     literal,    null,     .none      ),
    strat(.keyword_var,      null,       null,     .none      ),
    strat(.keyword_while,    null,       null,     .none      ),

    // Special
    strat(.eof,              null,       null,     .none      ),
    strat(.@"error",         null,       null,     .none      ),

};
// zig fmt: on

// Ensure parsing strategies are correctly ordered for indexing by token
comptime {
    for (strategies, 0..) |strategy, actual_index| {
        const expected_index: u8 = @intFromEnum(strategy.token);

        if (actual_index == expected_index) continue;

        @compileError(std.fmt.comptimePrint(
            "Parsing strategy '{s}' out of order. Expected {d}, got {d}",
            .{ @tagName(strategy.token), expected_index, actual_index },
        ));
    }
}
