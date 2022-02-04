const std = @import("std");
const builtin = @import("builtin");
const os = std.os;
const net = std.net;
const Loop = std.event.Loop;

const winsock = @import("./winsock.zig");

const Allocator = std.mem.Allocator;

pub const Client = if (builtin.os.tag == .windows)
    WindowsClient
else
    DefaultClient;

pub const NetworkLoop = struct {
    pub const ResumeNode = struct {
        frame: anyframe,
        overlapped: os.windows.OVERLAPPED,
        is_resumed: bool = false,
    };

    worker_threads: []std.Thread,
    io_port: os.windows.HANDLE,
    is_running: bool = false,


    pub fn init(loop: *NetworkLoop, allocator: Allocator) !void {
        loop.is_running = true;
        loop.io_port = try os.windows.CreateIoCompletionPort(os.windows.INVALID_HANDLE_VALUE, null, undefined, undefined);
    
        loop.worker_threads = try allocator.alloc(std.Thread, std.Thread.getCpuCount() catch 4);
        for (loop.worker_threads) |*thread| {
            thread.* = try std.Thread.spawn(.{}, NetworkLoop.run, .{loop});
        }
    }

    pub fn deinit(loop: *NetworkLoop) void {
        loop.is_running = false;
        os.windows.CloseHandle(loop.io_port);
    }

    fn run(loop: *NetworkLoop) !void {
        while (loop.is_running) {
            var completion_key: usize = undefined;
            var overlapped: ?*os.windows.OVERLAPPED = undefined;
            _ = winsock.getQueuedCompletionStatus(loop.io_port, &completion_key, &overlapped) catch |err| switch (err) {
                error.Aborted => return,
                error.Eof => {},
                else => continue,
            };

            if (overlapped) |o| {
                var resume_node = @fieldParentPtr(ResumeNode, "overlapped", o);
                if (@cmpxchgStrong(bool, &resume_node.is_resumed, false, true, .SeqCst, .SeqCst) == null) {
                    resume resume_node.frame;
                }
            }
        }
    }

    fn register(loop: *NetworkLoop, socket: os.socket_t) !void {
        _ = try os.windows.CreateIoCompletionPort(socket, loop.io_port, undefined, 0);
    }

    inline fn createResumeNode(frame: anyframe) ResumeNode {
        return .{ 
            .frame = frame,
            .overlapped = os.windows.OVERLAPPED{
                .Internal = 0,
                .InternalHigh = 0,
                .DUMMYUNIONNAME = .{
                    .DUMMYSTRUCTNAME = .{
                        .Offset = 0,
                        .OffsetHigh = 0,
                    },
                },
                .hEvent = null,
            }
        };
    }
};

const WindowsClient = struct {
    pub const Reader = std.io.Reader(WindowsClient, winsock.RecvError, recv);
    pub const Writer = std.io.Writer(WindowsClient, winsock.SendError, send);
    socket: os.socket_t,
    loop: *NetworkLoop,

    pub fn init(loop: *NetworkLoop, socket: os.socket_t) !Client {
        try loop.register(socket);
        return Client{
            .socket = socket,
            .loop = loop,
        };
    }

    pub fn connectToAddress(loop: *NetworkLoop, address: net.Address) !Client {
        const flags = os.windows.ws2_32.WSA_FLAG_OVERLAPPED | os.windows.ws2_32.WSA_FLAG_NO_HANDLE_INHERIT;
        const sockfd = try os.windows.WSASocketW(@intCast(i32, address.any.family), @as(i32, os.SOCK.STREAM), @as(i32, os.IPPROTO.TCP), null, 0, flags);
        errdefer os.closeSocket(sockfd);

        try os.connect(sockfd, &address.any, address.getOsSockLen());

        return try Client.init(loop, sockfd);
    }

    pub fn deinit(client: *Client) void {
        switch (os.windows.ws2_32.shutdown(client.socket, 1)) {
            0 => {
                _ = os.windows.ws2_32.closesocket(client.socket);
            },
            os.windows.ws2_32.SOCKET_ERROR => switch (os.windows.ws2_32.WSAGetLastError()) {
                .WSAENOTSOCK => {
                    std.log.warn("Tried to close a handle that is not a socket: {*}\nRetrying...", .{client.socket});
                },
                else => {},
            },
            else => unreachable,
        }
    }

    pub fn send(client: Client, data_buffer: []const u8) winsock.SendError!usize {
        var resume_node = NetworkLoop.createResumeNode(@frame());
        suspend {
            if (winsock.wsaSend(client.socket, data_buffer, &resume_node.overlapped)) {
                // if (@cmpxchgStrong(bool, &resume_node.is_resumed, false, true, .SeqCst, .SeqCst) == null) {
                //     std.log.debug("Got send result immediately, resuming frame {*}\n", .{&resume_node.frame});
                //     resume @frame();
                // }
            } else |_| {}
        }
        return try winsock.wsaGetOverlappedResult(client.socket, &resume_node.overlapped);
    }

    pub fn recv(client: Client, buffer: []u8) winsock.RecvError!usize {
        var resume_node = NetworkLoop.createResumeNode(@frame());
        suspend {
            if (winsock.wsaRecv(client.socket, buffer, &resume_node.overlapped)) {
                // if (@cmpxchgStrong(bool, &resume_node.is_resumed, false, true, .SeqCst, .SeqCst) == null) {
                //     std.log.debug("Got recv result immediately, resuming frame (node = {*})\n", .{&resume_node});
                //     // resume_node.is_resumed = true;
                //     resume @frame();
                // }
            } else |_| {}
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

const DefaultClient = struct {
    pub const Reader = net.StreamServer.Connection.Reader;
    pub const Writer = net.StreamServer.Connection.Writer;

    conn: net.StreamServer.Connection,

    pub fn init(conn: net.StreamServer.Connection) DefaultClient {
        return .{ .conn = conn };
    }

    pub fn reader(client: DefaultClient) Reader {
        return .{ .context = client.conn };
    }

    pub fn writer(client: DefaultClient) Writer {
        return .{ .context = client.conn };
    }

};
