const std = @import("std");
const zlox = @import("../../.lib.zig");

const Type = zlox.object.Obj.Type;

const Function = zlox.object.Obj.Function;
const String = zlox.object.Obj.String;

const comptimePrint = std.fmt.comptimePrint;

/// `Obj` variant payload type for the given object `type`.
pub fn Variant(comptime @"type": Type) type {
    const obj_type: type = switch (@"type") {
        .function => Function,
        .string => String,
    };

    // Ensure Obj children have `obj` header field.
    if (!@hasField(obj_type, "obj")) @compileError(
        comptimePrint(
            "Obj child struct '{}' missing 'obj: Obj' header field.",
            .{obj_type},
        ),
    );

    // Ensure Obj children have `destroy` function declaration
    if (!@hasDecl(obj_type, "destroy")) @compileError(
        comptimePrint(
            "Obj child struct '{}' missing 'destroy' function declaration.",
            .{obj_type},
        ),
    );

    // Ensure Obj children have `format` function declaration
    if (!@hasDecl(obj_type, "format")) @compileError(
        comptimePrint(
            "Obj child struct '{}' missing 'format' function declaration.",
            .{obj_type},
        ),
    );

    return obj_type;
}
