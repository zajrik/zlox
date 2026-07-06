/// Represents a specific expression grammar rule, used to signal to the compiler
/// how it should compile a given expression.
pub const Rule = enum {
    grouping,
    number,
    string,
    literal,
    variable,
    unary,
    binary,
    @"or",
    @"and",
    call,
    dot,
    nilish,
    funExpr,
    @"switch",
    thisExpr,
};
