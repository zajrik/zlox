//! A heap-allocated lox object.
//!
//! Implemented as a manually-tagged union (as opposed to a zig union(enum)) to
//! allow additional shared fields between objects.

const std = @import("std");
const zlox = @import("../../.lib.zig");

const mem = zlox.mem;

const Writer = std.Io.Writer;

pub const String = @import("string.zig");

// ============================================================================

const Obj: type = @This();

/// Represents the different union types of heap-allocated lox objects.
pub const Type = enum(u1) { string };

/// Object body payload type for the given object `type`.
pub fn Body(comptime @"type": Type) type {
    return switch (@"type") {
        .string => String,
    };
}

/// The union type tag of this lox object.
type: Type,

/// Pointer to the next lox object on the heap, forming a linked list of objects
/// at runtime for the garbage collector to trace.
next: ?*Obj = null,

/// Union of possible lox object types.
as: union {
    string: String,
},

/// Allocate a new `Obj` of the given `type` with the given `body`.
///
/// Returns a pointer to the allocated `Obj`. The caller owns this obj and
/// is responsible for freeing it.
///
/// Note: Objects created directly with this function are not able to be traced
/// by the garbage collector unless reachable through some other traceable structure.
///
/// Use `zlox.mem.createObj()` when creating objects that need to be garbage-collectable.
pub fn create(comptime @"type": Type, body: Body(@"type")) !*Obj {
    const obj: *Obj = try mem.create(Obj);
    obj.type = @"type";

    // Set obj payload to the given body
    switch (@"type") {
        inline .string => obj.as.string = body,
    }

    return obj;
}

/// Destroy this `Obj`, freeing its owned resources.
pub fn destroy(self: *const Obj) void {
    // Free data owned by the object
    switch (self.type) {
        .string => mem.free(self.as.string.chars),
    }

    // Free the object itself
    mem.destroy(self);
}

/// Returns whether this obj is of the given `type`.
pub fn is(self: *const Obj, @"type": Type) bool {
    return self.type == @"type";
}

/// Returns whether this obj is not of the given `type`.
pub fn isNot(self: *const Obj, @"type": Type) bool {
    return self.type != @"type";
}

/// Custom formatter for `Obj` values.
pub fn format(self: *const Obj, writer: *Writer) Writer.Error!void {
    switch (self.type) {
        .string => try writer.print("{f}", .{self.as.string}),
    }
}
