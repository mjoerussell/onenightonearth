const std = @import("std");
const Allocator = std.mem.Allocator;

const server = @import("server.zig");

pub const Request = @import("http/Request.zig");
pub const Response = @import("http/Response.zig");

pub const Client = server.Client;
pub const Server = server.Server;

pub fn HandlerFn(comptime ServerContext: type) type {
    return fn (*Client, ServerContext) anyerror!void;
}

pub fn TortieServer(comptime ServerContext: type) type {
    return struct {
        const Self = @This();
        const log = std.log.scoped(.tortie);

        handler_fn: *const HandlerFn(ServerContext),
        server: Server,
        context: ServerContext,

        pub fn init(address: std.net.Address, context: ServerContext, handler_fn: *const HandlerFn(ServerContext)) !Self {
            return Self{
                .server = try Server.init(address),
                .handler_fn = handler_fn,
                .context = context,
            };
        }

        pub fn run(tortie: *TortieServer) !void {
            var ready_clients: [16]*Client = undefined;
            const client_count = tortie.server.getCompletions(&ready_clients) catch |err| switch (err) {
                error.WouldBlock => return,
                else => return err,
            };

            for (ready_clients[0..client_count]) |client| {
                switch (client.state) {
                    .accepting => {
                        client.start_ts = std.time.microTimestamp();
                        server.recv(client) catch |err| {
                            log.err("Encountered error during recv(): {}", .{err});
                            server.deinitClient(client);
                        };
                    },
                    .reading => {
                        var fbs = std.io.fixedBufferStream(&client.buffer);
                        client.response = Response.writer(fbs.writer());

                        client.request = Request{ .data = client.buffer[0..client.len] };
                        tortie.handle_fn(client, tortie.context) catch |err| {
                            log.err("Error processing client request: {}", .{err});
                            server.deinitClient(client);
                            continue;
                        };

                        client.response.complete() catch {};
                        client.len = fbs.pos;

                        server.send(client) catch |err| {
                            std.log.err("Encountered error during send(): {}", .{err});
                            server.deinitClient(client);
                        };
                    },
                    .writing => {
                        server.deinitClient(client);
                    },
                    .disconnecting => {
                        server.acceptClient(client) catch |err| {
                            log.err("Error accepting new client: {}", .{err});
                        };
                    },
                    .idle => {
                        std.log.err("Got idle client from getCompletion(), which probably shouldn't ever happen. Nothing to do right now...", .{});
                    },
                }
            }
        }
    };
}
