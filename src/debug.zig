const std = @import("std");
const val = @import("object/value.zig");

const Chunk = @import("compiler/chunk.zig");
const OpCode = @import("compiler/opcode.zig").OpCode;
const Value = @import("object/value.zig").Value;

const printf = std.debug.print;

// ============================================================================

/// Print the contents (instructions, values, etc.) of the chunk at address `chunk`.
pub fn disassembleChunk(chunk: *Chunk, name: []const u8) void {
    printf("== {s} ==\n", .{name});
    var offset: usize = 0;
    while (offset < chunk.instructions.items.len) {
        offset = disassembleInstruction(chunk, offset);
    }
}

/// Prints the instruction from the chunk at address `chunk`, at `offset` in the
/// instructions array.
///
/// Returns the offset of the next instruction.
pub fn disassembleInstruction(chunk: *Chunk, offset: usize) usize {
    printf("{:04} ", .{offset});

    if (offset > 0 and chunk.lineAt(offset) == chunk.lineAt(offset - 1)) {
        printf("   | ", .{});
    } else {
        printf("{:4} ", .{chunk.lineAt(offset)});
    }

    const instruction: OpCode = @enumFromInt(chunk.instructionAt(offset));

    return switch (instruction) {
        .op_constant => constantInstruction("op_constant", chunk, offset),
        .op_add => simpleInstruction("op_add", offset),
        // .op_peek => byteInstruction("op_peek", chunk, offset),
        .op_print => simpleInstruction("op_print", offset),
        .op_return => simpleInstruction("op_return", offset),
        _ => {
            printf("Unknown opcode {d}\n", .{offset});
            return offset + 1;
        },
    };
}

/// Print the values of a stack given a pointer to the first item in the stack
/// and a pointer to the top of the stack.
pub fn printStack(stack: [*]Value, stack_top: [*]Value) void {
    printf("            ", .{});

    var slot: [*]Value = stack;
    while (@intFromPtr(slot) < @intFromPtr(stack_top)) : (slot += 1) {
        printf("[ ", .{});
        val.print(slot[0]);
        printf(" ]", .{});
    }

    printf("\n", .{});
}

/// Print the `name` of a simple instruction at `offset` in the instructions array.
///
/// Returns the offset of the next instruction.
fn simpleInstruction(name: []const u8, offset: usize) usize {
    printf("{s}\n", .{name});
    return offset + 1;
}

/// Print the `name` of a constant instruction at `offset` in the instructions
/// array, as well the value of the constant operand following the instruction.
///
/// Returns the offset of the next instruction (skipping over the constant operand).
fn constantInstruction(name: []const u8, chunk: *Chunk, offset: usize) usize {
    // Get the constant value byte after the instruction byte
    const constant: u8 = chunk.instructionAt(offset + 1);

    printf("{s:<16} {d:4} '", .{ name, constant });
    val.print(chunk.constantAt(constant));
    printf("'\n", .{});

    return offset + 2;
}

/// Print the `name` of an instruction accepting a single operand, along with the
/// raw byte value of its operand.
fn byteInstruction(name: []const u8, chunk: *Chunk, offset: usize) usize {
    const byte: u8 = chunk.instructionAt(offset + 1);
    printf("{s:<16} {d:4}\n", .{ name, byte });
    return offset + 2;
}
