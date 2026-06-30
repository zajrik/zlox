const std = @import("std");
const Obj = @import("obj.zig").Obj;

const Writer = std.Io.Writer;

// ============================================================================

/// Represents a lox value.
pub const Value: type = union(Type) {
    /// A `void` standin for a `nil` lox Value.
    nil,

    /// Holds the `bool` value of this Value if it is a `bool`.
    bool: bool,

    /// Holds the `f32` value of this Value if it is a `number`.
    number: f32,

    /// Holds a pointer to a heap-allocated lox object.
    obj: *Obj,

    // Represents the type of a lox value.
    pub const Type = enum { nil, bool, number, obj };

    /// The constant `nil` lox Value.
    pub const nil_val: Value = .nil;

    /// Creates a bool `Value` from the given `value`.
    pub fn boolVal(value: bool) Value {
        return .{ .bool = value };
    }

    /// Creates a number `Value` from the given `value`.
    pub fn numberVal(value: f32) Value {
        return .{ .number = value };
    }

    /// Creates an object `Value` from the given `obj`.
    pub fn objVal(obj: *Obj) Value {
        return .{ .obj = obj };
    }

    /// Returns whether this value is of the given `type`.
    pub fn is(self: Value, @"type": Type) bool {
        return self == @"type";
    }

    /// Returns whether this value is not of the given `type`.
    pub fn isNot(self: Value, @"type": Type) bool {
        return self != @"type";
    }

    /// Returns whether this value is an object of the given `type`.
    pub fn isObj(self: Value, @"type": Obj.Type) bool {
        return self.is(.obj) and self.obj.* == @"type";
    }

    /// Returns whether this value is falsey.
    ///
    /// `nil` and `false` are falsey, everything else is truthy.
    pub fn isFalsey(self: Value) bool {
        return self.is(.nil) or (self.is(.bool) and !self.bool);
    }

    /// Returns whether this value equals `other`.
    pub fn equals(self: Value, other: Value) bool {
        // Check if value types match
        if (@as(Type, self) != @as(Type, other)) return false;

        // Check if object types match
        if (self == .obj) {
            if (@as(Obj.Type, self.obj.*) != @as(Obj.Type, other.obj.*)) return false;
        }

        return switch (self) {
            .nil => true,
            .bool => self.bool == other.bool,
            .number => self.number == other.number,
            .obj => switch (self.obj.*) {
                // Compare string character equality
                .string => std.mem.eql(
                    u8,
                    self.obj.*.string.chars,
                    other.obj.*.string.chars,
                ),

                // Compare reference equality
                // else => self.obj == other.obj,
            },
        };
    }

    /// Custom formatter for `Value` values.
    pub fn format(self: Value, writer: *Writer) Writer.Error!void {
        switch (self) {
            .nil => try writer.writeAll("nil"),
            .bool => try writer.print("{}", .{self.bool}),
            .number => try writer.print("{d}", .{self.number}),
            .obj => try writer.print("{f}", .{self.obj}),
        }
    }
};
