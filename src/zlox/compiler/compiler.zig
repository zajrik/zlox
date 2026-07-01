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
const cmn = zlox.common;
const debug = zlox.debug;

const Chunk = zlox.compiler.Chunk;
const CompileStrategy = zlox.compiler.CompileStrategy;
const ExprFn = zlox.compiler.ExprFn;
const OpCode = zlox.compiler.OpCode;

const Parser = zlox.parser.Parser;
const ParseStrategy = zlox.parser.ParseStrategy;
const Precedence = zlox.parser.Precedence;
const Rule = zlox.parser.Rule;

const Token = zlox.tokenizer.Token;
const Tokenizer = zlox.tokenizer.Tokenizer;
const TokenType = zlox.tokenizer.TokenType;

const Obj = zlox.object.Obj;
const Value = zlox.object.Value;

const exit = std.process.exit;

// ============================================================================

const Compiler: type = @This();

/// Parser instance primed with the source we're compiling.
///
/// Not owned by the compiler.
parser: *Parser,

/// Current scope depth at a given point during compilation.
scope_depth: u16 = 0,

/// Currently-compiling chunk.
///
/// This is null if compilation failed, or if `compile()` has not been called yet.
/// If compilation failed, the chunk will be freed so no need to worry about freeing
/// it manually on failure.
///
/// TODO: Chunks will be encapsulated by function objects after objects are implemented
chunk: ?*Chunk = null,

/// Allocate a new `Compiler` instance on the heap, returning a pointer to it.
///
/// The caller owns the returned pointer and is responsible for freeing it.
pub fn create(parser: *Parser) !*Compiler {
    return try mem.createStruct(
        Compiler,
        Compiler{ .parser = parser },
    );
}

/// Destroy this `Compiler`, freeing its owned resources.
pub fn destroy(self: *Compiler) void {
    mem.destroy(self);
}

/// Begin compilation.
///
/// Returns a pointer to the compiled `Chunk`. The caller owns the returned pointer
/// and is responsible for freeing it.
pub fn compile(self: *Compiler) !?*Chunk {
    self.chunk = try Chunk.create();

    self.expression();

    self.parser.consume(.eof, "Expect end of expression.");

    if (self.parser.had_error) {
        defer self.chunk = null;
        defer self.chunk.?.destroy();
    }

    return self.endCompilation();
}

/// Return the compiled chunk, ending compilation.
fn endCompilation(self: *Compiler) ?*Chunk {
    if (self.chunk) |chunk| {
        self.emitOp(.@"return");
        if ((comptime debug.dump_chunk) and self.parser.had_error) {
            debug.disassembleChunk(chunk, "code");
        }
    }

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

// Statement compilation methods ==============================================

// Expression compilation methods =============================================

/// Get the strategy for compiling the given expression `token` from the parser.
fn getStrategy(token: Token) CompileStrategy {
    // This is a really pointless level of indirection in hindsight but I consider
    // determining how the expression should be compiled to be a part of the parsing
    // phase so I want to keep the pratt parser table in the parser namespace.
    //
    // An alternative could be to make the expression methods pub so they can just
    // be referenced directly in the parser. I'll consider it if this becomes a
    // compilation bottleneck

    const strategy: ParseStrategy = .forToken(token);
    return .{
        .prefix = mapRule(strategy.prefix),
        .infix = mapRule(strategy.infix),
        .precedence = strategy.precedence,
    };
}

/// Map the given parser `Rule` into its matching expression compilation function.
fn mapRule(rule: ?Rule) ?ExprFn {
    return if (rule) |r| switch (r) {
        .grouping => grouping,
        .string => string,
        .number => number,
        .literal => literal,
        // .variable => variable,
        .unary => unary,
        .binary => binary,
        // .orExpr => orExpr,
        // .andExpr => andExpr,
        // .call => call,
        // .dot => dot,
        // .nilish => nilish,
        // .funExpr => funExpr,
        // .thisExpr => thisExpr,
        else => null,
    } else null;
}

/// Compile an expression from source tokens.
fn expression(self: *Compiler) void {
    self.expr(.assignment);
}

/// Compile an expression from source tokens with the given `precedence`.
fn expr(self: *Compiler, precedence: Precedence) void {
    self.parser.advance();
    const prefix_rule: ExprFn = getStrategy(self.parser.current).prefix orelse {
        return self.parser.@"error"("Expected expression");
    };
    prefix_rule(self);

    while (precedence.lte(getStrategy(self.parser.next).precedence)) {
        self.parser.advance();
        const infix_rule: ExprFn = getStrategy(self.parser.current).infix orelse {
            return self.parser.@"error"("Expected expression");
        };
        infix_rule(self);
    }
}

/// Compile a parenthesized grouping expression from source tokens.
fn grouping(self: *Compiler) void {
    self.expression();
    self.parser.consume(.paren_right, "Expected ')' after expression.");
}

/// Compile a string expression from the current source token.
fn string(self: *Compiler) void {
    errdefer exit(1);

    const lexeme: []const u8 = self.parser.current.lexeme;
    const str_obj: *Obj = try mem.copyString(lexeme[1..(lexeme.len - 1)]);

    self.emitConstant(.Object(str_obj));
}

/// Compile a number expression from the current source token.
fn number(self: *Compiler) void {
    const value: f32 = std.fmt.parseFloat(f32, self.parser.current.lexeme) catch return;
    self.emitConstant(.Number(value));
}

/// Compile a literal expression from the current source token.
fn literal(self: *Compiler) void {
    switch (self.parser.current.type) {
        .keyword_nil => self.emitOp(.nil),
        .keyword_true => self.emitOp(.true),
        .keyword_false => self.emitOp(.false),
        else => return,
    }
}

/// Compile a unary expression from source tokens.
fn unary(self: *Compiler) void {
    const operator_type: TokenType = self.parser.current.type;

    self.expr(.unary);

    switch (operator_type) {
        .minus => self.emitOp(.negate),
        .bang => self.emitOp(.not),
        else => return,
    }
}

/// Compile a binary expression from source tokens.
fn binary(self: *Compiler) void {
    const operator: Token = self.parser.current;
    const strategy: ParseStrategy = .forToken(operator);

    // Compile expression right-hand side with precedence + 1
    self.expr(strategy.precedence.next());

    switch (operator.type) {
        .plus => self.emitOp(.add),
        .minus => self.emitOp(.subtract),
        .star => self.emitOp(.multiply),
        .slash => self.emitOp(.divide),

        .bang_equal => self.emitOps(.equal, .not),
        .equal_equal => self.emitOp(.equal),
        .greater => self.emitOp(.greater),
        .less => self.emitOp(.less),
        .greater_equal => self.emitOps(.less, .not),
        .less_equal => self.emitOps(.greater, .not),

        else => return,
    }
}

// Chunk-writing methods ======================================================

/// Add the given `value` to the constants in the chunk being compiled.
///
/// Returns the offset of the added constant.
fn makeConstant(self: *Compiler, value: Value) u8 {
    const offset: u8 = self.chunk.?.addConstant(value);

    if (offset > cmn.U8_MAX) {
        self.parser.@"error"("Too many constants in one chunk.");
        return 0;
    }

    return offset;
}

/// Write the given `byte` to the chunk currently being compiled.
fn emitByte(self: *Compiler, byte: u8) void {
    self.chunk.?.writeByte(byte, self.parser.current.line);
}

/// Write the given `op` to the chunk currently being compiled.
fn emitOp(self: *Compiler, op: OpCode) void {
    self.emitByte(op.toByte());
}

/// Write the two given `OpCode` values to the chunk currently being compiled.
fn emitOps(self: *Compiler, op_1: OpCode, op_2: OpCode) void {
    self.emitOp1(op_1, op_2.toByte());
}

/// Write the given `op` to the chunk currently being compiled, followed by a single
/// byte operand.
fn emitOp1(self: *Compiler, op: OpCode, byte: u8) void {
    self.emitOp(op);
    self.emitByte(byte);
}

/// Write the given `op` to the chunk currently being compiled, followed by two
/// byte operands.
fn emitOp2(self: *Compiler, op: OpCode, byte_1: u8, byte_2: u8) void {
    self.emitOp(op);
    self.emitByte(byte_1);
    self.emitByte(byte_2);
}

/// Write the given `op` to the chunk currently being compiled, followed by three
/// byte operands.
fn emitOp3(self: *Compiler, op: OpCode, byte_1: u8, byte_2: u8, byte_3: u8) void {
    self.emitOp(op);
    self.emitByte(byte_1);
    self.emitByte(byte_2);
    self.emitByte(byte_3);
}

/// Write `OpCode.constant` to the chunk currently being compiled, followed by
/// the constants array offset of the given `value`.
fn emitConstant(self: *Compiler, value: Value) void {
    self.emitOp1(.constant, self.makeConstant(value));
}
