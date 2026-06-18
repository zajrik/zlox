const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const DebugAllocator = std.heap.DebugAllocator;

// ============================================================================

pub const MemError = error{OutOfMemory};

var _debugAllocator: DebugAllocator(.{}) = if (builtin.mode == .Debug) .init else null;
var _allocator: ArenaAllocator = .init(switch (builtin.mode) {
    .Debug => _debugAllocator.allocator(),
    else => std.heap.smp_allocator,
});

/// Returns the global allocator.
pub fn allocator() Allocator {
    return _allocator.allocator();
}

/// Releases all resources allocated by the global allocator.
pub fn deinitAllocator() void {
    _allocator.deinit();
}

/// Allocate memory for a struct of type `T`.
///
/// Returns a pointer to the allocated struct.
pub fn create(comptime T: type) MemError!*T {
    return allocator().create(T);
}

/// Allocate memory for a struct of type `T`, setting its initial value to the
/// given `init` value.
///
/// Returns a pointer to the allocated struct.
pub fn createStruct(comptime T: type, init: T) MemError!*T {
    const result: *T = try create(T);
    result.* = init;
    return result;
}

/// Free resources at the given pointer.
pub fn destroy(ptr: anytype) void {
    return allocator().destroy(ptr);
}

/// Allocates an array of type `T`, sized for `n` items.
pub fn alloc(comptime T: type, n: usize) MemError![]T {
    return allocator().alloc(T, n);
}

/// Reallocates memory for `ptr` to the given `new_size`.
pub fn realloc(ptr: anytype, new_size: usize) MemError!@TypeOf(ptr) {
    return allocator().realloc(ptr, new_size);
}

/// Free an allocated array.
pub fn free(ptr: anytype) void {
    return allocator().free(ptr);
}
