//! A chunk of compiled lox instructions and constant values.

const std = @import("std");
const zlox = @import("../.lib.zig");

const mem = zlox.mem;

const ArrayList = std.ArrayList;

const OpCode = zlox.compiler.OpCode;
const Value = zlox.object.Value;

const exit = std.process.exit;

// ============================================================================

const Chunk: type = @This();

/// Compiled instruction opcodes and operands.
instructions: ArrayList(u8),

/// Compiled line data for instructions in this chunk.
///
/// Mirrors `instructions` layout where an instruction offset will map to the
/// line number of that instruction.
lines: ArrayList(u16),

/// Compiled constant values in this chunk.
constants: ArrayList(Value),

/// Allocate a new `Chunk` instance on the heap, returning a pointer to it.
///
/// The caller owns the returned pointer and is responsible for freeing it.
pub fn create() !*Chunk {
    return try mem.createStruct(Chunk, .{
        .instructions = .empty,
        .lines = .empty,
        .constants = .empty,
    });
}

/// Destroy this `Chunk`, freeing its owned resources.
pub fn destroy(self: *Chunk) void {
    defer mem.destroy(self);
    self.instructions.deinit(mem.allocator());
    self.lines.deinit(mem.allocator());

    // Free compile-time constant objs
    for (self.constants.items) |constant| {
        if (constant.is(.obj)) constant.obj.destroy();
    }
    self.constants.deinit(mem.allocator());
}

/// Returns whether this chunk has any instructions to execute.
pub fn isEmpty(self: *Chunk) bool {
    return self.instructions.items.len == 0;
}

/// Returns the instruction at the given offset.
pub inline fn instructionAt(self: *Chunk, offset: usize) u8 {
    return self.instructions.items[offset];
}

/// Returns the line number at the given offset.
pub inline fn lineAt(self: *Chunk, offset: usize) u16 {
    return self.lines.items[offset];
}

/// Returns the constant value at the given offset.
pub inline fn constantAt(self: *Chunk, offset: usize) Value {
    return self.constants.items[offset];
}

/// Write the given `byte` to this chunk.
pub fn writeByte(self: *Chunk, byte: u8, line: u16) void {
    errdefer exit(1);
    try self.instructions.append(mem.allocator(), byte);
    try self.lines.append(mem.allocator(), line);
}

/// Add the given constant `value` to this chunk's constants array.
///
/// Returns the offset of the added value within this chunk's constants array.
pub fn addConstant(self: *Chunk, value: Value) u8 {
    self.constants.append(mem.allocator(), value) catch exit(1);
    return @as(u8, @truncate(self.constants.items.len)) - 1;
}

/// Find the constant offset of the given `value` if it exists within this chunk's
/// constants array.
///
/// Returns `null` if the constant does not already exist.
pub fn findConstant(self: *Chunk, value: Value) ?u8 {
    for (self.constants.items, 0..) |constant, offset| {
        if (constant.equals(value)) return @as(u8, @truncate(offset));
    }
    return null;
}
