//! A lox closure `Obj` struct variant, wrapping a lox function obj.

const std = @import("std");
const zlox = @import("../.lib.zig");

const mem = zlox.mem;

const Obj = zlox.object.Obj;
const Value = zlox.object.Value;

const Writer = std.Io.Writer;

// =================================================================================================

const Self: type = @This();

/// The base lox object header.
obj: Obj = undefined,

/// Pointer to the lox function obj this closure wraps.
///
/// The function obj is not owned by the closure.
function: *Obj.Function,

/// Array of pointers to upvalues captured by this closure.
///
/// The closure owns this array, but not the upvalues its contents point to.
upvalues: []*Obj.Upvalue,

/// Free allocated memory owned by this obj.
pub fn destroy(self: *const Self) void {
    defer mem.destroy(self);
    mem.free(self.upvalues);
}

/// Cast this `Obj.Variant` pointer to a raw `Obj` pointer.
pub fn toObj(self: *Self) *Obj {
    return &self.obj;
}

/// Cast this `Obj.Variant` to an object `Value`.
pub fn toValue(self: *Self) Value {
    return .Object(self.toObj());
}

/// Custom formatter for `Obj` values of this variant.
pub fn format(self: *const Self, writer: *Writer) !void {
    try self.function.format(writer);
}
