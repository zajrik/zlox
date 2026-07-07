//! A heap-allocated lox object.
//!
//! Implemented with the closest safe approximation to C-like type punning/struct
//! inheritance I can manage in zig without just using extern structs. There might
//! be a better way of doing this, but I haven't found one yet.

const std = @import("std");
const zlox = @import("../../.lib.zig");

const mem = zlox.mem;

pub const Type = @import("type.zig").Type;
pub const Variant = @import("variant.zig").Variant;

pub const String = @import("string.zig");

const Writer = std.Io.Writer;

// ============================================================================

const Obj: type = @This();

/// The type tag of this lox object.
type: Type,

/// Whether this object is a constant object value. Constant objects are compiled
/// and owned by the chunk they are compiled into. They should not be freed by
/// the garbage collector.
is_constant: bool = false,

/// Pointer to the next lox object on the heap, forming a linked list of objects
/// at runtime for the garbage collector to trace.
next: ?*Obj = null,

/// Allocate a new `Obj` of the given `type` with the given `variant` payload.
///
/// Returns a pointer to the allocated `Obj`. The caller owns this obj and
/// is responsible for freeing it.
///
/// Note: Objects created directly with this function are not able to be traced
/// by the garbage collector unless reachable through some other traceable structure.
///
/// Use `Vm.createObj()` when creating objects that need to be garbage-collectable.
pub fn create(
    comptime @"type": Type,
    variant: Variant(@"type"),
) !*Variant(@"type") {
    const object: *Variant(@"type") = try mem.create(Variant(@"type"));
    object.* = variant;
    object.obj = Obj{ .type = @"type" };
    return object;
}

/// Allocate a new constant `Obj` of the given `type` with the given `variant` payload.
///
/// Returns a pointer to the allocated `Obj`.
///
/// This should only be called at compile time and any created constant objects
/// should be owned and cleaned up by the chunk they're compiled to.
pub fn createConstant(
    comptime @"type": Type,
    variant: Variant(@"type"),
) !*Variant(@"type") {
    const object: *Variant(@"type") = try create(@"type", variant);
    object.obj.is_constant = true;
    return object;
}

/// Destroy this `Obj`, freeing its owned resources.
pub fn destroy(self: *Obj) void {
    defer mem.destroy(self);

    // std.debug.print(
    //     "freeing {s}obj {*} {f}\n",
    //     .{ if (self.is_constant) "const " else "", self, self },
    // );

    switch (self.type) {
        inline else => |@"type"| self.as(@"type").destroy(),
    }
}

/// Returns whether this obj is of the given `type`.
pub fn is(self: *Obj, @"type": Type) bool {
    return self.type == @"type";
}

/// Returns whether this obj is not of the given `type`.
pub fn isNot(self: *Obj, @"type": Type) bool {
    return self.type != @"type";
}

/// Cast this `Obj` to an obj of the given `type`.
pub fn as(self: *Obj, comptime @"type": Type) *Variant(@"type") {
    return @alignCast(@fieldParentPtr("obj", self));
}

/// Custom formatter for `Obj` values.
pub fn format(self: *Obj, writer: *Writer) !void {
    switch (self.type) {
        inline else => |@"type"| try writer.print("{f}", .{self.as(@"type")}),
    }
}
