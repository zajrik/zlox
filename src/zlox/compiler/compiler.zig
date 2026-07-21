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
const ExprFn = zlox.compiler.ExprFn;
const Jump = zlox.compiler.Jump;
const JumpList = zlox.compiler.JumpList;
const Local = zlox.compiler.Local;
const LoopScope = zlox.compiler.LoopScope;
const OpCode = zlox.compiler.OpCode;
const Upvalue = zlox.compiler.Upvalue;

const Parser = zlox.parser.Parser;
const ParseStrategy = zlox.parser.ParseStrategy;
const Precedence = zlox.parser.Precedence;

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
const splitBytes = zlox.common.splitBytes;

// ============================================================================

const Compiler: type = @This();

/// Enclosing compiler, used for tracking and resolving upvalues.
///
/// The root compiler should always have a null `enclosing` value.
enclosing: ?*Compiler = null,

/// Parser instance primed with the source we're compiling.
///
/// Not owned by the compiler.
parser: *Parser,

/// The currently-compiling function object.
///
/// This is null if compilation failed, or if `compile()` has not been called yet.
///
/// If compilation failed, the allocated function will be freed so no need to worry
/// about freeing it manually on failure.
function: ?*Obj.Function = null,

/// Table for interning strings at compile time.
///
/// This is not owned by the compiler and does not need to be freed when the
/// compiler is freed.
strings: *HashTable,

/// Upvalues tracked by this compilation scope.
upvalues: [cmn.U8_SIZE]Upvalue,

/// Local variables tracked during compilation.
locals: [cmn.U8_SIZE]Local,

/// The number of local variables in scope at a given point during compilation.
local_count: u8 = 0,

/// Current scope depth at a given point during compilation.
scope_depth: u16 = 0,

/// The innermost loop scope at a given point during compilation.
///
/// Loop scopes must be freed when they end.
loop_scope: ?*LoopScope = null,

/// Allocate a new `Compiler` instance on the heap, returning a pointer to it.
///
/// The caller owns the returned pointer and is responsible for freeing it.
pub fn create(
    /// The type of function to compiled.
    T: Obj.Function.Type,
    /// Parser instance primed with source input to compile.
    parser: *Parser,
    /// Table for interning strings at compile time.
    interned_strings: *HashTable,
    /// Enclosing compiler, if any.
    enclosing: ?*Compiler,
) !*Compiler {
    const compiler: *Compiler = try mem.createStruct(Compiler, .{
        .enclosing = enclosing,
        .upvalues = undefined,
        .locals = undefined,
        .parser = parser,
        .strings = interned_strings,
    });

    // Initialize compiled function object
    compiler.function = try compiler.createObj(
        .function,
        Obj.Function{ .type = T, .chunk = .init() },
    );

    // If the function type is not `script` and the current token is an identifier,
    // capture its lexeme to use as the function identifier string
    if (T != .script and parser.current.is(.identifier)) {
        compiler.function.?.identifier = try compiler.copyString(
            parser.current.lexeme,
        );
    }

    // Reserve local slot 0 for the compiled function itself
    compiler.local_count += 1;
    compiler.locals[0] = Local{
        .identifier = Token.init(.identifier, "", 0, 0),
        .depth = 0,
    };

    return compiler;
}

/// Destroy this `Compiler`, freeing its owned resources.
pub fn destroy(self: *const Compiler) void {
    mem.destroy(self);
}

/// Returns a pointer to the `Chunk` of the currently-compiling function object.
///
/// This will panic if called after compilation finishes and any compilation errors
/// were emitted.
fn chunk(self: *const Compiler) *Chunk {
    return &self.function.?.chunk;
}

/// Returns the offset at which the next instruction will be inserted.
///
/// Autocomplete-able shortcut for `self.chunk.?.len()`.
fn instructionOffset(self: *const Compiler) usize {
    return self.chunk().len();
}

/// Compile the entirety of the source input into a function object to be executed
/// by the VM.
///
/// Returns a pointer to the compiled `Obj.Function`. The caller owns the returned
/// pointer and is responsible for freeing it.
///
/// Returns `null` if compilation failed for any reason.
pub fn compile(self: *Compiler) !?*Obj.Function {
    // Compile declarations from source until reaching end of input.
    while (!self.parser.match(.eof)) {
        self.declaration();
    }

    // Dump chunk and destroy compiling function if there were any errors
    if (self.parser.had_error) {
        if (comptime debug.dump_chunk) {
            debug.disassembleChunk(self.chunk(), "code");
        }
        self.function.?.destroy();
        self.function = null;
    }

    return self.endCompilation();
}

/// Return the compiled function, ending compilation.
fn endCompilation(self: *const Compiler) ?*Obj.Function {
    // Emit nil return to allow functions to return nil by default if they do not
    // specify a return value of their own
    if (self.function) |fun| {
        self.emitDefaultReturn();

        if ((comptime debug.dump_chunk) and !self.parser.had_error) {
            const chunk_name: []const u8 = it: {
                if (fun.identifier) |ident| break :it ident.chars;
                if (fun.type == .script) break :it "script";
                break :it "anon fun";
            };
            debug.disassembleChunk(&fun.chunk, chunk_name);
        }
    }

    return self.function;
}

// Scope management methods ===================================================

/// Begin a new lexical scope.
fn pushScope(self: *Compiler) void {
    self.scope_depth += 1;
}

/// End the current lexical scope.
fn popScope(self: *Compiler) void {
    self.scope_depth -= 1;

    // Pop locals from stack and close upvalues at end of scope
    while (self.local_count > 0 and self.lastLocal().depth > self.scope_depth) {
        self.emitOp(if (self.lastLocal().is_captured) .close else .pop);
        self.local_count -= 1;
    }
}

/// Execute the given statement rule within a new lexical scope.
///
/// The scope will be popped when the rule completes.
fn scope(self: *Compiler, rule: fn (*Compiler) void) void {
    self.pushScope();
    defer self.popScope();

    rule(self);
}

/// Begin a new loop scope.
fn pushLoopScope(self: *Compiler) void {
    self.loop_scope = LoopScope.create(self.loop_scope) catch return;
}

/// End the current loop scope.
fn popLoopScope(self: *Compiler) void {
    if (self.loop_scope) |it| {
        defer it.destroy();
        self.loop_scope = it.enclosing;
    }
}

// Statement compilation methods ==============================================

/// Compile a declaration from source tokens.
fn declaration(self: *Compiler) void {
    switch (self.parser.next.type) {
        .keyword_fun => do(self.parser.advance(), self.funDeclaration()),
        .keyword_var => do(self.parser.advance(), self.varDeclaration()),
        else => self.statement(),
    }

    if (self.parser.panic_mode) self.parser.synchronize();
}

/// Compile a function declaration from source tokens.
fn funDeclaration(self: *Compiler) void {
    const ident_offset: u8 = self.variableIdentifier("Expected function name.");

    // Mark function identifier as defined so it can refer to itself
    self.markDefined();

    self.compileFun(.function, false);
    self.defineVariable(ident_offset);
}

/// Compile a variable declaration statement from source tokens.
fn varDeclaration(self: *Compiler) void {
    const ident_offset: u8 = self.variableIdentifier("Expected variable name.");

    if (self.parser.match(.equal)) self.expression() else self.emitOp(.nil);
    self.parser.consume(.semicolon, "Expected ';' after variable declaration.");

    self.defineVariable(ident_offset);
}

/// Compile a statement from source tokens.
fn statement(self: *Compiler) void {
    switch (self.parser.next.type) {
        .keyword_print => do(self.parser.advance(), self.printStmt()),
        .keyword_if => do(self.parser.advance(), self.ifStmt()),
        .keyword_switch => do(self.parser.advance(), self.switchStmt()),
        .keyword_break => do(self.parser.advance(), self.breakStmt()),
        .keyword_continue => do(self.parser.advance(), self.continueStmt()),
        .keyword_return => do(self.parser.advance(), self.returnStmt()),
        .keyword_while => do(self.parser.advance(), self.whileStmt()),
        .keyword_for => do(self.parser.advance(), self.scope(forStmt)),
        .brace_left => do(self.parser.advance(), self.scope(block)),
        else => self.expressionStmt(),
    }
}

/// Compile a print statement from source tokens.
///
/// printStmt := "print" exprStmt ";" ;
fn printStmt(self: *Compiler) void {
    self.expression();
    self.parser.consume(.semicolon, "Expected ';' after value.");
    self.emitOp(.print);
}

/// Compile an if-statement from source tokens.
///
/// ifStmt := "if" "(" expression ")" statement ( "else" statement )? ;
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
    // to jump over else_jump, followed by a .pop for the else-branch to pop the value
    // left on the stack by the condition expression if the then-branch was jumped over
    const else_jump: usize = self.emitJump(.jump);
    self.patchJump(then_jump);
    self.emitOp(.pop);

    if (self.parser.match(.keyword_else)) self.statement();

    // Patch else_jump to the end of the if-statement bytecode
    self.patchJump(else_jump);
}

/// Compile a switch-statement from source tokens.
///
/// switchStmt  := "switch" "(" expression ")" "{" switchCase* defaultCase? "}" ;
/// switchCase  := "case" ":" statement ;
/// defaultCase := "default" ":" statement ;
fn switchStmt(self: *Compiler) void {
    const p: *Parser = self.parser;

    p.consume(.paren_left, "Expected '(' after 'switch'.");
    self.expression();
    p.consume(.paren_right, "Expected ')' after expression.");
    p.consume(.brace_left, "Expected '{' after switch value.");

    var default_found: bool = false;

    const exit_jumps: *JumpList = JumpList.create() catch return self.allocErr();
    defer exit_jumps.destroy();

    while (!p.blockEnd(.brace_right)) {
        if (!p.match(.keyword_case) and !p.match(.keyword_default)) {
            p.err("Expected 'case' or 'default'.");
        }

        // Compile non-default case expression
        if (p.current.isNot(.keyword_default)) {
            // Copy condition value on stack to compare condition and case expression
            // without popping the original condition value from the stack
            self.emitOp(.copy);

            self.expression();
            self.emitOp(.equal);
        }

        // Compile default case
        else {
            if (default_found) p.err(
                "A switch statement may only have a single 'default' case.",
            );
            default_found = true;

            self.emitOp(.true);
        }

        p.consume(.colon, "Expected ':'.");

        const case_jump: usize = self.emitJump(.jump_if_false);
        self.emitOp(.pop);
        self.statement();

        self.addJump(exit_jumps);
        self.patchJump(case_jump);
        self.emitOp(.pop);
    }

    p.consume(.brace_right, "Expected '}' after switch block.");

    self.patchJumpList(exit_jumps);

    // Pop condition value
    self.emitOp(.pop);
}

/// Compile a break statement from source tokens.
fn breakStmt(self: *Compiler) void {
    // Emit an unpatched jump for this break statement and add it to the scope
    if (self.loop_scope) |it| {
        it.addBreak(self.emitJump(.jump)) catch self.allocErr();
        return self.parser.consume(.semicolon, "Expected ';' after 'break'.");
    }

    self.err("'break' cannot be used outside of a loop.");
}

/// Compile a continue statement from source tokens.
fn continueStmt(self: *Compiler) void {
    // Emit a loop instruction with placeholder operand bytes to be patched when
    // continue statements are resolved at the end of the loop scope
    if (self.loop_scope) |it| {
        self.emitOp2(.loop, 0xff, 0xff);
        it.addContinue(self.instructionOffset() - 2) catch self.allocErr();
        return self.parser.consume(.semicolon, "Expected ';' after 'continue'.");
    }

    self.err("'continue' cannot be used outside of a loop.");
}

/// Compile a return statement from source tokens.
fn returnStmt(self: *Compiler) void {
    if (self.function.?.type == .script) self.err(
        "Can't return from top-level code.",
    );

    // Emit default return on empty return statement
    if (self.parser.match(.semicolon)) {
        self.emitDefaultReturn();
    }

    // Otherwise compile return value expression
    else {
        self.expression();
        self.parser.consume(.semicolon, "Expected ';' after return value.");
        self.emitOp(.@"return");
    }
}

/// Compile a while-loop statement from source tokens.
///
/// whileStmt := "while" "(" expression ")" statement ;
fn whileStmt(self: *Compiler) void {
    self.pushLoopScope();
    defer self.popLoopScope();

    const loop_start: usize = self.instructionOffset();

    self.parser.consume(.paren_left, "Expected '(' after 'while'.");
    self.expression();
    self.parser.consume(.paren_right, "Expected ')' after expression.");

    const exit_jump: usize = self.emitJump(.jump_if_false);

    // Pop condition expression value from stack it was truthy
    self.emitOp(.pop);

    // Evaluate loop body
    self.statement();

    // Loop back to start
    self.emitLoop(loop_start);

    // Patch exit here and pop condition expression value from stack
    self.patchJump(exit_jump);
    self.emitOp(.pop);

    // Resolve any break/continue statements compiled within in the loop body
    self.patchBreaks();
    self.patchContinues(loop_start);
}

/// Compiles a for-loop statement from source tokens.
///
/// forStmt := "for" "(" ( varDecl | expression? ";" )
///            expression? ";" expression? ")" statement ;
fn forStmt(self: *Compiler) void {
    const p: *Parser = self.parser;

    self.pushLoopScope();
    defer self.popLoopScope();

    p.consume(.paren_left, "Expected '(' after 'for'.");

    // Compile initializer clause
    switch (p.next.type) {
        .keyword_var => do(p.advance(), self.varDeclaration()),
        .semicolon => p.advance(),
        else => self.expressionStmt(),
    }

    // Set loop start before condition expression. If we have an increment expression,
    // this will be updated so that the final loop instruction jumps to the increment
    // expression which will then jump back here after executing
    var loop_start: usize = self.instructionOffset();

    var exit_jump: ?usize = null;

    // Compile loop condition if present and set exit jump placeholder
    if (!p.match(.semicolon)) {
        self.expression();
        p.consume(.semicolon, "Expected ';' after loop condition.");

        exit_jump = self.emitJump(.jump_if_false);
        self.emitOp(.pop);
    }

    // Compile increment expression if present
    if (!p.match(.paren_right)) {
        const increment_jump: usize = self.emitJump(.jump);
        const increment_start: usize = self.instructionOffset();

        self.expression();
        self.emitOp(.pop);
        p.consume(.paren_right, "Expected ')' after for-clauses.");

        // Loop back to start after executing increment expression, update loop_start
        // to point to the increment so the body loops back here after executing
        self.emitLoop(loop_start);
        loop_start = increment_start;

        self.patchJump(increment_jump);
    }

    // Compile loop body, emit loop to loop back to start (or to increment clause)
    self.statement();
    self.emitLoop(loop_start);

    // If a loop condition was provided, patch exit jump and pop condition
    if (exit_jump) |j| {
        self.patchJump(j);
        self.emitOp(.pop);
    }

    // Resolve any break/continue statements compiled within in the loop body
    self.patchBreaks();
    self.patchContinues(loop_start);
}

/// Compile a block statement from source tokens.
fn block(self: *Compiler) void {
    while (!self.parser.blockEnd(.brace_right)) self.declaration();
    self.parser.consume(.brace_right, "Expected '}' after block.");
}

/// Compile an expression statement from source tokens.
///
/// exprStmt := expression ";" ;
fn expressionStmt(self: *Compiler) void {
    self.expression();
    self.parser.consume(.semicolon, "Expected ';' after expression.");
    self.emitOp(.pop);
}

// Statement/expression compilation overlap functions =========================

/// Compile a function statement or expression of the given `type` from source tokens.
fn compileFun(self: *Compiler, T: Obj.Function.Type, is_expr: bool) void {
    const p: *Parser = self.parser;

    // Load identifier into the current token if this is a labeled function expression
    if (is_expr and p.next.is(.identifier)) p.advance();

    const fun_cmp: *Compiler = Compiler.create(T, p, self.strings, self) catch {
        return p.err("Error compiling function.");
    };
    defer fun_cmp.destroy();

    // Push scope for function to contain arguments and the function body. This
    // does not need to be closed since the scope will be discarded when the compiler
    // instance is freed
    fun_cmp.pushScope();

    p.consume(.paren_left, "Expected '(' after function name.");

    // Compile function parameters, if any
    if (p.next.isNot(.paren_right)) {
        const arity: *u8 = &fun_cmp.function.?.arity;

        while (true) : (if (p.listEnd(.paren_right)) break) {
            fun_cmp.defineVariable(
                fun_cmp.variableIdentifier("Expected parameter identifier."),
            );

            defer arity.* += 1;
            if (arity.* == 255) p.err(
                "A function can't have more than 255 parameters.",
            );
        }
    }

    p.consume(.paren_right, "Expected ')' after parameter list.");

    // Compile block function body if we see an opening brace
    if (p.match(.brace_left)) {
        fun_cmp.block();
    }

    // Compile expression body if we see `=`
    else if (p.match(.equal)) {
        fun_cmp.expression();
        fun_cmp.emitOp(.@"return");
        if (!is_expr) p.consume(.semicolon, "Expected ';' after function body.");
    }

    // Otherwise emit a compilation error
    else {
        p.err("Expected '{' or '=' before function body.");
    }

    const fun_obj: *Obj.Function = fun_cmp.endCompilation() orelse {
        return p.err("Error compiling function.");
    };

    // Add compiled function to chunk constants and emit closure op
    self.emitOp1(.closure, self.makeConstant(.Object(fun_obj.toObj())));

    // Emit closure upvalue bytecode
    var i: u8 = 0;
    while (i < fun_obj.upvalue_count) : (i += 1) {
        self.emitByte(@intFromBool(fun_cmp.upvalues[i].is_local));
        self.emitByte(fun_cmp.upvalues[i].offset);
    }
}

// Expression compilation methods =============================================

/// Compile an expression from source tokens.
fn expression(self: *Compiler) void {
    self.expr(.assignment);
}

/// Compile an expression from source tokens with the given `precedence`.
fn expr(self: *Compiler, precedence: Precedence) void {
    const p: *Parser = self.parser;

    p.advance();

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

    const prefix_rule: ExprFn = p.strategy(p.current).prefix orelse {
        return p.err("Expected expression.");
    };
    prefix_rule(self, can_assign);

    // If the precedence of the next token is higher, we stop here. This indicates
    // that it is impossible for the next token to be an infix operator that can
    // continue the expression because that would violate the order of operations
    // dictated by the precedence rules.
    //
    // Otherwise, we continue parsing infix expressions until hitting a token with
    // higher precedence.

    while (precedence.lte(p.strategy(p.next).precedence)) {
        p.advance();
        const infix_rule: ExprFn = p.strategy(p.current).infix orelse {
            return p.err("Expected expression.");
        };
        infix_rule(self, can_assign);
    }

    // `.equal` should have been consumed by the variable prefix rule at this point
    // if assignment was allowed, so we should error if we see `=`
    if (can_assign and p.match(.equal)) {
        p.err("Invalid assignment target.");
    }
}

/// Compile a parenthesized grouping expression from source tokens.
pub fn grouping(self: *Compiler, _: bool) void {
    self.expression();
    self.parser.consume(.paren_right, "Expected ')' after expression.");
}

/// Compile a string expression from the current source token.
pub fn string(self: *const Compiler, _: bool) void {
    const lexeme: []const u8 = self.parser.current.lexeme;
    const str: *Obj.String = self.copyString(
        lexeme[1..(lexeme.len - 1)],
    ) catch return self.allocErr();

    self.emitConstant(.Object(str.toObj()));
}

/// Compile a number expression from the current source token.
pub fn number(self: *const Compiler, _: bool) void {
    const value: f64 = parseFloat(f64, self.parser.current.lexeme) catch {
        return self.err("Invalid number literal.");
    };

    self.emitConstant(.Number(value));
}

/// Compile a literal expression from the current source token.
pub fn literal(self: *const Compiler, _: bool) void {
    switch (self.parser.current.type) {
        .keyword_nil => self.emitOp(.nil),
        .keyword_true => self.emitOp(.true),
        .keyword_false => self.emitOp(.false),
        else => return,
    }
}

/// Compile a variable/identifier get/set expression from the current source token.
pub fn variable(self: *Compiler, can_assign: bool) void {
    self.variableGetSet(self.parser.current, can_assign);
}

/// Compile a variable/identifier get/set expression, emitting bytecode to get/set
/// the value for that variable/identifier.
fn variableGetSet(self: *Compiler, identifier: Token, can_assign: bool) void {
    var var_offset: u8 = 0;
    var set_op: OpCode = undefined;
    var get_op: OpCode = undefined;

    if (self.resolveLocal(identifier)) |offset| {
        var_offset = offset;
        set_op = .local_set;
        get_op = .local_get;
    } else if (self.resolveUpvalue(identifier)) |offset| {
        var_offset = offset;
        set_op = .upvalue_set;
        get_op = .upvalue_get;
    } else {
        var_offset = self.makeIdentConstant(identifier);
        set_op = .global_set;
        get_op = .global_get;
    }

    if (can_assign and self.parser.match(.equal)) {
        self.expression();
        self.emitOp1(set_op, var_offset);
    } else {
        self.emitOp1(get_op, var_offset);
    }
}

/// Compile a unary expression from source tokens.
pub fn unary(self: *Compiler, _: bool) void {
    const operator_type: TokenType = self.parser.current.type;

    self.expr(.unary);

    switch (operator_type) {
        .minus => self.emitOp(.negate),
        .bang => self.emitOp(.not),
        else => return,
    }
}

/// Compile a binary expression from source tokens.
pub fn binary(self: *Compiler, _: bool) void {
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
pub fn andExpr(self: *Compiler, _: bool) void {
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
pub fn orExpr(self: *Compiler, _: bool) void {
    // The left-hand operand will be on the stack for this jump
    const end: usize = self.emitJump(.jump_if_true);

    self.emitOp(.pop);
    self.expr(.@"or");

    self.patchJump(end);
}

/// Compile a switch expression from source tokens.
///
/// switchExpr := "switch" "(" expression ")" "{" caseExpr* "}" ;
/// caseExpr   := ( expression | "_" ) "=>" expression ;
pub fn switchExpr(self: *Compiler, _: bool) void {
    const p: *Parser = self.parser;

    p.consume(.paren_left, "Expected '(' after 'switch'.");
    self.expression();
    p.consume(.paren_right, "Expected ')' after expression.");
    p.consume(.brace_left, "Expected '{' after switch value.");

    var wildcard_found: bool = false;

    const exit_jumps: *JumpList = JumpList.create() catch return self.allocErr();
    defer exit_jumps.destroy();

    while (!p.blockEnd(.brace_right)) {
        // Compile expression case
        if (p.next.isNot(.identifier) or !p.next.isDiscard()) {
            self.emitOp(.copy);
            self.expression();
            self.emitOp(.equal);
        }

        // Compile wildcard case
        else {
            if (wildcard_found) p.err(
                "A switch expression may only have a single wildcard case.",
            );
            wildcard_found = true;

            p.advance();
            self.emitOp(.true);
        }

        p.consume(.arrow, "Expected '=>'.");

        const case_jump: usize = self.emitJump(.jump_if_false);

        // Pop case expression and switch input expression from stack
        self.emitOp1(.pop_n, 2);

        self.expression();
        self.addJump(exit_jumps);
        self.patchJump(case_jump);
        self.emitOp(.pop);
    }

    p.consume(.brace_right, "Expected '}' after switch block.");

    // If we didn't find a wildcard case then we need to pop switch input expression
    // from the stack and return nil from the switch expression
    if (!wildcard_found) self.emitOps(.pop, .nil);

    self.patchJumpList(exit_jumps);
}

/// Compile a function expression from source tokens.
pub fn funExpr(self: *Compiler, _: bool) void {
    self.compileFun(.function, true);
}

/// Compile a function call expression from source tokens.
pub fn call(self: *Compiler, _: bool) void {
    const arg_count: u8 = self.argumentList();
    self.emitOp1(.call, arg_count);
}

/// Compile a series of argument expressions for a function call, returning the
/// number of compiled arguments.
///
/// The result of these expressions will be on the stack at runtime and captured
/// in the called function's callframe stack window.
fn argumentList(self: *Compiler) u8 {
    const p: *Parser = self.parser;

    var count: u8 = 0;

    if (p.next.isNot(.paren_right)) {
        while (true) : (if (p.listEnd(.paren_right)) break) {
            self.expression();

            defer count += 1;
            if (count == 255) p.err(
                "A function call may only have up to 255 arguments.",
            );
        }
    }

    p.consume(.paren_right, "Expected ')' after arguments.");

    return count;
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
    var i: u8 = self.local_count;
    while (i > 0) : (i -= 1) {
        const local: Local = self.locals[i - 1];

        if (local.depth != -1 and local.depth < self.scope_depth) break;
        if (identifier.equals(local.identifier)) self.err(
            "A variable with this name already exists in this scope.",
        );
    }

    if (self.local_count == cmn.U8_SIZE) return self.err(
        "Too many local variables in function.",
    );

    // Add declared local to locals array
    self.local_count += 1;
    self.locals[self.local_count - 1] = Local{
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
/// Returns `null` if it does not exist.
///
/// Because of the way the stack behaves with statements popping their stack values
/// when complete, the only values on the stack when a local is declared are the
/// values of other locals in scope. This means the offset of the local in the
/// locals array directly reflects its location in the stack.
fn resolveLocal(self: *const Compiler, identifier: Token) ?u8 {
    var i: u8 = self.local_count;
    while (i > 0) : (i -= 1) {
        const local_index: u8 = i - 1;
        const local: Local = self.locals[local_index];

        if (identifier.equals(local.identifier)) {
            if (local.depth == -1) self.err(
                "Can't read local variable in its own initializer.",
            );

            return local_index;
        }
    }

    return null;
}

/// Define a variable.
///
/// If we are in a local scope, the current local will be marked as defined. The
/// value lives on the stack and is modified on the stack when the variable is
/// modified so we don't need to do anything more for it.
///
/// If we're in the global scope, emit bytecode to define the global variable,
/// passing the offset of the global variable's constant identifier string as
/// the operand.
fn defineVariable(self: *Compiler, ident_const_offset: u8) void {
    if (self.scope_depth > 0) return self.markDefined();
    self.emitOp1(.global_define, ident_const_offset);
}

/// Resolve an upvalue with the given [identifier].
///
/// Returns `null` if no upvalue with the given `identifier` was found.
fn resolveUpvalue(self: *Compiler, identifier: Token) ?u8 {
    // If we have an enclosing scope, try to resolve upvalue from its locals/upvalues
    if (self.enclosing) |enclosing| {
        if (enclosing.resolveLocal(identifier)) |offset| {
            // Mark local in enclosing scope as captured
            enclosing.locals[offset].is_captured = true;
            return self.addUpvalue(offset, true);
        }

        if (enclosing.resolveUpvalue(identifier)) |offset| {
            return self.addUpvalue(offset, false);
        }
    }

    // No upvalue found, must be a global
    return null;
}

/// Add an upvalue to the compiled upvalues in this compilation scope.
///
/// Returns the offset for locating the upvalue at runtime.
///
/// If an upvalue with the given offset/locality already exists, its offset will
/// be returned.
fn addUpvalue(self: *Compiler, offset: u8, is_local: bool) u8 {
    const upvalue_count: u8 = self.function.?.upvalue_count;

    // Check for existing compiled upvalue matching the given offset/locality
    var i: u8 = 0;
    while (i < upvalue_count) : (i += 1) {
        const upvalue: Upvalue = self.upvalues[i];
        if (upvalue.offset == offset and upvalue.is_local == is_local) {
            return i;
        }
    }

    if (upvalue_count == cmn.U8_SIZE) {
        self.err("Too many closure variables in function.");
        return 0;
    }

    // Add upvalue to this compiler's tracked upvalues
    self.upvalues[upvalue_count] = Upvalue{
        .offset = offset,
        .is_local = is_local,
    };

    self.function.?.upvalue_count += 1;
    return upvalue_count;
}

// Chunk-writing methods ======================================================

/// Add the given `value` to the constants in the chunk being compiled.
///
/// Returns the offset of the added constant.
fn makeConstant(self: *const Compiler, value: Value) u8 {
    // Check for existing constant matching this value and return its offset if
    // it already exists.
    if (self.chunk().findConstant(value)) |offset| return offset;

    const offset: u8 = self.chunk().addConstant(value);

    if (offset > cmn.U8_MAX) {
        self.err("Too many constants in one chunk.");
        return 0;
    }

    return offset;
}

/// Push an identifier's string to the current chunk's constants array, returning
/// the offset of the added constant string.
fn makeIdentConstant(self: *const Compiler, token: Token) u8 {
    const ident: *Obj.String = self.copyString(token.lexeme) catch {
        self.err("Error copying identifier string.");
        return 0;
    };

    return self.makeConstant(.Object(ident.toObj()));
}

/// Write the given `byte` to the chunk currently being compiled.
fn emitByte(self: *const Compiler, byte: u8) void {
    self.chunk().writeByte(byte, self.parser.current.line);
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

/// Write `OpCode.constant` to the chunk currently being compiled, followed by
/// the constants array offset of the given `value`.
fn emitConstant(self: *const Compiler, value: Value) void {
    self.emitOp1(.constant, self.makeConstant(value));
}

/// Write default return instructions to the chunk currently being compiled.
fn emitDefaultReturn(self: *const Compiler) void {
    self.emitOps(.nil, .@"return");
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

/// Emit a `.jump` op beginning at the current instruction offset, adding it to
/// the given `jump_list` to be resolved later via `patchJumpList()`.
fn addJump(self: *const Compiler, jump_list: *JumpList) void {
    jump_list.addJump(self.emitJump(.jump)) catch self.allocErr();
}

/// Write `OpCode.loop` to the chunk currently being compiled, followed by loop
/// offset operands to loop back to the given instruction `offset`.
fn emitLoop(self: *const Compiler, offset: usize) void {
    const loop_offset: usize = self.instructionOffset() - offset + 3;
    const byte_1: u8, const byte_2: u8 = splitBytes(loop_offset);
    self.emitOp2(.loop, byte_1, byte_2);

    if (loop_offset > cmn.U16_MAX) self.err("Loop body is too large.");
}

/// Patch a 2-byte placeholder operand beginning at the given instruction `offset`,
/// replacing it with the given `bytes`.
///
/// `bytes` can be an unsigned integer of any size for callsite convenience, but
/// it will be truncated to its 16 least-significant bits before being split into
/// two separate bytes to patch the placeholder bytes.
fn patchBytes(self: *const Compiler, offset: usize, bytes: usize) void {
    if (bytes > cmn.U16_MAX) return self.err("Jump offset is too large.");

    const byte_1: u8, const byte_2: u8 = splitBytes(bytes);
    self.chunk().ipAt(offset).* = byte_1;
    self.chunk().ipAt(offset + 1).* = byte_2;
}

/// Patches the jump instruction operand at the given instruction `offset` to point
/// to the current instruction offset.
fn patchJump(self: *const Compiler, offset: usize) void {
    self.patchBytes(offset, self.instructionOffset() - offset - 2);
}

/// Patch all jumps in the given `jump_list` to the current instruction offset.
fn patchJumpList(self: *const Compiler, jump_list: *JumpList) void {
    var next: ?*Jump = jump_list.head;
    while (next) |it| : (next = it.next) self.patchJump(it.offset);
}

/// Patch all unresolved break statements within the current loop scope.
///
/// The jump instruction placeholders for break statements tracked by the current
/// loop scope will be patched to point to the current instruction offset.
fn patchBreaks(self: *const Compiler) void {
    if (self.loop_scope) |loop_scope| {
        var next: ?*Jump = loop_scope.breaks;
        while (next) |it| : (next = it.next) self.patchJump(it.offset);
    }
}

/// Patch all unresolved continue statements within the current loop scope.
///
/// The loop instruction placeholders for all continue statements tracked by the
/// current loop scope will be patched to point to the given `loop_start` instruction
/// offset.
fn patchContinues(self: *const Compiler, loop_start: usize) void {
    if (self.loop_scope) |loop_scope| {
        var next: ?*Jump = loop_scope.continues;
        while (next) |it| : (next = it.next) self.patchBytes(
            it.offset,
            it.offset - loop_start + 2,
        );
    }
}

// Object creation methods ====================================================

/// Allocate a new `Obj` of the given `type` with the given `variant` payload.
///
/// Returns a pointer to the allocated `Obj`. The caller owns the returned pointer
/// and is responsible for freeing it.
fn createObj(
    self: *const Compiler,
    comptime T: Obj.Type,
    variant: Obj.Variant(T),
) !*Obj.Variant(T) {
    const object: *Obj.Variant(T) = try Obj.createConstant(T, variant);

    // Pre-hash and intern string objects
    if (T == .string) {
        const hash: u32 = Fnv1a_32.hash(variant.chars);
        const interned: ?*Obj.String = self.strings.findString(variant.chars, hash);

        // Return interned string if it exists
        if (interned) |str| {
            object.destroy();
            return str;
        }

        object.hash = hash;
        _ = self.strings.set(object, .Nil);
    }

    return object;
}

/// Allocate a copy of the given `string` slice on the heap, wrapping it in a newly
/// allocated lox string `Obj`.
///
/// Returns a pointer to the allocated lox string `Obj`. The caller owns the returned
/// pointer and is responsible for freeing it.
fn copyString(self: *const Compiler, chars: []const u8) !*Obj.String {
    return self.createObj(
        .string,
        Obj.String{ .chars = try mem.allocator().dupe(u8, chars) },
    );
}

// Error reporting convenience methods ========================================

/// Report an error at the current token.
///
/// Shortcut for `self.parser.err(...)`
fn err(self: *const Compiler, msg: []const u8) void {
    self.parser.err(msg);
}

/// Report an error at the current token indicating memory allocation critical to
/// the compilation process failed while compiling.
fn allocErr(self: *const Compiler) void {
    self.err("Error allocating during compilation. Out of memory?");
}
