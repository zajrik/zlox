//! A lox function `Obj` struct variant.

const std = @import("std");
const zlox = @import("../../.lib.zig");

const mem = zlox.mem;

const Chunk = zlox.compiler.Chunk;
const Obj = zlox.object.Obj;

const Writer = std.Io.Writer;

// ============================================================================

const Function: type = @This();

/// Enum representing the distinction between different functions declarations.
pub const Type = enum(u2) { script, function, method };

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
arity: u8,

/// The chunk of compiled bytecode for this function.
///
/// This is owned by the function and must be freed when the function object is
/// destroyed.
chunk: Chunk,

/// Free allocated memory owned by this obj.
pub fn destroy(self: *const Function) void {
    self.chunk.deinit();
}

/// Custom formatter for `Obj.Function` values.
pub fn format(self: *const Function, writer: *Writer) !void {
    if (self.identifier) |identifier| {
        return try writer.print("<fn {f}>", .{identifier});
    }

    return try writer.writeAll("<anon fn>");
}
