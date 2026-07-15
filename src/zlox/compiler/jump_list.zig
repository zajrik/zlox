//! Base node of a linked list structure for declaring multiple jump instructions
//! that will all be resolved to the same endpoint.

const zlox = @import("../.lib.zig");

const mem = zlox.mem;

const Jump = zlox.compiler.Jump;

// ============================================================================

const JumpList: type = @This();

/// The first jump in the jump list.
head: ?*Jump = null,

/// Allocate a new `JumpList` on the heap.
///
/// Returns a pointer to the allocated jump list. The caller owns this jump list
/// and is responsible for freeing it.
pub fn create() !*JumpList {
    return try mem.createStruct(JumpList, .{});
}

/// Destroy this `JumpList`, freeing any allocated `Jump` structs it links, as
/// well as its own allocated memory.
pub fn destroy(self: *JumpList) void {
    defer mem.destroy(self);
    while (self.head) |it| : (it.destroy()) self.head = it.next;
}

/// Add a `Jump` beginning at the given `offset` to this jump list.
pub fn addJump(self: *JumpList, offset: usize) !void {
    self.head = try Jump.create(offset, self.head);
}
