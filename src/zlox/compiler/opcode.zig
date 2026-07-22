const std = @import("std");
const Writer = std.Io.Writer;

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
///
/// - `upvalue_offset`: An integer pointing to an upvalue in the closure of the
///   current callframe.
///
/// - `jump_offset`: A 2-byte integer indicating a number of instructions for a
///   jump instruction to jump over.
///
/// - `loop_offset`: A 2-byte integer indicating a number of instructions for a
///   loop instruction to jump back by.
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

    /// ### `OpCode.pop()`
    /// - Pops the top value off of the stack, discarding it.
    pop,

    /// ### `OpCode.pop_n(n: byte)`
    /// - Pops the top `n` values off of the stack, discarding them.
    pop_n,

    /// ### `OpCode.close()`
    /// - Close the upvalue capturing the local at the top of the stack and then
    ///   pop the local from the stack.
    close,

    /// ### `OpCode.copy()`
    /// - Pushes a copy of the value at the top of the stack to the top of the stack.
    copy,

    /// ### `OpCode.swap()`
    /// - Swaps the top two items on the stack.
    swap,

    /// ### `OpCode.print()`
    /// - Pops the value at the top of the stack and prints it.
    print,

    /// ### `OpCode.global_define(offset: constant_offset)`
    /// - Pops the top value off of the stack, assigning it to a global variable
    ///   with the name obtained from the constant offset operand.
    global_define,

    /// ### `OpCode.global_set(offset: constant_offset)`
    /// - Set the value of the global variable with the name obtained from the
    ///   constant offset operand to the value at the top of the stack.
    global_set,

    /// ### `OpCode.global_get(offset: constant_offset)`
    /// - Push the value of the global variable with the name obtained from the
    ///   constant offset operand to the top of the stack.
    global_get,

    /// ### `OpCode.local_set(offset: stack_offset)`
    /// - Set the value of the local variable at the stack offset obtained from
    ///   the operand to the value at the top of the stack.
    ///
    ///   The value stays at the top of the stack as the result of the assignment.
    local_set,

    /// ### `OpCode.local_get(offset: stack_offset)`
    /// - Get the value of the local variable at the stack offset obtained from
    ///   the operand, pushing it to the top of the stack.
    ///
    ///   The variable's value already exists on the stack in the slot from when it
    ///   was declared, which will be modified in-place by `.local_set` and will stay
    ///   on the stack until the local goes out of scope.
    ///
    ///   In contrast, the value we're pushing to the top of the stack here is the
    ///   result of a variable get expression and will be consumed by the enclosing
    ///   expression (or discarded at the end of a statement)
    local_get,

    /// ### `OpCode.upvalue_set(offset: upvalue_offset)`
    /// - Set the value of the upvalue at the offset obtained from the operand to
    ///   the value at the top of the stack.
    upvalue_set,

    /// ### `OpCode.upvalue_get(offset: upvalue_offset)`
    /// - Get the value of the upvalue at the offset obtained from the operand,
    ///   pushing it to the top of the stack.
    upvalue_get,

    /// ### `OpCode.jump_if_false(offset: jump_offset)`
    /// - Jump over a number of instructions obtained from the operand if the value
    ///   at the top of the stack is `false`.
    jump_if_false,

    /// ### `OpCode.jump_if_true(offset: jump_offset)`
    /// - Jump over a number of instructions obtained from the operand if the value
    ///   at the top of the stack is `true`.
    jump_if_true,

    /// ### `OpCode.jump_if_not_nil(offset: jump_offset)`
    /// - Jump over a number of instructions obtained from the operand if the value
    ///   at the top of the stack is not `nil`.
    jump_if_not_nil,

    /// ### `OpCode.jump(offset: jump_offset)`
    /// - Jump unconditionally over a number of instructions obtained from the operand.
    jump,

    /// ### `OpCode.loop(offset: loop_offset)`
    /// - Jump backwards a number of instructions obtained from the operand.
    loop,

    /// ### `OpCode.call(arg_count: byte)`
    /// - Call a function on the stack. Must be followed by an operand specifying
    ///   how many arguments are to be passed to the function.
    ///
    ///   The function value will be on the stack, followed by all of its arguments.
    call,

    /// ### `OpCode.closure(offset: constant_offset)`
    /// - Create a closure at runtime. Must be followed by an offset pointing to
    ///   the function object the closure is wrapping.
    closure,

    /// ### `OpCode.return()`
    /// - Returns the value at the top of the stack from whatever call frame
    ///   we're currently inside of.
    @"return",

    /// ### `OpCode.class(offset: constant_offset)`
    /// - Creates a class object with the identifier obtained from the operand.
    class,

    _,

    /// Convert the given byte `value` to its equivalent `OpCode` value.
    pub inline fn fromByte(value: u8) OpCode {
        return @enumFromInt(value);
    }

    /// Convert this opcode to its equivalent `u8` byte value.
    pub inline fn toByte(self: OpCode) u8 {
        return @intFromEnum(self);
    }

    /// Convert this opcode to a string representation.
    pub inline fn toString(self: OpCode) []const u8 {
        return std.fmt.comptimePrint("{any}", .{self});
    }
};
