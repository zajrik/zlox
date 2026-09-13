//! Base node of a linked list structure for declaring multiple jump instructions
//! that will all be resolved to the same endpoint.
//!
//! Initialize an empty jump list with `JumpList.empty` and deinitialize when finished
//! with `deinit()`.

const zlox = @import("../.lib.zig");

const mem = zlox.mem;

const Jump = zlox.compiler.Jump;

// =================================================================================================

const Self: type = @This();

/// An empty jump list containing no tracked jumps.
pub const empty: Self = .{};

/// The first jump in the jump list.
head: ?*Jump = null,

/// Deinitialize this `JumpList`, freeing any `Jump` structs it has allocated.
pub fn deinit(self: *Self) void {
    defer self.* = undefined;
    while (self.head) |it| : (it.destroy()) self.head = it.next;
}

/// Add a `Jump` beginning at the given `offset` to this jump list.
pub fn addJump(self: *Self, offset: usize) !void {
    self.head = try Jump.create(offset, self.head);
}
