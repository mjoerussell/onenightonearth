const std = @import("std");
const builtin = @import("builtin");
const os = std.os;
const net = std.net;

pub const Server = switch (builtin.os.tag) {
    .windows => WindowsServer,
    .linux => LinuxServer,
    else => net.StreamServer,
};

pub const AcceptError = error{WouldBlock, ConnectError};

const is_single_threaded = builtin.single_threaded;

/// A custom server that imitates the lowest-common-denominator of the net.StreamServer API.
/// This is needed to set up overlapped io on the incoming sockets without using non-blocking io
/// on the whole filesystem (the default event loop that would be used in that case doesn't work on windows).
const WindowsServer = struct {
    handle: ?os.socket_t = null,
    listen_address: net.Address = undefined,

    pub fn deinit(server: *Server) void {
        if (server.handle) |sock| {
            os.closeSocket(sock);
            server.handle = null;
            server.listen_address = undefined;
        }
    }

    pub fn listen(server: *Server, address: net.Address) !void {
        const flags = os.windows.ws2_32.WSA_FLAG_OVERLAPPED | os.windows.ws2_32.WSA_FLAG_NO_HANDLE_INHERIT;
        const socket = try os.windows.WSASocketW(@intCast(i32, address.any.family), @as(i32, os.SOCK.STREAM), @as(i32, os.IPPROTO.TCP), null, 0, flags);
        errdefer os.windows.closesocket(socket) catch unreachable;

        if (is_single_threaded) {
            // Make the socket non-blocking so that we don't get blocked on accept() in single-threaded mode
            var io_mode: u32 = 1;
            _ = os.windows.ws2_32.ioctlsocket(socket, os.windows.ws2_32.FIONBIO, &io_mode);
        }

        server.handle = socket;
        errdefer server.deinit();

        var socklen = address.getOsSockLen();
        try os.bind(socket, &address.any, socklen);
        try os.listen(socket, 128);
        try os.getsockname(socket, &server.listen_address.any, &socklen);
    }

    pub fn accept(server: *Server) AcceptError!os.socket_t {
        const client_sock = os.windows.accept(server.handle.?, null, null); // @note Could use these 'nulls' to get the client's address if needed
        if (client_sock == os.windows.ws2_32.INVALID_SOCKET) {
            const last_error = os.windows.ws2_32.WSAGetLastError();
            return switch (last_error) {
                os.windows.ws2_32.WinsockError.WSAEWOULDBLOCK => error.WouldBlock,
                else => return error.ConnectError,
            };
        } else {
            return client_sock;
        }
    }
};

const LinuxServer = struct {
    handle: ?os.socket_t = null,
    listen_address: net.Address = undefined,

    pub fn deinit(server: *Server) void {
        if (server.handle) |sock| {
            os.closeSocket(sock);
            server.handle = null;
            server.listen_address = undefined;
        }
    }

    pub fn listen(server: *Server, address: net.Address) !void {
        // Only create the socket in non-blocking mode if the server is running single threaded.
        // In multithreaded mode, we want to block on accept() while the worker threads handle the existing
        // connections
        const non_block_flag = if (is_single_threaded) os.SOCK.NONBLOCK else 0;
        const socket_flags = os.SOCK.STREAM | os.SOCK.CLOEXEC | non_block_flag;

        const socket = try os.socket(address.any.family, socket_flags, os.IPPROTO.TCP);
        server.handle = socket;
        errdefer server.deinit();

        var socklen = address.getOsSockLen();
        try os.bind(socket, &address.any, socklen);
        try os.listen(socket, 128);
        try os.getsockname(socket, &server.listen_address.any, &socklen);
    }

    pub fn accept(server: *Server) AcceptError!os.socket_t {
        var accepted_address: net.Address = undefined;
        var addr_len: os.socklen_t = @sizeOf(net.Address);

        return os.accept(server.handle.?, &accepted_address.any, &addr_len, os.SOCK.CLOEXEC) catch |err| switch (err) {
            error.WouldBlock => error.WouldBlock,
            else => error.ConnectError,
        };
    }
};