//! Represents the lexical scope of a loop in which break and continue statements
//! can be resolved during compilation to correctly control the flow of that loop.

const std = @import("std");
const zlox = @import("../.lib.zig");

const mem = zlox.mem;

const Chunk = zlox.compiler.Chunk;

// ============================================================================

const LoopScope: type = @This();

/// Tracks an unresolved break statement.
const Break = struct {
    /// The instruction offset at which placeholder operand bytes can be found for
    /// the unpatched jump instruction associated with this tracked break statement.
    offset: usize,

    /// The next tracked break statement to be resolved.
    next: ?*Break,
};

/// Tracks an unresolved continue statement.
const Continue = struct {
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

    // Destroy any lingering unresolved breaks/continues in case we errored out
    // of compiling a loop statement to completion
    while (self.breaks) |it| : (mem.destroy(it)) self.breaks = it.next;
    while (self.continues) |it| : (mem.destroy(it)) self.continues = it.next;
}

/// Track a break statement at the given instruction offset.
///
/// The offset must point to the placeholder operand bytes of a jump instruction
/// semantically tied to a break statement.
pub fn addBreak(self: *LoopScope, offset: usize) void {
    self.breaks = mem.createStruct(
        Break,
        .{ .offset = offset, .next = self.breaks },
    ) catch return;
}

/// Resolve all unresolved break statements in this loop scope.
///
/// The jump instruction placeholders within the given `chunk` for all unresolved
/// break statements in this scope will be patched to the current instruction
/// pointer offset of the given chunk.
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

/// Track a continue statement at the given instruction offset.
///
/// The offset must point to the placeholder operand bytes of a loop instruction
/// semantically tied to a continue statement.
pub fn addContinue(self: *LoopScope, offset: usize) void {
    self.continues = mem.createStruct(
        Continue,
        .{ .offset = offset, .next = self.continues },
    ) catch return;
}

/// Resolve all unresolved continue statements in this loop scope.
///
/// The loop instruction placeholders within the given `chunk` for all unresolved
/// continue statements in this scope will be patched to the given `loop_start`
/// instruction offset.
pub fn resolveContinues(self: *LoopScope, chunk: *Chunk, loop_start: usize) void {
    while (self.continues) |it| : (mem.destroy(it)) {
        defer self.continues = it.next;

        const loop_offset: usize = it.offset - loop_start + 2;
        const loop_byte_1: u8 = @as(u8, @truncate(loop_offset >> 8));
        const loop_byte_2: u8 = @as(u8, @truncate(loop_offset));

        chunk.ipAt(it.offset).* = loop_byte_1;
        chunk.ipAt(it.offset + 1).* = loop_byte_2;
    }
}
