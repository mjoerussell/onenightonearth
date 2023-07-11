const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;

const tortie = @import("tortie");
const TortieServer = tortie.TortieServer;
// const FileSource = tortie.FileSource;
// const FilePath = FileSource.FilePath;
const http = tortie.http;

// const allowed_paths = [_]FilePath{
//     FilePath.relative("../web", "index.html"),
//     FilePath.relative("../web", "dist/bundle.js"),
//     FilePath.relative("../web", "styles/main.css"),
//     FilePath.relative("../web", "assets/favicon.ico"),
//     FilePath.relative("../web/dist/wasm", "night-math.wasm"),
//     FilePath.absolute("star_data.bin"),
//     FilePath.absolute("const_data.bin"),
//     FilePath.absolute("const_meta.json"),
// };

pub const log_level = switch (builtin.mode) {
    .Debug => .debug,
    else => .info,
};

const ServerContext = struct {};

pub fn main() anyerror!void {
    const port = 8080;
    var localhost = try std.net.Address.parseIp("0.0.0.0", port);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var context = ServerContext{};
    var server = try TortieServer(ServerContext).init(allocator, localhost, context, handleRequest);
    // try server.init(allocator, localhost);
    // defer server.deinit(allocator);

    // var file_source = try FileSource.init(allocator, &allowed_paths, .{});
    // defer file_source.deinit();

    // server.file_source = file_source;

    // try server.addRoute("/", handleIndex);
    // try server.addRoute("/stars", handleStars);
    // try server.addRoute("/constellations", handleConstellations);
    // try server.addRoute("/constellations/meta", handleConstellationMetadata);

    std.log.info("Listening on port {}", .{port});
    std.log.debug("Build is single threaded: {}", .{builtin.single_threaded});

    while (true) {
        server.run() catch {};
    }
}

fn handleRequest(client: *tortie.Client, context: ServerContext) !void {
    _ = context;
    const request_path = client.request.getPath() catch blk: {
        std.log.warn("Could not parse path, defaulting to /", .{});
        break :blk "/";
    };

    if (std.mem.eql(u8, request_path, "/")) {
        try handleIndex(client);
    }
}

/// Handle the main index.html page. This is used instead of a FileSource file so that users can navigate to
/// onenightonearth.com instead of onenightonearth.com/index.html
// fn handleIndex(allocator: Allocator, request: http.Request, response_writer: *anyopaque) !void {
fn handleIndex(client: *tortie.Client) !void {
    // _ = request;

    // var index_data = try file_source.?.getFile("index.html");
    const cwd = std.fs.cwd();
    var index_file = try cwd.openFile("../web/index.html", .{});
    defer index_file.close();

    const stat = try index_file.stat();
    // var index_data = try index_file.readToEndAlloc(allocator, std.math.maxInt(u32));

    // var response = try http.Response.init(allocator);
    // response.status = .ok;
    try client.response.writeStatus(.ok);
    try client.response.writeHeader("Content-Type", "text/html");
    try client.response.writeHeader("Content-Length", stat.size);

    var buffer: [512]u8 = undefined;
    while (true) {
        const bytes_read = index_file.read(&buffer) catch |err| {
            std.log.warn("Error reading index.html: {}", .{err});
            break;
        };

        try client.response.writeBody(buffer[0..bytes_read]);
        if (bytes_read < buffer.len) break;
    }

    // try response.addHeader("Content-Type", "text/html");
    // try response.addHeader("Content-Length", index_data.len);

    // if (builtin.mode != .Debug) {
    //     try response.addHeader("Cache-Control", "max-age=3600");
    // }

    // if (file_source.?.config.should_compress) {
    //     try response.addHeader("Content-Encoding", "deflate");
    // }
    // response.body = index_data;
    // try response_writer.body(index_data);

    // return response;
}

// /// Handle the /stars endpoint. Returns the star data buffer as an octet-stream.
// fn handleStars(allocator: Allocator, file_source: ?FileSource, request: http.Request) !http.Response {
// fn handleStars(allocator: Allocator, file_source: ?FileSource, request: http.Request, response_writer: anytype) !void {
//     _ = request;
//     var star_data = try file_source.?.getFile("star_data.bin");

//     var response = try http.Response.init(allocator);
//     response.status = .ok;
//     try response.addHeader("Content-Type", "application/octet-stream");
//     try response.addHeader("Content-Length", star_data.len);

//     if (builtin.mode != .Debug) {
//         try response.addHeader("Cache-Control", "max-age=3600");
//     }

//     if (file_source.?.config.should_compress) {
//         try response.addHeader("Content-Encoding", "deflate");
//     }
//     response.body = star_data;

//     return response;
// }

// /// Handle the /constellations endpoint. Returns the constellation data buffer as an octet-stream.
// fn handleConstellations(allocator: Allocator, file_source: ?FileSource, request: http.Request) !http.Response {
//     _ = request;
//     var const_data = try file_source.?.getFile("const_data.bin");

//     var response = try http.Response.init(allocator);
//     try response.addHeader("Content-Type", "application/octet-stream");
//     try response.addHeader("Content-Length", const_data.len);

//     if (builtin.mode != .Debug) {
//         try response.addHeader("Cache-Control", "max-age=3600");
//     }

//     if (file_source.?.config.should_compress) {
//         try response.addHeader("Content-Encoding", "deflate");
//     }
//     response.body = const_data;
//     return response;
// }

// /// Handle the /constellations/meta endpoint. Returns the constellation metadata as a JSON-encoded value.
// fn handleConstellationMetadata(allocator: Allocator, file_source: ?FileSource, request: http.Request) !http.Response {
//     _ = request;
//     var const_meta_data = try file_source.?.getFile("const_meta.json");

//     var response = try http.Response.init(allocator);
//     response.status = .ok;
//     try response.addHeader("Content-Type", "application/json");
//     try response.addHeader("Content-Length", const_meta_data.len);

//     if (builtin.mode != .Debug) {
//         try response.addHeader("Cache-Control", "max-age=3600");
//     }

//     if (file_source.?.config.should_compress) {
//         try response.addHeader("Content-Encoding", "deflate");
//     }
//     response.body = const_meta_data;

//     return response;
// }
