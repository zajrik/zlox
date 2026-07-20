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

const HashTable = zlox.object.HashTable;
const Obj = zlox.object.Obj;
const Value = zlox.object.Value;

const CallFrame = zlox.vm.CallFrame;
const Vm = zlox.vm.Vm;

const ArrayList = std.ArrayList;

const printf = std.debug.print;

// ============================================================================

const Gc: type = @This();

/// Pointer to the VM instance for which the GC will collect garbage.
vm: *Vm,

/// Stack of objects marked as alive by the GC that can hold references to other
/// objects that need to be traced and marked.
stack: ArrayList(*Obj),

/// Allocate a new `Gc` instance on the heap, returning a pointer to it.
///
/// The caller owns the returned pointer and is responsible for freeing it.
pub fn create(vm: *Vm) !*Gc {
    return try mem.createStruct(
        Gc,
        .{ .vm = vm, .stack = .empty },
    );
}

/// Destroy the `Gc`, freeing its owned resources.
pub fn destroy(self: *Gc) void {
    defer mem.destroy(self);
    self.stack.deinit(mem.allocator());
}

/// Initiate a GC cycle, marking all living objs and freeing all non-living objs.
pub fn collect(self: *Gc) !void {
    if (comptime debug.print_gc) printf("GC start --\n", .{});

    try self.markRoots();
    try self.traceReferences();
    self.sweepTable(self.vm.strings);
    try self.sweep();

    self.vm.next_gc = self.vm.bytes_allocated * 2;

    if (comptime debug.print_gc) printf("GC end --\n", .{});
}

/// Mark all reachable objects in the VM as alive for this GC cycle.
pub fn markRoots(self: *Gc) !void {
    // Mark stack values
    var value: [*]Value = &self.vm.stack.values;
    while (@intFromPtr(value) < @intFromPtr(self.vm.stack.top)) : (value += 1) {
        try self.markValue(value[0]);
    }

    // Mark callframe closures
    var frame: [*]CallFrame = &self.vm.frame_stack.values;
    while (@intFromPtr(frame) < @intFromPtr(self.vm.frame_stack.top)) : (frame += 1) {
        try self.markObject(&frame[0].closure.obj);
    }

    // Mark open upvalues
    var upvalue: ?*Obj.Upvalue = self.vm.open_upvalues;
    while (upvalue) |it| : (upvalue = it.next) try self.markObject(&it.obj);

    // Mark globals
    try self.markTable(self.vm.globals);
}

/// Trace through marked object references to mark any further reachable objects.
pub fn traceReferences(self: *Gc) !void {
    while (self.stack.pop()) |obj| try self.visitObject(obj);
}

/// Free all objects that were not marked as alive during this GC cycle.
pub fn sweep(self: *const Gc) !void {
    var prev: ?*Obj = null;
    var next: ?*Obj = self.vm.heap;

    while (next) |it| {
        // Unmark marked object and advance
        if (it.flags.is_constant or it.flags.is_alive) {
            it.flags.is_alive = false;
            prev = it;
            next = it.next;
            continue;
        }

        // Otherwise free unmarked object and unlink it from the VMs tracked objs
        next = it.next;
        self.vm.releaseObj(it);

        // If there is a previous object then we're unlinking the object linked
        // to it. Otherwise we're unlinking the root object
        (if (prev) |obj| &obj.next else &self.vm.heap).* = next;
    }
}

/// Mark the given value as alive, allowing it to live through this GC cycle.
///
/// Only affects `Obj` values.
pub fn markValue(self: *Gc, value: Value) !void {
    if (value.is(.obj)) try self.markObject(value.obj);
}

/// Mark the given object as alive, allowing it to live through this GC cycle.
pub fn markObject(self: *Gc, obj: *Obj) !void {
    if (obj.flags.is_alive) return;
    obj.flags.is_alive = true;

    // Add objects with additional references to the stack to visit next
    switch (obj.type) {
        .closure, .upvalue => try self.stack.append(mem.allocator(), obj),
        else => return,
    }
}

/// Visit all object references reachable from the given `obj`, marking them as
/// alive for this GC cycle.
pub fn visitObject(self: *Gc, obj: *Obj) !void {
    switch (obj.type) {
        .upvalue => |T| try self.markValue(obj.as(T).closed),
        .closure => |T| for (obj.as(T).upvalues) |upvalue| {
            try self.markObject(&upvalue.obj);
        },
        else => return,
    }
}

/// Mark all keys and values in the given `table` as alive, allowing them to live
/// through this GC cycle.
pub fn markTable(self: *Gc, table: *HashTable) !void {
    for (table.entries) |entry| {
        if (entry.key) |key| try self.markObject(&key.obj);
        try self.markValue(entry.val);
    }
}

/// Remove all entries from the given table that have keys not marked as alive
/// for this GC cycle.
///
/// Constant keys will not be removed.
pub fn sweepTable(_: *const Gc, table: *HashTable) void {
    for (table.entries) |entry| {
        if (entry.key) |key| {
            if (key.obj.flags.is_constant or key.obj.flags.is_alive) continue;
            _ = table.delete(key);
        }
    }
}
