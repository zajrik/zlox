const std = @import("std");
const zlox = @import("zlox/.lib.zig");

const mem = zlox.mem;
const debug = zlox.debug;

const Io = std.Io;
const Dir = std.Io.Dir;

const Chunk = zlox.compiler.Chunk;
const OpCode = zlox.compiler.OpCode;
const ExecutionResult = zlox.vm.ExecutionResult;
const Stack = zlox.vm.Stack;
const Tokenizer = zlox.tokenizer.Tokenizer;
const Value = zlox.object.Value;
const Vm = zlox.vm.Vm;

// ============================================================================

pub fn main(init: std.process.Init) !void {
    mem.initArena(init.arena);
    defer mem.freeObjects();

    const lox_code: []u8 = try readFile(init.io, "test/test.lox");
    defer mem.free(lox_code);

    var tokenizer: Tokenizer = .init(lox_code);
    while (tokenizer.next()) |token| std.debug.print("{f}\n", .{token});

    const vm: *Vm = try .create();
    defer vm.destroy();

    const result: ExecutionResult = vm.interpret(lox_code);
    std.debug.print("{}\n", .{result});
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
