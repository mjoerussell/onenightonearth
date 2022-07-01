const std = @import("std");
const build = std.build;
const Pkg = build.Pkg;

pub fn buildPkg(exe: *build.LibExeObjStep, package_name: []const u8, package_path: []const u8) void {
    exe.addPackage(Pkg{
        .name = package_name,
        .source = build.FileSource.relative(package_path),
    });
}