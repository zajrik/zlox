//! Namespace containing all members of the `vm` directory.

pub const native = @import("native.zig");

pub const CallFrame = @import("call_frame.zig");
pub const ExecutionResult = @import("execution_result.zig").ExecutionResult;
pub const Stack = @import("stack.zig").Stack;
pub const Vm = @import("vm.zig");
