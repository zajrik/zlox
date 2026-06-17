const std = @import("std");
const mem = @import("../memory/memory.zig");
const val = @import("../object/value.zig");

const Chunk = @import("../compiler/chunk.zig");
const OpCode = @import("../compiler/opcode.zig").OpCode;
const InterpretResult = @import("interpret_result.zig").InterpretResult;
const Value = @import("../object/value.zig").Value;

const printf = std.debug.print;

/// Virtual machine for interpreting lox instructions.
const Vm: type = @This();

chunk: *Chunk,
ip: usize,

/// Allocate a new [Chunk], returning a pointer to it.
pub fn new() !*Vm {
    const vm: *Vm = try mem.create(Vm);
    return vm;
}

pub fn interpret(self: *Vm, chunk: *Chunk) InterpretResult {
    self.chunk = chunk;
    self.ip = 0;

    return self.run();
}

pub fn run(self: *Vm) InterpretResult {
    while (true) {
        const instruction: OpCode = @enumFromInt(self.readByte());
        switch (instruction) {
            .op_constant => {
                const constant: Value = self.readConstant();
                val.print(constant);
                printf("\n", .{});
            },
            .op_return => return .interpret_ok,

            _ => return .interpret_runtime_error,
        }
    }
}

pub fn readByte(self: *Vm) u8 {
    const result: u8 = self.chunk.instruction(self.ip);
    self.ip += 1;
    return result;
}

pub fn readConstant(self: *Vm) Value {
    return self.chunk.constant(self.readByte());
}
