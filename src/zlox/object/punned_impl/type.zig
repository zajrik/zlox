/// Represents the different types of heap-allocated lox objects.
pub const Type = enum(u2) {
    native,
    function,
    string,
};
