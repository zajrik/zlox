//! Represents a local variable tracked during compilation.

const std = @import("std");
const zlox = @import("../.lib.zig");

const Token = zlox.tokenizer.Token;

// ============================================================================

const Local: type = @This();

/// Token holding the identifier lexeme of this local.
identifier: Token,

/// Scope depth of this local.
depth: i32,

/// Whether this local has been captured in a closure.
is_captured: bool = false,
