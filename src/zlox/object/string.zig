//! A lox string `Obj` struct variant.

const std = @import("std");
const zlox = @import("../.lib.zig");

const mem = zlox.mem;

const Obj = zlox.object.Obj;
const Value = zlox.object.Value;

const Writer = std.Io.Writer;

// =================================================================================================

const String: type = @This();

/// The base lox object header.
obj: Obj = undefined,

/// Slice of characters within this lox string.
///
/// This slice is owned by the lox string obj if it is not a compile-time constant
/// string, in which case it must be freed when the obj is destroyed.
chars: []const u8,

/// Pre-calculated hash for this string.
hash: u32 = 0,

/// Free allocated memory owned by this obj.
pub fn destroy(self: *const String) void {
    defer mem.destroy(self);
    if (!self.obj.flags.is_constant) mem.free(self.chars);
}

/// Cast this `Obj.Variant` pointer to a raw `Obj` pointer.
pub fn toObj(self: *String) *Obj {
    return &self.obj;
}

/// Cast this `Obj.Variant` to an object `Value`.
pub fn toValue(self: *String) Value {
    return .Object(self.toObj());
}

/// Custom formatter for `Obj` values of this variant.
pub fn format(self: *const String, writer: *Writer) !void {
    try writer.print("{s}", .{self.chars});
}
