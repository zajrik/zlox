const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

pub const Error = error{OutOfMemory};

var _allocator: ArenaAllocator = .init(std.heap.page_allocator);

/// Returns the global allocator.
pub fn allocator() Allocator {
    return _allocator.allocator();
}

/// Releases all resources allocated by the global allocator.
pub fn deinitAllocator() void {
    _allocator.deinit();
}

/// Allocate memory for an object of type [T].
///
/// Returns a pointer to the allocated object.
pub fn create(comptime T: type) Error!*T {
    return allocator().create(T);
}

/// Free resources at the given pointer.
pub fn destroy(ptr: anytype) void {
    return allocator().destroy(ptr);
}

/// Allocates an array of type [T], sized for [n] items.
pub fn alloc(comptime T: type, n: usize) Error![]T {
    return allocator().alloc(T, n);
}

/// Reallocates memory for [ptr] to the given [new_size].
pub fn realloc(ptr: anytype, new_size: usize) Error!@TypeOf(ptr) {
    return allocator().realloc(ptr, new_size);
}

/// Free an allocated array.
pub fn free(ptr: anytype) void {
    return allocator().free(ptr);
}
