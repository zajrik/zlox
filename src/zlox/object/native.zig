//! A lox native function `Obj` struct variant.

const std = @import("std");
const zlox = @import("../.lib.zig");

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
pub fn destroy(_: *const Native) void {}

/// Custom formatter for `Obj.Native` values.
pub fn format(_: *const Native, writer: *Writer) !void {
    try writer.writeAll("<native fn>");
}
