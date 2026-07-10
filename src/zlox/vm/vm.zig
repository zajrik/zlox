//! Virtual machine for executing lox instructions.

const std = @import("std");
const zlox = @import("../.lib.zig");

const cmn = zlox.common;
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

const CallFrame = zlox.vm.CallFrame;
const ExecutionResult = zlox.vm.ExecutionResult;
const Stack = zlox.vm.Stack;

const Fnv1a_32 = std.hash.Fnv1a_32;

const printf = std.debug.print;

// ============================================================================

const Vm: type = @This();

/// Function call frame stack.
frame_stack: Stack(CallFrame, cmn.FRAME_MAX),

/// Virtual machine value stack.
stack: Stack(Value, cmn.STACK_MAX),

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
    vm.frame_stack.reset();
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
    const compiler: *Compiler = try .create(.script, parser, self.strings);
    const script: *Obj.Function = try compiler.compile() orelse return .compile_error;

    defer parser.destroy();
    defer compiler.destroy();
    defer script.destroy();

    if (script.chunk.isEmpty()) return .ok;

    // Push script object to stack to match reserved local slot 0
    self.stack.push(.Object(&script.obj));

    // Push callframe to execute script function
    self.frame_stack.push(CallFrame{
        .function = script,
        .ip = script.chunk.ip(),
        .slots = &self.stack.values,
    });

    return self.run();
}

/// Print a runtime error and stack trace at the current instruction.
fn runtimeError(self: *Vm, comptime fmt: []const u8, args: anytype) void {
    printf(fmt, args);
    printf("\n", .{});

    // Print stack trace
    var i: usize = self.frame_stack.size();
    while (i > 0) : (i -= 1) {
        const frame: *CallFrame = &self.frame_stack.values[i - 1];
        const function: *Obj.Function = frame.function;
        const instruction_offset: usize = frame.ip - function.chunk.ip() - 1;

        printf("[line {d}] in ", .{function.chunk.lineAt(instruction_offset)});

        if (function.identifier) |identifier| {
            printf("{f}()\n", .{identifier});
        } else {
            printf("script\n", .{});
        }
    }

    self.stack.reset();
}

/// Returns the current callframe off of the frame stack.
fn currentFrame(self: *const Vm) *CallFrame {
    return &(self.frame_stack.top - 1)[0];
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
    const b: []const u8 = self.stack.pop().obj.as(.string).chars;
    const a: []const u8 = self.stack.pop().obj.as(.string).chars;

    const new_len: usize = a.len + b.len;
    const new_chars: []u8 = try mem.alloc(u8, new_len);

    @memcpy(new_chars.ptr, a);
    @memcpy(new_chars.ptr + a.len, b);

    const new_string: *Obj.String = try self.takeString(new_chars);

    self.stack.push(.Object(&new_string.obj));
}

/// Attempt to call the given `callee` as a function using the top `arg_count` values
/// from the stack as its arguments.
///
/// Emits a runtime error if `callee` is not a callable function, method, or class
/// initializer.
///
/// Returns whether the `callee` is able to be called (no errors emitted).
fn callValue(self: *Vm, callee: Value, arg_count: u8) bool {
    if (callee.is(.obj)) switch (callee.obj.type) {
        .function => return self.callFun(callee.asObj(.function), arg_count),
        else => {},
    };

    self.runtimeError("Can only call functions, methods, and class initializers.", .{});
    return false;
}

/// Call the given `function`, using the top `arg_count` stack values as arguments.
///
/// Returns whether the function's instructions are able to begin executing.
fn callFun(self: *Vm, function: *Obj.Function, arg_count: u8) bool {
    if (arg_count != function.arity) {
        self.runtimeError(
            "Expected {d} arguments, got {d}",
            .{ function.arity, arg_count },
        );
        return false;
    }

    if (self.frame_stack.size() == cmn.FRAME_MAX) {
        self.runtimeError("Stack overflow.", .{});
        return false;
    }

    // Push callframe for the given function
    self.frame_stack.push(CallFrame{
        .function = function,
        .ip = function.chunk.ip(),
        .slots = @ptrCast(self.stack.top - 1 - arg_count),
    });

    return true;
}

// Instruction loop ===========================================================

/// Run instructions from the currently loaded chunk.
fn run(self: *Vm) ExecutionResult {
    debug.disassembleChunk(&self.currentFrame().function.chunk, "chunk");
    printf("\n== begin execution ==\n", .{});

    while (true) {
        // Grab the current frame off of the callframe stack
        const frame: *CallFrame = self.currentFrame();

        if (comptime debug.trace_execution) {
            if (debug.print_stack) printf("{f}", .{&self.stack});

            _ = debug.disassembleInstruction(
                &frame.function.chunk,
                // Find next instruction offset by subtracting the address of
                // the first instruction from the address of the next instruction
                frame.ip - frame.function.chunk.ip(),
            );
        }

        const instruction: OpCode = .fromByte(frame.readByte());

        switch (instruction) {
            .constant => self.stack.push(frame.readConstant()),
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
            .pop_n => self.stack.popN(frame.readByte()),
            .copy => self.stack.push(self.stack.peek(0)),
            .swap => {
                const b: Value = self.stack.pop();
                const a: Value = self.stack.pop();
                self.stack.push(b);
                self.stack.push(a);
            },

            .print => printf("{f}\n", .{self.stack.pop()}),

            .global_define => {
                const ident: *Obj.String = frame.readString();
                _ = self.globals.set(ident, self.stack.peek(0));
                _ = self.stack.pop();
            },
            .global_set => {
                const ident: *Obj.String = frame.readString();

                // If the global variable isn't defined before setting, throw a
                // runtime error and delete the entry from the globals table
                if (self.globals.set(ident, self.stack.peek(0))) {
                    _ = self.globals.delete(ident);
                    self.runtimeError("Undefined variable '{f}'", .{ident});
                    return .runtime_error;
                }
            },
            .global_get => {
                const ident: *Obj.String = frame.readString();
                const value: Value = self.globals.get(ident) orelse {
                    self.runtimeError("Undefined variable '{f}'.", .{ident});
                    return .runtime_error;
                };
                self.stack.push(value);
            },

            .local_set => frame.slots[frame.readByte()] = self.stack.peek(0),
            .local_get => self.stack.push(frame.slots[frame.readByte()]),

            .jump_if_false => {
                const offset: u16 = frame.readShort();
                if (self.stack.peek(0).isFalsey()) frame.ip += offset;
            },
            .jump_if_true => {
                const offset: u16 = frame.readShort();
                if (!self.stack.peek(0).isFalsey()) frame.ip += offset;
            },
            .jump_if_not_nil => {
                const offset: u16 = frame.readShort();
                if (self.stack.peek(0).isNot(.nil)) frame.ip += offset;
            },
            .jump => {
                const offset: u16 = frame.readShort();
                frame.ip += offset;
            },
            .loop => {
                const offset: u16 = frame.readShort();
                frame.ip -= offset;
            },

            .call => {
                const arg_count: u8 = frame.readByte();
                if (!self.callValue(self.stack.peek(arg_count), arg_count)) {
                    return .runtime_error;
                }
            },

            .@"return" => {
                // Pop return value from value stack
                const result: Value = self.stack.pop();

                // Pop callframe from frame stack, exiting if it was the root callframe
                if (self.frame_stack.discard() == 0) {
                    // Pop script function
                    _ = self.stack.pop();
                    return .ok;
                }

                // Discard callframe value stack slots and push return value to stack
                self.stack.top = frame.slots;
                self.stack.push(result);
            },

            _ => return .runtime_error,
        }
    }
}

// Object management functions ================================================

/// Allocate a new `Obj` of the given `type` with the given `variant` payload.
///
/// Returns a pointer to the allocated `Obj`.
///
/// Objects created this way are managed by the garbage collector, or cleaned up
/// when the VM is freed if they live until the end of the program.
pub fn createObj(
    self: *Vm,
    comptime T: Obj.Type,
    variant: Obj.Variant(T),
) !*Obj.Variant(T) {
    const object: *Obj.Variant(T) = try Obj.create(T, variant);

    // Pre-hash and intern string objects
    if (T == .string) {
        const hash: u32 = Fnv1a_32.hash(variant.chars);
        const interned: ?*Obj.String = self.strings.findString(variant.chars, hash);

        // Return interned string if it exists
        if (interned) |str| {
            object.destroy();
            return str;
        }

        object.hash = hash;
        _ = self.strings.set(object, .Nil);
    }

    // Link object for GC tracing
    object.obj.next = self.root_obj;
    self.root_obj = &object.obj;

    return object;
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
pub fn takeString(self: *Vm, string: []const u8) !*Obj.String {
    const str: *Obj.String = try self.createObj(
        .string,
        Obj.String{ .chars = string },
    );

    return str;
}

/// Allocate a copy of the given `string` slice on the heap, wrapping it in a newly
/// allocated lox string `Obj`.
///
/// Returns a pointer to the allocated lox string `Obj`.
///
/// Objects created this way are managed by the garbage collector, or cleaned up
/// when the VM is freed if they live until the end of the program.
pub fn copyString(self: *Vm, string: []const u8) !*Obj.String {
    const copy: []u8 = try mem.alloc(u8, string.len);
    @memcpy(copy.ptr, string);
    return try self.takeString(copy);
}

/// Free all lox objects allocated by the vm.
pub fn freeObjects(self: *Vm) void {
    while (self.root_obj) |obj| {
        self.root_obj = obj.next;
        obj.destroy();
    }
}

/// Register a native function with the VM.
fn defineNative(
    self: *Vm,
    identifier: []const u8,
    arity: u8,
    fn_ptr: Obj.Native.FnPtr,
) void {
    const fn_ident: *Obj.String = self.copyString(identifier);
    const fn_obj: *Obj.Native = self.createObj(
        .native,
        Obj.Native{ .arity = arity, .function = fn_ptr },
    );

    // TODO: Update this after starting GC and implementing some other way of keeping
    // pending objects safe from the GC until they're acually hitting userland. Bob's
    // technique of stashing them in the stack won't fly with the route I've taken with
    // the VM's obj allocation scheme

    self.globals.set(fn_ident, fn_obj);
}

// TODO: Move native functions to their own file/dir

/// Native `clock()` function.
fn native_clock(_: u8, _: [*]Value) Value {
    // TODO: Figure out how to get system time in zig without just calling C clock().
    // Searches are turning up really outdated information. I can call C if needed but
    // I don't want to if there's some clock function hiding in std somewhere
    return .Number(0);
}
