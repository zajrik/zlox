/// Represents the result of attempting to compile and execute a Lox program.
pub const ExecutionResult = enum {
    /// Execution was successful.
    ok,

    /// Execution was unable to begin due to an error during compilation.
    compile_error,

    /// Execution failed due to an error at runtime.
    runtime_error,
};
