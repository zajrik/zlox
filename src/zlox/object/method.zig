//! A lox method `Obj` struct variant, binding a lox closure to a class instance
//! as a class method.

const std = @import("std");
const zlox = @import("../.lib.zig");

const mem = zlox.mem;

const Obj = zlox.object.Obj;
const Value = zlox.object.Value;

const Writer = std.Io.Writer;

// =================================================================================================

const Method: type = @This();

/// The base lox object header.
obj: Obj = undefined,

/// Class instance value to which this method obj is binding a closure.
receiver: Value,

/// The closure this method object is binding.
///
/// This closure object is not owned by the method object.
closure: *Obj.Closure,

/// Free allocated memory owned by this obj.
pub fn destroy(self: *const Method) void {
    defer mem.destroy(self);
}

/// Cast this `Obj.Variant` pointer to a raw `Obj` pointer.
pub fn toObj(self: *Method) *Obj {
    return &self.obj;
}

/// Cast this `Obj.Variant` to an object `Value`.
pub fn toValue(self: *Method) Value {
    return .Object(self.toObj());
}

/// Custom formatter for `Obj` values of this variant.
pub fn format(self: *const Method, writer: *Writer) !void {
    // SAFETY: Class methods can't be declared without identifiers
    const class: *Obj.String = self.receiver.objCast(.instance).class.identifier;
    const method: *Obj.String = self.closure.function.identifier.?;

    try writer.print("<{f} instance fn {f}()>", .{ class, method });
}
