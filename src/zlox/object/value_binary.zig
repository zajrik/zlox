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
/// Implemented as a u64 using NaN-boxing to store type and value information within
/// the 64 bits of the value.
///
/// The u64 representation layout of a value looks like this:
///
/// ````````````````````````````````````````````````````````````````````````````````````````````````
/// Sign Exponent       Mantissa
///  0   00000000000    0000000000000000000000000000000000000000000000000000
/// 64  63         53  52                                                  1
///
/// 64  63           51  50                                             4  3 1
///  0   1111111111111    00000000000000000000000000000000000000000000000  011
///  |   |                |                                                |
///  |   |                Obj address space (if sign bit is set)           Tag bits
///  |   |
///  |   QNaN bits + 1, indicates value is --> a tagged variant if set
///  |                                    \`-> an Obj pointer if set with sign bit
///  |                                     `-> a number if not all set
///  |
///  Sign bit, indicates value is an Obj pointer if set with QNaN bits
///
/// ````````````````````````````````````````````````````````````````````````````````````````````````
///
/// This specific example is a `false` value. This specific example is also quite
/// possibly the most satisfied I've ever been with my notes 🤌
pub const Value = packed struct {
    // The underlying u64 representation of this lox value.
    val: u64,

    /// Represents the type variants of a lox value.
    pub const Type = enum(u2) { nil, bool, number, obj };

    /// Represents the type of a lox value from the zig side.
    pub fn Variant(comptime T: Value.Type) type {
        return switch (T) {
            .nil => void,
            .bool => bool,
            .number => f64,
            .obj => *Obj,
        };
    }

    /// Bitmask of the sign bit of an f64, represented as u64.
    ///
    /// Indicates the value is an obj pointer.
    const MaskSign: u64 = 0b1000000000000000000000000000000000000000000000000000000000000000;

    /// Bitmask of the QNaN bits (+1 bit) of an f64, represented as u64.
    ///
    /// Indicates the value is one of the tagged variants (nil, true, false).
    const MaskQnan: u64 = 0b0111111111111100000000000000000000000000000000000000000000000000;

    /// Bitmask of sign bit + QNaN bits for casting object pointers.
    const MaskObj: u64 = MaskSign | MaskQnan;

    /// Tag bitmask indicating a `nil` value.
    const TagNil: u3 = 0b001;

    /// Tag bits indicating a `true` value.
    const TagTrue: u3 = 0b010;

    /// Tag bitmask indicating a `false` value.
    const TagFalse: u3 = 0b011;

    /// The constant `nil` lox Value.
    pub const Nil: Value = .{ .val = MaskQnan | TagNil };

    /// The constant `true` lox Value.
    pub const True: Value = .{ .val = MaskQnan | TagTrue };

    /// The constant `false` lox Value.
    pub const False: Value = .{ .val = MaskQnan | TagFalse };

    /// Creates a bool `Value` from the given `boolean`.
    pub fn Bool(boolean: Value.Variant(.bool)) Value {
        return if (boolean) True else False;
    }

    /// Creates a number `Value` from the given `number`.
    pub fn Number(number: Value.Variant(.number)) Value {
        return .{ .val = @as(u64, @bitCast(number)) };
    }

    /// Creates an object `Value` from the given `obj`.
    pub fn Object(obj: Value.Variant(.obj)) Value {
        return .{ .val = MaskObj | @as(u64, @intFromPtr(obj)) };
    }

    /// Returns whether this value is of type `T`.
    pub fn is(self: Value, comptime T: Value.Type) bool {
        return switch (T) {
            .nil => self == Nil,
            .bool => self.val | 1 == False.val,
            .number => (self.val & MaskQnan) != MaskQnan,
            .obj => (self.val & MaskObj) == (MaskObj),
        };
    }

    /// Returns whether this value is not of type `T`.
    pub fn isNot(self: Value, comptime T: Value.Type) bool {
        return !self.is(T);
    }

    /// Returns whether this value is an object of type `T`.
    pub fn isObj(self: Value, comptime T: Obj.Type) bool {
        return if (self.as(.obj)) |it| it.is(T) else false;
    }

    /// Returns whether this value is falsey.
    ///
    /// `nil` and `false` are falsey, everything else is truthy.
    pub fn isFalsey(self: Value) bool {
        return self.is(.nil) or (self.is(.bool) and self == False);
    }

    /// Returns whether this value equals `other`.
    pub fn equals(self: Value, other: Value) bool {
        return self == other;
    }

    /// Returns the result of dividing `self` by `other`.
    ///
    /// Provided to allow implementation-specific divide-by-0 checks.
    ///
    /// Returns an error if dividing by zero. It is illegal behavior to call this
    /// with any non-number value.
    pub fn divideBy(self: Value, other: Value) !Value {
        // Runtime error on divide by 0
        // const number_a: Value.Variant(.number) = a.cast(.number);
        // const number_b: Value.Variant(.number) = b.cast(.number);
        // if (number_a == 0 or number_b == 0) return self.err("Divide by 0");

        // Runtime error on divide by 0, SIMD for funsies 🤡
        const Vec: type = @Vector(2, u64);
        const v_1: Vec = .{ self.val, other.val };
        const v_2: Vec = @splat(0);
        if (countTrues(v_1 == v_2) > 0) return error.divide_by_zero;

        return .Number(self.cast(.number) / other.cast(.number));
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
        return if (self.as(.obj)) |it| it.as(T) else null;
    }

    /// Cast this value to the zig representation of the given variant type `T`.
    ///
    /// It is illegal behavior to call this with the wrong type.
    pub fn cast(self: Value, comptime T: Value.Type) Value.Variant(T) {
        std.debug.assert(self.is(T));

        return switch (T) {
            .nil => Nil,
            .bool => self == True,
            .number => @as(Value.Variant(.number), @bitCast(self.val)),
            .obj => @as(Value.Variant(.obj), @ptrFromInt(self.val & ~MaskObj)),
        };
    }

    /// Returns this value cast to an object variant of type `T`.
    ///
    /// It is illegal behavior to call this with the wrong type.
    pub fn objCast(self: Value, comptime T: Obj.Type) *Obj.Variant(T) {
        return self.cast(.obj).cast(T);
    }

    /// Returns the name string of the type of this value for error printing.
    pub fn typeName(self: Value) []const u8 {
        if (self.is(.nil)) return "Nil";
        if (self.is(.bool)) return "Bool";
        if (self.is(.number)) return "Number";
        return "Obj";
    }

    /// Custom formatter for `Value` values.
    pub fn format(self: Value, writer: *Writer) !void {
        if (self.is(.nil)) return try writer.writeAll("nil");
        if (self.as(.bool)) |it| return try writer.print("{}", .{it});
        if (self.as(.number)) |it| return try writer.print("{}", .{it});
        if (self.as(.obj)) |it| return try writer.print("{f}", .{it});
        return try writer.writeAll("NaN");
    }
};
