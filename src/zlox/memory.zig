const std = @import("std");

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

// ============================================================================

var _allocator: *ArenaAllocator = undefined;

/// Initialize the memory module with the given `arena` allocator.
pub fn init(arena: *ArenaAllocator) void {
    _allocator = arena;
}

/// Returns the global allocator.
pub fn allocator() Allocator {
    return _allocator.allocator();
}

/// Releases all resources allocated by the global allocator.
///
/// This does not need to be called if using the ArenaAllocator provided by
/// juicy main, since that's automatically cleaned up on exit.
pub fn deinitAllocator() void {
    _allocator.deinit();
}

/// Allocate memory for a struct of type `T`.
///
/// Returns a pointer to the allocated struct.
pub fn create(comptime T: type) !*T {
    return allocator().create(T);
}

/// Allocate memory for a struct of type `T`, setting its initial value to the
/// given `initial` value.
///
/// Returns a pointer to the allocated struct.
pub fn createStruct(comptime T: type, initial: T) !*T {
    const result: *T = try create(T);
    result.* = initial;
    return result;
}

/// Free resources at the given pointer.
pub fn destroy(ptr: anytype) void {
    return allocator().destroy(ptr);
}

/// Allocates an array of type `T`, sized for `n` items.
pub fn alloc(comptime T: type, n: usize) ![]T {
    return allocator().alloc(T, n);
}

/// Reallocates memory for `ptr` to the given `new_size`.
pub fn realloc(ptr: anytype, new_size: usize) !@TypeOf(ptr) {
    return allocator().realloc(ptr, new_size);
}

/// Free an allocated array.
pub fn free(ptr: anytype) void {
    return allocator().free(ptr);
}
