/// Indicates the level of precedence with which to parse an expression.
///
/// Enum member order is significant here and reflects the actual grammar rule
/// precedence.
pub const Precedence = enum(u8) {
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

    /// Returns whether `other` is less than this precedence level.
    pub fn lessThan(self: Precedence, other: Precedence) bool {
        return @intFromEnum(self) < @intFromEnum(other);
    }

    /// Returns the next precedence level above this.
    pub fn next(self: Precedence) Precedence {
        return @enumFromInt(@intFromEnum(self) + 1);
    }
};
