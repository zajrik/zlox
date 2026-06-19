const std = @import("std");
const mem = @import("memory/memory.zig");
const debug = @import("debug.zig");

const Chunk = @import("compiler/chunk.zig");
const OpCode = @import("compiler/opcode.zig").OpCode;
const Vm = @import("vm/vm.zig");

// ============================================================================

pub fn main() !void {
    defer mem.deinitAllocator();

    const chunk: *Chunk = try .create();
    defer chunk.destroy();

    chunk.writeOp1(.op_constant, 1, chunk.addConstant(10));
    chunk.writeOp1(.op_constant, 2, chunk.addConstant(23));

    chunk.writeOp(.op_swap, 3);
    chunk.writeOp(.op_subtract, 3);
    chunk.writeOp(.op_negate, 3);
    chunk.writeOp(.op_print, 4);
    chunk.writeOp(.op_return, 5);

    debug.disassembleChunk(chunk, "test chunk");

    const vm: *Vm = try .create();
    defer vm.destroy();

    _ = vm.interpret(chunk);
}
