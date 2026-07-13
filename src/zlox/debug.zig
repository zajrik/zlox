const std = @import("std");
const builtin = @import("builtin");
const zlox = @import(".lib.zig");

const Chunk = zlox.compiler.Chunk;
const OpCode = zlox.compiler.OpCode;
const Obj = zlox.object.Obj;
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

/// Whether the vm should dump raw chunk bytes before dumping the chunk contents./
pub const dump_raw: bool = is_debug_mode and true;

/// Whether Obj memory being released should be logged.
pub const obj_free: bool = is_debug_mode and false;

/// Print the contents (instructions, values, etc.) of the chunk at address `chunk`.
pub fn disassembleChunk(chunk: *Chunk, name: []const u8) void {
    printf("== {s} ==\n", .{name});
    var offset: usize = 0;

    if (comptime dump_raw) {
        while (offset < chunk.len()) {
            printf("{d:02} ", .{chunk.instructionAt(offset)});
            offset += 1;
        }
        printf("\n", .{});
        offset = 0;
    }

    while (offset < chunk.len()) {
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
        .constant => |T| constantInstruction(T, chunk, offset),
        .nil => |T| simpleInstruction(T, offset),
        .true => |T| simpleInstruction(T, offset),
        .false => |T| simpleInstruction(T, offset),

        // Comparison ops
        .equal => |T| simpleInstruction(T, offset),
        .greater => |T| simpleInstruction(T, offset),
        .less => |T| simpleInstruction(T, offset),

        // Arithmetic ops
        .add => |T| simpleInstruction(T, offset),
        .subtract => |T| simpleInstruction(T, offset),
        .multiply => |T| simpleInstruction(T, offset),
        .divide => |T| simpleInstruction(T, offset),
        .negate => |T| simpleInstruction(T, offset),

        // Logical ops
        .not => |T| simpleInstruction(T, offset),

        // Stack ops
        // .peek => |op| byteInstruction(op, chunk, offset),
        .pop => |T| simpleInstruction(T, offset),
        .pop_n => |T| byteInstruction(T, chunk, offset),
        .close => |T| simpleInstruction(T, offset),
        .copy => |T| simpleInstruction(T, offset),
        .swap => |T| simpleInstruction(T, offset),

        .print => |T| simpleInstruction(T, offset),

        // Variable define/get/set etc. ops
        .global_define => |T| constantInstruction(T, chunk, offset),
        .global_set => |T| constantInstruction(T, chunk, offset),
        .global_get => |T| constantInstruction(T, chunk, offset),

        .local_set => |T| byteInstruction(T, chunk, offset),
        .local_get => |T| byteInstruction(T, chunk, offset),

        .upvalue_set => |T| byteInstruction(T, chunk, offset),
        .upvalue_get => |T| byteInstruction(T, chunk, offset),

        // Control flow ops
        .jump_if_false => |T| jumpInstruction(T, 1, chunk, offset),
        .jump_if_true => |T| jumpInstruction(T, 1, chunk, offset),
        .jump_if_not_nil => |T| jumpInstruction(T, 1, chunk, offset),
        .jump => |T| jumpInstruction(T, 1, chunk, offset),
        .loop => |T| jumpInstruction(T, -1, chunk, offset),

        .call => |T| byteInstruction(T, chunk, offset),

        .closure => |T| {
            var new_offset: usize = offset + 1;
            const constant: u8 = chunk.instructionAt(new_offset);
            const function: Value = chunk.constantAt(constant);
            const fun_obj: *Obj.Function = function.asObj(.function);

            printf("{s:<16} {d:4} {f}\n", .{ T.toString(), constant, function });

            new_offset += 1;

            var i: u8 = 0;
            while (i < fun_obj.upvalue_count) : (i += 1) {
                const is_local: u8 = chunk.instructionAt(new_offset);
                const upvalue_offset: u8 = chunk.instructionAt(new_offset + 1);
                defer new_offset += 2;

                printf("{d:04}    |                       {s} {d}\n", .{
                    new_offset,
                    if (is_local == 1) "local" else "upvalue",
                    upvalue_offset,
                });
            }

            return new_offset;
        },

        .@"return" => |T| simpleInstruction(T, offset),

        _ => {
            printf("Unknown opcode {d}\n", .{offset});
            return offset + 1;
        },
    };
}

/// Print the given `OpCode` without operands.
///
/// Returns the offset of the next instruction.
fn simpleInstruction(comptime op: OpCode, offset: usize) usize {
    printf("{s}\n", .{op.toString()});
    return offset + 1;
}

/// Print the given `OpCode`, followed by the value of the constant operand following
/// it in the compiled instructions of the given `chunk`.
///
/// Returns the offset of the next instruction (skipping over the constant operand).
fn constantInstruction(comptime op: OpCode, chunk: *Chunk, offset: usize) usize {
    const constant: u8 = chunk.instructionAt(offset + 1);
    printf("{s:<16} {d:4} '{f}'\n", .{ op.toString(), constant, chunk.constantAt(constant) });
    return offset + 2;
}

/// Print the given `OpCode`, followed by the raw byte operand following it in the
/// compiled instructions of the given `chunk`.
fn byteInstruction(comptime op: OpCode, chunk: *Chunk, offset: usize) usize {
    const byte: u8 = chunk.instructionAt(offset + 1);
    printf("{s:<16} {d:4}\n", .{ op.toString(), byte });
    return offset + 2;
}

/// Print the given `OpCode`, followed by the jump offset operand following it in
/// the compiled instructions of the given `chunk`.
fn jumpInstruction(comptime op: OpCode, sign: i2, chunk: *const Chunk, offset: usize) usize {
    var jump: i32 = @as(u16, chunk.instructionAt(offset + 1)) << 8;
    jump |= chunk.instructionAt(offset + 2);
    jump *= sign;

    printf(
        "{s:<16} {d:4} -> {d}\n",
        .{ op.toString(), offset, @as(i32, @intCast(offset)) + 3 + jump },
    );

    return offset + 3;
}
