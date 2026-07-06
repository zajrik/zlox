//! Base node of a linked list structure for declaring multiple jump instructions
//! that will all be resolved to the same endpoint.

const zlox = @import("../.lib.zig");
const mem = zlox.mem;

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
pub fn destroy(self: *const JumpList) void {
    var next: ?*Jump = self.head;
    while (next) |jump| {
        next = jump.next;
        jump.destroy();
    }
    mem.destroy(self);
}

/// Add a `Jump` beginning at the given `offset` to this jump list.
pub fn addJump(self: *JumpList, offset: usize) void {
    const jump: *Jump = Jump.create(offset) catch return;
    jump.next = self.head;
    self.head = jump;
}

/// A linked `JumpList` node indicating the instruction offset at which this jump
/// begins.
pub const Jump = struct {
    /// The instruction offset at which this jump begins.
    offset: usize,

    /// The next linked `Jump` node in the list, if any.
    next: ?*Jump = null,

    /// Allocate a new `Jump` on the heap with the given `offset`.
    ///
    /// Returns a pointer to the allocated jump struct.
    pub fn create(offset: usize) !*Jump {
        return try mem.createStruct(Jump, .{ .offset = offset });
    }

    /// Destroy this `Jump`, freeing its allocated memory.
    pub fn destroy(self: *const Jump) void {
        mem.destroy(self);
    }
};
