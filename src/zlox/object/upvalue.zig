//! A lox `Obj` struct variant referencing a local variable captured by a closure
//! at runtime.
//!
//! An upvalue starts off as open, pointing to a local variable somewhere on the
//! stack. When an upvalue is closed, that variable's value will be moved into
//! the upvalue itself on the heap, allowing the value to be accessed and modified
//! even after going out of scope (and thus leaving the stack).

const std = @import("std");
const zlox = @import("../.lib.zig");

const mem = zlox.mem;

const Obj = zlox.object.Obj;
const Value = zlox.object.Value;

const Writer = std.Io.Writer;

// =============================================================================

const Upvalue: type = @This();

/// The base lox object header.
obj: Obj = undefined,

/// Pointer to the captured local variable.
///
/// When this upvalue is open, this points to the slot on the stack where the
/// variable's value lives. When closed, the value will be moved into `closed`
/// and this pointer will be updated to point there for the remainder of this
/// upvalue's lifetime.
location: *Value,

/// The captured value of this upvalue.
///
/// Access this value through `location` rather than this field. I'd mark this
/// private if I could but struct fields are intrinsically public in zig 💀
closed: Value = .Nil,

/// Pointer to the next open upvalue, forming a linked list of open upvalues.
next: ?*Obj.Upvalue,

/// Free allocated memory owned by this obj.
pub fn destroy(self: *const Upvalue) void {
    mem.destroy(self);
}

/// Cast this `Obj.Variant` pointer to a raw `Obj` pointer.
pub fn toObj(self: *Upvalue) *Obj {
    return &self.obj;
}

/// Cast this `Obj.Variant` to an object `Value`.
pub fn toValue(self: *Upvalue) Value {
    return .Object(self.toObj());
}

/// Close this upvalue, hoisting the value of the variable it captures onto the
/// heap.
pub fn close(self: *Upvalue) void {
    self.closed = self.location.*;
    self.location = &self.closed;
}

/// Custom formatter for `Obj` values of this variant.
pub fn format(self: *const Upvalue, writer: *Writer) !void {
    try self.location.*.format(writer);
}
