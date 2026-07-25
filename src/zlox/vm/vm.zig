//! Virtual machine for executing lox instructions.

const std = @import("std");
const zlox = @import("../.lib.zig");

const debug = zlox.debug;
const mem = zlox.mem;
const native = zlox.vm.native;

const Chunk = zlox.compiler.Chunk;
const ClassContext = zlox.compiler.ClassContext;
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

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Fnv1a_32 = std.hash.Fnv1a_32;
const Io = std.Io;

const FRAME_MAX = zlox.common.FRAME_MAX;
const STACK_MAX = zlox.common.STACK_MAX;

const printf = std.debug.print;

// =================================================================================================

const Vm: type = @This();

/// `std.Io` interface to be passed to lox native functions.
io: Io,

/// Function call frame stack.
frame_stack: Stack(CallFrame, FRAME_MAX) = .empty,

/// Virtual machine value stack.
stack: Stack(Value, STACK_MAX) = .empty,

/// Contains all runtime-interned strings.
strings: HashTable = .empty,

/// Contains all runtime global variables.
globals: HashTable = .empty,

/// Linked list of open upvalues.
///
/// The head of the list is the open upvalue capturing the local variable highest
/// on the stack relative to other captured locals at the point the list is observed.
open: ?*Obj.Upvalue = null,

/// The virtual heap of the VM, implemented as a linked list of `Obj` values.
///
/// Contains all lox objects created by the VM at runtime, to be used by the
/// GC to reach unreferenced objects after tracing living object references.
heap: ?*Obj = null,

/// The number of bytes allocated by objects linked to the VM's heap.
heap_size: usize = 0,

/// The threshold of bytes allocated at which the next GC sweep should trigger.
next_gc: usize = 1024 * 1024,

/// Garbage collector instance.
///
/// This is owned by the VM and must be freed when the VM is freed.
gc: *Gc = undefined,

/// `init` function identifier string, for looking up class initializers.
///
/// This
init_string: ?*Obj.String = null,

/// Allocate a new `Vm` instance on the heap, returning a pointer to it.
///
/// The caller owns the returned pointer and is responsible for freeing it.
pub fn create(io: Io) !*Vm {
    const vm: *Vm = try mem.createStruct(Vm, .{ .io = io });
    vm.frame_stack.reset();
    vm.stack.reset();
    vm.gc = try .create(vm);

    // SAFETY: 🤌
    vm.init_string = try vm.copyString("init");
    vm.init_string.?.obj.flags.is_constant = true;

    return vm;
}

/// Destroy this `Vm`, freeing its owned resources.
pub fn destroy(self: *Vm) void {
    defer mem.destroy(self);
    self.strings.deinit();
    self.globals.deinit();
    self.gc.destroy();
    self.init_string = null;
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
    var class_context: ?*ClassContext = null;

    const parser: *Parser = try .create(&tokenizer);
    const compiler: *Compiler = try .create(
        .script,
        parser,
        null,
        &class_context,
        &self.strings,
    );

    defer self.freeInternedConstants();
    defer parser.destroy();
    defer compiler.destroy();
    defer self.freeHeap();

    const script: *Obj.Function = try compiler.compile() orelse return .compile_error;
    errdefer script.destroy();
    defer script.destroy();

    const closure: *Obj.Closure = try self.createObj(
        .closure,
        Obj.Closure{
            .function = script,
            .upvalues = try mem.alloc(*Obj.Upvalue, script.upvalue_count),
        },
    );

    if (script.chunk.isEmpty()) return .ok;

    // Push script closure to stack to match reserved local slot 0
    self.stack.push(closure.toValue());

    // Push callframe to execute script closure
    self.frame_stack.push(CallFrame{
        .closure = closure,
        .ip = script.chunk.ip(),
        .slots = &self.stack.values,
    });

    try native.bootstrapNatives(self);

    return self.run() catch |e| switch (e) {
        // If we catch a runtime error here, it's already been reported
        error.runtime_error => .runtime_error,

        // Otherwise report unexpected error
        else => self.errFmt(
            "An unexpected error occurred: {s}",
            .{@errorName(e)},
        ),
    };
}

/// Print a runtime error and stack trace at the current instruction.
fn err(self: *Vm, comptime fmt: []const u8) error{runtime_error} {
    return self.errFmt(fmt, .{});
}

/// Print a runtime error and stack trace at the current instruction.
///
/// Accepts a format string and a tuple of format arguments.
fn errFmt(self: *Vm, comptime fmt: []const u8, args: anytype) error{runtime_error} {
    printf("Runtime error: " ++ fmt, args);
    printf("\n", .{});

    // Print stack trace
    var i: usize = 0;
    while (i < self.frame_stack.size()) : (i += 1) {
        const frame: *CallFrame = self.frame_stack.slot(i);
        const function: *Obj.Function = frame.closure.function;
        const instruction_offset: usize = frame.ip - function.chunk.ip() - 1;

        printf("[line {d}] in ", .{function.chunk.lineAt(instruction_offset)});

        if (function.identifier) |it| {
            printf("{f}()\n", .{it});
        } else {
            printf("script\n", .{});
        }
    }

    self.stack.reset();
    return error.runtime_error;
}

/// Perform a binary operation with the top two number values on the stack.
fn binaryOp(self: *Vm, op: OpCode) !void {
    if (self.stack.peek(0).isNot(.number) or self.stack.peek(1).isNot(.number)) {
        return self.err("Operands must be numbers");
    }

    const b: Value = self.stack.pop();
    const a: Value = self.stack.pop();

    self.stack.push(switch (op) {
        .add => .Number(a.number + b.number),
        .subtract => .Number(a.number - b.number),
        .multiply => .Number(a.number * b.number),
        .divide => .Number(a.number / b.number),

        .greater => .Bool(a.number > b.number),
        .less => .Bool(a.number < b.number),

        else => return self.errFmt(
            "Invalid binary operator: '{s}'",
            .{@tagName(op)},
        ),
    });
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
    var next: ?*Obj.Upvalue = self.open;

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
    (if (upvalue) |it| &it.next else &self.open).* = capture;

    return capture;
}

/// Close the open upvalue associated with the given local variable, or the first
/// open upvalue capturing a local higher on the stack than the given one, as well
/// as any open upvalues capturing locals above it on the stack.
fn closeUpvalues(self: *Vm, local: *const Value) void {
    while (self.open) |it| : (self.open = it.next) {
        if (@intFromPtr(it.location) < @intFromPtr(local)) break;
        it.close();
    }
}

/// Attempt to bind a method with the given `ident` from the given `class` to the
/// receiver (class instance) at the top of the stack.
///
/// Replaces the receiver on the stack with the bound method.
///
/// Returns `null` if the method doesn't exist on the given class, returns an error
/// if something went wrong while allocating the bound method object.
fn bindMethod(self: *Vm, class: *Obj.Class, ident: *Obj.String) !?void {
    const method: Value = class.methods.get(ident) orelse return null;
    const bound_method: *Obj.Method = try self.createObj(
        .method,
        Obj.Method{
            .receiver = self.stack.peek(0),
            .closure = method.objCast(.closure),
        },
    );

    _ = self.stack.replace(0, bound_method.toValue());
}

/// Attempt to call the given `callee` as a function using the top `arg_count` values
/// from the stack as its arguments.
///
/// Emits a runtime error if `callee` is not a callable function, method, or class
/// initializer.
fn callValue(self: *Vm, callee: Value, arg_count: u8) !void {
    if (callee.is(.obj)) switch (callee.obj.type) {
        .native => {
            const native_obj: *Obj.Native = callee.objCast(.native);
            const native_fun: Obj.Native.FnPtr = native_obj.function;

            if (arg_count != native_obj.arity) return self.errFmt(
                "Expected {d} arguments, got {d}",
                .{ native_obj.arity, arg_count },
            );

            const result: Value = native_fun(
                self.io,
                arg_count,
                self.stack.top - arg_count,
            );

            // Pop native function and its args from stack
            self.stack.top -= arg_count + 1;

            self.stack.push(result);
        },

        .closure => return self.callFun(
            callee.objCast(.closure),
            arg_count,
        ),

        .class => {
            const instance: *Obj.Instance = try self.createObj(
                .instance,
                Obj.Instance{ .class = callee.objCast(.class) },
            );

            // Replace class object on stack with instance
            (self.stack.top - 1 - arg_count)[0] = instance.toValue();

            // Call initializer if present
            // SAFETY: init_string is definitely defined at this point
            if (instance.class.methods.get(self.init_string.?)) |init| {
                return self.callFun(init.objCast(.closure), arg_count);
            }

            // Otherwise error for mismatched arity on an empty initializer
            else if (arg_count != 0) return self.errFmt(
                "Expected 0 arguments, got {d}",
                .{arg_count},
            );

            return;
        },

        .method => {
            const method: *Obj.Method = callee.objCast(.method);
            // Replace method closure on stack with method receiver
            (self.stack.top - 1 - arg_count)[0] = method.receiver;
            return self.callFun(method.closure, arg_count);
        },

        // Fall through for non-callable values
        else => {},
    };

    return self.err(
        "Can only call functions, methods, and class initializers",
    );
}

/// Call the given `function`, using the top `arg_count` stack values as arguments.
fn callFun(self: *Vm, closure: *Obj.Closure, arg_count: u8) !void {
    if (arg_count != closure.function.arity) return self.errFmt(
        "Expected {d} arguments, got {d}",
        .{ closure.function.arity, arg_count },
    );

    if (self.frame_stack.size() == FRAME_MAX) return self.err(
        "Callframe stack overflow",
    );

    // Push callframe for the given function
    self.frame_stack.push(CallFrame{
        .closure = closure,
        .ip = closure.function.chunk.ip(),
        .slots = @ptrCast(self.stack.top - 1 - arg_count),
    });
}

/// Invoke a method with the given `ident` on the receiver found on the stack below
/// `arg_count` argument values.
fn invoke(self: *Vm, ident: *Obj.String, arg_count: u8) !void {
    const receiver: Value = self.stack.peek(arg_count);
    const instance: *Obj.Instance = receiver.asObj(.instance) orelse {
        return self.err("Can't call method on non-instance value");
    };

    // If the "method" is actually a function field, call it as a function rather
    // than performing a method lookup and invocation
    if (instance.fields.get(ident)) |it| {
        // Replace receiver with field function
        (self.stack.top - 1 - arg_count)[0] = it;
        try self.callValue(it, arg_count);
    }

    // Otherwise perform invoke the method
    try self.invokeFromClass(instance.class, ident, arg_count);
}

/// Invoke a method with the given `ident` from the given `class` on the receiver
/// on the stack using the given `arg_count` arguments.
///
/// The method will be called using the receiver already on the stack below
/// the method arguments.
///
/// Returns an error if the given method is undefined.
fn invokeFromClass(self: *Vm, class: *Obj.Class, ident: *Obj.String, arg_count: u8) !void {
    if (class.methods.get(ident)) |method| return try self.callFun(
        method.objCast(.closure),
        arg_count,
    );

    return self.errFmt("Undefined method '{f}'", .{ident});
}

// Instruction loop ================================================================================

/// Run instructions from the currently loaded chunk.
fn run(self: *Vm) !ExecutionResult {
    printf("\n== begin execution ==\n", .{});

    while (true) {
        // Grab the current frame off of the callframe stack
        const frame: *CallFrame = self.frame_stack.slot(0);

        if (comptime debug.trace_execution) {
            if (debug.print_stack) printf("{f}", .{&self.stack});

            _ = debug.disassembleInstruction(
                &frame.closure.function.chunk,
                // Find next instruction offset by subtracting the address of
                // the first instruction from the address of the next instruction
                frame.ip - frame.closure.function.chunk.ip(),
            );
        }

        const op: u8 = frame.readByte();

        switch (OpCode.fromByte(op)) {
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
                    try self.binaryOp(.add);
                    continue;
                }

                // Otherwise try to concatenate values into a string
                const c: *Obj.String = a.concat(b) catch |e| return switch (e) {
                    error.invalid_operand => self.errFmt(
                        "Invalid operands for '+', got: {s}, {s}",
                        .{ @tagName(a), @tagName(b) },
                    ),
                    else => self.errFmt(
                        "Error concatenating values: {s}",
                        .{@errorName(e)},
                    ),
                };

                self.stack.popN(2);
                self.stack.push((try self.linkObj(.string, c)).toValue());
            },
            .subtract => try self.binaryOp(.subtract),
            .multiply => try self.binaryOp(.multiply),
            .divide => try self.binaryOp(.divide),

            .negate => {
                const value: Value = self.stack.peek(0);
                if (value.isNot(.number)) return self.err(
                    "Operand must be a number",
                );
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
                _ = try self.globals.set(ident, self.stack.peek(0));
                _ = self.stack.pop();
            },
            .global_set => {
                const ident: *Obj.String = frame.readString();

                // If the global variable isn't defined before setting, throw a
                // runtime error and delete the entry from the globals table
                if (try self.globals.set(ident, self.stack.peek(0))) {
                    _ = self.globals.delete(ident);
                    return self.errFmt("Undefined variable '{f}'", .{ident});
                }
            },
            .global_get => {
                const ident: *Obj.String = frame.readString();
                const value: Value = self.globals.get(ident) orelse {
                    return self.errFmt("Undefined variable '{f}'", .{ident});
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

            .property_set => {
                // Peek instance on stack
                const inst_val: Value = self.stack.peek(1);
                const inst_obj: *Obj.Instance = inst_val.asObj(.instance) orelse {
                    return self.err("Only class instances have properties");
                };

                // Set property/field on instance
                const property: *Obj.String = frame.readString();
                _ = try inst_obj.fields.set(property, self.stack.peek(0));

                // Pop instance from stack, leaving set expression value
                _ = self.stack.swap(0, 1);
                _ = self.stack.pop();
            },
            .property_get => {
                // Peek instance on stack
                const inst_val: Value = self.stack.peek(0);
                const inst_obj: *Obj.Instance = inst_val.asObj(.instance) orelse {
                    return self.err("Only class instances have properties");
                };

                // Try getting property/field from instance
                const property: *Obj.String = frame.readString();
                if (inst_obj.fields.get(property)) |it| {
                    _ = self.stack.replace(0, it);
                    continue;
                }

                // If we couldn't find a property/field, try it as a method. If a
                // method is found, it'll be on the stack ready to be called so we
                // can continue to the next instruction
                try self.bindMethod(inst_obj.class, property) orelse {
                    // Return nil if prop/field/method doesn't exist
                    _ = self.stack.replace(0, .Nil);
                };
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
                try self.callValue(self.stack.peek(arg_count), arg_count);
            },
            .invoke => {
                const ident: *Obj.String = frame.readString();
                const arg_count: u8 = frame.readByte();
                try self.invoke(ident, arg_count);
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

                self.stack.push((try self.linkObj(.closure, closure)).toValue());
            },

            .class => {
                const class_ident: *Obj.String = frame.readString();
                const class_obj: *Obj.Class = try self.createObj(
                    .class,
                    Obj.Class{ .identifier = class_ident },
                );

                self.stack.push(class_obj.toValue());
            },

            .method => {
                const closure: Value = self.stack.peek(0);
                const class: *Obj.Class = self.stack.peek(1).objCast(.class);

                _ = try class.methods.set(frame.readString(), closure);
                _ = self.stack.pop();
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

            _ => return self.errFmt("Unknown opcode: {d}", .{op}),
        }
    }
}

// Object management functions =====================================================================

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
pub fn linkObj(self: *Vm, comptime T: Obj.Type, object: *Obj.Variant(T)) !*Obj.Variant(T) {
    // Pre-hash and intern string objects
    if (T == .string) {
        // Return interned string if it exists
        object.hash = Fnv1a_32.hash(object.chars);
        if (self.strings.findString(object.chars, object.hash)) |it| {
            object.destroy();
            return it;
        }

        _ = self.strings.set(object, .Nil) catch |e| return self.errFmt(
            "Error interning string: {s}",
            .{@errorName(e)},
        );
    }

    if (comptime debug.stress_gc) self.gc.collect() catch {};

    // Run GC if we exceed the GC threshold. This should only fail if we're out of
    // memory when allocating memory for tracking marked objs before tracing, at
    // which point things are out of our hands 💀 We could potentially allocate
    // a rainy-day fund of memory in the GC that can be freed if that happens and
    // then try running the GC again, but Bob didn't bother in the book so I'm not
    // likely to bother here unless it becomes a problem for me personally (it won't)

    self.heap_size += @sizeOf(Obj.Variant(T));
    if (T == .string) self.heap_size += @sizeOf(u8) * object.chars.len;
    if (self.heap_size > self.next_gc) self.gc.collect() catch |e| return self.errFmt(
        "Error running garbage collector: {s}",
        .{@errorName(e)},
    );

    // Link object to vm heap for gc tracing
    object.obj.next = self.heap;
    self.heap = object.toObj();

    return object;
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
    while (self.heap) |obj| : (self.releaseObj(obj)) {
        self.heap = obj.next;

        // Remove interned runtime strings before releasing
        if (obj.as(.string)) |it| _ = self.strings.delete(it);
    }
}

/// Free all compile-time constant strings owned by the interned strings table.
pub fn freeInternedConstants(self: *Vm) void {
    var keys: HashTable.KeyIterator = self.strings.keys();
    while (keys.next()) |it| {
        const obj: *Obj = it.toObj();
        if (obj.flags.is_constant) obj.destroy();
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

    // Link ident string first so we can use the existing interned string, if any,
    // and link the native fn after insertion when the ident string is safe from gc
    _ = try self.globals.set(try self.linkObj(.string, fn_ident), fn_obj.toValue());
    _ = try self.linkObj(.native, fn_obj);
}
