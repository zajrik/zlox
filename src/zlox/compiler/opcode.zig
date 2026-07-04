/// Enum of instruction opcodes to be executed by the lox virtual machine.
///
/// ## Opcode instruction format documentation syntax:
///
/// ### `OpCode.name(operand1: type, operand2: type, ...)`
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
    /// ### `OpCode.constant(offset: constant_offset)`
    /// - Loads a constant value at the given `offset` onto the stack.
    constant,

    /// ### `OpCode.nil()`
    /// - Loads the constant value `nil` onto the stack.
    nil,

    /// ### `OpCode.true()`
    /// - Loads the constant value `true` onto the stack.
    true,

    /// ### `OpCode.false()`
    /// - Loads the constant value `false` onto the stack.
    false,

    /// ### `OpCode.equal()`
    /// - Pops the top two values off the stack, compares them, and pushes the
    ///   result to the top of the stack.
    equal,

    /// ### `OpCode.greater()`
    /// - Pops the top two values off the stack, compares them, and pushes the
    ///   result to the top of the stack.
    greater,

    /// ### `OpCode.less()`
    /// - Pops the top two values off the stack, compares them, and pushes the
    ///   result to the top of the stack.
    less,

    /// ### `OpCode.add()`
    /// - Pops the top two values off the stack, adds them, and pushes the result
    ///   to the top of the stack.
    add,

    /// ### `OpCode.subtract()`
    /// - Pops the top two values off the stack, subtracts them, and pushes the
    ///   result to the top of the stack.
    subtract,

    /// ### `OpCode.multiply()`
    /// - Pops the top two values off the stack, multiplies them, and pushes the
    ///   result to the top of the stack.
    multiply,

    /// ### `OpCode.divide()`
    /// - Pops the top two values off the stack, divides them, and pushes the result
    ///   to the top of the stack.
    divide,

    /// ### `OpCode.negate()`
    /// - Pops the top numerical value off the stack, negates it, and pushes the
    ///   result to the top of the stack.
    negate,

    /// ### `OpCode.not()`
    /// - Pops the top boolean value off the stack, negates it, and pushes the
    ///   result to the top of the stack.
    not,

    // /// ### `OpCode.peek(offset: stack_offset)`
    // /// - Prints the value on the stack at the given `offset` from the top of
    // ///   the stack.
    // peek,

    /// ### `OpCode.pop()`
    /// - Pops the top value off of the stack, discarding it.
    pop,

    /// ### `OpCode.pop_n(n: byte)`
    /// - Pops the top `n` values off of the stack, discarding them.
    pop_n,

    /// ### `OpCode.copy()`
    /// - Pushes a copy of the value at the top of the stack to the top of the stack.
    copy,

    /// ### `OpCode.swap()`
    /// - Swaps the top two items on the stack.
    swap,

    /// ### `OpCode.print()`
    /// - Pops the value at the top of the stack and prints it.
    print,

    /// ### `OpCode.global_define(offset: constant_offset)
    /// - Pops the top value off of the stack, assigning it to a global variable
    ///   with the name obtained from the constant offset operand.
    global_define,

    /// ### `OpCode.global_set(offset: constant_offset)
    /// - Set the value of the global variable with the name obtained from the
    ///   constant offset operand to the value at the top of the stack, popping
    ///   the value from the stack.
    global_set,

    /// ### `OpCode.global_get(offset: constant_offset)
    /// - Push the value of the global variable with the name obtained from the
    ///   constant offset operand to the top of the stack.
    global_get,

    /// ### `OpCode.return()`
    /// - Returns the value at the top of the stack from whatever call frame
    ///   we're currently inside of.
    @"return",

    _,

    /// Convert the given byte `value` to its equivalent `OpCode` value.
    pub inline fn fromByte(value: u8) OpCode {
        return @enumFromInt(value);
    }

    /// Convert this opcode to its equivalent `u8` byte value.
    pub inline fn toByte(self: OpCode) u8 {
        return @intFromEnum(self);
    }
};
