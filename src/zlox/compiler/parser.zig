//! Encapsulates the process of fetching tokens from the `Tokenizer`, bridging
//! the gap between tokenization and compilation.
//!
//! The compiler will use the parser both for obtaining lox tokens from source
//! and for reporting errors related to parsing and compiling those tokens.
//!
//! Lox programs are compiled in a single pass, with each bit of source code passing
//! through the tokenizer, to the parser, and finally to the compiler, so all
//! errors encountered during tokenization and parsing are treated as compilation
//! errors.

const std = @import("std");
const zlox = @import("../.lib.zig");

const Token = zlox.compiler.Token;
const Tokenizer = zlox.compiler.Tokenizer;

// ============================================================================

const Parser: type = @This();

/// The token currently being parsed for compilation.
current: Token,

/// The next token to be parsed for compilation.
next: Token,

/// Whether we encountered at least one (1) error while parsing/compiling.
had_error: bool,

/// Whether the parser is panicking.
///
/// While panicking, we'll skip tokens until we find a valid token boundary to
/// synchronize to so that we can return to parsing the remainder of the input
/// to find any other errors to report, if any.
panic_mode: bool,
