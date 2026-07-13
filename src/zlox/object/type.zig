/// Represents the different types of heap-allocated lox objects.
pub const Type = enum(u3) {
    string,
    function,
    closure,
    native,
    upvalue,
};
