const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const os = std.os;
const net = std.net;
const Timer = std.time.Timer;

const http = @import("http");

const log = std.log.scoped(.tortie_client);

const TortieClient = @This();

const CommonClient = @import("client.zig").Client;
const EventLoop = @import("event_loop.zig").EventLoop;
const FileSource = @import("FileSource.zig");

const Connection = switch (builtin.os.tag) {
    .windows, .linux => std.os.socket_t,
    else => net.StreamServer.Connection,
};

// Used to map a URI to a handler function.
const RequestHandler = fn (Allocator, FileSource, http.Request) anyerror!http.Response;
const route_handlers = std.ComptimeStringMap(RequestHandler, .{
    .{ "/", handleIndex },
    .{ "/stars", handleStars },
    .{ "/constellations", handleConstellations },
    .{ "/constellations/meta", handleConstellationMetadata },
});

common_client: CommonClient,
handle_frame: *@Frame(TortieClient.handle) = undefined,
arena: std.heap.ArenaAllocator,
connected: bool = false,

pub fn init(allocator: Allocator, event_loop: *EventLoop, conn: Connection) !*TortieClient {
    var client = try allocator.create(TortieClient);

    const common_client = switch (builtin.os.tag) {
        .windows, .linux => try CommonClient.init(event_loop, conn),
        else => CommonClient.init(conn),
    };

    if (builtin.os.tag != .windows and builtin.os.tag != .linux) _ = event_loop;

    client.common_client = common_client;
    client.arena = std.heap.ArenaAllocator.init(allocator);
    client.connected = true;

    client.handle_frame = try allocator.create(@Frame(TortieClient.handle));

    return client;
}

pub fn close(client: *TortieClient) void {
    switch (builtin.os.tag) {
        .windows, .linux => client.common_client.deinit(),
        else => client.common_client.conn.stream.close(),
    }
    client.arena.deinit();
    @atomicStore(bool, &client.connected, false, .SeqCst);
}

pub fn run(client: *TortieClient, file_source: FileSource) void {
    client.handle_frame.* = async client.handle(file_source);
}

fn handle(client: *TortieClient, file_source: FileSource) !void {   
    // Each client will only handle 1 request/response (http1.1), so after handling is complete we'll close the connection
    defer client.close();
    errdefer |err| {
        // Something happened and we're bubbling up an error all the way to the handler.
        // We'll log it here for tracking
        log.err("Client terminated with error: {}", .{err});
    }

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
        log.info("Thread {}: Handling request for {s} took {d:.6}ms", .{std.Thread.getCurrentId(), uri, (@intToFloat(f64, end_ts) - @intToFloat(f64, start_ts)) / std.time.ns_per_ms});
    }

    const uri = request.uri() orelse {
        var response = http.Response.initStatus(allocator, .bad_request);
        try response.write(writer);
        return;
    };

    log.debug("Handling request for {s}", .{uri});

    // If the request uri has a registered handler, then use it to processs the request and generate the response
    if (route_handlers.get(uri)) |handler| {
        // Get the response from the handler. If an error occurs, then get a 500 reponse
        var response = handler(allocator, file_source, request) catch |err| blk: {
            log.err("Error handling request at {s}: {}", .{uri, err});
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
                log.warn("Client tried to get file {s}, but it could not be found", .{uri});
                var response = http.Response.initStatus(allocator, .not_found);
                try response.write(writer);
                return;
            },
            else => {
                // Some unknown error occurred, just send 500 back
                log.err("Error when trying to get file {s}: {}", .{uri, err});
                var response = http.Response.initStatus(allocator, .internal_server_error);
                try response.write(writer);
                return;
            }
        };

        // Start building the file response
        // getContentType can't return null here because we know at this point that the file the client is fetching
        // is a know file in FileSource, and all of the known files have valid file extensions for getContentType
        const content_type = getContentType(uri).?;
        
        var response = http.Response.init(allocator);    
        try response.header("Content-Length", file_data.len);
        try response.header("Content-Type", content_type);
        if (builtin.mode != .Debug) {
            try response.header("Cache-Control", "max-age=3600");
        }
        if (file_source.is_compressed) {
            try response.header("Content-Encoding", "deflate");
        }
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
fn handleIndex(allocator: Allocator, file_source: FileSource, request: http.Request) !http.Response {
    _ = request;

    var index_data = try file_source.getFile(allocator, "index.html");

    var response = http.Response.init(allocator);
    response.status = .ok;
    try response.header("Content-Type", "text/html");
    try response.header("Content-Length", index_data.len);

    if (builtin.mode != .Debug) {
        try response.header("Cache-Control", "max-age=3600");
    }

    if (file_source.is_compressed) {
        try response.header("Content-Encoding", "deflate");
    }
    response.body = index_data;

    return response;
}

/// Handle the /stars endpoint. Returns the star data buffer as an octet-stream.
fn handleStars(allocator: Allocator, file_source: FileSource, request: http.Request) !http.Response {
    _ = request;
    var star_data = try file_source.getFile(allocator, "star_data.bin");

    var response = http.Response.init(allocator);
    response.status = .ok;
    try response.header("Content-Type", "application/octet-stream");
    try response.header("Content-Length", star_data.len);

    if (builtin.mode != .Debug) {
        try response.header("Cache-Control", "max-age=3600");
    }

    if (file_source.is_compressed) {
        try response.header("Content-Encoding", "deflate");
    }
    response.body = star_data;

    return response;
}

/// Handle the /constellations endpoint. Returns the constellation data buffer as an octet-stream.
fn handleConstellations(allocator: Allocator, file_source: FileSource, request: http.Request) !http.Response {
    _ = request;
    var const_data = try file_source.getFile(allocator, "const_data.bin");

    var response = http.Response.init(allocator);
    try response.header("Content-Type", "application/octet-stream");
    try response.header("Content-Length", const_data.len);

    if (builtin.mode != .Debug) {
        try response.header("Cache-Control", "max-age=3600");
    }

    if (file_source.is_compressed) {
        try response.header("Content-Encoding", "deflate");
    }
    response.body = const_data;
    return response;
}

/// Handle the /constellations/meta endpoint. Returns the constellation metadata as a JSON-encoded value.
fn handleConstellationMetadata(allocator: Allocator, file_source: FileSource, request: http.Request) !http.Response {
    _ = request;
    var const_meta_data = try file_source.getFile(allocator, "const_meta.json");

    var response = http.Response.init(allocator);
    response.status = .ok;
    try response.header("Content-Type", "application/json");
    try response.header("Content-Length", const_meta_data.len);

    if (builtin.mode != .Debug) {
        try response.header("Cache-Control", "max-age=3600");
    }
 
    if (file_source.is_compressed) {
        try response.header("Content-Encoding", "deflate");
    }
    response.body = const_meta_data;

    return response;
}