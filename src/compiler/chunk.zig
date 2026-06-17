const std = @import("std");
const mem = @import("../memory/memory.zig");

const OpCode = @import("opcode.zig").OpCode;
const Value = @import("../object/value.zig").Value;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const exit = std.process.exit;

/// A chunk of compiled lox instructions and constant values.
const Chunk: type = @This();

/// Compiled instruction opcodes and operands.
instructions: ArrayList(u8),

/// Compiled instruction line data.
///
/// Mirrors [instructions] layout where an instruction offset will map to the
/// line number of that instruction.
lines: ArrayList(u16),

/// Compiled constant values.
constants: ArrayList(Value),

/// Allocate a new [Chunk], returning a pointer to it.
pub fn new() !*Chunk {
    const chunk: *Chunk = try mem.create(Chunk);
    chunk.* = Chunk{
        .instructions = .empty,
        .lines = .empty,
        .constants = .empty,
    };
    return chunk;
}

/// Destroy this [Chunk], freeing its owned resources.
pub fn destroy(self: *Chunk) void {
    self.instructions.deinit(mem.allocator());
    self.lines.deinit(mem.allocator());
    self.constants.deinit(mem.allocator());
    mem.destroy(self);
}

/// Returns the instruction at the given offset.
pub fn instruction(self: *Chunk, offset: usize) u8 {
    return self.instructions.items[offset];
}

/// Returns the line number at the given offset.
pub fn line(self: *Chunk, offset: usize) u16 {
    return self.lines.items[offset];
}

pub fn constant(self: *Chunk, offset: usize) Value {
    return self.constants.items[offset];
}

/// Write the given [op] to this chunk.
pub fn writeOp(self: *Chunk, op: OpCode, lineNum: u16) void {
    self.writeByte(op.byte(), lineNum);
}

/// Write the given [byte] to this chunk.
pub fn writeByte(self: *Chunk, byte: u8, lineNum: u16) void {
    self.instructions.append(mem.allocator(), byte) catch exit(1);
    self.lines.append(mem.allocator(), lineNum) catch exit(1);
}

/// Add a constant to this chunk.
///
/// Returns the offset of the added chunk within the constants array.
pub fn addConstant(self: *Chunk, value: Value) u8 {
    self.constants.append(mem.allocator(), value) catch exit(1);
    return @as(u8, @truncate(self.constants.items.len)) - 1;
}
