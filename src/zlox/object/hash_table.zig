//! A simple hash-table implementation mapping lox string object keys to lox values.

const std = @import("std");
const zlox = @import("../.lib.zig");

const mem = zlox.mem;

const Obj = zlox.object.Obj;
const Value = zlox.object.Value;

const Writer = std.Io.Writer;

const exit = std.process.exit;

// ============================================================================

const HashTable: type = @This();

const max_load: f32 = 0.75;

/// An entry within a hash-table.
pub const Entry = struct {
    /// The key associated with this entry.
    ///
    /// An entry with a `null` key is either unused, or a tombstone for a
    /// deleted entry.
    key: ?*Obj,

    /// The value associated with this entry.
    val: Value,

    /// An empty `Entry` struct.
    pub const empty: Entry = .{ .key = null, .val = .Nil };

    /// A tombstone `Entry` value, inserted in place of deleted entries.
    pub const tombstone: Entry = .{ .key = null, .val = .Bool(true) };

    /// Custom formatter for `Entry` values.
    pub fn format(self: Entry, writer: *Writer) Writer.Error!void {
        try writer.print(
            "HashTable.Entry {{ .key = {?f}, .val = {f} }}",
            .{ self.key, self.val },
        );
    }
};

/// The number of entries within this hash-table.
count: usize = 0,

/// Array slice containing all entries within this hash-table.
///
/// The length of this slice is the capacity of the table.
entries: []Entry,

/// Allocates a new `HashTable` on the heap.
///
/// Returns a pointer to the allocated table. The caller owns this table and is
/// responsible for freeing it.
pub fn create() !*HashTable {
    const table: *HashTable = try mem.create(HashTable);
    table.entries = &.{};
    return table;
}

/// Destroy this `HashTable`, freeing its owned resources.
pub fn destroy(self: *HashTable) void {
    mem.free(self.entries);
    mem.destroy(self);
}

/// Resize this table to the given `capacity`.
///
/// A new backing array of the given capacity will be allocated, existing entries
/// will be inserted into the new array and the old array will be freed.
///
/// If the new capacity is less than the old capacity, a maximum of `capacity`
/// entries from the existing table will be moved. The subset of entries that
/// are moved in this case is technically deterministic because of the hashing
/// algorithm for string keys and the open addressing method of entry insertion,
/// but I certainly couldn't prove it mathmatically 🤡
pub fn resize(self: *HashTable, capacity: usize) !void {
    // Allocate and pre-populate new entries array
    const entries: []Entry = try mem.alloc(Entry, capacity);
    for (entries) |*entry| entry.* = .empty;

    self.count = 0;

    // Move existing entries to new entries array
    for (self.entries) |entry| if (entry.key) |key| {
        const dest_entry: *Entry = self.findEntry(key);
        dest_entry.key = key;
        dest_entry.val = entry.val;
        self.count += 1;

        if (self.count >= capacity) break;
    };

    mem.free(self.entries);
    self.entries = entries;
}

/// Find an `Entry` with the given `key` in this table.
fn findEntry(self: *HashTable, key: *Obj) *Entry {
    var index: usize = key.as.string.hash % self.entries.len;
    var tombstone: ?*Entry = null;

    while (true) {
        const entry: *Entry = &self.entries[index];

        // If entry key is null but value is nil, it's an empty slot. If the value
        // isn't nil then it's a tombstone, and we'll set that aside and move to
        // the next slot
        //
        // If we hit an empty slot again but have a tombstone set aside then the
        // tombstone is a valid entry slot we can return for the given key
        if (entry.key == null) {
            if (entry.val.is(.nil)) return tombstone orelse entry;
            if (tombstone == null) tombstone = entry;
        }

        // Otherwise check if key matches and move on to the next slot if not.
        //
        // Comparing strings for now but we'll compare references after string
        // interning is in place
        else if (std.mem.eql(u8, entry.key.?.as.string.chars, key.as.string.chars)) {
            return entry;
        }

        index = (index + 1) % self.entries.len;
    }
}

/// Set a value in this table under the given `key`.
///
/// Returns whether an existing entry was overwritten.
pub fn set(self: *HashTable, key: *Obj, val: Value) bool {
    errdefer exit(1);

    const max_load_capacity: f32 = @as(f32, @floatFromInt(self.entries.len)) * max_load;
    const new_count: f32 = @as(f32, @floatFromInt(self.count + 1));
    if (new_count > max_load_capacity) {
        try self.resize(mem.growCapacity(self.entries.len));
    }

    const entry: *Entry = self.findEntry(key);
    const is_open: bool = entry.key == null;

    // Only increase count if we're not overwriting a tombstone
    if (is_open and entry.val.is(.nil)) self.count += 1;

    entry.key = key;
    entry.val = val;

    return is_open;
}

/// Add all entries from `other` to this table.
pub fn addAll(self: *HashTable, other: *HashTable) void {
    for (other.entries) |entry| {
        if (entry.key) |key| {
            _ = self.set(key, entry.value);
        }
    }
}

/// Get the value from this table at the given `key`, if it exists.
pub fn get(self: *HashTable, key: *Obj) ?Value {
    if (self.count == 0) return null;

    const entry: *Entry = self.findEntry(key);
    if (entry.key == null) return null;

    return entry.val;
}

/// Returns whether this table has an existing entry for the given `key`.
pub fn hasKey(self: *HashTable, key: *Obj) bool {
    return self.count != 0 and self.findEntry(key).key != null;
}

/// Remove the entry with the given `key` from this table, if it exists.
///
/// Returns whether an entry was removed.
pub fn delete(self: *HashTable, key: *Obj) bool {
    const entry: *Entry = self.findEntry(key);
    if (entry.key == null) return false;

    // Replace entry with tombstone
    entry.* = .tombstone;

    return true;
}
