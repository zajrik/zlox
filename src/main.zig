const std = @import("std");
const mem = @import("memory/memory.zig");
const debug = @import("debug.zig");

const Chunk = @import("compiler/chunk.zig");
const OpCode = @import("compiler/opcode.zig").OpCode;
const Vm = @import("vm/vm.zig");

pub fn main() !void {
    const chunk: *Chunk = try .new();
    defer chunk.destroy();

    const constantOffset = chunk.addConstant(1.2);

    chunk.writeOp(.op_constant, 123);
    chunk.writeByte(constantOffset, 123);
    chunk.writeOp(.op_return, 123);

    debug.disassembleChunk(chunk, "test chunk");
    const vm: *Vm = try .new();
    _ = vm.interpret(chunk);
}
