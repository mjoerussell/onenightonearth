const std = @import("std");
const TypeInfo = std.builtin.TypeInfo;
const fs = std.fs;

const imports = struct {
    pub const star_math = @import("src/star_math.zig");
    pub const math_utils = @import("src/math_utils.zig");
    pub const wasm_interface = @import("src/wasm_interface.zig");
    pub const star_renderer = @import("src/StarRenderer.zig");
    pub const canvas = @import("src/Canvas.zig");
    pub const star = @import("src/Star.zig");
    pub const constellation = @import("src/Constellation.zig");
    pub const sky_coord = @import("src/SkyCoord.zig");
};

fn writeTypescriptPrimative(comptime T: type, writer: anytype) !void {
    switch (@typeInfo(T)) {
        .int, .float, .bool => {
            try writer.writeAll("WasmPrimative." ++ @typeName(T));
        },
        .@"enum" => |enum_info| {
            try writeTypescriptPrimative(enum_info.tag_type, writer);
        },
        else => @compileError("Cannot write Typescript primative for type " ++ @typeName(T)),
    }
}

fn writeTypescriptTypeName(comptime T: type, writer: anytype) !void {
    switch (@typeInfo(T)) {
        .int => |info| {
            if (info.bits >= 64) {
                try writer.writeAll("BigInt");
            } else {
                try writer.writeAll("number");
            }
        },
        .float => try writer.writeAll("number"),
        .pointer => |info| switch (info.size) {
            .one, .many, .c => try writer.writeAll("pointer"),
            else => @compileError("Slices are not valid as arguments in an exported function"),
        },
        .optional => |info| {
            try writeTypescriptTypeName(info.child, writer);
            if (@typeInfo(info.child) != .Pointer) {
                try writer.writeAll(" | null");
            }
        },
        .void => try writer.writeAll("void"),
        .@"enum" => try writer.writeAll("number"),
        else => @compileError("Cannot generate Typescript type for Zig type " ++ @typeName(T)),
    }
}

pub fn main() !void {
    const cwd = fs.cwd();

    cwd.makePath("../web/src/wasm") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    var out_file = try cwd.createFile("../web/src/wasm/wasm_module.ts", .{});
    defer out_file.close();

    var buffered_writer = std.io.bufferedWriter(out_file.writer());
    defer buffered_writer.flush() catch {};

    var writer = buffered_writer.writer();

    try writer.writeAll(
        \\// This file was auto-generated by night-math/generate_interface.zig
        \\export type pointer = number;
        \\export enum WasmPrimative {
        \\    bool,
        \\    u8,
        \\    u16,
        \\    u32,
        \\    u64,
        \\    i8,
        \\    i16,
        \\    i32,
        \\    i64,  
        \\    f16,
        \\    f32,
        \\    f64,
        \\}
        \\
        \\export type Sized<T> = {
        \\    [K in keyof T]: WasmPrimative;
        \\};
        \\
        \\/**
        \\* Get the number of bytes needed to store a given `WasmPrimative`.
        \\* @param data The primative type being checked.
        \\*/
        \\export const sizeOfPrimative = (data: WasmPrimative): number => {
        \\    switch (data) {
        \\        case WasmPrimative.bool:
        \\        case WasmPrimative.u8:
        \\        case WasmPrimative.i8:
        \\            return 1;
        \\        case WasmPrimative.u16:
        \\        case WasmPrimative.i16:
        \\        case WasmPrimative.f16:
        \\            return 2;
        \\        case WasmPrimative.u32:
        \\        case WasmPrimative.i32:
        \\        case WasmPrimative.f32:
        \\            return 4;
        \\        case WasmPrimative.u64:
        \\        case WasmPrimative.i64:
        \\        case WasmPrimative.f64:
        \\            return 8;
        \\        default:
        \\            return data;
        \\    }
        \\};
        \\
        \\/**
        \\* Get the total size required of an arbitrary `Allocatable` data type.
        \\* @param type A `Sized` instance of some data type.
        \\*/
        \\export const sizeOf = <T>(type: Sized<T>): number => {
        \\    let size = 0;
        \\    for (const key in type) {
        \\        if (type.hasOwnProperty(key)) {
        \\            size += sizeOfPrimative(type[key] as WasmPrimative);
        \\        }
        \\    }
        \\    return size;
        \\};
        \\
        \\
    );

    // Write out all of the public packed or extern structs in standard interface format, and write out their
    // Sized<T> instances. This will allow them to be easily allocated and used from Typescript code.
    inline for (@typeInfo(imports).@"struct".decls) |import_decl| {
        const ImportDecl = @field(imports, import_decl.name);
        inline for (@typeInfo(ImportDecl).@"struct".decls) |decl| {
            const Decl = @field(ImportDecl, decl.name);
            switch (@typeInfo(@TypeOf(Decl))) {
                .type => switch (@typeInfo(Decl)) {
                    .@"struct" => |struct_info| {
                        if (struct_info.layout == .@"extern" or struct_info.layout == .@"packed") {
                            try writer.print("export type {s} = {{\n", .{decl.name});
                            inline for (struct_info.fields) |field| {
                                try writer.print("\t{s}: ", .{field.name});
                                try writeTypescriptTypeName(field.type, writer);
                                try writer.writeAll(";\n");
                            }
                            try writer.writeAll("};\n\n");
                            try writer.print("export const sized{s}: Sized<{s}> = {{\n", .{ decl.name, decl.name });
                            inline for (struct_info.fields) |field| {
                                try writer.print("\t{s}: ", .{field.name});
                                try writeTypescriptPrimative(field.type, writer);
                                try writer.writeAll(",\n");
                            }
                            try writer.writeAll("};\n\n");
                        }
                    },
                    else => {},
                },
                else => {},
            }
        }
    }

    // Write out all of the exported functions inside the WasmModule interface. The WasmModule interface
    // can then be used in Typescript by casting WebAssembly.Interface.exports to it.
    try writer.writeAll("export interface WasmModule {\n");
    try writer.writeAll("\tmemory: WebAssembly.Memory;\n");
    inline for (@typeInfo(imports).@"struct".decls) |import_decl| {
        const ImportDecl = @field(imports, import_decl.name);
        inline for (@typeInfo(ImportDecl).@"struct".decls) |decl| {
            const Decl = @field(ImportDecl, decl.name);
            switch (@typeInfo(@TypeOf(Decl))) {
                .@"fn" => |func_info| {
                    // hack to get around missing support for func.is_export
                    if (func_info.calling_convention == .c) {
                        // const func_info = @typeInfo(func.fn_type).Fn;
                        try writer.print("\t{s}: (", .{decl.name});
                        if (func_info.params.len > 0) {
                            inline for (func_info.params, 0..) |fn_arg, arg_index| {
                                if (fn_arg.type) |arg_type| {
                                    try writer.print("arg_{}: ", .{arg_index});
                                    try writeTypescriptTypeName(arg_type, writer);
                                    if (arg_index < func_info.params.len - 1) {
                                        try writer.writeAll(", ");
                                    }
                                }
                            }
                        }
                        try writer.writeAll(") => ");
                        try writeTypescriptTypeName(func_info.return_type orelse void, writer);
                        try writer.writeAll(";\n");
                    }
                },
                else => {},
            }
        }
    }
    try writer.writeAll("};\n");
}
