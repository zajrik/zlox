/// Bitfield for extra data flags used by lox `Obj` structs.
pub const Flags = packed struct {
    /// Whether this object is a constant object value. Constant objects are compiled
    /// and owned by the chunk they are compiled into. They should not be freed by
    /// the garbage collector.
    is_constant: bool = false,

    /// Whether this object is alive as marked by the GC in a given GC cycle.
    is_alive: bool = false,
};
