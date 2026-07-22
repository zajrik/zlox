//! A lox class instance `Obj` struct variant.

const std = @import("std");
const zlox = @import("../.lib.zig");

const mem = zlox.mem;

const HashTable = zlox.object.HashTable;
const Obj = zlox.object.Obj;
const Value = zlox.object.Value;

const Writer = std.Io.Writer;

// ============================================================================

const Instance: type = @This();

/// The base lox object header.
obj: Obj = undefined,

/// The class this instance obj is an instance of.
///
/// This object is not owned by the instance obj.
class: *Obj.Class,

/// Holds field data for this class instance.
fields: HashTable = .empty,

/// Free allocated memory owned by this obj.
pub fn destroy(self: *Instance) void {
    defer mem.destroy(self);
    self.fields.deinit();
}

/// Cast this `Obj.Variant` pointer to a raw `Obj` pointer.
pub fn toObj(self: *Instance) *Obj {
    return &self.obj;
}

/// Cast this `Obj.Variant` to an object `Value`.
pub fn toValue(self: *Instance) Value {
    return .Object(self.toObj());
}

/// Custom formatter for `Obj` values of this variant.
pub fn format(self: *const Instance, writer: *Writer) !void {
    try writer.print("<Instance of {f}>", .{self.class.identifier});
}
