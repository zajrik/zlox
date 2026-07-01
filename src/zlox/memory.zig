//! The zlox memory management module.
//!
//! This is the one piece of global state I'm allowing myself in this project.
//! I don't want to have to pass allocators all over the place when I'm not even
//! writing this for public consumption or like as a library or anything 🤡

const std = @import("std");
const zlox = @import(".lib.zig");

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const Obj = zlox.object.Obj;

// ============================================================================

var _arena: *ArenaAllocator = undefined;
var _allocator: Allocator = undefined;
var _initialized: bool = false;
var _is_arena: bool = false;

/// Linked list of heap-allocated `Obj` values.
///
/// Contains all lox objects created by the VM at runtime, to be used by the
/// garbage collector to reach unreferenced objects after tracing living object
/// references.
var root_obj: ?*Obj = null;

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

// Object management functions ================================================

// Free all allocated lox objects.
pub fn freeObjects() void {
    var object: ?*Obj = root_obj;
    while (object != null) {
        const next: ?*Obj = object.?.next;
        object.?.destroy();
        object = next;
    }
}

/// Allocate a new `Obj` of the given `type` with the given `body`.
///
/// Returns a pointer to the allocated `Obj`.
///
/// Objects created with this function are linked to allow tracing by the GC.
pub fn createObj(comptime @"type": Obj.Type, body: Obj.Body(@"type")) !*Obj {
    const obj: *Obj = try .create(@"type", body);

    obj.next = root_obj;
    root_obj = obj;

    return obj;
}

/// Allocate a copy of the given `string` slice on the heap, wrapping it in a newly
/// allocated lox string `Obj`.
///
/// Returns a pointer to the allocated lox string `Obj`. The caller owns the returned
/// pointer and is responsible for freeing it.
pub fn copyString(string: []const u8) !*Obj {
    const copy: []u8 = try alloc(u8, string.len);
    @memcpy(copy.ptr, string);

    return try createObj(
        .string,
        Obj.String{ .chars = copy },
    );
}

/// Allocate a new lox string `Obj` on the heap, wrapping and taking ownership of
/// the given slice.
///
/// Returns a pointer to the allocated lox string `Obj`. The caller owns the returned
/// pointer and is responsible for freeing it.
///
/// The given `string` slice will be freed when the allocated `Obj` is freed.
pub fn takeString(string: []const u8) !*Obj {
    return try createObj(
        .string,
        Obj.String{ .chars = string },
    );
}
