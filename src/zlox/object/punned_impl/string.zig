//! A lox string `Obj` struct.

const zlox = @import("../../.lib.zig");

const Obj = @import("obj.zig");

// ============================================================================

const String: type = @This();

/// The base lox object header.
obj: Obj = undefined,

/// Slice of characters within this lox string.
///
/// This slice is owned by the lox string obj and must be freed when the obj
/// is destroyed.
chars: []const u8,
