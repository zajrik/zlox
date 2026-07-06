const std = @import("std");
const builtin = @import("builtin");
const zlox = @import(".lib.zig");

const val = zlox.object.val;

const Chunk = zlox.compiler.Chunk;
const OpCode = zlox.compiler.OpCode;
const Value = zlox.object.Value;
const Stack = zlox.vm.Stack;

const printf = std.debug.print;

// ============================================================================

/// Whether we've compiled in debug mode.
pub const is_debug_mode: bool = builtin.mode == .Debug;

/// Whether the vm should print instruction traces during execution.
pub const trace_execution: bool = is_debug_mode and true;

/// Whether the vm should print the stack in between instruction traces.
pub const print_stack: bool = is_debug_mode and true;

/// Whether the vm should dump the compiled chunk when there were errors.
pub const dump_chunk: bool = is_debug_mode and true;

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
    if (chunk.isEmpty()) return offset;

    printf("{:04} ", .{offset});

    if (offset > 0 and chunk.lineAt(offset) == chunk.lineAt(offset - 1)) {
        printf("   | ", .{});
    } else {
        printf("{:4} ", .{chunk.lineAt(offset)});
    }

    const instruction: OpCode = @enumFromInt(chunk.instructionAt(offset));

    return switch (instruction) {
        // Constant ops
        .constant => constantInstruction(".constant", chunk, offset),
        .nil => simpleInstruction(".nil", offset),
        .true => simpleInstruction(".true", offset),
        .false => simpleInstruction(".false", offset),

        // Comparison ops
        .equal => simpleInstruction(".equal", offset),
        .greater => simpleInstruction(".greater", offset),
        .less => simpleInstruction(".less", offset),

        // Arithmetic ops
        .add => simpleInstruction(".add", offset),
        .subtract => simpleInstruction(".subtract", offset),
        .multiply => simpleInstruction(".multiply", offset),
        .divide => simpleInstruction(".divide", offset),
        .negate => simpleInstruction(".negate", offset),

        // Logical ops
        .not => simpleInstruction(".not", offset),

        // Stack ops
        // .peek => byteInstruction(".peek", chunk, offset),
        .pop => simpleInstruction(".pop", offset),
        .pop_n => byteInstruction(".pop_n", chunk, offset),
        .copy => simpleInstruction(".copy", offset),
        .swap => simpleInstruction(".swap", offset),

        .print => simpleInstruction(".print", offset),

        .global_define => constantInstruction(".global_define", chunk, offset),
        .global_set => constantInstruction(".global_set", chunk, offset),
        .global_get => constantInstruction(".global_get", chunk, offset),

        .local_set => byteInstruction(".local_set", chunk, offset),
        .local_get => byteInstruction(".local_get", chunk, offset),

        .jump_if_false => jumpInstruction(".jump_if_false", 1, chunk, offset),
        .jump_if_true => jumpInstruction(".jump_if_true", 1, chunk, offset),
        .jump_if_not_nil => jumpInstruction(".jump_if_not_nil", 1, chunk, offset),
        .jump => jumpInstruction(".jump", 1, chunk, offset),
        .loop => jumpInstruction(".loop", -1, chunk, offset),

        .@"return" => simpleInstruction(".return", offset),

        _ => {
            printf("Unknown opcode {d}\n", .{offset});
            return offset + 1;
        },
    };
}

/// Print the values on the given `stack`.
pub fn printStack(stack: *const Stack(Value)) void {
    // If stack is empty, don't print anything
    if (stack.isEmpty()) return;

    printf("           ", .{});

    var slot: [*]const Value = &stack.values;
    while (@intFromPtr(slot) < @intFromPtr(stack.top)) : (slot += 1) {
        printf("[ {f} ]", .{slot[0]});
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
    const constant: u8 = chunk.instructionAt(offset + 1);
    printf("{s:<16} {d:4} '{f}'\n", .{ name, constant, chunk.constantAt(constant) });
    return offset + 2;
}

/// Print the `name` of an instruction accepting a single operand, along with the
/// raw byte value of its operand.
fn byteInstruction(name: []const u8, chunk: *Chunk, offset: usize) usize {
    const byte: u8 = chunk.instructionAt(offset + 1);
    printf("{s:<16} {d:4}\n", .{ name, byte });
    return offset + 2;
}

/// Print the `name` of a jump instruction, followed by the current offset and the
/// offset after the jump is executed.
fn jumpInstruction(name: []const u8, sign: i2, chunk: *const Chunk, offset: usize) usize {
    var jump: i32 = @as(u16, chunk.instructionAt(offset + 1)) << 8;
    jump |= chunk.instructionAt(offset + 2);
    jump *= sign;

    printf(
        "{s:<16} {d:4} -> {d}\n",
        .{ name, offset, @as(i32, @intCast(offset)) + 3 + jump },
    );

    return offset + 3;
}
