const std = @import("std");

const Writer = std.Io.Writer;

// ============================================================================

/// Represents a lox value.
pub const Value: type = union(Type) {
    /// Holds the `bool` value of this Value if it is a `bool`.
    bool: bool,

    /// Holds the `f32` value of this Value if it is a `number`.
    number: f32,

    /// A `void` standin for a `nil` lox Value.
    nil,

    // Represents the type of a lox value.
    pub const Type = enum { bool, number, nil };

    /// Creates a bool `Value` from the given `value`.
    pub fn boolVal(value: bool) Value {
        return .{ .bool = value };
    }

    /// Creates a number `Value` from the given `value`.
    pub fn numberVal(value: f32) Value {
        return .{ .number = value };
    }

    /// The constant `nil` lox Value.
    pub const nil_val: Value = .nil;

    /// Returns whether this value is of the given `type`.
    pub fn is(self: Value, @"type": Type) bool {
        return self == @"type";
    }

    /// Returns whether this value is not of the given `type`.
    pub fn isNot(self: Value, @"type": Type) bool {
        return self != @"type";
    }

    /// Returns whether this value is falsey.
    ///
    /// `nil` and `false` are falsey, everything else is truthy.
    pub fn isFalsey(self: Value) bool {
        return self.is(.nil) or (self.is(.bool) and !self.bool);
    }

    /// Returns whether this value equals `other`.
    pub fn equals(self: Value, other: Value) bool {
        if (@as(Type, self) != @as(Type, other)) return false;

        return switch (self) {
            .nil => true,
            .bool => self.bool == other.bool,
            .number => self.number == other.number,
        };
    }

    /// Custom formatter for `Value` values.
    pub fn format(self: Value, writer: *Writer) Writer.Error!void {
        switch (self) {
            .bool => try writer.print("{}", .{self.bool}),
            .number => try writer.print("{d}", .{self.number}),
            .nil => try writer.writeAll("nil"),
        }
    }
};
