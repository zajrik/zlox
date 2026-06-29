//! Struct mapping a `ParseStrategy` for a given expression token to the compilation
//! phase.

const zlox = @import("../.lib.zig");

const ExprFn = zlox.compiler.ExprFn;
const Precedence = zlox.parser.Precedence;

// ============================================================================

const CompileStrategy: type = @This();

/// Pointer to the function for compiling this expression token in prefix position.
prefix: ?ExprFn,

/// Pointer to the function for compiling this expression token in infix position.
infix: ?ExprFn,

/// The precedence this expression was parsed with
precedence: Precedence,
