/// Represents the different types of heap-allocated lox objects.
pub const Type = enum(u2) {
    string,
    function,
    closure,
    native,
};
