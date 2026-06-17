pub const OpCode = enum(u8) {
    op_constant,
    op_return,
    _,

    pub fn byte(self: OpCode) u8 {
        return @intFromEnum(self);
    }
};
