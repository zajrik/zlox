//! A lox native function `Obj` struct variant.

const std = @import("std");
const zlox = @import("../.lib.zig");

const mem = zlox.mem;

const Obj = zlox.object.Obj;
const Value = zlox.object.Value;

const Writer = std.Io.Writer;

// ============================================================================

const Native: type = @This();

/// Represents a pointer to a native function callable from lox code.
pub const FnPtr: type = *const fn (std.Io, u8, [*]Value) Value;

/// The base lox object header.
obj: Obj = undefined,

/// The number of arguments the wrapped native function accepts.
arity: u8,

/// Pointer to the native function this obj wraps.
function: FnPtr,

/// Free allocated memory owned by this obj.
pub fn destroy(self: *const Native) void {
    defer mem.destroy(self);
}

/// Cast this `Obj.Variant` pointer to a raw `Obj` pointer.
pub fn toObj(self: *Native) *Obj {
    return &self.obj;
}

/// Cast this `Obj.Variant` to an object `Value`.
pub fn toValue(self: *Native) Value {
    return .Object(self.toObj());
}

/// Custom formatter for `Obj.Native` values.
pub fn format(_: *const Native, writer: *Writer) !void {
    try writer.writeAll("<native fn>");
}
