const std = @import("std");
const mem = @import("memory.zig");
const debug = @import("debug.zig");

const Chunk = @import("compiler/chunk.zig");
const OpCode = @import("compiler/opcode.zig").OpCode;
const Stack = @import("vm/stack.zig").Stack;
const Tokenizer = @import("compiler/tokenizer.zig");
const Value = @import("object/value.zig").Value;
const Vm = @import("vm/vm.zig");

// ============================================================================

pub fn main() !void {
    defer mem.deinitAllocator();

    const chunk: *Chunk = try .create();
    defer chunk.destroy();

    chunk.writeOp1(.op_constant, 1, chunk.addConstant(5));
    chunk.writeOp1(.op_constant, 2, chunk.addConstant(20));

    chunk.writeOp(.op_swap, 3);
    chunk.writeOp(.op_subtract, 3);
    chunk.writeOp(.op_negate, 3);
    chunk.writeOp(.op_print, 4);
    chunk.writeOp(.op_return, 5);

    debug.disassembleChunk(chunk, "test chunk");

    const vm: *Vm = try .create();
    defer vm.destroy();

    _ = vm.interpret(chunk);

    var tokenizer = Tokenizer.init("foo bar baz");
    while (!tokenizer.isAtEnd()) : (_ = tokenizer.advance()) {
        std.debug.print("{c}", .{tokenizer.peek()});
    }
}
