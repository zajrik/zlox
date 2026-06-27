//! Root library namespace.

pub const mem = @import("memory.zig");
pub const debug = @import("debug.zig");
pub const common = @import("common.zig");

pub const compiler = @import("compiler/.lib.zig");
pub const object = @import("object/.lib.zig");
pub const parser = @import("parser/.lib.zig");
pub const tokenizer = @import("tokenizer/.lib.zig");
pub const vm = @import("vm/.lib.zig");
