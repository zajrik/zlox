/// Enum of instruction opcodes to be executed by the lox virtual machine.
///
/// ## Opcode instruction format documentation syntax:
///
/// ### `op_name(operand1: type, operand2: type, ...)`
///
/// ### Operand byte types:
///
/// - `byte`: A single-byte value (8 bits).
///
/// - `short`: A two-byte value (16 bits), encoded as two individual bytes.
///
/// - `constant_offset`: An integer offset pointing to a value within a chunk's
///   constants array.
///
/// - `stack_offset`: An integer pointing to a value on the stack, offset from the
///   top of the stack. A stack offset of `0` points to the top of the stack, `1`
///   to the item below that, etc.
pub const OpCode = enum(u8) {
    /// ### `op_constant(offset: constant_offset)`
    /// - Loads a constant value at the given `offset` onto the stack.
    op_constant,

    /// ### `op_add()`
    /// - Pops the top two values off the stack, adds them, and pushes the result
    ///   to the top of the stack.
    op_add,

    /// ### `op_subtract()`
    /// - Pops the top two values off the stack, subtracts them, and pushes the
    ///   result to the top of the stack.
    op_subtract,

    /// ### `op_multiply()`
    /// - Pops the top two values off the stack, multiplies them, and pushes the
    ///   result to the top of the stack.
    op_multiply,

    /// ### `op_divide()`
    /// - Pops the top two values off the stack, divides them, and pushes the result
    ///   to the top of the stack.
    op_divide,

    /// ### `op_negate()`
    /// - Pops the top value off the stack, negates it, and pushes the result to
    ///   the top of the stack.
    op_negate,

    // /// ### `op_peek(offset: stack_offset)`
    // /// - Prints the value on the stack at the given `offset` from the top of
    // ///   the stack.
    // op_peek,

    /// ### `op_pop()`
    /// - Pops the top value off of the stack, discarding it.
    op_pop,

    /// ### `op_pop_n(n: byte)`
    /// - Pops the top `n` values off of the stack, discarding them.
    op_pop_n,

    /// ### `op_copy()`
    /// - Pushes a copy of the value at the top of the stack to the top of the stack.
    op_copy,

    /// ### `op_swap()`
    /// - Swaps the top two items on the stack.
    op_swap,

    /// ### `op_print()`
    /// - Pops the value at the top of the stack and prints it.
    op_print,

    /// ### `op_return()`
    /// - Returns the value at the top of the stack from whatever call frame
    ///   we're currently inside of.
    op_return,

    _,

    /// Convert the given byte `value` to its equivalent `OpCode` value.
    pub fn fromByte(value: u8) OpCode {
        return @enumFromInt(value);
    }

    /// Convert this opcode to its equivalent `u8` byte value.
    pub fn toByte(self: OpCode) u8 {
        return @intFromEnum(self);
    }
};
