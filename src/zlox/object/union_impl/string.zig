//! A lox string `Obj` union struct.
const String: type = @This();

/// Slice of characters within this lox string.
///
/// This slice is owned by the lox string obj and must be freed when the obj
/// is destroyed.
chars: []const u8,
