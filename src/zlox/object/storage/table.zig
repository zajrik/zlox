//! Hash-table implementation mapping lox string object keys to lox values.
//!
//! Implemented using open addressing and linear probing for inserts and tombstones
//! for deletions.
//!
//! Initialize a new Table with `Table.empty`.
//!
//! A Table owns allocated memory that must be released at the end of its lifetime
//! by calling `Table.deinit()`.

const std = @import("std");
const zlox = @import("../../.lib.zig");

const mem = zlox.mem;

const Obj = zlox.object.Obj;
const Value = zlox.object.Value;

const Writer = std.Io.Writer;

const eql = std.mem.eql;
const exit = std.process.exit;

// =================================================================================================

const Table: type = @This();

/// The number of entries within this hash-table.
count: usize = 0,

/// Array slice containing all entries within this hash-table.
///
/// The length of this slice is the capacity of the table.
entries: []Entry = undefined,

/// Maximum load factor before resizing.
const max_load: f32 = 0.75;

/// A `Table` containing no entries.
pub const empty: Table = .{};

/// Deinitialize this `Table`, freeing its owned resources.
pub fn deinit(self: *Table) void {
    mem.free(self.entries);
}

/// Increase the given `capacity` by a predefined growth factor (`2`).
///
/// The growth factor is defined such that the resulting capacity is always a power
/// of `2` to support bit-twiddling our backing-array key-hash indexing rather than
/// using the modulus of the hash and capacity, which is much, much slower.
///
/// Returns the increased capacity.
fn grow(capacity: usize) usize {
    return if (capacity < 8) 8 else capacity * 2;
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
fn resize(self: *Table, capacity: usize) !void {
    // Allocate and pre-populate new entries array
    const entries: []Entry = try mem.alloc(Entry, capacity);
    for (entries) |*entry| entry.* = .empty;

    self.count = 0;

    // Move existing entries to new entries array
    for (self.entries) |entry| if (entry.key) |key| {
        findEntry(entries, key).* = .{ .key = key, .val = entry.val };
        self.count += 1;
        if (self.count >= capacity) break;
    };

    mem.free(self.entries);
    self.entries = entries;
}

/// Find an `Entry` with the given `key` in the given `entries` slice.
fn findEntry(entries: []Entry, key: *Obj.String) *Entry {
    var index: usize = key.hash & (entries.len - 1);
    var tombstone: ?*Entry = null;

    while (true) : (index = (index + 1) & (entries.len - 1)) {
        const entry: *Entry = &entries[index];

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
        else if (entry.key == key) return entry;
    }
}

/// Find a string key object in this table matching the given `chars` and `hash`.
///
/// Returns a pointer to the string key object, or `null` if no key was found.
pub fn findString(self: *const Table, chars: []const u8, hash: u32) ?*Obj.String {
    if (self.count == 0 or self.entries.len == 0) return null;

    var index: usize = hash & (self.entries.len - 1);

    while (true) : (index = (index + 1) & (self.entries.len - 1)) {
        const entry: *Entry = &self.entries[index];

        // If entry key isn't null, check that it's the one we're looking for
        // and return it if so
        if (entry.key) |key| {
            const key_match: bool = key.chars.len == chars.len and
                key.hash == hash and
                eql(u8, key.chars, chars);

            if (key_match) return key;
        }

        // If it's an empty slot, no key was found
        else if (entry.val.is(.nil)) return null;
    }
}

/// Set a value in this table under the given `key`.
///
/// Returns whether the entry was empty before the given value was set.
///
/// Returns an error if a resize was necessary but allocation failed.
pub fn set(self: *Table, key: *Obj.String, val: Value) !bool {
    const new_count: f128 = @floatFromInt(self.count + 1);
    const entries: f128 = @floatFromInt(self.entries.len);
    const max_load_capacity: f128 = entries * max_load;

    if (new_count > max_load_capacity) {
        try self.resize(grow(self.entries.len));
    }

    const entry: *Entry = findEntry(self.entries, key);
    const is_open: bool = entry.key == null;

    // Only increase count if we're not overwriting a tombstone
    if (is_open and entry.val.is(.nil)) self.count += 1;

    entry.key = key;
    entry.val = val;

    return is_open;
}

/// Add all entries from `other` to this table.
pub fn addAll(self: *Table, other: *Table) !void {
    for (other.entries) |entry| {
        if (entry.key) |key| {
            _ = try self.set(key, entry.val);
        }
    }
}

/// Get the value from this table at the given `key`, if it exists.
pub fn get(self: *const Table, key: *Obj.String) ?Value {
    if (self.count == 0) return null;

    const entry: *Entry = findEntry(self.entries, key);
    if (entry.key == null) return null;

    return entry.val;
}

/// Returns whether this table has an existing entry for the given `key`.
pub fn hasKey(self: *const Table, key: *Obj.String) bool {
    return self.count != 0 and findEntry(self.entries, key).key != null;
}

/// Remove the entry with the given `key` from this table, if it exists.
///
/// Returns whether an entry was removed.
pub fn delete(self: *Table, key: *Obj.String) bool {
    const entry: *Entry = findEntry(self.entries, key);
    if (entry.key == null) return false;

    // Replace entry with tombstone
    entry.* = .tombstone;

    return true;
}

/// Returns an iterator over key strings in this `Table`.
pub fn keys(self: *const Table) KeyIterator {
    return .{
        .count = self.entries.len,
        .entries = self.entries.ptr,
    };
}

/// An entry within a `Table`.
pub const Entry = struct {
    /// The key associated with this entry.
    ///
    /// An entry with a `null` key is either unused, or a tombstone for a
    /// deleted entry.
    key: ?*Obj.String,

    /// The value associated with this entry.
    val: Value,

    /// An empty `Entry` struct.
    const empty: Entry = .{ .key = null, .val = .Nil };

    /// A tombstone `Entry` value, inserted in place of deleted entries.
    const tombstone: Entry = .{ .key = null, .val = .True };

    /// Custom formatter for `Entry` values.
    pub fn format(self: Entry, writer: *Writer) !void {
        try writer.print(
            "Table.Entry{{ .key = {?f}, .val = {f} }}",
            .{ self.key, self.val },
        );
    }
};

/// An iterator over `Table` keys.
pub const KeyIterator = struct {
    /// The total *potential* number of keys yielded by this iterator.
    ///
    /// This is not a guarantee of key count.
    count: usize,

    /// Pointer to the entries from which this iterator yields keys.
    entries: [*]Entry,

    /// Returns the next key from this iterator.
    pub fn next(self: *KeyIterator) ?*Obj.String {
        return while (self.count > 0) {
            const entry: Entry = self.entries[0];
            self.count -= 1;
            self.entries += 1;
            if (entry.key) |key| break key;
        } else null;
    }
};
