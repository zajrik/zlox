//! A heap-allocated lox object.

const std = @import("std");
const zlox = @import("../.lib.zig");

const mem = zlox.mem;
const debug = zlox.debug;

pub const Type = @import("type.zig").Type;
pub const Variant = @import("variant.zig").Variant;
pub const Flags = @import("flags.zig").Flags;

pub const Closure = @import("closure.zig");
pub const Function = @import("function.zig");
pub const Native = @import("native.zig");
pub const String = @import("string.zig");
pub const Upvalue = @import("upvalue.zig");
pub const Class = @import("class.zig");
pub const Instance = @import("instance.zig");

const Writer = std.Io.Writer;

// =================================================================================================

const Obj: type = @This();

/// The type tag of this lox object.
type: Type,

/// Bit-flags carrying extra data about this lox object.
flags: Flags = .{},

/// Pointer to the next lox object on the heap, forming a linked list of objects
/// at runtime for the garbage collector to trace.
next: ?*Obj = null,

/// Allocate a new `Obj` of the given `type` with the given `variant` payload.
///
/// Returns a pointer to the allocated `Obj`. The caller owns this obj and
/// is responsible for freeing it.
///
/// Objects created this way are NOT managed by the garbage collector and must be
/// manually linked with the VM to be managed.
///
/// See also:
/// - `Vm.linkObj`
pub fn create(comptime T: Type, variant: Variant(T)) !*Variant(T) {
    const object: *Variant(T) = try mem.create(Variant(T));
    object.* = variant;
    object.obj = Obj{ .type = T };
    return object;
}

/// Allocate a new constant `Obj` of the given type `T` with the given `variant`
/// payload.
///
/// Returns a pointer to the allocated `Obj`.
///
/// This should only be called at compile time and any created constant objects
/// should be owned and cleaned up by the chunk they're compiled to.
pub fn createConstant(comptime T: Type, variant: Variant(T)) !*Variant(T) {
    const object: *Variant(T) = try create(T, variant);
    object.obj.flags.is_constant = true;
    return object;
}

/// Allocate a new lox string `Obj` on the heap, wrapping and taking ownership of
/// the given slice.
///
/// The given `string` slice will be freed when the allocated `Obj` is freed.
///
/// Returns a pointer to the allocated lox string `Obj`.
///
/// Strings created this way are NOT managed by the garbage collector and must be
/// manually linked with the VM to be managed.
///
/// See also:
/// - `Vm.linkObj`
pub fn takeString(chars: []const u8) !*Obj.String {
    return create(.string, Obj.String{ .chars = chars });
}

/// Allocate a copy of the given `string` slice on the heap, wrapping it in a newly
/// allocated lox string `Obj`.
///
/// Returns a pointer to the allocated lox string `Obj`.
///
/// Strings created this way are NOT managed by the garbage collector and must be
/// manually linked with the VM to be managed.
///
/// See also:
/// - `Vm.linkObj`
pub fn copyString(chars: []const u8) !*Obj.String {
    return takeString(try mem.dupe(u8, chars));
}

/// Destroy this `Obj`, freeing its owned resources.
pub fn destroy(self: *Obj) void {
    defer switch (self.type) {
        inline else => |T| self.cast(T).destroy(),
    };

    if (comptime debug.obj_free) std.debug.print(
        "freeing {s}obj({any}) [{*}] {f}\n",
        .{ if (self.flags.is_constant) "const " else "", self.type, self, self },
    );
}

/// Returns whether this obj is of the given type `T`.
pub fn is(self: *Obj, T: Type) bool {
    return self.type == T;
}

/// Returns whether this obj is not of the given type `T`.
pub fn isNot(self: *Obj, T: Type) bool {
    return self.type != T;
}

/// Cast this `Obj` to an obj of the given type `T`.
///
/// Panics on access if the obj is not of the given type `T`.
pub fn cast(self: *Obj, comptime T: Type) *Variant(T) {
    return @alignCast(@fieldParentPtr("obj", self));
}

/// Safely cast this `Obj` to an obj of the given type `T`.
///
/// Returns `null` if the obj is not of the given type `T`.
pub fn as(self: *Obj, comptime T: Type) ?*Variant(T) {
    return if (self.is(T)) self.cast(T) else null;
}

/// Returns the runtime size of an `Obj` variant of the given `type`.
pub fn size(self: *Obj) usize {
    return switch (self.type) {
        .string => |T| @sizeOf(Variant(T)) + @sizeOf(u8) * self.cast(T).chars.len,
        inline else => |T| @sizeOf(Variant(T)),
    };
}

/// Custom formatter for `Obj` values.
pub fn format(self: *Obj, writer: *Writer) !void {
    switch (self.type) {
        inline else => |T| try self.cast(T).format(writer),
    }
}
