const std = @import("std");
const mem = @import("memory.zig");
const debug = @import("debug.zig");

const Io = std.Io;
const Dir = std.Io.Dir;

const Chunk = @import("compiler/chunk.zig");
const OpCode = @import("compiler/opcode.zig").OpCode;
const Stack = @import("vm/stack.zig").Stack;
const Tokenizer = @import("compiler/tokenizer.zig");
const Value = @import("object/value.zig").Value;
const Vm = @import("vm/vm.zig");

// ============================================================================

pub fn main(init: std.process.Init) !void {
    mem.init(init.arena);

    // const chunk: *Chunk = try .create();
    // defer chunk.destroy();

    // chunk.writeOp1(.op_constant, 1, chunk.addConstant(5));
    // chunk.writeOp1(.op_constant, 2, chunk.addConstant(20));

    // chunk.writeOp(.op_swap, 3);
    // chunk.writeOp(.op_subtract, 3);
    // chunk.writeOp(.op_negate, 3);
    // chunk.writeOp(.op_print, 4);
    // chunk.writeOp(.op_return, 5);

    // debug.disassembleChunk(chunk, "test chunk");

    // const vm: *Vm = try .create();
    // defer vm.destroy();

    // _ = vm.interpret(chunk);

    const lox_code: []u8 = try readFile(init.io, "test/test.lox");
    defer mem.free(lox_code);

    var tokenizer = Tokenizer.init(lox_code);
    while (!tokenizer.isAtEnd()) {
        std.debug.print("{f}\n", .{tokenizer.consumeToken()});
    }
}

/// Read the contents of the file at the given `path` using the given `Io` implementation.
///
/// Returns a slice containing the characters in the file. The caller owns this
/// slice and is responsible for freeing it.
pub fn readFile(io: Io, path: []const u8) ![]u8 {
    return try Dir.readFileAlloc(
        Dir.cwd(),
        io,
        path,
        mem.allocator(),
        .unlimited,
    );
}
