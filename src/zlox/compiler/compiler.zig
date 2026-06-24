//! Compiles lox source code into lox bytecode to run on the virtual machine.
//!
//! A `Compiler` is responsible for compiling a single function scope. Any functions
//! encountered within the currently compiling scope will receive their own `Compiler`
//! instance to handle compilation of that function scope.
//!
//! The root of a lox program is itself an implicitly-executed function scope for
//! purposes of having only a single abstracted compilation process.

const std = @import("std");
const zlox = @import("../.lib.zig");

// ============================================================================

const Compiler: type = @This();

/// Current scope depth at a given point during compilation.
scope_depth: u16,
