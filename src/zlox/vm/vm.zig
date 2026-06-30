//! Virtual machine for executing lox instructions.

const std = @import("std");
const zlox = @import("../.lib.zig");

const debug = zlox.debug;
const mem = zlox.mem;
const val = zlox.object.val;

const Chunk = zlox.compiler.Chunk;
const Compiler = zlox.compiler.Compiler;
const OpCode = zlox.compiler.OpCode;

const Tokenizer = zlox.tokenizer.Tokenizer;

const Obj = zlox.object.obj.Obj;
const Value = zlox.object.Value;

const Parser = zlox.parser.Parser;

const ExecutionResult = zlox.vm.ExecutionResult;
const Stack = zlox.vm.Stack;

const printf = std.debug.print;

// ============================================================================

const Vm: type = @This();

/// Chunk of instructions currently being executed.
chunk: *Chunk,

/// Pointer to the next instruction to be executed.
ip: [*]u8,

/// Virtual machine value stack.
stack: Stack(Value),

/// Allocate a new `Vm` instance on the heap, returning a pointer to it.
///
/// The caller owns the returned pointer and is responsible for freeing it.
pub fn create() !*Vm {
    const vm: *Vm = try mem.create(Vm);
    vm.stack.reset();
    return vm;
}

/// Destroy this `Vm`, freeing its owned resources.
pub fn destroy(self: *Vm) void {
    mem.destroy(self);
}

/// Interpret the given lox source code by compiling it to lox bytecode and running it.
///
/// Returns the result of executing the given code.
pub fn interpret(self: *Vm, source: []const u8) ExecutionResult {
    return self.interp(source) catch .compile_error;
}

/// Interpret the given lox source code.
///
/// Returns the result of compilation or an error to be replaced with `.compile_error`.
fn interp(self: *Vm, source: []const u8) !ExecutionResult {
    var tokenizer: Tokenizer = .init(source);
    const parser: *Parser = try .create(&tokenizer);
    const compiler: *Compiler = try .create(parser);
    const chunk: *Chunk = try compiler.compile() orelse return .compile_error;

    defer parser.destroy();
    defer compiler.destroy();
    defer chunk.destroy();

    if (chunk.isEmpty()) return .ok;

    self.chunk = chunk;
    self.ip = chunk.instructions.items.ptr;

    return self.run();
}

/// Perform a binary operation with the top two number values on the stack.
fn binaryOp(self: *Vm, op: OpCode) error{ invalid_operator, invalid_operand }!void {
    if (self.stack.peek(0).isNot(.number) or self.stack.peek(1).isNot(.number)) {
        self.runtimeError("Operands must be numbers.", .{});
        return error.invalid_operand;
    }

    const b: Value = self.stack.pop();
    const a: Value = self.stack.pop();

    self.stack.push((switch (op) {
        .add => .numberVal(a.number + b.number),
        .subtract => .numberVal(a.number - b.number),
        .multiply => .numberVal(a.number * b.number),
        .divide => .numberVal(a.number / b.number),

        .greater => .boolVal(a.number > b.number),
        .less => .boolVal(a.number < b.number),

        else => {
            self.runtimeError("Invalid binary operator: '{s}'", .{@tagName(op)});
            return error.invalid_operator;
        },
    }));
}

/// Pop the top two strings off of the stack, concatenate them, and push the resulting
/// string to the stack.
fn concatenate(self: *Vm) !void {
    const b: []const u8 = self.stack.pop().obj.*.string.chars;
    const a: []const u8 = self.stack.pop().obj.*.string.chars;

    const new_len: usize = a.len + b.len;
    const new_chars: []u8 = try mem.alloc(u8, new_len);

    @memcpy(new_chars.ptr, a);
    @memcpy(new_chars.ptr + a.len, b);

    self.stack.push(.objVal(try .create(.string, .{ .chars = new_chars })));
}

/// Run instructions from the currently loaded chunk.
fn run(self: *Vm) ExecutionResult {
    while (true) {
        if (comptime debug.trace_execution) {
            debug.printStack(&self.stack);

            _ = debug.disassembleInstruction(
                self.chunk,
                // Find next instruction offset by subtracting the address of
                // the first instruction from the address of the next instruction
                @intFromPtr(self.ip) - @intFromPtr(self.chunk.instructions.items.ptr),
            );
        }

        const instruction: OpCode = .fromByte(self.readByte());

        switch (instruction) {
            .constant => self.stack.push(self.readConstant()),
            .nil => self.stack.push(.nil_val),
            .true => self.stack.push(.boolVal(true)),
            .false => self.stack.push(.boolVal(false)),

            // Comparison ops
            .equal => {
                const b: Value = self.stack.pop();
                const a: Value = self.stack.pop();
                self.stack.push(.boolVal(a.equals(b)));
            },
            .greater => self.binaryOp(.greater) catch return .runtime_error,
            .less => self.binaryOp(.less) catch return .runtime_error,

            // Arithmetic ops
            .add => {
                const b: Value = self.stack.peek(0);
                const a: Value = self.stack.peek(1);

                // If both values are strings, conctatenate them
                if (a.isObj(.string) and b.isObj(.string)) {
                    self.concatenate() catch |err| {
                        self.runtimeError("Error concatenating strings: {any}", .{err});
                        return .runtime_error;
                    };
                }

                // If both values are numbers, add them
                else if (a.is(.number) and b.is(.number)) {
                    const b_number: f32 = self.stack.pop().number;
                    const a_number: f32 = self.stack.pop().number;
                    self.stack.push(.numberVal(a_number + b_number));
                }

                // Otherwise error for invalid operands
                else {
                    self.runtimeError("Operands must be both numbers or both strings.", .{});
                    return .runtime_error;
                }
            },
            .subtract => self.binaryOp(.subtract) catch return .runtime_error,
            .multiply => self.binaryOp(.multiply) catch return .runtime_error,
            .divide => self.binaryOp(.divide) catch return .runtime_error,

            .negate => {
                const value: Value = self.stack.peek(0);
                if (value.isNot(.number)) {
                    self.runtimeError("Operand must be a number.", .{});
                    return .runtime_error;
                }
                _ = self.stack.replace(0, .numberVal(-value.number));
            },

            // Logical ops
            .not => _ = self.stack.replace(0, .boolVal(self.stack.peek(0).isFalsey())),

            // Stack ops
            // .peek => printf("{any}\n", .{self.stack.peek(self.readByte())}),
            .pop => _ = self.stack.pop(),
            .pop_n => self.stack.popN(self.readByte()),
            .copy => self.stack.push(self.stack.peek(0)),
            .swap => {
                const b: Value = self.stack.pop();
                const a: Value = self.stack.pop();
                self.stack.push(b);
                self.stack.push(a);
            },

            .print => printf("{any}\n", .{self.stack.pop()}),

            .@"return" => return .ok,

            _ => return .runtime_error,
        }
    }
}

/// Read the next byte from the currently loaded chunk's instructions array.
fn readByte(self: *Vm) u8 {
    self.ip += 1;
    return (self.ip - 1)[0];
}

/// Read the next two bytes from the currenty loaded chunk's instructions array,
/// treating them as a single 16-bit value.
fn readShort(self: *Vm) u16 {
    self.ip += 2;
    return (self.ip - 2)[0] << 8 | (self.ip - 1)[0];
}

/// Read a constant value from the currently loaded chunk's instructions array by
/// reading the next byte, which is expected to be an offset pointing to a constant
/// value within the currently loaded chunk's constants array.
fn readConstant(self: *Vm) Value {
    return self.chunk.constantAt(self.readByte());
}

/// Print a runtime error and stack trace at the current instruction.
fn runtimeError(self: *Vm, comptime fmt: []const u8, args: anytype) void {
    printf(fmt, args);
    printf("\n", .{});

    // Get current erroring instruction line
    const instruction: usize = @intFromPtr(self.ip) - @intFromPtr(self.chunk.instructions.items.ptr) - 1;
    const line: u16 = self.chunk.lineAt(instruction);

    // TODO: Add stack trace printing when callframes are ported

    printf("[line {d}] in script\n", .{line});
    self.stack.reset();
}
