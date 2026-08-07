//! A chunk of compiled lox instructions and constant values.
//!
//! Initialize a new Chunk instance with `Chunk.empty`.
//!
//! A chunk owns allocated memory that must be released at the end of its lifetime
//! by calling `Chunk.deinit()`.

const std = @import("std");
const zlox = @import("../.lib.zig");

const mem = zlox.mem;

const ArrayList = std.ArrayList;

const OpCode = zlox.compiler.OpCode;
const Value = zlox.object.Value;

// =================================================================================================

const Chunk: type = @This();

/// Compiled instruction opcodes and operands.
instructions: ArrayList(u8) = .empty,

/// Compiled constant values in this chunk.
constants: ArrayList(Value) = .empty,

/// Compiled line data for instructions in this chunk.
///
/// Mirrors `instructions` layout where an instruction offset will map to the
/// line number of that instruction.
lines: ArrayList(u16) = .empty,

/// An empty `Chunk` containing no instructions.
pub const empty: Chunk = .{};

/// Release all allocated memory owned by this chunk.
pub fn deinit(self: *Chunk) void {
    defer self.instructions.deinit(mem.allocator());
    defer self.constants.deinit(mem.allocator());
    defer self.lines.deinit(mem.allocator());

    // Free compile-time constant non-string objs
    for (self.constants.items) |c| {
        if (c.as(.obj)) |it| {
            if (it.isNot(.string)) it.destroy();
        }
    }
}

/// Returns the number of instructions compiled to this chunk.
pub fn len(self: *const Chunk) usize {
    return self.instructions.items.len;
}

/// Returns whether this chunk has no instructions to execute.
pub fn isEmpty(self: *const Chunk) bool {
    return self.len() == 0;
}

/// Returns whether this chunk has at least one instruction to execute.
pub fn isNotEmpty(self: *const Chunk) bool {
    return self.len() > 0;
}

/// Returns whether this chunk's instructions end with a `.@"return"` instruction.
pub fn hasReturn(self: *const Chunk) bool {
    return self.isNotEmpty() and
        self.instructionAt(self.len() - 1) == OpCode.@"return".toByte();
}

/// Returns a pointer to the first compiled instruction in this chunk.
pub fn ip(self: *const Chunk) [*]u8 {
    return self.instructions.items.ptr;
}

/// Returns a pointer to the instruction at the given offset.
pub fn ipAt(self: *const Chunk, offset: usize) *u8 {
    return &self.instructions.items[offset];
}

/// Returns the instruction at the given offset.
pub fn instructionAt(self: *const Chunk, offset: usize) u8 {
    return self.instructions.items[offset];
}

/// Returns the line number at the given offset.
pub fn lineAt(self: *const Chunk, offset: usize) u16 {
    return self.lines.items[offset];
}

/// Returns the constant value at the given offset.
pub fn constantAt(self: *const Chunk, offset: usize) Value {
    return self.constants.items[offset];
}

/// Write the given `byte` to this chunk.
pub fn writeByte(self: *Chunk, byte: u8, line: u16) !void {
    try self.instructions.append(mem.allocator(), byte);
    try self.lines.append(mem.allocator(), line);
}

/// Add the given constant `value` to this chunk's constants array.
///
/// Returns the offset of the added value within this chunk's constants array.
pub fn addConstant(self: *Chunk, value: Value) !usize {
    try self.constants.append(mem.allocator(), value);
    return self.constants.items.len - 1;
}

/// Find the constant offset of the given `value` if it exists within this chunk's
/// constants array.
///
/// Returns `null` if the constant does not already exist.
pub fn findConstant(self: *const Chunk, value: Value) ?u8 {
    for (self.constants.items, 0..) |constant, offset| {
        if (constant.equals(value)) return @truncate(offset);
    }
    return null;
}
