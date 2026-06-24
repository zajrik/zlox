//! Namespace containing all members of the `object` directory.

/// `Value` namespace. Will be eliminated when Value is changed to a struct
/// type down the road.
pub const val = @import("value.zig");

pub const Value = @import("value.zig").Value;
