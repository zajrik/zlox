const std = @import("std");
const zlox = @import("../.lib.zig");

const mem = zlox.mem;

const Chunk = zlox.compiler.Chunk;

// ============================================================================

const LoopScope: type = @This();

/// Tracks an unresolved break statement.
const Break = struct {
    /// The instruction offset where the break jump-placeholder bytes are found.
    offset: usize,

    /// The next break to be resolved.
    next: ?*Break,
};

/// The enclosing loop scope, if any.
enclosing: ?*LoopScope = null,

/// Linked list of unresolved `Break` structs.
breaks: ?*Break = null,

/// Allocate a new `LoopScope` instance on the heap, returning a pointer to it.
///
/// The caller owns the returned pointer and is responsible for freeing it.
pub fn create(enclosing: ?*LoopScope) !*LoopScope {
    return try mem.createStruct(LoopScope, .{ .enclosing = enclosing });
}

/// Destroy this `LoopScope`, freeing its owned resources.
pub fn destroy(self: *LoopScope) void {
    defer mem.destroy(self);
    while (self.breaks) |it| : (mem.destroy(it)) self.breaks = it.next;
}

/// Track a break statement at the given instruction offset.
///
/// The offset must point to the operand placeholder bytes of a jump instruction
/// semantically tied to a break statement.
pub fn addBreak(self: *LoopScope, offset: usize) void {
    self.breaks = mem.createStruct(
        Break,
        .{ .offset = offset, .next = self.breaks },
    ) catch return;
}

/// Resolve all jump instructions tied to break statements in this scope.
///
/// The jump instruction placeholders for all unresolved break jumps will be
/// patched to the current instruction pointer offset of the given `chunk`.
pub fn resolveBreaks(self: *LoopScope, chunk: *Chunk) void {
    while (self.breaks) |it| : (mem.destroy(it)) {
        defer self.breaks = it.next;

        const jump_offset: usize = chunk.len() - it.offset - 2;
        const jump_byte_1: u8 = @as(u8, @truncate(jump_offset >> 8));
        const jump_byte_2: u8 = @as(u8, @truncate(jump_offset));

        chunk.ipAt(it.offset).* = jump_byte_1;
        chunk.ipAt(it.offset + 1).* = jump_byte_2;
    }
}

