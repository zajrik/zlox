//! A lox class `Obj` struct variant.

const std = @import("std");
const zlox = @import("../.lib.zig");

const mem = zlox.mem;

const Table = zlox.object.storage.Table;
const Obj = zlox.object.Obj;
const Value = zlox.object.Value;

const Writer = std.Io.Writer;

// =================================================================================================

const Class: type = @This();

/// The base lox object header.
obj: Obj = undefined,

/// The name of this class.
///
/// This string is a compile-time constant and not owned by the class itself.
identifier: *Obj.String,

/// Holds methods defined for instances of this class.
///
/// The method objs live on the virtual heap and are not owned by the class itself.
methods: Table = .empty,

/// Free allocated memory owned by this obj.
pub fn destroy(self: *Class) void {
    defer mem.destroy(self);
    self.methods.deinit();
}

/// Cast this `Obj.Variant` pointer to a raw `Obj` pointer.
pub fn toObj(self: *Class) *Obj {
    return &self.obj;
}

/// Cast this `Obj.Variant` to an object `Value`.
pub fn toValue(self: *Class) Value {
    return .Object(self.toObj());
}

/// Custom formatter for `Obj` values of this variant.
pub fn format(self: *const Class, writer: *Writer) !void {
    try writer.print("<class {f}>", .{self.identifier});
}
