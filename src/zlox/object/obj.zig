const std = @import("std");
const zlox = @import("../.lib.zig");

const mem = zlox.mem;

const Writer = std.Io.Writer;

/// A heap-allocated lox object.
pub const Obj = union(Type) {
    /// Represents the different types of heap-allocated lox objects.
    pub const Type = enum(u8) { string };

    /// Object data payload type for the given object `type`.
    fn Data(comptime @"type": Type) type {
        return switch (@"type") {
            .string => Obj.ObjString,
        };
    }

    /// A heap-allocated lox string object.
    pub const ObjString = struct {
        /// Slice of characters within this lox string.
        chars: []const u8,
    };
    string: ObjString,

    /// Allocate a new `Obj` of the given `type` with the given `data`.
    ///
    /// Returns a pointer to the allocated `Obj`. The caller owns this obj and
    /// is responsible for freeing it.
    pub fn create(comptime @"type": Type, data: Data(@"type")) !*Obj {
        const obj: *Obj = try mem.create(Obj);

        // Set obj payload to the given data
        switch (@"type") {
            .string => obj.*.string = data,
        }

        return obj;
    }

    /// Destroy this `Obj`, freeing its owned resources.
    pub fn destroy(self: *Obj) void {
        // Free data owned by the object
        switch (self) {
            .string => mem.free(self.string.chars),
        }

        // Free the object itself
        mem.destroy(self);
    }

    /// Returns whether this obj is of the given `type`.
    pub fn is(self: *Obj, @"type": Type) bool {
        return self == @"type";
    }

    /// Returns whether this obj is not of the given `type`.
    pub fn isNot(self: *Obj, @"type": Type) bool {
        return self != @"type";
    }

    /// Custom formatter for `Obj` values.
    pub fn format(self: *Obj, writer: *Writer) Writer.Error!void {
        switch (self.*) {
            .string => try writer.print("{s}", .{self.string.chars}),
        }
    }
};
