//! Linked list node tracking compilation of nested classes.
const ClassContext: type = @This();

/// The next linked class context node, representing the enclosing class context,
/// i.e. the class context *this* class context is nested within.
///
/// The presence of this indicates we are compiling a locally defined class within
/// the method body of an enclosing class.
enclosing: ?*ClassContext = null,

/// Whether the class in context has a superclass.
has_superclass: bool = false,
