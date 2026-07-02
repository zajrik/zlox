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

const HashTable = zlox.object.HashTable;

// ============================================================================

pub fn main(init: std.process.Init) !void {
    mem.initArena(init.arena);

    const lox_code: []u8 = try readFile(init.io, "test/test.lox");
    defer mem.free(lox_code);

    var tokenizer: Tokenizer = .init(lox_code);
    while (tokenizer.next()) |token| std.debug.print("{f}\n", .{token});

    const vm: *Vm = try .create();
    defer vm.destroy();

    const result: ExecutionResult = vm.interpret(lox_code);
    std.debug.print("{}\n", .{result});

    const table = try HashTable.create();
    const str_1 = try vm.copyString("aaa");
    const str_2 = try vm.copyString("bbb");
    defer table.destroy();

    _ = table.set(str_1, .Number(420));
    _ = table.set(str_2, .Number(69));

    std.debug.print("{?f} {?f}\n", .{ table.get(str_1), table.get(str_2) });

    std.debug.print("{any}\n", .{table.entries});
    std.debug.print("{any}\n", .{table.entries.len});

    _ = table.set(str_2, .Number(420));
    _ = table.set(str_1, .Number(69));

    std.debug.print("{?f} {?f}\n", .{ table.get(str_1), table.get(str_2) });

    for (table.entries) |entry| std.debug.print("{f}, ", .{entry});
    std.debug.print("{d}\n", .{table.entries.len});
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
