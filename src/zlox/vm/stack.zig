const std = @import("std");
const zlox = @import("../.lib.zig");

const mem = zlox.mem;
const cmn = zlox.common;

const printf = std.debug.print;

// ============================================================================

/// A classic generic last-in, first-out stack structure with a fixed max-size.
///
/// `reset()` must be called before first use unless manually allocating a Stack
/// instance on the heap using `create()`.
///
/// This is only going to be used in one place in the VM and doesn't need to be
/// generic but I wanted to play with generics in zig and this was a good candidate.
pub fn Stack(comptime T: type) type {
    return struct {
        /// Array holding the values on this stack.
        values: [cmn.STACK_MAX]T,

        /// Pointer to the next slot on this stack.
        ///
        /// When a value is pushed to the stack it will be inserted at this address
        /// and the pointer will be incremented to point to the next slot on the
        /// stack.
        top: [*]T,

        /// Initialize a new `Stack` instance on the zig stack.
        ///
        /// You *must* call `reset()` before using the stack.
        pub fn init() Stack(T) {
            return .{
                .values = undefined,
                .top = undefined,
            };
        }

        /// Allocate a new `Stack` instance on the heap, returning a pointer to it.
        ///
        /// The caller owns the returned pointer and is responsible for freeing it.
        pub fn create() !*Stack(T) {
            var stack: *Stack(T) = try mem.create(Stack(T));
            stack.reset();
            return stack;
        }

        /// Destroy this `Stack`, freeing its owned resources.
        pub fn destroy(self: *Stack(T)) void {
            mem.destroy(self);
        }

        /// Reset this `Stack` by setting the top pointer to the address of the
        /// first item in the stack, allowing it to be overwritten on the next push.
        pub fn reset(self: *Stack(T)) void {
            self.top = &self.values;
        }

        /// Returns whether this stack is empty.
        pub fn isEmpty(self: *Stack(T)) bool {
            return self.top == &self.values;
        }

        /// Returns whether this stack has at least one item on it.
        pub fn isNotEmpty(self: *Stack(T)) bool {
            return self.top > &self.values;
        }

        /// Push the given `value` to the top of this stack.
        pub fn push(self: *Stack(T), value: T) void {
            self.top[0] = value;
            self.top += 1;
        }

        /// Pop the value off of the top of this stack and return it.
        pub fn pop(self: *Stack(T)) T {
            self.top -= 1;
            return self.top[0];
        }

        /// Pop the top `n` values off the top of this stack, allowing them to be
        /// overwritten on subsequent pushes.
        pub fn popN(self: *Stack(T), n: u8) void {
            self.top -= n;
        }

        /// Peek at a value in the stack, offset by `distance` from the top of this
        /// stack.
        pub fn peek(self: *Stack(T), distance: usize) T {
            return (self.top - 1 - distance)[0];
        }

        /// Replace a value at `distance` from the top of this stack with the given
        /// `value`.
        ///
        /// Returns the original, replaced value.
        pub fn replace(self: *Stack(T), distance: usize, value: T) T {
            const slot: *T = @ptrCast(self.top - 1 - distance);
            const oldVal: T = slot.*;
            slot.* = value;
            return oldVal;
        }
    };
}
