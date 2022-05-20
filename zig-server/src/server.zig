const std = @import("std");
const builtin = @import("builtin");
const os = std.os;
const net = std.net;

pub const Server = switch (builtin.os.tag) {
    .windows => WindowsServer,
    else => net.StreamServer,
};

/// A custom server that imitates the lowest-common-denominator of the net.StreamServer API.
/// This is needed to set up overlapped io on the incoming sockets without using non-blocking io
/// on the whole filesystem (the default event loop that would be used in that case doesn't work on windows).
const WindowsServer = struct {
    handle: ?os.socket_t = null,
    listen_address: net.Address,

    pub fn init(config: anytype) Server {
        _ = config;
        if (builtin.os.tag != .windows) @compileError("Unsupported OS");
        return Server{
            .listen_address = undefined,
        };
    }

    pub fn deinit(server: *Server) void {
        if (server.handle) |sock| {
            os.closeSocket(sock);
            server.handle = null;
        }
    }

    pub fn listen(server: *Server, address: net.Address) !void {
        const flags = os.windows.ws2_32.WSA_FLAG_OVERLAPPED | os.windows.ws2_32.WSA_FLAG_NO_HANDLE_INHERIT;
        server.handle = try os.windows.WSASocketW(@intCast(i32, address.any.family), @as(i32, os.SOCK.STREAM), @as(i32, os.IPPROTO.TCP), null, 0, flags);
        errdefer os.windows.closesocket(server.handle.?) catch unreachable;

        var socklen = address.getOsSockLen();
        try os.bind(server.handle.?, &address.any, socklen);
        try os.listen(server.handle.?, 128);
        try os.getsockname(server.handle.?, &server.listen_address.any, &socklen);
    }

    pub fn accept(server: *Server) !os.socket_t {
        while (true) {
            const client_sock = os.windows.accept(server.handle.?, null, null); // @note Could use these 'nulls' to get the client's address if needed
            if (client_sock == os.windows.ws2_32.INVALID_SOCKET) {
                switch (os.windows.ws2_32.WSAGetLastError()) {
                    os.windows.ws2_32.WinsockError.WSAEWOULDBLOCK => continue,
                    else => return error.ConnectError,
                }
            } else {
                return client_sock;
            }
        }
    }
};