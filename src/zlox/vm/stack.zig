const std = @import("std");
const zlox = @import("../.lib.zig");

const mem = zlox.mem;
const cmn = zlox.common;

const Writer = std.Io.Writer;

const cmpfmt = std.fmt.comptimePrint;

// ============================================================================

/// A classic generic last-in, first-out stack structure.
///
/// Initialize a new Stack instance with `Stack.empty`.
///
/// `reset()` must be called before first use to set the `Stack.top` pointer to
/// point to the first open slot.
pub fn Stack(comptime T: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();

        /// A `Stack` containing no elements.
        pub const empty: Self = .{};

        /// Array holding the values on this stack.
        values: [capacity]T = undefined,

        /// Pointer to the next slot on this stack.
        ///
        /// When a value is pushed to the stack it will be inserted at this address
        /// and the pointer will be incremented to point to the next slot on the
        /// stack.
        top: [*]T = undefined,

        /// Reset this `Stack` by setting the top pointer to the address of the
        /// first slot in the stack, allowing it to be overwritten on the next push.
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

        /// Peek at the value at `offset` from the top of this stack.
        pub fn peek(self: *const Self, offset: usize) T {
            return (self.top - 1 - offset)[0];
        }

        /// Returns a pointer to the stack slot at the given `offset` from the top
        /// of this stack.
        pub fn slot(self: *const Self, offset: usize) *T {
            return @ptrCast(self.top - 1 - offset);
        }

        /// Push the given `value` to the top of this stack.
        pub fn push(self: *Self, value: T) void {
            if (self.size() == capacity) @panic(
                cmpfmt("Stack({any}, {d}): Stack overflow", .{ T, capacity }),
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

        /// Pop a single value off of the top of this stack, discarding it.
        ///
        /// Returns the new stack size after discarding the value.
        pub fn discard(self: *Self) usize {
            _ = self.pop();
            return self.size();
        }

        /// Push a copy of the value at `offset` from the top of this stack to
        /// the top of this stack.
        pub fn copy(self: *Self, offset: usize) void {
            self.push(self.peek(offset));
        }

        /// Replace a value at `offset` from the top of this stack with the given
        /// `value`.
        ///
        /// Returns the original, replaced value.
        pub fn replace(self: *Self, offset: usize, value: T) T {
            const old_val: T = self.slot(offset).*;
            self.slot(offset).* = value;
            return old_val;
        }

        /// Swap the values on this stack at the given offsets from the top of this
        /// stack.
        pub fn swap(self: *Self, offset_1: usize, offset_2: usize) void {
            _ = self.replace(offset_1, self.replace(offset_2, self.peek(offset_1)));
        }

        /// Custom formatter for `Stack` values.
        ///
        /// Stacks must be formatted by reference, not by value, and the values
        /// within the stack must implement a `format` method.
        pub fn format(self: *const Self, writer: *Writer) !void {
            // If stack is empty, don't print anything
            if (self.isEmpty()) return;

            try writer.writeAll("        |  ");
            defer writer.writeAll("\n") catch {};

            var it: [*]const T = &self.values;
            while (@intFromPtr(it) < @intFromPtr(self.top)) : (it += 1) {
                try writer.print("[ {f} ]", .{it[0]});
            }
        }
    };
}
