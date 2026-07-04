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

const HashTable = zlox.object.HashTable;
const Obj = zlox.object.Obj;
const Value = zlox.object.Value;

const Fnv1a_32 = std.hash.Fnv1a_32;

const exit = std.process.exit;
const parseFloat = std.fmt.parseFloat;

const do = zlox.common.do;

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

/// Table for interning strings at compile time.
///
/// This is not owned by the compiler and does not need to be freed when the
/// compiler is freed.
strings: *HashTable,

/// Allocate a new `Compiler` instance on the heap, returning a pointer to it.
///
/// The caller owns the returned pointer and is responsible for freeing it.
pub fn create(parser: *Parser, interned_strings: *HashTable) !*Compiler {
    return try mem.createStruct(Compiler, .{
        .parser = parser,
        .strings = interned_strings,
    });
}

/// Destroy this `Compiler`, freeing its owned resources.
pub fn destroy(self: *const Compiler) void {
    mem.destroy(self);
}

/// Begin compilation.
///
/// Returns a pointer to the compiled `Chunk`. The caller owns the returned pointer
/// and is responsible for freeing it.
pub fn compile(self: *Compiler) !?*Chunk {
    self.chunk = try Chunk.create();

    while (!self.parser.nextMatches(.eof)) {
        self.declaration();
    }

    if (self.parser.had_error) {
        self.chunk.?.destroy();
        self.chunk = null;
    }

    return self.endCompilation();
}

/// Return the compiled chunk, ending compilation.
fn endCompilation(self: *const Compiler) ?*Chunk {
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
fn scope(self: *Compiler, rule: fn (*const Compiler) void) void {
    self.pushScope();
    rule(self);
    self.popScope();
}

// Statement compilation methods ==============================================

/// Compile a declaration from source tokens.
fn declaration(self: *const Compiler) void {
    switch (self.parser.next.type) {
        .keyword_var => do(self.parser.advance(), self.variableDeclaration()),
        else => self.statement(),
    }

    if (self.parser.panic_mode) self.parser.synchronize();
}

/// Compile a variable declaration statement from source tokens.
fn variableDeclaration(self: *const Compiler) void {
    const ident_offset: u8 = self.variableIdentifier("Expected variable name.");

    if (self.parser.nextMatches(.equal)) self.expression() else self.emitOp(.nil);
    self.parser.consume(.semicolon, "Expected ';' after variable declaration.");

    self.defineVariable(ident_offset);
}

/// Compile a statement from source tokens.
fn statement(self: *const Compiler) void {
    switch (self.parser.next.type) {
        .keyword_print => do(self.parser.advance(), self.printStmt()),
        else => self.expressionStmt(),
    }
}

/// Compile a print statement from source tokens.
fn printStmt(self: *const Compiler) void {
    self.expression();
    self.parser.consume(.semicolon, "Expected ';' after value.");
    self.emitOp(.print);
}

/// Compile an expression statement from source tokens.
fn expressionStmt(self: *const Compiler) void {
    self.expression();
    self.parser.consume(.semicolon, "Expected ';' after expression.");
    self.emitOp(.pop);
}

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
        .variable => variable,
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
fn expression(self: *const Compiler) void {
    self.expr(.assignment);
}

/// Compile an expression from source tokens with the given `precedence`.
fn expr(self: *const Compiler, precedence: Precedence) void {
    self.parser.advance();

    // Check if this expression is allowed to be treated as an assignment expression
    const can_assign: bool = precedence.lte(.assignment);

    // Start with a prefix rule to parse/compile the first expression. The first token
    // will always start a prefix expression. It may end up nested as an operand inside
    // one or more infix expressions, but it always starts with a prefix expression.
    //
    // 1 + 1;   // number is a prefix rule
    // foo + 1; // identifier is a prefix rule
    // (1 + 1); // grouping is a prefix rule
    // -1 + 1); // unary minus is a prefix rule

    const prefix_rule: ExprFn = getStrategy(self.parser.current).prefix orelse {
        return self.parser.@"error"("Expected expression");
    };
    prefix_rule(self, can_assign);

    // If the precedence of the next token is too low, we stop here. This indicates
    // that it is impossible for the next token to be an infix operator that can
    // continue the expression because that would violate the order of operations
    // dictated by the precedence rules.
    //
    // Otherwise, we continue parsing infix expressions until hitting a token with
    // too low precedence.

    while (precedence.lte(getStrategy(self.parser.next).precedence)) {
        self.parser.advance();
        const infix_rule: ExprFn = getStrategy(self.parser.current).infix orelse {
            return self.parser.@"error"("Expected expression");
        };
        infix_rule(self, can_assign);
    }

    // `.equal` should have been consumed by the variable prefix rule at this point
    // if assignment was allowed, so we should error if we see `=`
    if (can_assign and self.parser.nextMatches(.equal)) {
        self.parser.@"error"("Invalid assignment target.");
    }
}

/// Compile a parenthesized grouping expression from source tokens.
fn grouping(self: *const Compiler, _: bool) void {
    self.expression();
    self.parser.consume(.paren_right, "Expected ')' after expression.");
}

/// Compile a string expression from the current source token.
fn string(self: *const Compiler, _: bool) void {
    errdefer exit(1);

    const lexeme: []const u8 = self.parser.current.lexeme;
    const str_obj: *Obj = try self.copyString(lexeme[1..(lexeme.len - 1)]);

    self.emitConstant(.Object(str_obj));
}

/// Compile a number expression from the current source token.
fn number(self: *const Compiler, _: bool) void {
    const value: f32 = parseFloat(f32, self.parser.current.lexeme) catch {
        return self.parser.@"error"("Invalid number literal.");
    };
    self.emitConstant(.Number(value));
}

/// Compile a literal expression from the current source token.
fn literal(self: *const Compiler, _: bool) void {
    switch (self.parser.current.type) {
        .keyword_nil => self.emitOp(.nil),
        .keyword_true => self.emitOp(.true),
        .keyword_false => self.emitOp(.false),
        else => return,
    }
}

/// Compile a variable/identifier get/set expression from the current source token.
fn variable(self: *const Compiler, can_assign: bool) void {
    self.variableGetSet(self.parser.current, can_assign);
}

/// Compile a variable/identifier get/set expression, emitting bytecode to get/set
/// the value for that variable/identifier.
fn variableGetSet(self: *const Compiler, identifier: Token, can_assign: bool) void {
    const offset: u8 = self.makeIdentConstant(&identifier);

    if (can_assign and self.parser.nextMatches(.equal)) {
        self.expression();
        self.emitOp1(.global_set, offset);
    } else {
        self.emitOp1(.global_get, offset);
    }
}

/// Compile a unary expression from source tokens.
fn unary(self: *const Compiler, _: bool) void {
    const operator_type: TokenType = self.parser.current.type;

    self.expr(.unary);

    switch (operator_type) {
        .minus => self.emitOp(.negate),
        .bang => self.emitOp(.not),
        else => return,
    }
}

/// Compile a binary expression from source tokens.
fn binary(self: *const Compiler, _: bool) void {
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

// Variable parse/compilation/management functions ============================

/// Compile a variable identifier, returning the offset to the constant string
/// for the variable's identifier in the compiling chunk's constants array.
///
/// If the variable identifier cannot be parsed, errors with message `expect`.
fn variableIdentifier(self: *const Compiler, expect: []const u8) u8 {
    self.parser.consume(.identifier, expect);
    return self.makeIdentConstant(&self.parser.current);
}

/// Define a variable.
///
/// If we are in a local scope, the current local will be marked as defined. The
/// value lives on the stack and is modified on the stack when the variable is
/// modified so we don't need to do anything more for it. (not yet implemented)
///
/// If we're in the global scope, emit bytecode to define the global variable,
/// passing the offset of the global variable's constant identifier string as
/// the operand.
fn defineVariable(self: *const Compiler, ident_const_offset: u8) void {
    self.emitOp1(.global_define, ident_const_offset);
}

// Chunk-writing methods ======================================================

/// Add the given `value` to the constants in the chunk being compiled.
///
/// Returns the offset of the added constant.
fn makeConstant(self: *const Compiler, value: Value) u8 {
    // Check for existing constant matching this value and return its offset if
    // it already exists.
    if (self.chunk.?.findConstant(value)) |offset| return offset;

    const offset: u8 = self.chunk.?.addConstant(value);

    if (offset > cmn.U8_MAX) {
        self.parser.@"error"("Too many constants in one chunk.");
        return 0;
    }

    return offset;
}

/// Push an identifier's string to the current chunk's constants array, returning
/// the offset of the added constant string.
fn makeIdentConstant(self: *const Compiler, token: *const Token) u8 {
    return self.makeConstant(
        .Object(
            self.copyString(token.lexeme) catch {
                self.parser.@"error"("Error copying identifier string.");
                return 0;
            },
        ),
    );
}

/// Write the given `byte` to the chunk currently being compiled.
fn emitByte(self: *const Compiler, byte: u8) void {
    self.chunk.?.writeByte(byte, self.parser.current.line);
}

/// Write the given `op` to the chunk currently being compiled.
fn emitOp(self: *const Compiler, op: OpCode) void {
    self.emitByte(op.toByte());
}

/// Write the two given `OpCode` values to the chunk currently being compiled.
fn emitOps(self: *const Compiler, op_1: OpCode, op_2: OpCode) void {
    self.emitOp1(op_1, op_2.toByte());
}

/// Write the given `op` to the chunk currently being compiled, followed by a single
/// byte operand.
fn emitOp1(self: *const Compiler, op: OpCode, byte: u8) void {
    self.emitOp(op);
    self.emitByte(byte);
}

/// Write the given `op` to the chunk currently being compiled, followed by two
/// byte operands.
fn emitOp2(self: *const Compiler, op: OpCode, byte_1: u8, byte_2: u8) void {
    self.emitOp(op);
    self.emitByte(byte_1);
    self.emitByte(byte_2);
}

/// Write the given `op` to the chunk currently being compiled, followed by three
/// byte operands.
fn emitOp3(self: *const Compiler, op: OpCode, byte_1: u8, byte_2: u8, byte_3: u8) void {
    self.emitOp(op);
    self.emitByte(byte_1);
    self.emitByte(byte_2);
    self.emitByte(byte_3);
}

/// Write `OpCode.constant` to the chunk currently being compiled, followed by
/// the constants array offset of the given `value`.
fn emitConstant(self: *const Compiler, value: Value) void {
    self.emitOp1(.constant, self.makeConstant(value));
}

// Object creation methods ====================================================

/// Allocate a new `Obj` of the given `type` with the given `body`.
///
/// Returns a pointer to the allocated `Obj`. The caller owns the returned pointer
/// and is responsible for freeing it.
pub fn createObj(
    self: *const Compiler,
    comptime @"type": Obj.Type,
    body: Obj.Body(@"type"),
) !*Obj {
    const obj: *Obj = try .createConstant(@"type", body);

    // Pre-hash and intern string objects
    if (@"type" == .string) {
        const hash: u32 = Fnv1a_32.hash(body.chars);
        const interned_string: ?*Obj = self.strings.findString(body.chars, hash);

        // Return interned string if it exists
        if (interned_string) |str| {
            obj.destroy();
            return str;
        }

        obj.as.string.hash = hash;
        _ = self.strings.set(obj, .Nil);
    }

    return obj;
}

/// Allocate a copy of the given `string` slice on the heap, wrapping it in a newly
/// allocated lox string `Obj`.
///
/// Returns a pointer to the allocated lox string `Obj`. The caller owns the returned
/// pointer and is responsible for freeing it.
pub fn copyString(self: *const Compiler, chars: []const u8) !*Obj {
    const copy: []u8 = try mem.alloc(u8, chars.len);
    @memcpy(copy.ptr, chars);

    return try self.createObj(
        .string,
        Obj.String{ .chars = copy },
    );
}
