//! A lox closure `Obj` struct variant, wrapping a lox function obj.

const std = @import("std");
const zlox = @import("../../.lib.zig");

const Obj = zlox.object.Obj;

const Writer = std.Io.Writer;

// ============================================================================

const Closure: type = @This();

/// The base lox object header.
obj: Obj = undefined,

/// Pointer to the lox function obj this closure wraps.
///
/// The function obj is not owned by the closure.
function: *Obj.Function,

/// Free allocated memory owned by this obj.
pub fn destroy(_: *const Closure) void {}

/// Custom formatter for `Obj.Closure` values.
pub fn format(self: *const Closure, writer: *Writer) !void {
    try self.function.format(writer);
}
