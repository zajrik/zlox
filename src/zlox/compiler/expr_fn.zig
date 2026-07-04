const zlox = @import("../.lib.zig");

/// A pointer to a compiler function that compiles an expression from source tokens.
pub const ExprFn = *const fn (*const zlox.compiler.Compiler, bool) void;
