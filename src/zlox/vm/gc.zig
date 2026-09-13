//! A mark-sweep garbage collector implementation lovingly shoehorned into what
//! has diverged far enough from the book that I'm sure this will be a challenge
//! 🤡🤡🤡🤡🤡
//!
//! ### Garbage Collection
//!
//! The book presents a problem wherein an object can be created at runtime and
//! swept by the GC on the next allocation if that object was not put in a location
//! that allows it to be marked as alive by the GC. Bob avoids this by stashing the
//! object in the stack until it's no longer at risk of being swept. This is fine
//! because these stack-stashing operations all happen within the same instruction
//! loop so the stack is not accessed by any additional instructions while the objects
//! are stashed there.
//!
//! I don't like it though, it feels clunky and things that feel clunky make me
//! itchy until I write a tailor-made solution that doesn't make me feel that way.
//!
//! I avoid this problem and thus the need to rely on the stack as a stash for
//! wayward objects by evaluating whether to run the GC when the object is linked
//! with the VM rather than when it is allocated. Any object that is created at
//! runtime without being linked to the VM is assumed to be critical to the runtime
//! until it is linked and becomes managed.
//!
//! This eliminates the need to stash objects on the stack during operations as
//! demonstrated in the book, but does mean that any object that for whatever reason
//! might actually need to be swept immediately will live until the next GC cycle.
//!
//! Now, I'm no expert, but I can't foresee any reason why an object would ever need
//! to live that briefly, so I don't think this should ever be a problem.
//!
//! That said, in the event that *additional* objects need to be allocated before
//! any preceeding object has been safely homed, they should all be created manually
//! using `Obj.create` and linked with the VM as they're being placed in their homes,
//! wherever that may be. This ensures none of the objects are able to be swept
//! by the GC before it is safe to do so.

const std = @import("std");
const zlox = @import("../.lib.zig");

const mem = zlox.mem;
const debug = zlox.debug;

const StackIterator = zlox.object.storage.StackIterator;
const Heap = zlox.object.storage.Heap;
const Table = zlox.object.storage.Table;
const Obj = zlox.object.Obj;
const Value = zlox.object.Value;

const CallFrame = zlox.vm.CallFrame;
const Vm = zlox.vm.Vm;

const ArrayList = std.ArrayList;

const printf = std.debug.print;

// =================================================================================================

const Self: type = @This();

/// Pointer to the VM instance for which the GC will collect garbage.
vm: *Vm,

/// The threshold of bytes allocated on the VM's heap at which the next GC sweep
/// should trigger.
next_gc: usize = 1024 * 1024,

/// Stack of objects marked as alive by the GC that can hold references to other
/// objects that need to be traced and marked.
visit_stack: ArrayList(*Obj) = .empty,

/// Represents possible errors returned from GC operations.
pub const Error = error{GcFailure};

/// Allocate a new `Gc` instance on the heap, returning a pointer to it.
///
/// The caller owns the returned pointer and is responsible for freeing it.
pub fn create(vm: *Vm) !*Self {
    return try mem.createStruct(Self, .{ .vm = vm });
}

/// Destroy the `Gc`, freeing its owned resources.
pub fn destroy(self: *Self) void {
    defer mem.destroy(self);
    self.visit_stack.deinit(mem.allocator());
}

/// Report the given object being linked to the virtual heap to the GC.
///
/// If the heap size after adding the given object exceeds the GC threshold, a sweep
/// will be triggered to make sure there is room on the heap for the given object.
///
/// Returns the size of the given object in bytes, or an error if something went
/// wrong while running the GC sweep.
pub fn report(self: *Self, obj: *Obj) Error!usize {
    const obj_size: usize = obj.size();

    // Run GC if we exceed the GC threshold. This should only fail if we're out of
    // memory when allocating memory for tracking marked objs before tracing, at
    // which point things are out of our hands 💀 We could potentially allocate
    // a rainy-day fund of memory in the GC that can be freed if that happens and
    // then try running the GC again, but Bob didn't bother in the book so I'm not
    // likely to bother here unless it becomes a problem for me personally (it won't)

    if (self.vm.heap.size + obj_size > self.next_gc or debug.stress_gc) {
        self.collect() catch return Error.GcFailure;
    }

    return obj_size;
}

/// Initiate a GC cycle, marking all living objs and freeing all non-living objs.
pub fn collect(self: *Self) !void {
    if (comptime debug.print_gc) printf("-- GC start\n", .{});
    defer if (comptime debug.print_gc) printf("-- GC end\n", .{});

    try self.markRoots();
    try self.visitReferences();

    self.sweepTable(&self.vm.strings);
    self.sweep();

    self.next_gc = self.vm.heap.size * 2;
}

/// Mark the given value as alive, allowing it to live through this GC cycle.
///
/// Only affects `Obj` values.
pub fn markValue(self: *Self, value: *Value) !void {
    if (value.as(.obj)) |it| try self.markObject(it);
}

/// Mark the given object as alive, allowing it to live through this GC cycle.
pub fn markObject(self: *Self, obj: *Obj) !void {
    if (obj.flags.is_alive) return;
    obj.flags.is_alive = true;

    // Add objects with additional references to the stack to visit next
    switch (obj.type) {
        .closure,
        .upvalue,
        .class,
        .instance,
        .method,
        => try self.visit_stack.append(mem.allocator(), obj),

        else => return,
    }
}

/// Mark all keys and values in the given `table` as alive, allowing them to live
/// through this GC cycle.
pub fn markTable(self: *Self, table: *Table) !void {
    for (table.entries) |*entry| {
        if (entry.key) |key| try self.markObject(key.toObj());
        try self.markValue(&entry.val);
    }
}

/// Mark all reachable objects in the VM as alive for this GC cycle.
pub fn markRoots(self: *Self) !void {
    // Mark stack values
    var stack_iter: StackIterator(Value) = self.vm.stack.iter();
    while (stack_iter.next()) |it| try self.markValue(it);

    // Mark callframe closures
    var frame_iter: StackIterator(CallFrame) = self.vm.frame_stack.iter();
    while (frame_iter.next()) |it| try self.markObject(it.closure.toObj());

    // Mark open upvalues
    var upvalue: ?*Obj.Upvalue = self.vm.open;
    while (upvalue) |it| : (upvalue = it.next) try self.markObject(it.toObj());

    // Mark globals, etc.
    try self.markTable(&self.vm.globals);
    if (self.vm.init_string) |it| try self.markObject(it.toObj());
}

/// Visit all object references reachable from the given `obj`, marking them as
/// alive for this GC cycle.
pub fn visit(self: *Self, obj: *Obj) !void {
    switch (obj.type) {
        .upvalue => |T| try self.markValue(&obj.cast(T).closed),
        .closure => |T| for (obj.cast(T).upvalues) |upvalue| {
            try self.markObject(upvalue.toObj());
        },
        .class => |T| {
            const class: *Obj.Class = obj.cast(T);
            try self.markTable(&class.methods);
        },
        .instance => |T| {
            const instance: *Obj.Instance = obj.cast(T);
            try self.markObject(instance.class.toObj());
            try self.markTable(&instance.fields);
        },
        .method => |T| {
            const method: *Obj.Method = obj.cast(T);
            try self.markValue(&method.receiver);
            try self.markObject(method.closure.toObj());
        },
        else => return,
    }
}

/// Visit all marked objects that hold references to other objects, marking those
/// objects as alive for this cycle.
///
/// Any further nested objects with references will be added to the visit stack to
/// be visited until all reachable objects have been marked and the stack is empty.
pub fn visitReferences(self: *Self) !void {
    while (self.visit_stack.pop()) |it| try self.visit(it);
}

/// Free all objects on the virtual heap that were not marked as alive during
/// this GC cycle.
pub fn sweep(self: *const Self) void {
    var iter: Heap.Iterator = self.vm.heap.iter();
    while (iter.next()) |it| {
        // Unmark marked object and advance
        if (it.flags.is_constant or it.flags.is_alive) {
            it.flags.is_alive = false;
            continue;
        }

        // Otherwise release unmarked object from the heap
        self.vm.heap.release(it);
    }
}

/// Remove all entries from the given table that have keys not marked as alive
/// for this GC cycle.
///
/// Constant keys will not be removed.
pub fn sweepTable(_: *const Self, table: *Table) void {
    for (table.entries) |entry| {
        if (entry.key) |key| {
            if (key.obj.flags.is_constant or key.obj.flags.is_alive) continue;
            _ = table.delete(key);
        }
    }
}
