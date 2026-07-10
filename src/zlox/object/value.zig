const std = @import("std");
const zlox = @import("../.lib.zig");

const Obj = zlox.object.Obj;

const Writer = std.Io.Writer;

// ============================================================================

/// Represents a lox value.
pub const Value: type = union(Value.Type) {
    // Represents the type of a lox value.
    pub const Type = enum { nil, bool, number, obj };

    /// A `void` standin for a `nil` lox Value.
    nil,

    /// Holds the `bool` value of this Value if it is a `bool`.
    bool: bool,

    /// Holds the `f64` value of this Value if it is a `number`.
    number: f64,

    /// Holds a pointer to a heap-allocated lox object.
    obj: *Obj,

    /// The constant `nil` lox Value.
    pub const Nil: Value = .nil;

    /// Creates a bool `Value` from the given `value`.
    pub fn Bool(value: bool) Value {
        return Value{ .bool = value };
    }

    /// Creates a number `Value` from the given `value`.
    pub fn Number(value: f64) Value {
        return Value{ .number = value };
    }

    /// Creates an object `Value` from the given `obj`.
    pub fn Object(obj: *Obj) Value {
        return Value{ .obj = obj };
    }

    /// Returns whether this value is of type `T`.
    pub fn is(self: Value, comptime T: Value.Type) bool {
        return self == T;
    }

    /// Returns whether this value is not of type `T`.
    pub fn isNot(self: Value, comptime T: Value.Type) bool {
        return self != T;
    }

    /// Returns whether this value is an object of type `T`.
    pub fn isObj(self: Value, comptime T: Obj.Type) bool {
        return self.is(.obj) and self.obj.is(T);
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
        if (@as(Value.Type, self) != @as(Value.Type, other)) return false;

        // Check if object types match
        if (self.is(.obj) and self.obj.isNot(other.obj.type)) return false;

        return switch (self) {
            .nil => true,
            .bool => self.bool == other.bool,
            .number => self.number == other.number,
            .obj => self.obj == other.obj,
        };
    }

    /// Returns this value cast to an object of type `T`.
    ///
    /// Panics if this value is not an object.
    pub fn asObj(self: Value, comptime T: Obj.Type) *Obj.Variant(T) {
        return self.obj.as(T);
    }

    /// Custom formatter for `Value` values.
    pub fn format(self: Value, writer: *Writer) Writer.Error!void {
        switch (self) {
            .nil => try writer.writeAll("nil"),
            .bool => try writer.print("{}", .{self.bool}),
            .number => try writer.print("{}", .{self.number}),
            .obj => try writer.print("{f}", .{self.obj}),
        }
    }
};
