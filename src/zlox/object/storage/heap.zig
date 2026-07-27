//! A virtual heap for the virtual machine.
//!
//! Objects must be linked to the heap to be allowed to be managed by the virtual
//! machine and garbage collector.

const std = @import("std");
const zlox = @import("../../.lib.zig");

const Obj = zlox.object.Obj;
const Table = zlox.object.storage.Table;
const Gc = zlox.vm.Gc;

const Fnv1a_32 = std.hash.Fnv1a_32;

// =================================================================================================

const Heap: type = @This();

/// The root node in a linked list of objects linked to the heap.
///
/// The garbage collector will traverse this list and free objects that are no
/// longer referenced.
root: ?*Obj = null,

/// The total size in bytes of all allocated objects linked to the heap.
size: usize = 0,

/// Reference to the VM's interned-strings table.
strings: *Table,

/// Reference to the garbage collector for reporting heap allocations.
gc: *Gc,

/// Represents possible errors returned from heap operations.
pub const Error = error{intern_failure} || Gc.Error;

/// Initialize a new heap on the stack.
///
/// The heap itself does not need any deinitialization, but don't forget to call
/// `Heap.free()` at the end of the VM's lifetime.
pub fn init(strings: *Table, gc: *Gc) Heap {
    return .{
        .strings = strings,
        .gc = gc,
    };
}

/// Link the given object with the virtual heap, allowing it to be traced by the GC.
///
/// Returns a pointer to the linked object. In the event that the given object is
/// a string that has already been interned, it will be destroyed and the interned
/// string will be returned instead.
///
/// Assume the heap takes ownership of any object given so there will be no need
/// to manually clean that object up.
///
/// The size of the created object will be reported to the GC so that it can keep
/// track of when it needs to run.
pub fn link(self: *Heap, comptime T: Obj.Type, object: *Obj.Variant(T)) Error!*Obj.Variant(T) {
    // Intern string objects
    if (T == .string) {
        // Return interned string if it already exists
        if (self.strings.findString(object.chars, object.hash)) |it| {
            object.destroy();
            return it;
        }
        _ = self.strings.set(object, .Nil) catch return Error.intern_failure;
    }

    self.size += try self.gc.report(T, object);

    object.obj.next = self.root;
    self.root = object.toObj();

    return object;
}

/// Destroy an object linked to the virtual heap, making note of the released bytes
/// to keep heap size up-to-date.
///
/// Note: Make sure the object is unlinked from the VM heap before releasing.
pub fn release(self: *Heap, obj: *Obj) void {
    self.size -= obj.size();
    obj.destroy();
}

/// Free all allocated lox objects linked to the virtual heap.
pub fn free(self: *Heap) void {
    while (self.root) |obj| : (self.release(obj)) {
        self.root = obj.next;

        // Remove interned runtime strings before releasing
        if (obj.as(.string)) |it| _ = self.strings.delete(it);
    }
}
