//! The zlox memory management module.
//!
//! This is the one piece of global state I'm allowing myself in this project.
//! I don't want to have to pass allocators all over the place when I'm not even
//! writing this for public consumption or like as a library or anything 🤡

const std = @import("std");
const zlox = @import(".lib.zig");

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

// =============================================================================

var _arena: *ArenaAllocator = undefined;
var _allocator: Allocator = undefined;
var _initialized: bool = false;
var _is_arena: bool = false;

/// Growth factor for expanding array/table capacity.
const growth_factor: usize = 2;

/// Initialize the memory module with the given `arena` allocator.
///
/// The memory module may only be initialized once.
pub fn initArena(arena: *ArenaAllocator) void {
    if (_initialized) return;
    _initialized = true;
    _is_arena = true;

    _arena = arena;
    _allocator = arena.allocator();
}

/// Initialize the memory module with the given `Allocator`.
///
/// The memory module may only be initialized once.
pub fn init(a: Allocator) void {
    if (_initialized) return;
    _initialized = true;

    _allocator = a;
}

/// Returns the global allocator.
pub fn allocator() Allocator {
    return _allocator;
}

/// Releases all resources allocated by the global arena allocator.
///
/// Does nothing if the module was initialized with a non-arena allocator.
///
/// This does not need to be called if using the ArenaAllocator provided by
/// juicy main, since that's automatically cleaned up on exit.
pub fn deinitAllocator() void {
    if (!_is_arena) return;
    _arena.deinit();
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

/// Allocates an array of type `T`, sized for `n` items.
pub fn alloc(comptime T: type, n: usize) ![]T {
    return allocator().alloc(T, n);
}

/// Reallocates memory for `ptr` to the given `new_size`.
pub fn realloc(ptr: anytype, new_size: usize) !@TypeOf(ptr) {
    return allocator().realloc(ptr, new_size);
}

/// Allocates a duplicate slice of the given type `T`.
///
/// Returns the allocated slice. The caller owns this slice and is responsible for
/// freeing it.
///
/// Shortcut for `mem.allocator().dupe(...)`
pub fn dupe(comptime T: type, m: []const T) ![]T {
    return allocator().dupe(T, m);
}

/// Free resources at the given pointer.
pub fn destroy(ptr: anytype) void {
    return allocator().destroy(ptr);
}

/// Free an allocated array.
pub fn free(ptr: anytype) void {
    return allocator().free(ptr);
}

/// Increase the given `capacity` by a predefined growth factor.
///
/// Returns the increased capacity.
pub fn growCapacity(capacity: usize) usize {
    return if (capacity < 8) 8 else capacity * growth_factor;
}

/// Returns an interpolated string using `std.fmt.allocPrint`, allocating as needed.
///
/// If allocation fails for any reason, returns the unformatted `fmt` string.
pub fn allocfmt(comptime fmt: []const u8, args: anytype) []const u8 {
    return std.fmt.allocPrint(allocator(), fmt, args) catch fmt;
}
