//! Virtual machine for executing lox instructions.

const std = @import("std");
const builtin = @import("builtin");
const zlox = @import("../.lib.zig");

const debug = zlox.debug;
const mem = zlox.mem;
const val = zlox.object.val;

const printf = std.debug.print;

const Chunk = zlox.compiler.Chunk;
const Compiler = zlox.compiler.Compiler;
const OpCode = zlox.compiler.OpCode;
const Tokenizer = zlox.tokenizer.Tokenizer;
const Value = zlox.object.Value;
const Parser = zlox.parser.Parser;
const ExecutionResult = zlox.vm.ExecutionResult;
const Stack = zlox.vm.Stack;

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

/// Run instructions from the currently loaded chunk.
fn run(self: *Vm) ExecutionResult {
    while (true) {
        if (comptime builtin.mode == .Debug) {
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

            // Arithmetic ops
            .add => {
                const b: Value = self.stack.pop();
                const a: Value = self.stack.pop();
                self.stack.push(a + b);
            },
            .subtract => {
                const b: Value = self.stack.pop();
                const a: Value = self.stack.pop();
                self.stack.push(a - b);
            },
            .multiply => {
                const b: Value = self.stack.pop();
                const a: Value = self.stack.pop();
                self.stack.push(a * b);
            },
            .divide => {
                const b: Value = self.stack.pop();
                const a: Value = self.stack.pop();
                self.stack.push(a / b);
            },
            .negate => _ = self.stack.replace(0, -self.stack.peek(0)),

            // .not => _ = self.stack.replace(0, negate bool value object TBI),

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
