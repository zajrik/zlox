const std = @import("std");
const zlox = @import("../.lib.zig");

const mem = zlox.mem;
const cmn = zlox.common;

const Writer = std.Io.Writer;

const cmpfmt = std.fmt.comptimePrint;

// ============================================================================

/// A classic generic last-in, first-out stack structure.
///
/// `reset()` must be called before first use unless manually allocating a Stack
/// instance on the heap using `create()`.
pub fn Stack(comptime T: type, max: comptime_int) type {
    return struct {
        const Self = @This();

        /// Array holding the values on this stack.
        values: [max]T,

        /// Pointer to the next slot on this stack.
        ///
        /// When a value is pushed to the stack it will be inserted at this address
        /// and the pointer will be incremented to point to the next slot on the
        /// stack.
        top: [*]T,

        /// Initialize a new `Stack` instance on the zig stack.
        ///
        /// You *must* call `reset()` before using the stack.
        pub fn init() Self {
            return .{
                .values = undefined,
                .top = undefined,
            };
        }

        /// Allocate a new `Stack` instance on the heap, returning a pointer to it.
        ///
        /// The caller owns the returned pointer and is responsible for freeing it.
        pub fn create() !*Self {
            var stack: *Self = try mem.create(Self);
            stack.reset();
            return stack;
        }

        /// Destroy this `Stack`, freeing its owned resources.
        pub fn destroy(self: *Self) void {
            mem.destroy(self);
        }

        /// Reset this `Stack` by setting the top pointer to the address of the
        /// first item in the stack, allowing it to be overwritten on the next push.
        pub fn reset(self: *Self) void {
            self.top = &self.values;
        }

        /// Returns the number of items on this stack.
        pub fn size(self: *const Self) usize {
            return self.top - &self.values;
        }

        /// Returns whether this stack is empty.
        pub fn isEmpty(self: *const Self) bool {
            return self.size() == 0;
        }

        /// Returns whether this stack has at least one item on it.
        pub fn isNotEmpty(self: *const Self) bool {
            return self.size() > 0;
        }

        /// Push the given `value` to the top of this stack.
        pub fn push(self: *Self, value: T) void {
            if (self.size() == max) @panic(
                cmpfmt("Stack({any}): Stack overflow", .{T}),
            );

            self.top[0] = value;
            self.top += 1;
        }

        /// Pop the value off of the top of this stack and return it.
        pub fn pop(self: *Self) T {
            self.top -= 1;
            return self.top[0];
        }

        /// Pop the top `n` values off the top of this stack, allowing them to be
        /// overwritten on subsequent pushes.
        pub fn popN(self: *Self, n: u8) void {
            self.top -= n;
        }

        /// Peek at a value in the stack, offset by `distance` from the top of this
        /// stack.
        pub fn peek(self: *const Self, distance: usize) T {
            return (self.top - 1 - distance)[0];
        }

        /// Replace a value at `distance` from the top of this stack with the given
        /// `value`.
        ///
        /// Returns the original, replaced value.
        pub fn replace(self: *Self, distance: usize, value: T) T {
            const slot: *T = @ptrCast(self.top - 1 - distance);
            const oldVal: T = slot.*;
            slot.* = value;
            return oldVal;
        }

        /// Custom formatter for `Stack` values.
        ///
        /// Stacks must be formatted by reference, not by value, and the values
        /// within the stack must implement a `format` method.
        pub fn format(self: *const Self, writer: *Writer) !void {
            // If stack is empty, don't print anything
            if (self.isEmpty()) return;

            try writer.writeAll("           ");
            defer writer.writeAll("\n") catch {};

            var slot: [*]const T = &self.values;
            while (@intFromPtr(slot) < @intFromPtr(self.top)) : (slot += 1) {
                try writer.print("[ {f} ]", .{slot[0]});
            }
        }
    };
}
