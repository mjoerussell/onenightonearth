const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const os = std.os;
const net = std.net;
const Timer = std.time.Timer;

const http = @import("http");

const OneNightClient = @This();

const CommonClient = @import("client.zig").Client;
const NetworkLoop = @import("client.zig").NetworkLoop;
const FileSource = @import("FileSource.zig");

const Connection = switch (builtin.os.tag) {
    .windows, .linux => std.os.socket_t,
    else => net.StreamServer.Connection,
};

// Used to map a URI to a handler function.
const RequestHandler = fn (Allocator, http.Request) anyerror!http.Response;
const route_handlers = std.ComptimeStringMap(RequestHandler, .{
    .{ "/", handleIndex },
    .{ "/stars", handleStars },
    .{ "/constellations", handleConstellations },
    .{ "/constellations/meta", handleConstellationMetadata },
});

const star_data = @embedFile("../star_data.bin");
const const_data = @embedFile("../const_data.bin");

common_client: CommonClient,
handle_frame: *@Frame(OneNightClient.handle) = undefined,
arena: std.heap.ArenaAllocator,
connected: bool = false,

pub fn init(allocator: Allocator, loop: *NetworkLoop, conn: Connection) !*OneNightClient {
    var client = try allocator.create(OneNightClient);

    const common_client = switch (builtin.os.tag) {
        .windows, .linux => try CommonClient.init(loop, conn),
        else => CommonClient.init(conn),
    };

    if (builtin.os.tag != .windows and builtin.os.tag != .linux) _ = loop;

    client.common_client = common_client;
    client.arena = std.heap.ArenaAllocator.init(allocator);
    client.connected = true;

    client.handle_frame = try allocator.create(@Frame(OneNightClient.handle));

    return client;
}

pub fn close(client: *OneNightClient) void {
    switch (builtin.os.tag) {
        .windows, .linux => client.common_client.deinit(),
        else => client.common_client.conn.stream.close(),
    }
    client.arena.deinit();
    @atomicStore(bool, &client.connected, false, .SeqCst);
}

pub fn run(client: *OneNightClient, file_source: FileSource) void {
    client.handle_frame.* = async client.handle(file_source);
}

fn handle(client: *OneNightClient, file_source: FileSource) !void {   
    // Each client will only handle 1 request/response (http1.1), so after handling is complete we'll close the connection
    defer client.close();

    var timer = Timer.start() catch unreachable;

    const start_ts = timer.read();

    const allocator = client.arena.allocator();
    
    // Don't need to explictly deinit because we'll be deiniting the arena allocator once this function completes
    var request_writer = std.ArrayList(u8).init(allocator);
    
    var reader = client.common_client.reader();
    var writer = client.common_client.writer();

    // Read incoming data into a temp buffer and then copy it into an arraylist-backed buffer
    var request_buffer: [std.mem.page_size]u8 = undefined;
    var bytes_read: usize = try reader.read(request_buffer[0..]);
    while (bytes_read > 0) {
        try request_writer.writer().writeAll(request_buffer[0..bytes_read]);

        if (bytes_read < request_buffer.len) break;

        bytes_read = try reader.read(request_buffer[0..]);
    }

    // Get a request instance for the recieved data
    var request = http.Request{ .data = request_writer.items };
    defer {
        const end_ts = timer.read();
        const uri = request.uri() orelse "/";
        std.log.info("Thread {}: Handling request for {s} took {d:.6}ms", .{std.Thread.getCurrentId(), uri, (@intToFloat(f64, end_ts) - @intToFloat(f64, start_ts)) / std.time.ns_per_ms});
    }

    const uri = request.uri() orelse {
        var response = http.Response.initStatus(allocator, .bad_request);
        try response.write(writer);
        return;
    };

    // If the request uri has a registered handler, then use it to processs the request and generate the response
    if (route_handlers.get(uri)) |handler| {
        // Get the response from the handler. If an error occurs, then get a 500 reponse
        var response = handler(allocator, request) catch |err| blk: {
            std.log.err("Error handling request at {s}: {}", .{uri, err});
            break :blk http.Response.initStatus(allocator, .internal_server_error);
        };
        // Send the response
        try response.write(writer);
    } else {
        // If this doesn't match an 'api' (as defined in route_handlers) then we'll assume that the user is trying to fetch a file
        // We'll use file_source to try to read the file. If there's an error, then we'll handle it appropriately.
        const file_data = file_source.getFile(allocator, uri) catch |err| switch (err) {
            error.FileNotFound => {
                // The file either a) doesn't exist or b) is not one of the files registered in FileSource to be readable
                std.log.warn("Client tried to get file {s}, but it could not be found", .{uri});
                var response = http.Response.initStatus(allocator, .not_found);
                try response.write(writer);
                return;
            },
            else => {
                // Some unknown error occurred, just send 500 back
                std.log.err("Error when trying to get file {s}: {}", .{uri, err});
                var response = http.Response.initStatus(allocator, .internal_server_error);
                try response.write(writer);
                return;
            }
        };

        // Start building the file response
        const content_type = getContentType(uri).?;
        
        var response = http.Response.init(allocator);    
        try response.header("Content-Length", file_data.len);
        try response.header("Content-Type", content_type);
        response.body = file_data;

        // Send the response
        try response.write(writer);
    }
}

/// Gets the content-type of a file using the file extension. Only supports css, html, js, wasm, and ico files currently
fn getContentType(filename: []const u8) ?[]const u8 {
    if (std.mem.endsWith(u8, filename, ".css")) {
        return "text/css";
    }

    if (std.mem.endsWith(u8, filename, ".html")) {
        return "text/html";
    }

    if (std.mem.endsWith(u8, filename, ".js")) {
        return "application/javascript";
    }

    if (std.mem.endsWith(u8, filename, ".wasm")) {
        return "application/wasm";
    }

    if (std.mem.endsWith(u8, filename, ".ico")) {
        return "image/x-icon";
    }

    return null;
}

/// Handle the main index.html page. This is used instead of a FileSource file so that users can navigate to 
/// onenightonearth.com instead of onenightonearth.com/index.html
fn handleIndex(allocator: Allocator, request: http.Request) !http.Response {
    _ = request;
    const cwd = std.fs.cwd();
    std.log.info("Reading index.html", .{});
    var index_file = try cwd.openFile("../web/index.html", .{});
    defer index_file.close(); 

    
    const index_data = try index_file.readToEndAlloc(allocator, std.math.maxInt(usize));
    
    var response = http.Response.init(allocator);
    response.status = .ok;
    try response.header("Content-Type", "text/html");
    try response.header("Content-Length", index_data.len);
    response.body = index_data;

    return response;
}

/// Handle the /stars endpoint. Returns the star data buffer as an octet-stream.
fn handleStars(allocator: Allocator, request: http.Request) !http.Response {
    _ = request;
    var response = http.Response.init(allocator);
    response.status = .ok;
    try response.header("Content-Type", "application/octet-stream");
    try response.header("Content-Length", star_data.len);
    try response.header("Content-Encoding", "deflate");
    response.body = star_data;

    return response;
}

/// Handle the /constellations endpoint. Returns the constellation data buffer as an octet-stream.
fn handleConstellations(allocator: Allocator, request: http.Request) !http.Response {
    _ = request;
    var response = http.Response.init(allocator);
    try response.header("Content-Type", "application/octet-stream");
    try response.header("Content-Length", const_data.len);
    try response.header("Content-Encoding", "deflate");
    response.body = const_data;
    return response;
}

/// Handle the /constellations/meta endpoint. Returns the constellation metadata as a JSON-encoded value.
fn handleConstellationMetadata(allocator: Allocator, request: http.Request) !http.Response {
    _ = request;
    const cwd = std.fs.cwd();
    var index_file = try cwd.openFile("const_meta.json", .{});
    defer index_file.close();

    const index_data = try index_file.readToEndAlloc(allocator, std.math.maxInt(usize));
    
    var response = http.Response.init(allocator);
    response.status = .ok;
    try response.header("Content-Type", "application/json");
    try response.header("Content-Length", index_data.len);
    try response.header("Content-Encoding", "deflate");
    response.body = index_data;

    return response;
}