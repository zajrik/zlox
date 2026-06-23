//! Virtual machine for executing lox instructions.

const std = @import("std");
const builtin = @import("builtin");

const debug = @import("../debug.zig");
const mem = @import("../memory.zig");
const val = @import("../object/value.zig");

const printf = std.debug.print;

const Chunk = @import("../compiler/chunk.zig");
const ExecutionResult = @import("execution_result.zig").ExecutionResult;
const OpCode = @import("../compiler/opcode.zig").OpCode;
const Stack = @import("stack.zig").Stack;
const Value = @import("../object/value.zig").Value;

// ============================================================================

const Vm: type = @This();

/// Chunk of instructions currently being executed.
chunk: *Chunk,

/// Pointer to the next instruction to be executed.
ip: [*]u8,

/// Virtual machine value stack.
stack: Stack(Value),

/// Allocate a new `Vm` instance on the heap, returning a pointer to it.
///
/// The caller owns the returned pointer and is responsible for freeing it.
pub fn create() !*Vm {
    const vm: *Vm = try mem.create(Vm);
    vm.stack.reset();
    return vm;
}

/// Destroy this `Vm`, freeing its owned resources.
pub fn destroy(self: *Vm) void {
    mem.destroy(self);
}

/// Interpret the given chunk of lox instructions
pub fn interpret(self: *Vm, chunk: *Chunk) ExecutionResult {
    self.chunk = chunk;
    self.ip = chunk.instructions.items.ptr;

    return self.run();
}

/// Run instructions from the currently loaded chunk.
pub fn run(self: *Vm) ExecutionResult {
    while (true) {
        if (builtin.mode == .Debug) {
            debug.printStack(&self.stack);

            _ = debug.disassembleInstruction(
                self.chunk,
                // Find next instruction offset by subtracting the address of
                // the first instruction from the address of the next instruction
                @intFromPtr(self.ip) - @intFromPtr(self.chunk.instructions.items.ptr),
            );
        }

        const instruction: OpCode = .fromByte(self.readByte());

        switch (instruction) {
            .op_constant => self.stack.push(self.readConstant()),

            // Arithmetic ops
            .op_add => {
                const b: Value = self.stack.pop();
                const a: Value = self.stack.pop();
                self.stack.push(a + b);
            },
            .op_subtract => {
                const b: Value = self.stack.pop();
                const a: Value = self.stack.pop();
                self.stack.push(a - b);
            },
            .op_multiply => {
                const b: Value = self.stack.pop();
                const a: Value = self.stack.pop();
                self.stack.push(a * b);
            },
            .op_divide => {
                const b: Value = self.stack.pop();
                const a: Value = self.stack.pop();
                self.stack.push(a / b);
            },
            .op_negate => _ = self.stack.replace(0, -self.stack.peek(0)),

            // Stack ops
            // .op_peek => printf("{any}\n", .{self.stack.peek(self.readByte())}),
            .op_pop => _ = self.stack.pop(),
            .op_pop_n => self.stack.popN(self.readByte()),
            .op_copy => self.stack.push(self.stack.peek(0)),
            .op_swap => {
                const b: Value = self.stack.pop();
                const a: Value = self.stack.pop();
                self.stack.push(b);
                self.stack.push(a);
            },

            .op_print => printf("{any}\n", .{self.stack.pop()}),

            .op_return => return .ok,

            _ => return .runtime_error,
        }
    }
}

/// Read the next byte from the currently loaded chunk's instructions array.
pub fn readByte(self: *Vm) u8 {
    self.ip += 1;
    return (self.ip - 1)[0];
}

/// Read the next two bytes from the currenty loaded chunk's instructions array,
/// treating them as a single 16-bit value.
pub fn readShort(self: *Vm) u16 {
    self.ip += 2;
    return (self.ip - 2)[0] << 8 | (self.ip - 1)[0];
}

/// Read a constant value from the currently loaded chunk's instructions array by
/// reading the next byte, which is expected to be an offset pointing to a constant
/// value within the currently loaded chunk's constants array.
pub fn readConstant(self: *Vm) Value {
    return self.chunk.constantAt(self.readByte());
}
