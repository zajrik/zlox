/// Enum of instruction opcodes to be executed by the lox virtual machine.
///
/// ## Opcode instruction format documentation syntax:
///
/// ### `op_name(operand1: type, operand2: type, ...)`
pub const OpCode = enum(u8) {
    /// ### `op_constant(offset: constant_offset)`
    /// - Loads a constant value at the given `offset` onto the stack.
    op_constant,

    /// ### `op_return()`
    /// - Returns the value at the top of the stack from whatever call frame
    ///   we're currently inside of.
    op_return,

    _,

    /// Return this opcode as a byte value.
    pub fn byte(self: OpCode) u8 {
        return @intFromEnum(self);
    }

    /// Convert the given byte [value] to its equivalent [OpCode] value.
    pub fn fromByte(value: u8) OpCode {
        return @enumFromInt(value);
    }
};
