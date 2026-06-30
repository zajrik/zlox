//! A heap-allocated lox object.
//!
//! Implemented with the closest safe approximation to C-like type punning/struct
//! inheritance I can manage in zig without just using extern structs. There might
//! be a better way of doing this, but I haven't found one yet.
//!
//! This is mostly a proof-of-concept in case the union implementation is too bulky
//! since all objects, even smaller ones, will have the size of the largest object
//! type in the union (plus the base obj fields and any alignment padding).
//!
//! I'll be moving forward with the union implementation for now, but this can be
//! swapped in easily, it just requires updating all `obj.as.type` references from
//! union field access to `obj.as(.type)` method calls. Light work with find/replace.

const std = @import("std");
const zlox = @import("../../.lib.zig");

const mem = zlox.mem;

pub const String = @import("string.zig");

const Writer = std.Io.Writer;

// ============================================================================

const Obj: type = @This();

/// Represents the different types of heap-allocated lox objects.
pub const Type = enum(u1) { string };

/// Object body payload type for the given object `type`.
fn Body(comptime @"type": Type) type {
    const obj_type: type = switch (@"type") {
        .string => String,
    };

    // Ensure Obj children have `obj` header field.
    if (!@hasField(obj_type, "obj")) @compileError(
        std.fmt.comptimePrint(
            "Obj child struct '{}' missing 'obj: Obj' header field.",
            .{obj_type},
        ),
    );

    return obj_type;
}

/// The type tag of this lox object.
type: Type,

/// Pointer to the next lox object on the heap, forming a linked list of objects
/// at runtime for the garbage collector to trace.
next: ?*Obj = null,

/// Allocate a new `Obj` of the given `type` with the given `body`.
///
/// Returns a pointer to the allocated `Obj`. The caller owns this obj and
/// is responsible for freeing it.
pub fn create(comptime @"type": Type, body: Body(@"type")) !*Obj {
    const obj: *Body(@"type") = try mem.create(Body(@"type"));
    obj.* = body;
    obj.obj = Obj{ .type = @"type" };
    return &obj.obj;
}

/// Destroy this `Obj`, freeing its owned resources.
pub fn destroy(self: *const Obj) void {
    // Free data owned by the object
    switch (self.type) {
        .string => mem.free(self.as(.string).chars),
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

/// Cast this `Obj` to an obj of the given `type`.
pub fn as(self: *const Obj, comptime @"type": Type) *const Body(@"type") {
    return @alignCast(@fieldParentPtr("obj", self));
}

/// Custom formatter for `Obj` values.
pub fn format(self: *const Obj, writer: *Writer) Writer.Error!void {
    switch (self.type) {
        .string => try writer.print("{s}", .{self.as(.string).chars}),
    }
}
