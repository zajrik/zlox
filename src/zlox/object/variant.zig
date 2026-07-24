const std = @import("std");
const zlox = @import("../.lib.zig");

const Type = zlox.object.Obj.Type;

const String = zlox.object.Obj.String;
const Function = zlox.object.Obj.Function;
const Closure = zlox.object.Obj.Closure;
const Native = zlox.object.Obj.Native;
const Upvalue = zlox.object.Obj.Upvalue;
const Class = zlox.object.Obj.Class;
const Instance = zlox.object.Obj.Instance;
const Method = zlox.object.Obj.Method;

const comptimePrint = std.fmt.comptimePrint;

/// `Obj` variant payload type for the given object `type`.
pub fn Variant(comptime T: Type) type {
    const obj_type: type = switch (T) {
        .string => String,
        .function => Function,
        .closure => Closure,
        .native => Native,
        .upvalue => Upvalue,
        .class => Class,
        .instance => Instance,
        .method => Method,
    };

    // Enforce obj fields
    if (!@hasField(obj_type, "obj")) @compileError(comptimePrint(
        "Obj variant struct '{}' missing 'obj: Obj' header field.",
        .{obj_type},
    ));

    // Enforce obj functions
    if (!@hasDecl(obj_type, "destroy")) @compileError(comptimePrint(
        "Obj variant struct '{}' missing 'destroy' function declaration.",
        .{obj_type},
    ));
    if (!@hasDecl(obj_type, "toObj")) @compileError(comptimePrint(
        "Obj variant struct '{}' missing 'toObj' function declaration.",
        .{obj_type},
    ));
    if (!@hasDecl(obj_type, "toValue")) @compileError(comptimePrint(
        "Obj variant struct '{}' missing 'toValue' function declaration.",
        .{obj_type},
    ));
    if (!@hasDecl(obj_type, "format")) @compileError(comptimePrint(
        "Obj variant struct '{}' missing 'format' function declaration.",
        .{obj_type},
    ));

    return obj_type;
}
