//! A virtual heap for the virtual machine.
//!
//! Objects must be linked to the heap to be allowed to be managed by the virtual
//! machine and garbage collector.

const std = @import("std");
const zlox = @import("../../.lib.zig");

const Obj = zlox.object.Obj;
const Table = zlox.object.storage.Table;
const Gc = zlox.vm.Gc;

const DoublyLinkedList = std.DoublyLinkedList;
const Fnv1a_32 = std.hash.Fnv1a_32;

// =================================================================================================

const Heap: type = @This();

/// Doubly-linked-list of objects linked to the heap.
heap_list: DoublyLinkedList = .{},

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
/// If the given object is a string, it will be interned.
///
/// Returns a pointer to the linked object. In the event that the given object is
/// a string that has already been interned, it will be destroyed and the a pointer
/// to the interned string will be returned instead.
///
/// Assume the heap takes ownership of any object given so there will be no need
/// to manually clean that object up.
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

    // Report link to GC to trigger sweep if needed
    self.size += try self.gc.report(T, object);

    self.heap_list.append(&object.toObj().heap_node);
    return object;
}

/// Destroy an object linked to the virtual heap, releasing its allocated memory
/// and unlinking it from the heap.
pub fn release(self: *Heap, obj: *Obj) void {
    self.heap_list.remove(&obj.heap_node);
    self.size -= obj.size();
    obj.destroy();
}

/// Free all allocated lox objects linked to the virtual heap.
pub fn free(self: *Heap) void {
    var heap: Iterator = self.iter();
    while (heap.next()) |obj| : (self.release(obj)) {
        // Remove interned runtime strings before releasing
        if (obj.as(.string)) |it| _ = self.strings.delete(it);
    }
}

/// Returns an iterator over the objects on the virtual heap.
pub fn iter(self: *Heap) Iterator {
    return .{ .next_obj = self.heap_list.first };
}

/// An iterator over objects on the virtual heap.
pub const Iterator = struct {
    /// Heap node of the next object on the virtual heap.
    next_obj: ?*DoublyLinkedList.Node,

    /// Returns the next object on the virtual heap, if any.
    ///
    /// Returns `null` if we've reached the end of the heap.
    pub fn next(self: *Iterator) ?*Obj {
        if (self.next_obj) |it| {
            self.next_obj = it.next;
            return @fieldParentPtr("heap_node", it);
        }
        return null;
    }
};
