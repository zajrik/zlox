//! Namespace containing lox native functions.

const std = @import("std");
const zlox = @import("../.lib.zig");

const Value = zlox.object.Value;
const Vm = zlox.vm.Vm;

const Io = std.Io;

/// Register all native functions with the given `vm` instance.
pub fn bootstrapNatives(vm: *Vm) !void {
    try vm.defineNative("clock", 0, native_clock);
}

/// Native `clock()` function.
///
/// Returns the current time since epoch with millisecond precision.
fn native_clock(_: []Value, vm: *Vm) Value {
    const now: Io.Timestamp = Io.Clock.real.now(vm.io);
    return .Number(@floatFromInt(now.toMilliseconds()));
}
