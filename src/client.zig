const std = @import("std");
const builtin = @import("builtin");
const os = std.os;
const net = std.net;

const EventLoop = @import("event_loop.zig").EventLoop;
const winsock = @import("./winsock.zig");

const Allocator = std.mem.Allocator;

const log = std.log.scoped(.client);
const is_windows = builtin.os.tag == .windows;

pub const Client = switch (builtin.os.tag) {
    .windows => WindowsClient,
    .linux => LinuxClient,
    else => DefaultClient,
};

const WindowsClient = struct {
    pub const Reader = std.io.Reader(WindowsClient, winsock.RecvError, recv);
    pub const Writer = std.io.Writer(WindowsClient, winsock.SendError, send);
    socket: os.socket_t,
    event_loop: *EventLoop,

    pub fn init(event_loop: *EventLoop, socket: os.socket_t) !Client {
        // The windows event event_loop uses IO completion ports, so we need to call this to register this socket with the
        // port
        try event_loop.register(socket);
        return Client{
            .socket = socket,
            .event_loop = event_loop,
        };
    }

    pub fn deinit(client: *Client) void {
        // Shutdown the socket before closing it to ensure that nobody is currently using the socket
        switch (os.windows.ws2_32.shutdown(client.socket, 1)) {
            0 => {
                _ = os.windows.ws2_32.closesocket(client.socket);
            },
            os.windows.ws2_32.SOCKET_ERROR => switch (os.windows.ws2_32.WSAGetLastError()) {
                .WSAENOTSOCK => {
                    log.warn("Tried to close a handle that is not a socket: {*}\nRetrying...", .{client.socket});
                },
                else => {},
            },
            else => unreachable,
        }
    }

    /// Send data over the socket.
    pub fn send(client: Client, data_buffer: []const u8) winsock.SendError!usize {
        var resume_node = EventLoop.createResumeNode(@frame());
        suspend {
            winsock.wsaSend(client.socket, data_buffer, &resume_node.overlapped) catch {};
        }
        return try winsock.wsaGetOverlappedResult(client.socket, &resume_node.overlapped);
    }

    /// Recieve data from the socket.
    pub fn recv(client: Client, buffer: []u8) winsock.RecvError!usize {
        var resume_node = EventLoop.createResumeNode(@frame());
        suspend {
            winsock.wsaRecv(client.socket, buffer, &resume_node.overlapped) catch {};
        }
        return try winsock.wsaGetOverlappedResult(client.socket, &resume_node.overlapped);
    }

    pub fn reader(self: Client) Reader {
        return .{ .context = self };
    }

    pub fn writer(self: Client) Writer {
        return .{ .context = self };
    }
};

const LinuxClient = struct {
    const RecvError = error{RecvErr, SubmitErr};
    const SendError = error{SendErr, SubmitErr};
    pub const Reader = std.io.Reader(LinuxClient, RecvError, recv);
    pub const Writer = std.io.Writer(LinuxClient, SendError, send);
    socket: os.socket_t,
    event_loop: *EventLoop,

    pub fn init(event_loop: *EventLoop, socket: os.socket_t) !Client {
        return Client{
            .socket = socket,
            .event_loop = event_loop,
        };
    }

    pub fn deinit(client: *Client) void {
        os.close(client.socket);
    }

    pub fn send(client: Client, data_buffer: []const u8) SendError!usize {
        const flags = os.linux.IOSQE_ASYNC;
        var resume_node = EventLoop.createResumeNode(@frame());

        suspend {
            _ = client.event_loop.io_uring.send(@intCast(u64, @ptrToInt(&resume_node)), client.socket, data_buffer, flags) catch return error.SendErr;
            _ = client.event_loop.io_uring.submit() catch return error.SubmitErr;
        }

        return std.math.min(resume_node.bytes_worked, data_buffer.len);
    }

    pub fn recv(client: Client, buffer: []u8) RecvError!usize {
        const flags = os.linux.IOSQE_ASYNC;
        var resume_node = EventLoop.createResumeNode(@frame());
        suspend {
            _ = client.event_loop.io_uring.recv(@intCast(u64, @ptrToInt(&resume_node)), client.socket, .{ .buffer = buffer }, flags) catch return error.RecvErr;
            _ = client.event_loop.io_uring.submit() catch return error.SubmitErr;
        }

        return resume_node.bytes_worked;
    }

    pub fn reader(self: Client) Reader {
        return .{ .context = self };
    }

    pub fn writer(self: Client) Writer {
        return .{ .context = self };
    }
};

const DefaultClient = struct {
    pub const Reader = net.Stream.Reader;
    pub const Writer = net.Stream.Writer;

    conn: net.StreamServer.Connection,

    pub fn init(conn: net.StreamServer.Connection) DefaultClient {
        return .{ .conn = conn };
    }

    pub fn reader(client: DefaultClient) Reader {
        return .{ .context = client.conn.stream };
    }

    pub fn writer(client: DefaultClient) Writer {
        return .{ .context = client.conn.stream };
    }

};
