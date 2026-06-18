/// Represents the result of attempting to interpret a series of lox instructions.
pub const InterpretResult = enum {
    interpret_ok,
    interpret_compile_error,
    interpret_runtime_error,
};
