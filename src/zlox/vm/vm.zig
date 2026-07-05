//! Virtual machine for executing lox instructions.

const std = @import("std");
const zlox = @import("../.lib.zig");

const debug = zlox.debug;
const mem = zlox.mem;

const Chunk = zlox.compiler.Chunk;
const Compiler = zlox.compiler.Compiler;
const OpCode = zlox.compiler.OpCode;

const Tokenizer = zlox.tokenizer.Tokenizer;

const HashTable = zlox.object.HashTable;
const Obj = zlox.object.Obj;
const Value = zlox.object.Value;

const Parser = zlox.parser.Parser;

const ExecutionResult = zlox.vm.ExecutionResult;
const Stack = zlox.vm.Stack;

const Fnv1a_32 = std.hash.Fnv1a_32;

const printf = std.debug.print;

// ============================================================================

const Vm: type = @This();

/// Chunk of instructions currently being executed.
chunk: *Chunk,

/// Pointer to the next instruction to be executed.
ip: [*]u8,

/// Virtual machine value stack.
stack: Stack(Value),

/// Contains all runtime-interned strings.
strings: *HashTable,

/// Contains all runtime global variables.
globals: *HashTable,

/// Linked list of heap-allocated `Obj` values.
///
/// Contains all lox objects created by the VM at runtime, to be used by the
/// garbage collector to reach unreferenced objects after tracing living object
/// references.
root_obj: ?*Obj,

/// Allocate a new `Vm` instance on the heap, returning a pointer to it.
///
/// The caller owns the returned pointer and is responsible for freeing it.
pub fn create() !*Vm {
    const vm: *Vm = try mem.create(Vm);
    vm.stack.reset();
    vm.strings = try .create();
    vm.globals = try .create();
    vm.root_obj = null;
    return vm;
}

/// Destroy this `Vm`, freeing its owned resources.
pub fn destroy(self: *Vm) void {
    self.strings.destroy();
    self.globals.destroy();
    self.freeObjects();
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
    const compiler: *Compiler = try .create(parser, self.strings);
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
        .add => .Number(a.number + b.number),
        .subtract => .Number(a.number - b.number),
        .multiply => .Number(a.number * b.number),
        .divide => .Number(a.number / b.number),

        .greater => .Bool(a.number > b.number),
        .less => .Bool(a.number < b.number),

        else => {
            self.runtimeError("Invalid binary operator: '{s}'", .{@tagName(op)});
            return error.invalid_operator;
        },
    }));
}

/// Pop the top two strings off of the stack, concatenate them, and push the resulting
/// string to the stack.
fn concatenate(self: *Vm) !void {
    const b: []const u8 = self.stack.pop().obj.as.string.chars;
    const a: []const u8 = self.stack.pop().obj.as.string.chars;

    const new_len: usize = a.len + b.len;
    const new_chars: []u8 = try mem.alloc(u8, new_len);

    @memcpy(new_chars.ptr, a);
    @memcpy(new_chars.ptr + a.len, b);

    const new_string: *Obj = try self.takeString(new_chars);

    self.stack.push(.Object(new_string));
}

/// Run instructions from the currently loaded chunk.
fn run(self: *Vm) ExecutionResult {
    while (true) {
        if (comptime debug.trace_execution) {
            if (debug.print_stack) debug.printStack(&self.stack);

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
            .nil => self.stack.push(.Nil),
            .true => self.stack.push(.Bool(true)),
            .false => self.stack.push(.Bool(false)),

            // Comparison ops
            .equal => {
                const b: Value = self.stack.pop();
                const a: Value = self.stack.pop();
                self.stack.push(.Bool(a.equals(b)));
            },
            .greater => self.binaryOp(.greater) catch return .runtime_error,
            .less => self.binaryOp(.less) catch return .runtime_error,

            // Arithmetic ops
            .add => {
                const b: Value = self.stack.peek(0);
                const a: Value = self.stack.peek(1);

                // If both values are numbers, add them
                if (a.is(.number) and b.is(.number)) {
                    const b_number: f32 = self.stack.pop().number;
                    const a_number: f32 = self.stack.pop().number;
                    self.stack.push(.Number(a_number + b_number));
                }

                // If both values are strings, conctatenate them
                else if (a.isObj(.string) and b.isObj(.string)) {
                    self.concatenate() catch |err| {
                        self.runtimeError("Error concatenating strings: {any}", .{err});
                        return .runtime_error;
                    };
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
                _ = self.stack.replace(0, .Number(-value.number));
            },

            // Logical ops
            .not => _ = self.stack.replace(0, .Bool(self.stack.peek(0).isFalsey())),

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

            .print => printf("{f}\n", .{self.stack.pop()}),

            .global_define => {
                const ident: *Obj = self.readString();
                _ = self.globals.set(ident, self.stack.peek(0));
                _ = self.stack.pop();
            },
            .global_set => {
                const ident: *Obj = self.readString();

                // If the global variable isn't defined before setting, throw a
                // runtime error and delete the entry from the globals table
                if (self.globals.set(ident, self.stack.peek(0))) {
                    _ = self.globals.delete(ident);
                    self.runtimeError("Undefined variable '{f}'", .{ident});
                    return .runtime_error;
                }
            },
            .global_get => {
                const ident: *Obj = self.readString();
                const value: Value = self.globals.get(ident) orelse {
                    self.runtimeError("Undefined variable '{f}'.", .{ident});
                    return .runtime_error;
                };
                self.stack.push(value);
            },

            .local_set => self.stack.values[self.readByte()] = self.stack.peek(0),
            .local_get => self.stack.push(self.stack.values[self.readByte()]),

            .@"return" => return .ok,

            _ => return .runtime_error,
        }
    }
}

/// Read the next byte from the currently loaded chunk's instructions array.
fn readByte(self: *Vm) u8 {
    defer self.ip += 1;
    return self.ip[0];
}

/// Read the next two bytes from the currently loaded chunk's instructions array,
/// treating them as a single 16-bit value.
fn readShort(self: *Vm) u16 {
    defer self.ip += 2;
    return self.ip[0] << 8 | self.ip[1];
}

/// Read a constant value from the currently loaded chunk's instructions array by
/// reading the next byte, which is expected to be an offset pointing to a constant
/// value within the currently loaded chunk's constants array.
fn readConstant(self: *Vm) Value {
    return self.chunk.constantAt(self.readByte());
}

/// Read the string constant value at the offset obtained by reading the next byte.
fn readString(self: *Vm) *Obj {
    return self.readConstant().obj;
}

// Object management functions ================================================

/// Allocate a new `Obj` of the given `type` with the given `body`.
///
/// Returns a pointer to the allocated `Obj`.
///
/// Objects created this way are managed by the garbage collector, or cleaned up
/// when the VM is freed if they live until the end of the program.
pub fn createObj(self: *Vm, comptime @"type": Obj.Type, body: Obj.Body(@"type")) !*Obj {
    const obj: *Obj = try .create(@"type", body);

    // Pre-hash and intern string objects
    if (@"type" == .string) {
        const hash: u32 = Fnv1a_32.hash(body.chars);
        const interned_string: ?*Obj = self.strings.findString(body.chars, hash);

        // Return interned string if it exists
        if (interned_string) |str| {
            obj.destroy();
            return str;
        }

        obj.as.string.hash = hash;
        _ = self.strings.set(obj, .Nil);
    }

    // Link object for GC tracing
    obj.next = self.root_obj;
    self.root_obj = obj;

    return obj;
}

/// Allocate a new lox string `Obj` on the heap, wrapping and taking ownership of
/// the given slice.
///
/// The given `string` slice will be freed when the allocated `Obj` is freed.
///
/// Returns a pointer to the allocated lox string `Obj`.
///
/// Objects created this way are managed by the garbage collector, or cleaned up
/// when the VM is freed if they live until the end of the program.
pub fn takeString(self: *Vm, string: []const u8) !*Obj {
    return try self.createObj(
        .string,
        Obj.String{ .chars = string },
    );
}

/// Allocate a copy of the given `string` slice on the heap, wrapping it in a newly
/// allocated lox string `Obj`.
///
/// Returns a pointer to the allocated lox string `Obj`.
///
/// Objects created this way are managed by the garbage collector, or cleaned up
/// when the VM is freed if they live until the end of the program.
pub fn copyString(self: *Vm, string: []const u8) !*Obj {
    const copy: []u8 = try mem.alloc(u8, string.len);
    @memcpy(copy.ptr, string);
    return try self.takeString(copy);
}

// Free all lox objects allocated by the vm.
pub fn freeObjects(self: *Vm) void {
    while (self.root_obj) |obj| {
        self.root_obj = obj.next;
        obj.destroy();
    }
}

// ============================================================================

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
