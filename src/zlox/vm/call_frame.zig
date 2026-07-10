//! A function call frame, tracking and facilitating execution of a function's
//! compiled instructions at runtime.
//!
//! All lox functions are currently wrapped in closures for convenience. That's
//! how it's presented in the book, but it's a little wasteful allocating a closure
//! for every single function. I'd like to eventually separate the two if I can.

const std = @import("std");
const zlox = @import("../.lib.zig");

const Obj = zlox.object.Obj;
const Value = zlox.object.Value;

// ============================================================================

const CallFrame: type = @This();

/// The function being invoked.
closure: *Obj.Closure,

/// Instruction pointer pointing to the next compiled instruction in the function
/// being invoked.
ip: [*]u8,

/// Pointer to the beginning of this frame's stack window.
slots: [*]Value,

/// Read the next byte from the invoked function's compiled instructions.
pub fn readByte(self: *CallFrame) u8 {
    defer self.ip += 1;
    return self.ip[0];
}

/// Read the next two bytes from the invoked function's compiled instructions,
/// treating them as a single 16-bit value.
pub fn readShort(self: *CallFrame) u16 {
    defer self.ip += 2;
    return @as(u16, self.ip[0]) << 8 | self.ip[1];
}

/// Read a constant value from the compiled constants of the invoked function
/// by its constant offset obtained from reading the next byte from the compiled
/// instructions.
pub fn readConstant(self: *CallFrame) Value {
    return self.closure.function.chunk.constantAt(self.readByte());
}

/// Read a string constant value from the compiled constants of the invoked function
/// by its constant offset obtained from reading the next byte from the compiled
/// instructions.
///
/// See also:
/// - `readConstant`
pub fn readString(self: *CallFrame) *Obj.String {
    return self.readConstant().obj.as(.string);
}
