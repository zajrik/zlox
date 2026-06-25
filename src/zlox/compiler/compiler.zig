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

const mem = zlox.mem;

const Chunk = zlox.compiler.Chunk;
const OpCode = zlox.compiler.OpCode;
const Parser = zlox.compiler.Parser;
const Token = zlox.compiler.Token;
const Tokenizer = zlox.compiler.Tokenizer;

// ============================================================================

const Compiler: type = @This();

/// Parser instance primed with the source we're compiling.
///
/// Not owned by the compiler.
parser: *Parser,

/// Enclosing compiler forming a linked list of nested compilation scopes, each
/// compiling a single encapsulating function object.
///
/// A compiler with null `enclosing` is the root compiler.
// enclosing: ?*Compiler,

/// Current scope depth at a given point during compilation.
scope_depth: u16 = 0,

/// Currently-compiling chunk.
///
/// TODO: Chunks will be encapsulated by function objects after objects are implemented
chunk: *Chunk = undefined,

/// Allocate a new `Compiler` instance on the heap, returning a pointer to it.
///
/// The caller owns the returned pointer and is responsible for freeing it.
pub fn create(parser: *Parser) !*Compiler {
    return try mem.createStruct(Compiler, .{
        .parser = parser,
        // .enclosing = enclosing,
    });
}

/// Destroy this `Compiler`, freeing its owned resources.
pub fn destroy(self: *Compiler) void {
    mem.destroy(self);
}

/// Begin compilation.
///
/// Returns a pointer to the compiled `Chunk`. The caller owns the returned pointer
/// and is responsible for freeing it.
pub fn compile(self: *Compiler) !*Chunk {
    self.chunk = try .create();

    self.expression();

    return self.endCompilation();
}

/// Return the compiled chunk, ending compilation.
fn endCompilation(self: *Compiler) !*Chunk {
    return self.chunk;
}

// Scope management methods ===================================================

/// Begin a new scope.
fn pushScope(self: *Compiler) void {
    self.scope_depth += 1;
}

/// End the current scope.
fn popScope(self: *Compiler) void {
    self.scope_depth -= 1;
}

/// Execute the given statement rule within a new scope.
///
/// The scope will be popped when the rule completes.
fn scope(self: *Compiler, rule: fn (*Compiler) void) void {
    self.pushScope();
    rule(self);
    self.popScope();
}

/// Compile an expression from source tokens.
pub fn expression(_: *Compiler) void {}

// Chunk-writing methods ======================================================

/// Write the given `byte` to the chunk currently being compiled.
fn emitByte(self: *Compiler, byte: u8) void {
    self.chunk.writeByte(byte, self.parser.current.line);
}

/// Write the given `op` to the chunk currently being compiled.
fn emitOp(self: *Compiler, op: OpCode) void {
    self.chunk.writeOp(op, self.parser.current.line);
}

/// Write the given `op` to the chunk currently being compiled, followed by a single
/// byte operand.
fn emitOp1(self: *Compiler, op: OpCode, byte: u8) void {
    self.chunk.writeOp1(op, self.parser.current.line, byte);
}

/// Write the given `op` to the chunk currently being compiled, followed by two
/// byte operands.
fn emitOp2(self: *Compiler, op: OpCode, byte_1: u8, byte_2: u8) void {
    self.chunk.writeOp2(op, self.parser.current.line, byte_1, byte_2);
}

/// Write the given `op` to the chunk currently being compiled, followed by three
/// byte operands.
fn emitOp3(self: *Compiler, op: OpCode, byte_1: u8, byte_2: u8, byte_3: u8) void {
    self.chunk.writeOp3(op, self.parser.current.line, byte_1, byte_2, byte_3);
}
