const std = @import("std");
const Allocator = std.mem.Allocator;

const server_impl = @import("server.zig");

pub const Request = @import("http/Request.zig");
pub const Response = @import("http/Response.zig");

pub const Client = server_impl.Client;
pub const Server = server_impl.Server;

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

        pub fn init(allocator: Allocator, address: std.net.Address, context: ServerContext, handler_fn: *const HandlerFn(ServerContext)) !Self {
            return Self{
                .server = try Server.init(allocator, address),
                .handler_fn = handler_fn,
                .context = context,
            };
        }

        pub fn run(tortie: *Self) !void {
            var ready_clients: [16]*Client = undefined;
            const client_count = tortie.server.getCompletions(&ready_clients) catch |err| switch (err) {
                error.WouldBlock => return,
                else => return err,
            };

            for (ready_clients[0..client_count]) |client| {
                switch (client.state) {
                    .accepting => {
                        client.start_ts = std.time.microTimestamp();
                        client.request_buffer.items.len = 0;
                        tortie.server.recv(client) catch |err| {
                            log.err("Encountered error during recv(): {}", .{err});
                            tortie.server.deinitClient(client);
                        };
                    },
                    .reading => {
                        tortie.server.recv(client) catch |err| {
                            log.err("Encountered error during recv: {}", .{err});
                            tortie.server.deinitClient(client);
                        };
                    },
                    .read_complete => {
                        std.debug.print("Handling request using client {}\n", .{client.id});
                        client.response = Response.writer(client.response_buffer.writer());

                        client.request = Request{
                            .data = client.request_buffer.items,
                        };

                        if (client.request.findHeader("Connection")) |conn| {
                            client.keep_alive = !std.mem.eql(u8, conn, "close");
                        }

                        tortie.handler_fn(client, tortie.context) catch |err| {
                            log.err("Error processing client request: {}", .{err});
                            tortie.server.deinitClient(client);
                            continue;
                        };

                        client.response.complete() catch {};

                        tortie.server.send(client) catch |err| {
                            std.log.err("Encountered error during send(): {}", .{err});
                            tortie.server.deinitClient(client);
                        };
                    },
                    .writing => {
                        if (!client.keep_alive) {
                            tortie.server.deinitClient(client);
                        }
                    },
                    .disconnecting => {
                        tortie.server.acceptClient(client) catch |err| {
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
