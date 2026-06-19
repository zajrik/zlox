//! A chunk of compiled lox instructions and constant values.

const std = @import("std");
const mem = @import("../memory/memory.zig");

const OpCode = @import("opcode.zig").OpCode;
const Value = @import("../object/value.zig").Value;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

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

/// Allocate a new `Chunk`, returning a pointer to it.
pub fn create() !*Chunk {
    return try mem.createStruct(Chunk, .{
        .instructions = .empty,
        .lines = .empty,
        .constants = .empty,
    });
}

/// Destroy this `Chunk`, freeing its owned resources.
pub fn destroy(self: *Chunk) void {
    self.instructions.deinit(mem.allocator());
    self.lines.deinit(mem.allocator());
    self.constants.deinit(mem.allocator());
    mem.destroy(self);
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
    self.instructions.append(mem.allocator(), byte) catch exit(1);
    self.lines.append(mem.allocator(), line) catch exit(1);
}

/// Write the given `op` to this chunk.
///
/// See also:
/// - `writeOp1`
/// - `writeOp2`
/// - `writeOp3`
pub fn writeOp(self: *Chunk, op: OpCode, line: u16) void {
    self.writeByte(op.toByte(), line);
}

/// Write the given `op` to this chunk, followed by a single byte operand.
pub fn writeOp1(self: *Chunk, op: OpCode, line: u16, byte: u8) void {
    self.writeOp(op, line);
    self.writeByte(byte, line);
}

/// Write the given `op` to this chunk, followed by two byte operands.
pub fn writeOp2(self: *Chunk, op: OpCode, line: u16, byte_1: u8, byte_2: u8) void {
    self.writeOp(op, line);
    self.writeByte(byte_1, line);
    self.writeByte(byte_2, line);
}

/// Write the given `op` to this chunk, followed by three byte operands.
pub fn writeOp3(self: *Chunk, op: OpCode, line: u16, byte_1: u8, byte_2: u8, byte_3: u8) void {
    self.writeOp(op, line);
    self.writeByte(byte_1, line);
    self.writeByte(byte_2, line);
    self.writeByte(byte_3, line);
}

/// Add the given constant `value` to this chunk's constants array.
///
/// Returns the offset of the added value within this chunk's constants array.
pub fn addConstant(self: *Chunk, value: Value) u8 {
    self.constants.append(mem.allocator(), value) catch exit(1);
    return @as(u8, @truncate(self.constants.items.len)) - 1;
}
