//! A linked list node detailing the instruction offset of the operand bytes for
//! a jump or loop instruction to be patched.

const zlox = @import("../.lib.zig");

const mem = zlox.mem;

// =============================================================================

const Jump: type = @This();

/// The instruction offset at which the tracked operand bytes begin.
offset: usize,

/// The next linked `Jump` node in the list, if any.
next: ?*Jump = null,

/// Allocate a new `Jump` node on the heap with the given `offset`.
///
/// Returns a pointer to the allocated jump node.
pub fn create(offset: usize, next: ?*Jump) !*Jump {
    return try mem.createStruct(
        Jump,
        .{ .offset = offset, .next = next },
    );
}

/// Destroy this `Jump` node, freeing its allocated memory.
pub fn destroy(self: *const Jump) void {
    mem.destroy(self);
}
