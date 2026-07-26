//! Represents a local variable tracked during compilation.

const std = @import("std");
const zlox = @import("../.lib.zig");

const Token = zlox.tokenizer.Token;

// =================================================================================================

const Local: type = @This();

/// Token holding the identifier lexeme of this local.
identifier: Token,

/// Scope depth of this local.
depth: i32 = 0,

/// Whether this local has been captured in a closure.
is_captured: bool = false,

/// Custom formatter for `Local` values.
pub fn format(self: Local, writer: *std.Io.Writer) !void {
    try writer.print(
        "Local{{ .identifier = '{s}', .depth = {d}, .is_captured = {} }}",
        .{ self.identifier.lexeme, self.depth, self.is_captured },
    );
}
