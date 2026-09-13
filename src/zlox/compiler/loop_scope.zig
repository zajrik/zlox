//! Represents the lexical scope of a loop in which break and continue statements
//! can be resolved during compilation to correctly control the flow of that loop.

const std = @import("std");
const zlox = @import("../.lib.zig");

const mem = zlox.mem;

const Chunk = zlox.compiler.Chunk;
const Jump = zlox.compiler.Jump;

// =================================================================================================

const Self: type = @This();

/// The enclosing loop scope, if any.
enclosing: ?*Self = null,

/// Linked list of unresolved `jump` instructions tied to break statements.
breaks: ?*Jump = null,

/// Linked list of unresolved `loop` instructions tied to continue statements.
continues: ?*Jump = null,

/// Allocate a new `LoopScope` instance on the heap, returning a pointer to it.
///
/// The caller owns the returned pointer and is responsible for freeing it.
pub fn create(enclosing: ?*Self) !*Self {
    return try mem.createStruct(
        Self,
        .{ .enclosing = enclosing },
    );
}

/// Destroy this `LoopScope`, freeing its owned resources.
pub fn destroy(self: *Self) void {
    defer mem.destroy(self);
    while (self.breaks) |it| : (it.destroy()) self.breaks = it.next;
    while (self.continues) |it| : (it.destroy()) self.continues = it.next;
}

/// Track a break statement at the given instruction offset.
///
/// The offset must point to the placeholder operand bytes of a jump instruction
/// semantically tied to a break statement.
pub fn addBreak(self: *Self, offset: usize) !void {
    self.breaks = try Jump.create(offset, self.breaks);
}

/// Track a continue statement at the given instruction offset.
///
/// The offset must point to the placeholder operand bytes of a loop instruction
/// semantically tied to a continue statement.
pub fn addContinue(self: *Self, offset: usize) !void {
    self.continues = try Jump.create(offset, self.continues);
}
