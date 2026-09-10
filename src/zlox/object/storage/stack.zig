const std = @import("std");
const zlox = @import("../../.lib.zig");

const mem = zlox.mem;
const cmn = zlox.common;

const Writer = std.Io.Writer;

const assert = std.debug.assert;
const panic = std.debug.panic;

// =================================================================================================

/// A classic generic last-in, first-out stack structure with a fixed capacity.
///
/// Initialize a new Stack instance with `Stack.empty`.
pub fn Stack(comptime T: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();

        /// Array holding the values on this stack.
        values: [capacity]T = undefined,

        /// Pointer to the next slot on this stack.
        ///
        /// When a value is pushed to the stack it will be inserted at this address
        /// and the pointer will be incremented to point to the next slot on the
        /// stack.
        top: StackPtr = uninitialized,

        /// Represents a pointer to a slot/value on the stack.
        const StackPtr: type = [*]allowzero T;

        /// Uninitialized stack top pointer value.
        ///
        /// A stack with its top pointer equal to this has never stored a value.
        /// Any other value indicates a stack that has been used.
        const uninitialized: StackPtr = @ptrFromInt(0);

        /// A `Stack` containing no elements.
        pub const empty: Self = .{};

        /// Reset this `Stack` by setting the top pointer to the address of the
        /// first slot in the stack, allowing it to be overwritten on the next push.
        pub fn reset(self: *Self) void {
            self.top = &self.values;
        }

        /// Returns the number of items on this stack.
        pub fn size(self: *const Self) usize {
            if (self.top == uninitialized) return 0;
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
            assert(self.isNotEmpty());
            return (self.top - 1 - offset)[0];
        }

        /// Returns a pointer to the stack slot at the given `offset` from the top
        /// of this stack.
        pub fn slot(self: *const Self, offset: usize) *T {
            assert(self.isNotEmpty());
            return @ptrCast(self.top - 1 - offset);
        }

        /// Push the given `value` to the top of this stack.
        pub fn push(self: *Self, value: T) void {
            // Initialize the stack on first push
            if (self.top == uninitialized) self.reset();

            if (self.size() == capacity) panic(
                "Stack({any}, {d}): Stack overflow",
                .{ T, capacity },
            );

            self.top[0] = value;
            self.top += 1;
        }

        /// Pop the value off of the top of this stack and return it.
        pub fn pop(self: *Self) T {
            assert(self.isNotEmpty());
            self.top -= 1;
            return self.top[0];
        }

        /// Pop the top `n` values off the top of this stack, allowing them to be
        /// overwritten on subsequent pushes.
        pub fn popN(self: *Self, n: usize) void {
            assert(n <= self.size());
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

        /// Replace a value at `offset` from the top of this stack with the given `value`.
        ///
        /// Returns the original, replaced value.
        pub fn replace(self: *Self, offset: usize, value: T) T {
            assert(self.isNotEmpty());
            const old_val: T = self.slot(offset).*;
            self.slot(offset).* = value;
            return old_val;
        }

        /// Swap the values on this stack at the given offsets from the top of this
        /// stack.
        pub fn swap(self: *Self, a: usize, b: usize) void {
            _ = self.replace(a, self.replace(b, self.peek(a)));
        }

        /// Returns an iterator over the values of this stack.
        pub fn iter(self: *Self) StackIterator(T) {
            return .{ .count = self.size(), .values = &self.values };
        }

        /// Custom formatter for `Stack` values.
        ///
        /// Stacks must be formatted by reference, not by value, and the values
        /// within the stack must implement a `format` method.
        pub fn format(self: *Self, writer: *Writer) !void {
            if (self.isEmpty()) return;

            try writer.writeAll("        |  ");
            defer writer.writeAll("\n") catch {};

            var values: StackIterator(T) = self.iter();
            while (values.next()) |it| try writer.print("[ {f} ]", .{it});
        }
    };
}

/// An iterator over the values on a `Stack`, yielding pointers to those values.
///
/// Iteration is in bottom-up order.
///
/// If values are somehow popped from the stack during iteration, they will still
/// exist in the backing array to be iterated over as they were when the iterator
/// was initialized unless they've been overwritten, but there's no way to know if
/// they have.
///
/// Additionally, if values are pushed to the array during iteration, they will not
/// be captured in the iterator since it captures the size of the stack when the
/// iterator is initialized.
pub fn StackIterator(comptime T: type) type {
    return struct {
        const Self = @This();

        /// The number of remaining values in this iterator.
        count: usize,

        /// Pointer to the backing array from which this iterator yields values.
        values: [*]T,

        /// Returns the next value from this iterator.
        pub fn next(self: *Self) ?*T {
            return while (self.count > 0) {
                const value: *T = &self.values[0];
                self.count -= 1;
                self.values += 1;
                break value;
            } else null;
        }
    };
}
