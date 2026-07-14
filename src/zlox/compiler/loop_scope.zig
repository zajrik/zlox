//! Represents the lexical scope of a loop in which break and continue statements
//! can be resolved during compilation to correctly control the flow of that loop.

const std = @import("std");
const zlox = @import("../.lib.zig");

const mem = zlox.mem;

const Chunk = zlox.compiler.Chunk;

// ============================================================================

const LoopScope: type = @This();

/// Tracks an unresolved break statement.
pub const Break = struct {
    /// The instruction offset at which placeholder operand bytes can be found for
    /// the unpatched jump instruction associated with this tracked break statement.
    offset: usize,

    /// The next tracked break statement to be resolved.
    next: ?*Break,
};

/// Tracks an unresolved continue statement.
pub const Continue = struct {
    /// The instruction offset at which placeholder operand bytes can be found for
    /// the unpatched loop instruction associated with this tracked continue statement.
    offset: usize,

    /// The next tracked continue statement to be resolved.
    next: ?*Continue,
};

/// The enclosing loop scope, if any.
enclosing: ?*LoopScope = null,

/// Linked list of unresolved `Break` structs.
breaks: ?*Break = null,

/// Linked list of unresolved `Continue` structs.
continues: ?*Continue = null,

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
    while (self.continues) |it| : (mem.destroy(it)) self.continues = it.next;
}

/// Track a break statement at the given instruction offset.
///
/// The offset must point to the placeholder operand bytes of a jump instruction
/// semantically tied to a break statement.
pub fn addBreak(self: *LoopScope, offset: usize) !void {
    self.breaks = try mem.createStruct(
        Break,
        .{ .offset = offset, .next = self.breaks },
    );
}

/// Track a continue statement at the given instruction offset.
///
/// The offset must point to the placeholder operand bytes of a loop instruction
/// semantically tied to a continue statement.
pub fn addContinue(self: *LoopScope, offset: usize) !void {
    self.continues = try mem.createStruct(
        Continue,
        .{ .offset = offset, .next = self.continues },
    );
}
