const std = @import("std");
const zlox = @import("zlox/.lib.zig");

const mem = zlox.mem;
const debug = zlox.debug;

const Io = std.Io;
const Dir = std.Io.Dir;

const ExecutionResult = zlox.vm.ExecutionResult;
const Vm = zlox.vm.Vm;

// =============================================================================

pub fn main(init: std.process.Init) !void {
    mem.initArena(init.arena);

    const lox_code: []u8 = try readFile(init.io, "test/test.lox");
    const vm: *Vm = try .create(init.io);

    defer mem.free(lox_code);
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

test "main" {
    mem.init(std.testing.allocator);

    const lox_code: []u8 = try readFile(std.testing.io, "test/test.lox");
    const vm: *Vm = try .create(std.testing.io);

    defer mem.free(lox_code);
    defer vm.destroy();

    const result: ExecutionResult = vm.interpret(lox_code);
    std.debug.print("{}\n", .{result});
}
