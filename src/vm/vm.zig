const std = @import("std");
const builtin = @import("builtin");
const mem = @import("../memory/memory.zig");
const val = @import("../object/value.zig");
const debug = @import("../debug.zig");

const printf = std.debug.print;

const Chunk = @import("../compiler/chunk.zig");
const OpCode = @import("../compiler/opcode.zig").OpCode;
const Value = @import("../object/value.zig").Value;

const InterpretResult = @import("interpret_result.zig").InterpretResult;

const U8_MAX = 255;
const U8_SIZE = U8_MAX + 1;
const FRAME_MAX = 64;
const STACK_MAX = FRAME_MAX * U8_SIZE;

// ============================================================================

/// Virtual machine for interpreting lox instructions.
const Vm: type = @This();

/// Chunk of instructions currently being executed.
chunk: *Chunk,

/// Pointer to the next instruction to be executed.
ip: [*]u8,

/// Virtual machine value stack.
stack: [STACK_MAX]Value,

/// Pointer to the next slot on the vm stack.
stack_top: [*]Value,

/// Allocate a new `Vm`, returning a pointer to it.
pub fn create() !*Vm {
    const vm: *Vm = try mem.create(Vm);
    vm.stack_top = &vm.stack;
    return vm;
}

/// Destroy this `Vm`, freeing its owned resources.
pub fn destroy(self: *Vm) void {
    mem.destroy(self);
}

/// Interpret the given chunk of lox instructions
pub fn interpret(self: *Vm, chunk: *Chunk) InterpretResult {
    self.chunk = chunk;
    self.ip = chunk.instructions.items.ptr;

    return self.run();
}

/// Run instructions from the currently loaded chunk.
pub fn run(self: *Vm) InterpretResult {
    while (true) {
        if (builtin.mode == .Debug) {
            debug.printStack(&self.stack, self.stack_top);

            _ = debug.disassembleInstruction(
                self.chunk,
                // Find current instruction offset by subtracting the address of
                // the first instruction from the address of the current instruction
                @intFromPtr(self.ip) - @intFromPtr(self.chunk.instructions.items.ptr),
            );
        }

        const instruction: OpCode = .fromByte(self.readByte());

        switch (instruction) {
            .op_constant => self.push(self.readConstant()),

            .op_add => {
                const b: Value = self.pop();
                const a: Value = self.pop();
                self.push(a + b);
            },

            // .op_peek => printf("{any}\n", .{self.peek(self.readByte())}),

            .op_print => printf("{any}\n", .{self.pop()}),

            .op_return => return .interpret_ok,

            _ => return .interpret_runtime_error,
        }
    }
}

/// Read the next byte from the currently loaded chunk's instructions array.
pub fn readByte(self: *Vm) u8 {
    const result: u8 = self.ip[0];
    self.ip += 1;
    return result;
}

/// Read a constant value from the currently loaded chunk's instructions array by
/// reading the next byte, which is expected to be an offset pointing to a constant
/// value within the currently loaded chunk's constants array.
pub fn readConstant(self: *Vm) Value {
    return self.chunk.constantAt(self.readByte());
}

/// Push the given `value` to the top of the stack.
pub fn push(self: *Vm, value: Value) void {
    self.stack_top[0] = value;
    self.stack_top += 1;
}

/// Pop the value off of the top of the stack and return it.
pub fn pop(self: *Vm) Value {
    self.stack_top -= 1;
    return self.stack_top[0];
}

/// Peek at a value in the stack, offset by `distance` from the top of the stack
pub fn peek(self: *Vm, distance: usize) Value {
    return (self.stack_top - 1 - distance)[0];
}
