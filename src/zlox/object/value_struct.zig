const std = @import("std");
const zlox = @import("../.lib.zig");

const mem = zlox.mem;

const Obj = zlox.object.Obj;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Writer = std.Io.Writer;

const countTrues = std.simd.countTrues;

// =================================================================================================

/// Represents a lox value.
///
/// Implemented as a tagged union of possible lox value types.
pub const Value: type = union(Value.Type) {
    /// A `void` standin for a `nil` lox Value.
    nil: Value.Variant(.nil),

    /// Holds the `bool` value of this Value if it is a `bool`.
    bool: Value.Variant(.bool),

    /// Holds the `f64` value of this Value if it is a `number`.
    number: Value.Variant(.number),

    /// Holds a pointer to a heap-allocated lox object.
    obj: Value.Variant(.obj),

    /// Represents the type variants of a lox value.
    pub const Type = enum { nil, bool, number, obj };

    /// Represents the type of a lox value from the zig side.
    pub fn Variant(comptime T: Value.Type) type {
        return switch (T) {
            .nil => void,
            .bool => bool,
            .number => f64,
            .obj => *Obj,
        };
    }

    /// The constant `nil` lox Value.
    pub const Nil: Value = .nil;

    /// The constant `true` lox Value.
    pub const True: Value = .Bool(true);

    /// The constant `false` lox Value.
    pub const False: Value = .Bool(false);

    /// Creates a bool `Value` from the given `boolean`.
    pub fn Bool(boolean: Value.Variant(.bool)) Value {
        return Value{ .bool = boolean };
    }

    /// Creates a number `Value` from the given `number`.
    pub fn Number(number: Value.Variant(.number)) Value {
        return Value{ .number = number };
    }

    /// Creates an object `Value` from the given `obj`.
    pub fn Object(obj: Value.Variant(.obj)) Value {
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

    /// Returns the result of dividing `self` by `other`.
    ///
    /// Provided for allowing implementation-specific divide-by-0 checks.
    ///
    /// Returns an error if dividing by zero. It is illegal behavior to call this
    /// with any non-number value.
    pub fn divideBy(self: Value, other: Value) !Value {
        // Runtime error on divide by 0
        // const number_a: Value.Variant(.number) = a.cast(.number);
        // const number_b: Value.Variant(.number) = b.cast(.number);
        // if (number_a == 0 or number_b == 0) return error.divide_by_zero;

        // Runtime error on divide by 0, SIMD for funsies 🤡
        const Vec: type = @Vector(2, Value.Variant(.number));
        const v_1: Vec = .{ self.number, self.number };
        const v_2: Vec = @splat(0);
        if (countTrues(v_1 == v_2) > 0) return error.divide_by_zero;

        return .Number(self.number / other.number);
    }

    /// Concatenate this value with `other` if at least one of the two is a string.
    ///
    /// Returns an error if neither is a string, or if something went wrong while
    /// allocating the concatenated string.
    pub fn concat(self: Value, other: Value) !*Obj.String {
        if (!self.isObj(.string) and !other.isObj(.string)) {
            return error.invalid_operand;
        }

        var buffer: ArrayList(u8) = .empty;
        const alloc: Allocator = mem.allocator();
        errdefer buffer.deinit(alloc);

        try buffer.print(alloc, "{f}{f}", .{ self, other });
        const chars: []u8 = try buffer.toOwnedSlice(alloc);
        errdefer alloc.free(chars);

        return try Obj.takeString(chars);
    }

    /// Safely cast this value to the zig representation of the given variant
    /// type `T`.
    ///
    /// Returns `null` if the value is not of the given variant type.
    pub fn as(self: Value, comptime T: Value.Type) ?Value.Variant(T) {
        return if (self.is(T)) self.cast(T) else null;
    }

    /// Returns this value safely cast to an object variant of type `T`.
    ///
    /// Returns `null` if this value is not an object of the given type.
    pub fn asObj(self: Value, comptime T: Obj.Type) ?*Obj.Variant(T) {
        return if (self.is(.obj)) self.obj.as(T) else null;
    }

    /// Cast this value to the zig representation of the given variant type `T`.
    ///
    /// It is illegal behavior to call this with the wrong type.
    pub fn cast(self: Value, comptime T: Value.Type) Value.Variant(T) {
        return switch (T) {
            .nil => self.nil,
            .bool => self.bool,
            .number => self.number,
            .obj => self.obj,
        };
    }

    /// Returns this value cast to an object variant of type `T`.
    ///
    /// It is illegal behavior to call this with the wrong type.
    pub fn objCast(self: Value, comptime T: Obj.Type) *Obj.Variant(T) {
        return self.obj.cast(T);
    }

    /// Returns the name string of the type of this value for error printing.
    pub fn typeName(self: Value) []const u8 {
        return switch (self) {
            .nil => "Nil",
            .bool => "Bool",
            .number => "Number",
            .obj => "Obj",
        };
    }

    /// Custom formatter for `Value` values.
    pub fn format(self: Value, writer: *Writer) !void {
        switch (self) {
            .nil => try writer.writeAll("nil"),
            .bool => try writer.print("{}", .{self.bool}),
            .number => try writer.print("{}", .{self.number}),
            .obj => try writer.print("{f}", .{self.obj}),
        }
    }
};
