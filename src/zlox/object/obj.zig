//! A heap-allocated lox object.
//!
//! Implemented as a manually-tagged union (as opposed to a zig union(enum)) to
//! allow additional shared fields between objects.

const std = @import("std");
const zlox = @import("../.lib.zig");

const mem = zlox.mem;

pub const String = @import("string.zig");

const Writer = std.Io.Writer;

// ============================================================================

const Obj: type = @This();

/// Represents the different union types of heap-allocated lox objects.
pub const Type = enum(u1) { string };

/// Object data payload type for the given object `type`.
fn Data(comptime @"type": Type) type {
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

/// Allocate a new `Obj` of the given `type` with the given `data`.
///
/// Returns a pointer to the allocated `Obj`. The caller owns this obj and
/// is responsible for freeing it.
pub fn create(comptime @"type": Type, data: Data(@"type")) !*Obj {
    const obj: *Obj = try mem.create(Obj);
    obj.type = @"type";

    // Set obj payload to the given data
    switch (@"type") {
        inline .string => obj.as.string = data,
    }

    return obj;
}

/// Destroy this `Obj`, freeing its owned resources.
pub fn destroy(self: *Obj) void {
    // Free data owned by the object
    switch (self.type) {
        .string => mem.free(self.as.string.chars),
    }

    // Free the object itself
    mem.destroy(self);
}

/// Returns whether this obj is of the given `type`.
pub fn is(self: *Obj, @"type": Type) bool {
    return self.type == @"type";
}

/// Returns whether this obj is not of the given `type`.
pub fn isNot(self: *Obj, @"type": Type) bool {
    return self.type != @"type";
}

/// Custom formatter for `Obj` values.
pub fn format(self: *Obj, writer: *Writer) Writer.Error!void {
    switch (self.type) {
        inline .string => try writer.print("{s}", .{self.as.string.chars}),
    }
}
