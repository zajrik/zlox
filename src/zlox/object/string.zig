//! A lox string `Obj` struct variant.

const std = @import("std");
const zlox = @import("../.lib.zig");

const mem = zlox.mem;

const Obj = zlox.object.Obj;

const Writer = std.Io.Writer;

// ============================================================================

const String: type = @This();

/// The base lox object header.
obj: Obj = undefined,

/// Slice of characters within this lox string.
///
/// This slice is owned by the lox string obj and must be freed when the obj
/// is destroyed.
chars: []const u8,

/// Pre-calculated hash for this string.
hash: u32 = 0,

/// Free allocated memory owned by this obj.
pub fn destroy(self: *const String) void {
    mem.free(self.chars);
}

/// Custom formatter for `Obj.String` values.
pub fn format(self: *const String, writer: *Writer) !void {
    try writer.print("{s}", .{self.chars});
}
