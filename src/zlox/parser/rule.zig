/// Represents a specific expression grammar rule, used to signal to the compiler
/// how it should compile a given expression.
pub const Rule = enum {
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
