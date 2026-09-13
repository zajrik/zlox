//! Represents an upvalue tracked at compile time.

const std = @import("std");

const Self: type = @This();

/// The offset of this upvalue in its function's upvalues array.
offset: u8,

/// Whether this upvalue is a local in the scope from which it is captured.
is_local: bool,

/// Custom formatter for `Upvalue` values.
pub fn format(self: Self, writer: *std.Io.Writer) !void {
    try writer.print(
        "Upvalue{{ .offset = {d}, .is_local = {} }}",
        .{ self.offset, self.is_local },
    );
}
