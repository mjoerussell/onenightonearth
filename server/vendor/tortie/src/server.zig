const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const os = std.os;
const net = std.net;
const windows = std.os.windows;
const winsock = @import("winsock.zig");

const Request = @import("http/Request.zig");
const Response = @import("http/Response.zig");

const log = std.log.scoped(.server);

// @todo Better async handling. Right now there's no way to create a sequence of async events on a single client.
//       The read and write parts much each be one-shot operations.

// @todo Mac implementation
pub const Server = switch (builtin.os.tag) {
    .windows => WindowsServer,
    .linux => LinuxServer,
    else => @compileError("Platform not supported"),
};

pub const ClientState = enum {
    idle,
    accepting,
    reading,
    read_complete,
    writing,
    write_complete,
    disconnecting,
};

pub const ClientBuffers = struct {
    const min_capacity: usize = 1024;
    const ResponseWriter = Response.Writer(std.ArrayList(u8).Writer);

    request_buffer: std.ArrayList(u8),
    response_buffer: std.ArrayList(u8),

    pub fn init(allocator: Allocator) !ClientBuffers {
        var request_buffer = try std.ArrayList(u8).initCapacity(allocator, min_capacity);
        errdefer request_buffer.deinit();
        const response_buffer = try std.ArrayList(u8).initCapacity(allocator, min_capacity);

        return ClientBuffers{
            .request_buffer = request_buffer,
            .response_buffer = response_buffer,
        };
    }

    pub fn deinit(buffers: *ClientBuffers) void {
        buffers.request_buffer.deinit();
        buffers.response_buffer.deinit();
    }

    pub fn reset(buffers: *ClientBuffers) void {
        if (buffers.request_buffer.capacity > min_capacity) {
            buffers.request_buffer.shrinkAndFree(min_capacity);
        }
        buffers.request_buffer.items.len = 0;

        if (buffers.response_buffer.capacity > min_capacity) {
            buffers.response_buffer.shrinkAndFree(min_capacity);
        }
        buffers.response_buffer.items.len = 0;
    }

    pub fn request(buffers: *ClientBuffers) Request {
        return Request{ .data = buffers.request_buffer.items };
    }

    pub fn responseWriter(buffers: *ClientBuffers) ResponseWriter {
        return Response.writer(buffers.response_buffer.writer());
    }
};

pub const Client = struct {
    socket: os.socket_t,

    buffers: ClientBuffers,

    start_ts: i64 = 0,
    state: ClientState = .idle,
    id: ?usize = null,
    keep_alive: bool = false,

    fn init(allocator: Allocator) !Client {
        return Client{
            .socket = undefined,
            .buffers = try ClientBuffers.init(allocator),
        };
    }

    fn deinit(client: *Client) void {
        client.buffers.deinit();
    }

    fn reset(client: *Client) void {
        client.state = .idle;
        client.buffers.reset();
    }
};

const WindowsServer = struct {
    const client_count = 256;

    socket: os.socket_t = undefined,
    clients: [client_count]Client = undefined,
    overlapped: []windows.OVERLAPPED = undefined,

    listen_address: net.Address = undefined,
    io_port: os.windows.HANDLE,

    pub fn init(allocator: Allocator, address: net.Address) !WindowsServer {
        var server = WindowsServer{
            .io_port = try windows.CreateIoCompletionPort(windows.INVALID_HANDLE_VALUE, null, undefined, undefined),
            .listen_address = address,
        };

        const socket = try server.getSocket();
        errdefer |err| {
            std.log.err("Error occurred while listening on address {}: {}", .{ address, err });
            os.closeSocket(socket);
        }

        var io_mode: u32 = 1;
        _ = os.windows.ws2_32.ioctlsocket(socket, os.windows.ws2_32.FIONBIO, &io_mode);

        server.socket = socket;
        server.overlapped = try allocator.alloc(windows.OVERLAPPED, client_count);

        errdefer server.deinit(allocator);

        var socklen = address.getOsSockLen();
        try os.bind(socket, &address.any, socklen);
        try os.listen(socket, 128);
        try os.getsockname(socket, &server.listen_address.any, &socklen);

        _ = try os.windows.CreateIoCompletionPort(socket, server.io_port, undefined, 0);

        // Init all clients to a mostly empty, but usable, state
        for (&server.clients, 0..) |*client, index| {
            client.* = try Client.init(allocator);
            client.id = index;
            client.socket = try server.getSocket();
            _ = try windows.CreateIoCompletionPort(client.socket, server.io_port, undefined, 0);
            try server.acceptClient(client);
        }

        return server;
    }

    pub fn deinit(server: *WindowsServer, allocator: Allocator) void {
        allocator.free(server.overlapped);
        for (&server.clients) |*client| client.deinit();
    }

    pub fn acceptClient(server: *WindowsServer, client: *Client) !void {
        server.resetClient(client);
        client.state = .accepting;
        const client_overlapped = server.overlappedFromClient(client) orelse return;

        winsock.acceptEx(server.socket, client.socket, client.buffers.request_buffer.items, &client.buffers.request_buffer.items.len, client_overlapped) catch |err| switch (err) {
            error.IoPending, error.ConnectionReset => {},
            else => {
                log.warn("Error occurred during acceptEx(): {}", .{err});
                return err;
            },
        };
    }

    pub fn deinitClient(server: *WindowsServer, client: *Client) void {
        const client_overlapped = server.overlappedFromClient(client) orelse return;

        winsock.disconnectEx(client.socket, client_overlapped, true) catch |err| {
            switch (err) {
                error.IoPending => {
                    // Disconnect in progress, socket can be reused after it's completed
                    client.state = .disconnecting;
                },
                else => {
                    log.err("Error disconnecting client: {}", .{err});

                    // Since we couldn't gracefully disconnect the client, we'll shut down its socket and re-create
                    // it.
                    os.closeSocket(client.socket);
                    server.resetClient(client);
                },
            }

            const end_ts = std.time.microTimestamp();
            const duration = @as(f64, @floatFromInt(end_ts - client.start_ts)) / std.time.us_per_ms;
            std.log.info("Request completed in {d:4}ms", .{duration});
            return;
        };
    }

    pub fn resetClient(server: *WindowsServer, client: *Client) void {
        client.reset();
        const client_overlapped = server.overlappedFromClient(client) orelse return;
        client_overlapped.* = .{
            .Internal = 0,
            .InternalHigh = 0,
            .DUMMYUNIONNAME = .{
                .DUMMYSTRUCTNAME = .{
                    .Offset = 0,
                    .OffsetHigh = 0,
                },
            },
            .hEvent = null,
        };
    }

    pub fn recv(server: *WindowsServer, client: *Client) !void {
        client.state = .reading;
        const client_overlapped = server.overlappedFromClient(client) orelse return;

        winsock.wsaRecv(client.socket, client.buffers.request_buffer.unusedCapacitySlice(), client_overlapped) catch |err| switch (err) {
            error.IoPending => return,
            else => return err,
        };
    }

    pub fn send(server: *WindowsServer, client: *Client) !void {
        client.state = .writing;
        const client_overlapped = server.overlappedFromClient(client) orelse return;

        winsock.wsaSend(client.socket, client.buffers.response_buffer.items, client_overlapped) catch |err| switch (err) {
            error.IoPending => return,
            else => return err,
        };
    }

    pub fn getCompletions(server: *WindowsServer, clients: []*Client) !usize {
        var overlapped_entries: [16]windows.OVERLAPPED_ENTRY = undefined;
        const entries_removed = try winsock.getQueuedCompletionStatusEx(server.io_port, &overlapped_entries, null, false);

        for (overlapped_entries[0..entries_removed], 0..) |entry, client_index| {
            var client = server.clientFromOverlapped(entry.lpOverlapped);
            const bytes_transferred: usize = @intCast(entry.dwNumberOfBytesTransferred);
            if (client.state == .accepting) {
                os.setsockopt(client.socket, os.windows.ws2_32.SOL.SOCKET, os.windows.ws2_32.SO.UPDATE_ACCEPT_CONTEXT, &std.mem.toBytes(server.socket)) catch |err| {
                    std.log.err("Error during setsockopt: {}", .{err});
                };
            } else if (client.state == .reading) {
                const total_bytes_recv = client.buffers.request_buffer.items.len + bytes_transferred;
                if (total_bytes_recv == client.buffers.request_buffer.capacity) {
                    // We've received bytes until we ran out of capacity. We'll increase the capacity
                    // and then try to recieve more bytes
                    client.buffers.request_buffer.resize(client.buffers.request_buffer.capacity + 1024) catch {
                        log.err("Reached capacity on request_buffer, but could not allocate additional space. Will try to handle the request with the data received so far...", .{});
                        client.state = .read_complete;
                    };
                } else {
                    // We stopped receiving bytes before running out of capacity, which signals to us
                    // that the client is done sending data. We'll mark ourselves as done reading
                    // and move on to handle the request.
                    client.state = .read_complete;
                }

                // We wrote to the buffer directly, so the len wasn't automatically updated.
                client.buffers.request_buffer.items.len = total_bytes_recv;
            } else if (client.state == .writing) {
                if (bytes_transferred == 0 or bytes_transferred == client.buffers.response_buffer.items.len) {
                    client.state = .write_complete;
                } else {
                    const current_len = client.buffers.response_buffer.items.len;
                    const remaining_data_len = current_len - bytes_transferred;
                    std.mem.copyForwards(u8, client.buffers.response_buffer.items[0..], client.buffers.response_buffer.items[bytes_transferred..]);
                    client.buffers.response_buffer.items.len = remaining_data_len;
                }
            }
            clients[client_index] = client;
        }

        return entries_removed;
    }

    fn getSocket(server: WindowsServer) !os.socket_t {
        const flags = os.windows.ws2_32.WSA_FLAG_OVERLAPPED;
        return try os.windows.WSASocketW(@as(i32, @intCast(server.listen_address.any.family)), @as(i32, os.SOCK.STREAM), @as(i32, os.IPPROTO.TCP), null, 0, flags);
    }

    fn overlappedFromClient(server: *WindowsServer, client: *const Client) ?*windows.OVERLAPPED {
        const client_index = client.id orelse return null;
        std.debug.assert(client_index < client_count);
        const overlapped = &server.overlapped[client_index];
        return overlapped;
    }

    fn clientFromOverlapped(server: *WindowsServer, overlapped: *windows.OVERLAPPED) *Client {
        const overlapped_index = (@intFromPtr(overlapped) - @intFromPtr(server.overlapped.ptr)) / @sizeOf(windows.OVERLAPPED);
        std.debug.assert(overlapped_index < client_count);
        return &server.clients[overlapped_index];
    }
};

const LinuxServer = struct {
    socket: os.socket_t = undefined,
    clients: [256]Client = undefined,
    listen_address: net.Address = undefined,
    io_uring: std.os.linux.IO_Uring,

    pub fn init(allocator: Allocator, address: net.Address) !LinuxServer {
        var server: LinuxServer = undefined;

        const flags = 0;
        var entries: u16 = 4096;
        server.io_uring = while (entries > 1) {
            if (std.os.linux.IO_Uring.init(@as(u13, @intCast(entries)), flags)) |ring| {
                log.info("Submission queue created with {} entries", .{entries});
                break ring;
            } else |err| switch (err) {
                error.SystemResources => {
                    entries /= 2;
                    continue;
                },
                else => return err,
            }
        } else return error.NotEnoughResources;

        server.listen_address = address;

        const socket_flags = os.SOCK.STREAM;
        server.socket = try os.socket(address.any.family, socket_flags, os.IPPROTO.TCP);
        errdefer os.closeSocket(server.socket);

        var enable: u32 = 1;
        try std.os.setsockopt(server.socket, os.SOL.SOCKET, os.SO.REUSEADDR, std.mem.asBytes(&enable));

        var socklen = address.getOsSockLen();
        try os.bind(server.socket, &address.any, socklen);
        try os.listen(server.socket, 128);
        try os.getsockname(server.socket, &server.listen_address.any, &socklen);

        for (&server.clients, 0..) |*client, index| {
            client.* = try Client.init(allocator);
            client.id = index;
            try server.acceptClient(client);
        }

        _ = try server.io_uring.submit();

        return server;
    }

    pub fn deinit(server: *LinuxServer, _: Allocator) void {
        os.closeSocket(server.socket);
        for (&server.clients) |*client| client.deinit();
    }

    pub fn acceptClient(server: *LinuxServer, client: *Client) !void {
        server.resetClient(client);
        client.state = .accepting;
        const flags = os.SOCK.CLOEXEC | os.SOCK.NONBLOCK;

        _ = server.io_uring.accept(@intCast(@intFromPtr(client)), server.socket, null, null, flags) catch |err| {
            log.err("Error while trying to accept client: {}", .{err});
            return err;
        };
    }

    pub fn resetClient(server: *LinuxServer, client: *Client) void {
        _ = server;
        client.reset();
    }

    pub fn deinitClient(server: *LinuxServer, client: *Client) void {
        client.state = .disconnecting;
        _ = server.io_uring.close(@intCast(@intFromPtr(client)), client.socket) catch |err| {
            std.log.err("Error submiting SQE for close(): {}", .{err});
            return;
        };
        _ = server.io_uring.submit() catch |err| {
            log.err("Error while trying to close client: {}", .{err});
        };
        const end_ts = std.time.microTimestamp();
        const duration = end_ts - client.start_ts;
        log.info("Request completed in {}ms", .{@divFloor(duration, std.time.us_per_ms)});
    }

    pub fn recv(server: *LinuxServer, client: *Client) !void {
        client.state = .reading;

        const flags = 0;
        _ = try server.io_uring.recv(@intCast(@intFromPtr(client)), client.socket, .{ .buffer = client.buffers.request_buffer.unusedCapacitySlice() }, flags);
    }

    pub fn send(server: *LinuxServer, client: *Client) !void {
        client.state = .writing;

        const flags = 0;
        log.info("Response length: {} bytes", .{client.buffers.response_buffer.items.len});
        _ = try server.io_uring.send(@intCast(@intFromPtr(client)), client.socket, client.buffers.response_buffer.items, flags);
    }

    pub fn getCompletions(server: *LinuxServer, clients: []*Client) !usize {
        var client_count: usize = 0;

        _ = server.io_uring.submit() catch |err| {
            log.err("Error submitting SQEs: {}", .{err});
            return err;
        };

        // @todo Even though the user is giving us a slice of clients to fetch, we're still capping the max at 16
        var cqes: [16]std.os.linux.io_uring_cqe = undefined;
        const count = server.io_uring.copy_cqes(&cqes, 1) catch |err| {
            log.err("Error while copying CQEs: {}", .{err});
            return err;
        };
        if (count == 0) return error.WouldBlock;

        for (cqes[0..count]) |cqe| {
            var client = @as(?*Client, @ptrFromInt(@as(usize, @intCast(cqe.user_data)))) orelse continue;
            switch (cqe.err()) {
                .SUCCESS => {
                    if (client.state == .accepting) {
                        client.socket = cqe.res;
                    } else if (client.state == .reading) {
                        const bytes_transferred: usize = @intCast(cqe.res);
                        const total_bytes_recv = client.buffers.request_buffer.items.len + bytes_transferred;

                        if (total_bytes_recv == 0) {
                            client.state = .writing;
                            client.keep_alive = false;
                        } else if (total_bytes_recv == client.buffers.request_buffer.capacity) {
                            client.buffers.request_buffer.resize(client.buffers.request_buffer.capacity + 1024) catch {
                                log.err("Reached capacity on request_buffer, but could not allocate additional space. Will try to handle the request with the data received so far...", .{});
                                client.state = .read_complete;
                            };
                        } else {
                            client.state = .read_complete;
                        }

                        client.buffers.request_buffer.items.len = total_bytes_recv;
                    } else if (client.state == .writing) {
                        const bytes_transferred: usize = @intCast(cqe.res);

                        if (bytes_transferred == 0 or bytes_transferred == client.buffers.response_buffer.items.len) {
                            client.state = .write_complete;
                        } else {
                            const current_len = client.buffers.response_buffer.items.len;
                            const remaining_data_len = current_len - bytes_transferred;
                            std.mem.copyForwards(u8, client.buffers.response_buffer.items[0..], client.buffers.response_buffer.items[bytes_transferred..]);
                            client.buffers.response_buffer.items.len = remaining_data_len;
                        }
                    }
                    clients[client_count] = client;
                    client_count += 1;
                },
                .AGAIN => {
                    if (client.state == .accepting) {
                        try server.acceptClient(client);
                    }
                },
                else => |err| {
                    log.err("getCompletion error: {} (during state {})", .{ err, client.state });
                },
            }
        }

        return client_count;
    }
};
