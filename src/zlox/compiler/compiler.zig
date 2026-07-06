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
const Local = zlox.compiler.Local;
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

/// Local variables tracked during compilation.
locals: [cmn.U8_SIZE]Local,

/// The number of local variables in scope at a given point during compilation.
local_count: u16 = 0,

/// Current scope depth at a given point during compilation.
scope_depth: u16 = 0,

/// Allocate a new `Compiler` instance on the heap, returning a pointer to it.
///
/// The caller owns the returned pointer and is responsible for freeing it.
pub fn create(parser: *Parser, interned_strings: *HashTable) !*Compiler {
    return try mem.createStruct(Compiler, .{
        .locals = undefined,
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

    // Pop local variables at end of scope
    while (self.local_count > 0 and self.lastLocal().depth > self.scope_depth) {
        self.emitOp(.pop);
        self.local_count -= 1;
    }
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

/// Compile a declaration from source tokens.
fn declaration(self: *Compiler) void {
    switch (self.parser.next.type) {
        .keyword_var => do(self.parser.advance(), self.variableDeclaration()),
        else => self.statement(),
    }

    if (self.parser.panic_mode) self.parser.synchronize();
}

/// Compile a variable declaration statement from source tokens.
fn variableDeclaration(self: *Compiler) void {
    const ident_offset: u8 = self.variableIdentifier("Expected variable name.");

    if (self.parser.nextMatches(.equal)) self.expression() else self.emitOp(.nil);
    self.parser.consume(.semicolon, "Expected ';' after variable declaration.");

    self.defineVariable(ident_offset);
}

/// Compile a statement from source tokens.
fn statement(self: *Compiler) void {
    switch (self.parser.next.type) {
        .keyword_if => do(self.parser.advance(), self.ifStmt()),
        .keyword_while => do(self.parser.advance(), self.whileStmt()),
        .keyword_print => do(self.parser.advance(), self.printStmt()),
        .brace_left => do(self.parser.advance(), self.scope(block)),
        else => self.expressionStmt(),
    }
}

/// Compile an if-statement from source tokens.
fn ifStmt(self: *Compiler) void {
    self.parser.consume(.paren_left, "Expected '(' after 'if'.");
    self.expression();
    self.parser.consume(.paren_right, "Expected ')' after expression.");

    // Emit .jump_if_false to jump over then-branch if condition is false. We emit
    // a .pop to pop the value left on the stack by the condition expression and
    // then compile the then-branch statement. These will be executed if the condition
    // is not false
    const then_jump: usize = self.emitJump(.jump_if_false);
    self.emitOp(.pop);
    self.statement();

    // Emit .jump to jump over else-branch if we reach this instruction. This keeps
    // the then-branch from falling through to the else-branch. We then patch then_jump
    // to jump over the .jump, followed by a .pop for the else-branch to pop the value
    // left on the stack by the condition expression if the then-branch was jumped over
    const else_jump: usize = self.emitJump(.jump);
    self.patchJump(then_jump);
    self.emitOp(.pop);

    if (self.parser.nextMatches(.keyword_else)) self.statement();

    // Patch else_jump to the end of the if-statement bytecode
    self.patchJump(else_jump);
}

/// Compile a while-loop statement from source tokens.
fn whileStmt(self: *Compiler) void {
    const loop_start: usize = self.instructionOffset();

    self.parser.consume(.paren_left, "Expected '(' after 'while'.");
    self.expression();
    self.parser.consume(.paren_right, "Expected ')' after expression.");

    const exit_jump: usize = self.emitJump(.jump_if_false);

    self.emitOp(.pop);
    self.statement();

    self.emitLoop(loop_start);
    self.patchJump(exit_jump);
    self.emitOp(.pop);
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

/// Compile a block statement from source tokens.
fn block(self: *Compiler) void {
    while (self.parser.next.isNot(.brace_right) and self.parser.next.isNot(.eof)) {
        self.declaration();
    }
    self.parser.consume(.brace_right, "Expected '}' after block.");
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
        .orExpr => orExpr,
        .andExpr => andExpr,
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
    var set_op: OpCode = undefined;
    var get_op: OpCode = undefined;

    var var_offset: i32 = self.resolveLocal(identifier);
    if (var_offset != -1) {
        set_op = .local_set;
        get_op = .local_get;
    } else {
        var_offset = self.makeIdentConstant(identifier);
        set_op = .global_set;
        get_op = .global_get;
    }

    if (can_assign and self.parser.nextMatches(.equal)) {
        self.expression();
        self.emitOp1(set_op, @intCast(var_offset));
    } else {
        self.emitOp1(get_op, @intCast(var_offset));
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

/// Compile an `and` operator expression.
///
/// The left-hand operand of the `and` expression has already been compiled to
/// the chunk at the point this will be executed.
fn andExpr(self: *const Compiler, _: bool) void {
    // The left-hand operand will be on the stack for this jump
    const end: usize = self.emitJump(.jump_if_false);

    self.emitOp(.pop);
    self.expr(.@"and");

    self.patchJump(end);
}

/// Compile an `or` operator expression.
///
/// The left-hand operand of the `or` expression has already been compiled to
/// the chunk at the point this will be executed.
fn orExpr(self: *const Compiler, _: bool) void {
    // The left-hand operand will be on the stack for this jump
    const end: usize = self.emitJump(.jump_if_true);

    self.emitOp(.pop);
    self.expr(.@"or");

    self.patchJump(end);
}

// Variable compilation/management functions ==================================

/// Compile a variable identifier, returning the offset to the constant string
/// for the variable's identifier in the compiling chunk's constants array.
///
/// If the variable identifier cannot be parsed, errors with message `expect`.
fn variableIdentifier(self: *Compiler, expect: []const u8) u8 {
    self.parser.consume(.identifier, expect);

    // Declare local if we're in a local scope. We just return 0 if so since locals
    // are resolved by identifier tokens while global variables are resolved by
    // their runtime-constant identifier strings loaded into the VM before the
    // lox bytecode is executed
    if (self.scope_depth > 0) {
        self.declareLocal();
        return 0;
    }

    return self.makeIdentConstant(self.parser.current);
}

/// Declare a variable in the current scope with the current token as its identifier.
///
/// Does nothing if we're currently in the global scope. Global variables are declared
/// and defined separately from local variables.
///
/// The local will be considered uninitialized/undefined until `markDefined()`
/// is called.
fn declareLocal(self: *Compiler) void {
    if (self.scope_depth == 0) return;

    const identifier: Token = self.parser.current;

    // Check for existing variable with this identifier in this scope
    var i: i32 = @as(i32, self.local_count) - 1;
    while (i >= 0) : (i -= 1) {
        const local: Local = self.locals[@intCast(i)];

        if (local.depth != -1 and local.depth < self.scope_depth) break;
        if (identifier.lexemeEquals(local.identifier)) {
            self.parser.@"error"(
                "A variable with this name already exists in this scope.",
            );
        }
    }

    if (self.local_count == cmn.U8_SIZE) {
        return self.parser.@"error"("Too many local variables in function.");
    }

    defer self.local_count += 1;

    // Add declared local to locals array
    self.locals[self.local_count] = Local{
        .identifier = identifier,
        .depth = -1,
        .is_captured = false,
    };
}

/// Returns a pointer to the most recently defined local variable.
fn lastLocal(self: *Compiler) *Local {
    return &self.locals[self.local_count - 1];
}

/// Mark the most recently declared local as defined/ready for use.
///
/// Does nothing if we're currently in the global scope. Global variables are declared
/// and defined separately from local variables.
fn markDefined(self: *Compiler) void {
    if (self.scope_depth == 0) return;
    self.lastLocal().depth = self.scope_depth;
}

/// Walks down scoped locals array until locating the local variable with the given
/// `identifier`, returning the offset within the locals array of that local.
///
/// Returns `-1` if it does not exist.
///
/// Because of the way the stack behaves with statements popping their stack values
/// when complete, the only values on the stack when a local is declared are the
/// values of other locals in scope. This means the offset of the local in the
/// locals array directly reflects its location in the stack.
fn resolveLocal(self: *const Compiler, identifier: Token) i32 {
    var i: i32 = self.local_count;
    while (i >= 0) : (i -= 1) {
        const local: Local = self.locals[@intCast(i)];

        if (identifier.lexemeEquals(local.identifier)) {
            if (local.depth != -1) return i;
            self.parser.@"error"("Can't read local variable in its own initializer.");
        }
    }

    return -1;
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
fn defineVariable(self: *Compiler, ident_const_offset: u8) void {
    if (self.scope_depth > 0) return self.markDefined();
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
fn makeIdentConstant(self: *const Compiler, token: Token) u8 {
    const ident: *Obj = self.copyString(token.lexeme) catch {
        self.parser.@"error"("Error copying identifier string.");
        return 0;
    };

    return self.makeConstant(.Object(ident));
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

/// Returns the offset at which the next instruction will be inserted.
///
/// Shortcut for `self.chunk.?.instructions.items.len`.
fn instructionOffset(self: *const Compiler) usize {
    return self.chunk.?.instructions.items.len;
}

/// Write a jump `op` followed by placeholder bytes for the jump offset operand.
///
/// Must be patched with `patchJump()` to wire up the accompanying jump offset.
///
/// Returns the instruction offset of the operand to be patched.
fn emitJump(self: *const Compiler, op: OpCode) usize {
    self.emitOp2(op, 0xff, 0xff);
    return self.instructionOffset() - 2;
}

/// Patches the jump instruction operand at `offset` to the current instruction
/// offset.
fn patchJump(self: *const Compiler, offset: usize) void {
    const jump_offset: usize = self.instructionOffset() - offset - 2;

    if (jump_offset > cmn.U16_MAX) {
        self.parser.@"error"("Jump offset is too large.");
    }

    // Patch first and second bytes of 2-byte jump instruction operand
    const jump_byte_1: u8 = @as(u8, @truncate(jump_offset >> 8));
    const jump_byte_2: u8 = @as(u8, @truncate(jump_offset));
    self.chunk.?.instructions.items[offset] = jump_byte_1;
    self.chunk.?.instructions.items[offset + 1] = jump_byte_2;
}

/// Write `OpCode.loop` to the chunk currently being compiled, followed by loop
/// offset operands to loop back to the given instruction `offset`.
fn emitLoop(this: *const Compiler, offset: usize) void {
    const loop_offset: usize = this.instructionOffset() - offset + 3;

    if (loop_offset > cmn.U16_MAX) {
        this.parser.@"error"("Loop body is too large.");
    }

    const loop_byte_1: u8 = @as(u8, @truncate(loop_offset >> 8));
    const loop_byte_2: u8 = @as(u8, @truncate(loop_offset));
    this.emitOp2(.loop, loop_byte_1, loop_byte_2);
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
