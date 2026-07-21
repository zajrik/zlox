//! Virtual machine for executing lox instructions.

const std = @import("std");
const zlox = @import("../.lib.zig");

const cmn = zlox.common;
const debug = zlox.debug;
const mem = zlox.mem;
const native = zlox.vm.native;

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
const Gc = zlox.vm.Gc;
const Stack = zlox.vm.Stack;

const Fnv1a_32 = std.hash.Fnv1a_32;
const Io = std.Io;

const printf = std.debug.print;

// ============================================================================

const Vm: type = @This();

/// `std.Io` interface to be passed to lox native functions.
io: Io,

/// Function call frame stack.
frame_stack: Stack(CallFrame, cmn.FRAME_MAX) = undefined,

/// Virtual machine value stack.
stack: Stack(Value, cmn.STACK_MAX) = undefined,

/// Contains all runtime-interned strings.
strings: *HashTable,

/// Contains all runtime global variables.
globals: *HashTable,

/// Linked list of open upvalues.
///
/// The head of the list is the open upvalue capturing the local variable highest
/// on the stack relative to other captured locals at the point the list is observed.
open_upvalues: ?*Obj.Upvalue,

/// Linked list of heap-allocated `Obj` values.
///
/// Contains all lox objects created by the VM at runtime, to be used by the
/// garbage collector to reach unreferenced objects after tracing living object
/// references.
heap: ?*Obj,

/// Garbage collector instance.
///
/// This is owned by the VM and must be freed when the VM is freed.
gc: *Gc = undefined,

/// The number of bytes allocated by objects linked to the VM's heap.
heap_size: usize = 0,

/// The threshold of bytes allocated at which the next GC sweep should trigger.
next_gc: usize = 1024 * 1024,

/// Allocate a new `Vm` instance on the heap, returning a pointer to it.
///
/// The caller owns the returned pointer and is responsible for freeing it.
pub fn create(io: Io) !*Vm {
    const vm: *Vm = try mem.createStruct(Vm, .{
        .io = io,
        .strings = try .create(),
        .globals = try .create(),
        .open_upvalues = null,
        .heap = null,
    });

    vm.frame_stack.reset();
    vm.stack.reset();
    vm.gc = try .create(vm);

    return vm;
}

/// Destroy this `Vm`, freeing its owned resources.
pub fn destroy(self: *Vm) void {
    defer mem.destroy(self);
    self.strings.destroy();
    self.globals.destroy();
    self.gc.destroy();
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
    const compiler: *Compiler = try .create(.script, parser, self.strings, null);
    const script: *Obj.Function = try compiler.compile() orelse return .compile_error;

    const closure: *Obj.Closure = try self.createObj(
        .closure,
        Obj.Closure{
            .function = script,
            .upvalues = try mem.alloc(*Obj.Upvalue, script.upvalue_count),
        },
    );

    defer self.freeConstStrings();
    defer parser.destroy();
    defer compiler.destroy();
    defer script.destroy();
    defer self.freeHeap();

    if (script.chunk.isEmpty()) return .ok;

    // Push script closure to stack to match reserved local slot 0
    self.stack.push(.Object(closure.toObj()));

    // Push callframe to execute script closure
    self.frame_stack.push(CallFrame{
        .closure = closure,
        .ip = script.chunk.ip(),
        .slots = &self.stack.values,
    });

    try native.bootstrapNatives(self);

    return self.run() catch |err| it: {
        self.runtimeError("An unexpected error occurred: {any}", .{err});
        break :it .runtime_error;
    };
}

/// Print a runtime error and stack trace at the current instruction.
fn runtimeError(self: *Vm, comptime fmt: []const u8, args: anytype) void {
    printf(fmt, args);
    printf("\n", .{});

    // Print stack trace
    var i: usize = self.frame_stack.size();
    while (i > 0) : (i -= 1) {
        const frame: *CallFrame = &self.frame_stack.values[i - 1];
        const function: *Obj.Function = frame.closure.function;
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
    return self.frame_stack.slot(0);
}

/// Perform a binary operation with the top two number values on the stack.
fn binaryOp(self: *Vm, op: OpCode) error{ invalid_operator, invalid_operand }!void {
    if (self.stack.peek(0).isNot(.number) or self.stack.peek(1).isNot(.number)) {
        self.runtimeError("Operands must be numbers.", .{});
        return error.invalid_operand;
    }

    const b: Value = self.stack.pop();
    const a: Value = self.stack.pop();

    self.stack.push(switch (op) {
        .subtract => .Number(a.number - b.number),
        .multiply => .Number(a.number * b.number),
        .divide => .Number(a.number / b.number),

        .greater => .Bool(a.number > b.number),
        .less => .Bool(a.number < b.number),

        else => {
            self.runtimeError("Invalid binary operator: '{s}'", .{@tagName(op)});
            return error.invalid_operator;
        },
    });
}

/// Pop the top two strings off of the stack, concatenate them, and push the resulting
/// string to the stack.
fn concatenate(self: *Vm) !void {
    const b: []const u8 = self.stack.pop().objCast(.string).chars;
    const a: []const u8 = self.stack.pop().objCast(.string).chars;

    const new_len: usize = a.len + b.len;
    const new_chars: []u8 = try mem.alloc(u8, new_len);

    @memcpy(new_chars.ptr, a);
    @memcpy(new_chars.ptr + a.len, b);

    const new_string: *Obj.String = try self.takeString(new_chars);

    self.stack.push(.Object(new_string.toObj()));
}

/// Capture an upvalue from the given pointer to a `local` variable slot on the
/// stack.
///
/// Attempts to find an existing upvalue for the given local variable slot before
/// allocating a new one.
///
/// Returns a pointer to the captured upvalue. The returned object is managed by
/// the garbage collector.
fn captureUpvalue(self: *Vm, local: *Value) !*Obj.Upvalue {
    var upvalue: ?*Obj.Upvalue = null;
    var next: ?*Obj.Upvalue = self.open_upvalues;

    // Walk the list of open upvalues, starting at the upvalue that captures the
    // local variable highest on the stack relative to other captured local vars
    // (the head of the list).
    //
    // We'll exit the loop if any of these conditions are met:
    // - `next` is an existing upvalue capturing the given local variable slot
    // - `next` is an upvalue capturing a local on the stack below the given local
    // - We've run out of open upvalues to check
    while (next) |it| : (next = it.next) {
        if (@intFromPtr(it.location) <= @intFromPtr(local)) break;
        upvalue = it;
    }

    // If we find an existing open upvalue for the given local, return it
    if (next) |it| if (it.location == local) return it;

    // Otherwise create a new upvalue to capture the given local. `next` refers
    // to an upvalue lower on the stack than the given local, so this will be
    // inserted before `next` in the linked list
    const capture: *Obj.Upvalue = try self.createObj(
        .upvalue,
        Obj.Upvalue{ .location = local, .next = next },
    );

    // If `upvalue` is not null, then the given local (now `capture`) is on the
    // stack between the locals captured by `upvalue` and `next`, and is inserted
    // into the list of open upvalues between the two.
    //
    // The slice of these three linked upvalues should then look like this:
    //
    // `upvalue`
    //  `-.next -> `capture`
    //              `-.next -> `next`
    //                          `-.next = ...
    //
    // If `upvalue` IS null then there is no captured local higher on the stack
    // than the given local so we can insert `capture` at the head of the list as
    // the highest captured local on the stack
    (if (upvalue) |it| &it.next else &self.open_upvalues).* = capture;

    return capture;
}

/// Close the open upvalue associated with the given local variable, or the first
/// open upvalue capturing a local higher on the stack than the given one, as well
/// as any open upvalues capturing locals above it on the stack.
fn closeUpvalues(self: *Vm, local: *const Value) void {
    while (self.open_upvalues) |upvalue| {
        if (@intFromPtr(upvalue.location) < @intFromPtr(local)) break;
        upvalue.close();
        self.open_upvalues = upvalue.next;
    }
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
        .closure => return self.callFun(callee.objCast(.closure), arg_count),
        .native => {
            const native_obj: *Obj.Native = callee.objCast(.native);
            const native_fun: Obj.Native.FnPtr = native_obj.function;

            if (arg_count != native_obj.arity) {
                self.runtimeError(
                    "Expected {d} arguments, got {d}",
                    .{ native_obj.arity, arg_count },
                );
                return false;
            }

            // Call native function, capturing its returned value
            const result: Value = native_fun(
                self.io,
                arg_count,
                self.stack.top - arg_count,
            );

            // Pop native function and its args from stack
            self.stack.top -= arg_count + 1;

            self.stack.push(result);
            return true;
        },
        else => {},
    };

    self.runtimeError("Can only call functions, methods, and class initializers.", .{});
    return false;
}

/// Call the given `function`, using the top `arg_count` stack values as arguments.
///
/// Returns whether the function's instructions are able to begin executing.
fn callFun(self: *Vm, closure: *Obj.Closure, arg_count: u8) bool {
    if (arg_count != closure.function.arity) {
        self.runtimeError(
            "Expected {d} arguments, got {d}",
            .{ closure.function.arity, arg_count },
        );
        return false;
    }

    if (self.frame_stack.size() == cmn.FRAME_MAX) {
        self.runtimeError("Stack overflow.", .{});
        return false;
    }

    // Push callframe for the given function
    self.frame_stack.push(CallFrame{
        .closure = closure,
        .ip = closure.function.chunk.ip(),
        .slots = @ptrCast(self.stack.top - 1 - arg_count),
    });

    return true;
}

// Instruction loop ===========================================================

/// Run instructions from the currently loaded chunk.
fn run(self: *Vm) !ExecutionResult {
    printf("\n== begin execution ==\n", .{});

    while (true) {
        // Grab the current frame off of the callframe stack
        const frame: *CallFrame = self.currentFrame();

        if (comptime debug.trace_execution) {
            if (debug.print_stack) printf("{f}", .{&self.stack});

            _ = debug.disassembleInstruction(
                &frame.closure.function.chunk,
                // Find next instruction offset by subtracting the address of
                // the first instruction from the address of the next instruction
                frame.ip - frame.closure.function.chunk.ip(),
            );
        }

        const instruction: OpCode = .fromByte(frame.readByte());

        switch (instruction) {
            // Constant ops
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
            .greater => try self.binaryOp(.greater),
            .less => try self.binaryOp(.less),

            // Arithmetic ops
            .add => {
                const b: Value = self.stack.peek(0);
                const a: Value = self.stack.peek(1);

                // If both values are numbers, add them
                if (a.is(.number) and b.is(.number)) {
                    const b_number: f64 = self.stack.pop().number;
                    const a_number: f64 = self.stack.pop().number;
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
            .subtract => try self.binaryOp(.subtract),
            .multiply => try self.binaryOp(.multiply),
            .divide => try self.binaryOp(.divide),

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
            .pop => _ = self.stack.pop(),
            .pop_n => self.stack.popN(frame.readByte()),
            .close => {
                self.closeUpvalues(self.stack.slot(0));
                _ = self.stack.pop();
            },
            .copy => self.stack.copy(0),
            .swap => self.stack.swap(0, 1),

            .print => printf("{f}\n", .{self.stack.pop()}),

            // Variable define/get/set etc. ops
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
                    self.runtimeError("Undefined variable '{f}'.", .{ident});
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

            .upvalue_set => {
                const offset: u8 = frame.readByte();
                const upvalue: *Obj.Upvalue = frame.closure.upvalues[offset];
                upvalue.location.* = self.stack.peek(0);
            },
            .upvalue_get => {
                const offset: u8 = frame.readByte();
                const upvalue: *Obj.Upvalue = frame.closure.upvalues[offset];
                self.stack.push(upvalue.location.*);
            },

            // Control flow ops
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

            .closure => {
                const function: *Obj.Function = frame.readConstant().objCast(.function);
                const closure: *Obj.Closure = try Obj.create(
                    .closure,
                    Obj.Closure{
                        .function = function,
                        .upvalues = try mem.alloc(*Obj.Upvalue, function.upvalue_count),
                    },
                );

                // Capture upvalues from enclosing scopes
                var i: u8 = 0;
                while (i < function.upvalue_count) : (i += 1) {
                    const is_local: bool = frame.readByte() == 1;
                    const offset: u8 = frame.readByte();

                    closure.upvalues[i] = it: {
                        // Capture local from the frame's stack window if upvalue is local
                        if (is_local) {
                            const local_ptr: *Value = @ptrCast(frame.slots + offset);
                            break :it try self.captureUpvalue(local_ptr);
                        }

                        // Otherwise reference existing upvalue from frame
                        break :it frame.closure.upvalues[offset];
                    };
                }

                self.stack.push(.Object(&self.linkObj(.closure, closure).obj));
            },

            .@"return" => {
                // Pop return value from value stack
                const result: Value = self.stack.pop();

                // Close any open upvalues on the stack within this callframe's scope
                self.closeUpvalues(@ptrCast(frame.slots));

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
    return self.linkObj(T, try Obj.create(T, variant));
}

/// Link the given object with the VM, allowing it to be traced by the GC.
///
/// Returns a pointer to the linked object. In the event that the given object is
/// a string that has already been interned, it will be destroyed and the interned
/// string will be returned instead.
///
/// Assume the VM takes ownership of any object given so there will be no need
/// to manually clean that object up.
///
/// The size of the created object will be noted so that we can keep track of
/// when the GC needs to run.
pub fn linkObj(self: *Vm, comptime T: Obj.Type, variant: *Obj.Variant(T)) *Obj.Variant(T) {
    // Pre-hash and intern string objects
    if (T == .string) {
        const hash: u32 = Fnv1a_32.hash(variant.chars);
        const interned: ?*Obj.String = self.strings.findString(variant.chars, hash);

        // Return interned string if it exists
        if (interned) |str| {
            variant.destroy();
            return str;
        }

        variant.hash = hash;
        _ = self.strings.set(variant, .Nil);
    }

    if (comptime debug.stress_gc) self.gc.collect() catch {};

    self.heap_size += @sizeOf(Obj.Variant(T));
    if (T == .string) self.heap_size += @sizeOf(u8) * variant.chars.len;

    // Run GC if we've exceeded the GC threshold. This should only fail if we're
    // out of memory when allocating memory for tracking marked objs before tracing,
    // at which point things are out of our hands 💀 We could potentially allocate
    // a rainy-day fund of memory in the GC that can be freed if that happens and
    // then try running the GC again, but Bob didn't bother in the book so I'm not
    // likely to bother here unless it becomes a problem for me personally (it won't)
    if (self.heap_size > self.next_gc) self.gc.collect() catch |err| {
        self.runtimeError("Error running garbage collector: {any}", .{err});
        std.process.exit(1);
    };

    // Link object for GC tracing
    variant.obj.next = self.heap;
    self.heap = variant.toObj();

    return variant;
}

/// Destroy an object linked to the VM, making note of the released bytes so that
/// we can keep track of when the GC needs to run.
///
/// Note: Make sure the object is unlinked from the VM heap before releasing.
pub fn releaseObj(self: *Vm, obj: *Obj) void {
    self.heap_size -= obj.size();
    obj.destroy();
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
pub fn takeString(self: *Vm, chars: []const u8) !*Obj.String {
    return self.linkObj(.string, try Obj.takeString(chars));
}

/// Allocate a copy of the given `string` slice on the heap, wrapping it in a newly
/// allocated lox string `Obj`.
///
/// Returns a pointer to the allocated lox string `Obj`.
///
/// Objects created this way are managed by the garbage collector, or cleaned up
/// when the VM is freed if they live until the end of the program.
pub fn copyString(self: *Vm, chars: []const u8) !*Obj.String {
    return self.linkObj(.string, try Obj.copyString(chars));
}

/// Free all lox objects allocated on the VM's virtual heap.
pub fn freeHeap(self: *Vm) void {
    while (self.heap) |obj| {
        self.heap = obj.next;
        self.releaseObj(obj);
    }
}

/// Free all compile-time constant strings owned by the interned strings table.
pub fn freeConstStrings(self: *Vm) void {
    for (self.strings.entries) |entry| {
        if (entry.key) |it| {
            const obj: *Obj = it.toObj();
            if (obj.flags.is_constant) obj.destroy();
        }
    }
}

/// Register a native function with the VM.
pub fn defineNative(
    self: *Vm,
    identifier: []const u8,
    arity: u8,
    fn_ptr: Obj.Native.FnPtr,
) !void {
    const fn_ident: *Obj.String = try Obj.copyString(identifier);
    const fn_obj: *Obj.Native = try Obj.create(
        .native,
        Obj.Native{ .arity = arity, .function = fn_ptr },
    );

    // Link ident string first so we can get an existing interned string, if any,
    // and link the native fn after insertion when the ident string is safe from gc
    _ = self.globals.set(self.linkObj(.string, fn_ident), .Object(fn_obj.toObj()));
    _ = self.linkObj(.native, fn_obj);
}
