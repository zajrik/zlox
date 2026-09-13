//! A lox function `Obj` struct variant.

const std = @import("std");
const zlox = @import("../.lib.zig");

const mem = zlox.mem;

const Chunk = zlox.compiler.Chunk;
const Obj = zlox.object.Obj;
const Value = zlox.object.Value;

const Writer = std.Io.Writer;

// =================================================================================================

const Self: type = @This();

/// Enum representing the distinction between different functions declarations.
pub const Type = enum(u2) { script, function, initializer, method };

/// The base lox object header.
obj: Obj = undefined,

/// The type of function this object represents.
type: Type,

/// The identifier string of this lox function, i.e. the name used to call the
/// function at runtime, assuming the function isn't anonymous.
///
/// This string is not owned by the function, it lives in the constants of the
/// chunk this function is compiled into.
identifier: ?*Obj.String = null,

/// The number of arguments this function expects and accepts at runtime.
arity: u8 = 0,

/// The number of upvalues this function relies on.
upvalue_count: u8 = 0,

/// The chunk of compiled bytecode for this function.
///
/// This is owned by the function and must be freed when the function object is
/// destroyed.
chunk: Chunk,

/// Free allocated memory owned by this obj.
pub fn destroy(self: *Self) void {
    defer mem.destroy(self);
    self.chunk.deinit();
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
    if (self.type == .script) return try writer.writeAll("<script>");
    if (self.identifier) |it| return try writer.print("<fn {f}()>", .{it});
    return try writer.writeAll("<anon fn()>");
}
