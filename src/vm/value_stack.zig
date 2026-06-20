//! A stack of lox `Value` objects.

const common = @import("../common.zig");
const std = @import("std");
const mem = @import("../memory/memory.zig");

const Value = @import("../object/value.zig").Value;

const printf = std.debug.print;

const STACK_MAX = common.STACK_MAX;

// ============================================================================

const ValueStack: type = @This();

/// Array holding the values on this stack.
values: [STACK_MAX]Value,

/// Pointer to the next slot on this stack.
///
/// When a value is pushed to the stack it will be inserted at this address and
/// the pointer will be incremented to point to the next slot on the stack.
top: [*]Value,

/// Allocate a new `ValueStack`, returning a pointer to it.
pub fn create() !*ValueStack {
    const stack: *ValueStack = try mem.create(ValueStack);
    stack.reset();
    return stack;
}

/// Destroy this `ValueStack`, freeing its owned resources.
pub fn destroy(self: *ValueStack) void {
    mem.destroy(self);
}

/// Reset this stack by setting the stack top pointer to the address of the first
/// item in the stack, allowing it to be overwritten on the next push.
pub fn reset(self: *ValueStack) void {
    self.top = &self.values;
}

/// Push the given `value` to the top of this stack.
pub fn push(self: *ValueStack, value: Value) void {
    self.top[0] = value;
    self.top += 1;
}

/// Pop the value off of the top of this stack and return it.
pub fn pop(self: *ValueStack) Value {
    self.top -= 1;
    return self.top[0];
}

/// Pop the top `n` values off the top of this stack, discarding them.
///
/// Technically they're not being discarded, they'll just be overwritten when new
/// values get pushed to the popped slots.
pub fn popN(self: *ValueStack, n: u8) void {
    self.top -= n;
}

/// Peek at a value in the stack, offset by `distance` from the top of this stack
pub fn peek(self: *ValueStack, distance: usize) Value {
    return (self.top - 1 - distance)[0];
}

/// Replace a value at `distance` from the top of this stack with the given `value`.
///
/// Returns the original value.
pub fn replace(self: *ValueStack, distance: usize, value: Value) Value {
    const slot: *Value = @ptrCast(self.top - 1 - distance);
    const oldVal: Value = slot.*;
    slot.* = value;
    return oldVal;
}
