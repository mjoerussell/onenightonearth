const std = @import("std");
const os = std.os;
const windows = os.windows;

pub const OverlappedError = error{
    NotInitialized,
    NetworkDown,
    NotASocket,
    InvalidEventHandle,
    InvalidParameter,
    IoIncomplete,
    Fault,
    GeneralError,
};

pub const RecvError = error{
    IoPending,
    WouldBlock,
    ConnectionReset,
    ConnectionAborted,
    Disconnected,
    NetworkDown,
    NetworkReset,
    NotConnected,
    TimedOut,
    OperationAborted,
    GeneralError,
} || OverlappedError;

pub const SendError = error{
    IoPending,
    WouldBlock,
    ConnectionReset,
    ConnectionAborted,
    Disconnected,
    NetworkDown,
    NetworkReset,
    NotConnected,
    TimedOut,
    OperationAborted,
    GeneralError,
} || OverlappedError;

// pub fn wsaRecv(socket: os.socket_t, buffer: []u8, overlapped: *windows.OVERLAPPED) RecvError!usize {
pub fn wsaRecv(socket: os.socket_t, buffer: []u8, overlapped: *windows.OVERLAPPED) RecvError!void {
    var wsa_buf = windows.ws2_32.WSABUF{
        .buf = buffer.ptr,
        .len = @as(u32, @truncate(buffer.len)),
    };

    var bytes_recieved: u32 = 0;
    var flags: u32 = 0;
    const result = windows.ws2_32.WSARecv(socket, @as([*]windows.ws2_32.WSABUF, @ptrCast(&wsa_buf)), 1, &bytes_recieved, &flags, overlapped, null);
    if (result != os.windows.ws2_32.SOCKET_ERROR) {
        return;
        // return wsaGetOverlappedResult(socket, overlapped) catch |err| switch (err) {
        //     error.InvalidEventHandle, error.NotInitialized, error.NotASocket => unreachable,
        //     else => err,
        // };
    }

    const last_error = windows.ws2_32.WSAGetLastError();
    return switch (last_error) {
        .WSA_IO_PENDING => error.IoPending,
        .WSAEWOULDBLOCK => error.WouldBlock,
        .WSAECONNRESET => error.ConnectionReset,
        .WSAECONNABORTED => error.ConnectionAborted,
        .WSAEDISCON => error.Disconnected,
        .WSAENETDOWN => error.NetworkDown,
        .WSAENETRESET => error.NetworkReset,
        .WSAENOTCONN => error.NotConnected,
        .WSAETIMEDOUT => error.TimedOut,
        .WSA_OPERATION_ABORTED => error.OperationAborted,
        else => error.GeneralError,
    };
}

// pub fn wsaSend(socket: os.socket_t, buffer: []const u8, overlapped: *windows.OVERLAPPED) SendError!usize {
pub fn wsaSend(socket: os.socket_t, buffer: []const u8, overlapped: *windows.OVERLAPPED) SendError!void {
    var wsa_buf = windows.ws2_32.WSABUF{
        .buf = @as([*]u8, @ptrFromInt(@intFromPtr(buffer.ptr))),
        .len = @as(u32, @truncate(buffer.len)),
    };

    var bytes_sent: u32 = 0;
    const flags: u32 = 0;
    const result = windows.ws2_32.WSASend(socket, @as([*]windows.ws2_32.WSABUF, @ptrCast(&wsa_buf)), 1, &bytes_sent, flags, overlapped, null);
    if (result != os.windows.ws2_32.SOCKET_ERROR) {
        return;
        // return wsaGetOverlappedResult(socket, overlapped) catch |err| switch (err) {
        //     error.InvalidEventHandle, error.NotInitialized, error.NotASocket => unreachable,
        //     else => err,
        // };
    }

    return switch (windows.ws2_32.WSAGetLastError()) {
        .WSA_IO_PENDING => error.IoPending,
        .WSAEWOULDBLOCK => error.WouldBlock,
        .WSAECONNRESET => error.ConnectionReset,
        .WSAECONNABORTED => error.ConnectionAborted,
        .WSAEDISCON => error.Disconnected,
        .WSAENETDOWN => error.NetworkDown,
        .WSAENETRESET => error.NetworkReset,
        .WSAENOTCONN => error.NotConnected,
        .WSAETIMEDOUT => error.TimedOut,
        .WSA_OPERATION_ABORTED => error.OperationAborted,
        else => error.GeneralError,
    };
}

pub fn wsaGetOverlappedResult(socket: os.socket_t, overlapped: *windows.OVERLAPPED) OverlappedError!usize {
    var bytes_recieved: u32 = 0;
    var flags: u32 = 0;
    const result = windows.ws2_32.WSAGetOverlappedResult(socket, overlapped, &bytes_recieved, windows.FALSE, &flags);
    if (result != windows.FALSE) {
        return @as(usize, @intCast(bytes_recieved));
    }

    return switch (windows.ws2_32.WSAGetLastError()) {
        .WSANOTINITIALISED => error.NotInitialized,
        .WSAENETDOWN => error.NetworkDown,
        .WSAENOTSOCK => error.NotASocket,
        .WSA_INVALID_HANDLE => error.InvalidEventHandle,
        .WSA_INVALID_PARAMETER => error.InvalidParameter,
        .WSA_IO_INCOMPLETE => error.IoIncomplete,
        .WSAEFAULT => error.Fault,
        else => error.GeneralError,
    };
}

pub fn getQueuedCompletionStatus(completion_port: os.windows.HANDLE, completion_key: *os.windows.ULONG_PTR, lp_overlapped: *?*os.windows.OVERLAPPED, should_block: bool) !u32 {
    var bytes_transferred: u32 = 0;
    const result = os.windows.kernel32.GetQueuedCompletionStatus(completion_port, &bytes_transferred, completion_key, lp_overlapped, if (should_block) windows.INFINITE else 0);

    if (result == os.windows.TRUE) {
        return bytes_transferred;
    }

    if (lp_overlapped.* == null) return error.WouldBlock;

    return switch (os.windows.kernel32.GetLastError()) {
        .NETNAME_DELETED => error.ConnectionReset,
        .CONNECTION_ABORTED => error.ConnectionAborted,
        .NO_NETWORK => error.NetworkDown,
        .ABANDONED_WAIT_0 => error.Abandoned,
        .OPERATION_ABORTED => error.Cancelled,
        .HANDLE_EOF => error.Eof,
        else => error.GeneralError,
    };
}

pub fn getQueuedCompletionStatusEx(completion_port: os.windows.HANDLE, overlapped_entries: []os.windows.OVERLAPPED_ENTRY, timeout_ms: ?u32, alertable: bool) !usize {
    var entries_removed: u32 = 0;

    const alertable_ext: c_int = if (alertable) os.windows.TRUE else os.windows.FALSE;
    const result = os.windows.kernel32.GetQueuedCompletionStatusEx(completion_port, overlapped_entries.ptr, @as(u32, @intCast(overlapped_entries.len)), &entries_removed, timeout_ms orelse os.windows.INFINITE, alertable_ext);

    if (result == os.windows.TRUE) {
        return entries_removed;
    }

    if (entries_removed == 0) return error.WouldBlock;

    return switch (os.windows.kernel32.GetLastError()) {
        .NETNAME_DELETED => error.ConnectionReset,
        .CONNECTION_ABORTED => error.ConnectionAborted,
        .NO_NETWORK => error.NetworkDown,
        .ABANDONED_WAIT_0 => error.Abandoned,
        .OPERATION_ABORTED => error.Cancelled,
        .HANDLE_EOF => error.Eof,
        else => error.GeneralError,
    };
}

var lp_accept_ex: ?os.windows.ws2_32.LPFN_ACCEPTEX = null;
pub fn acceptEx(listen_socket: os.socket_t, accept_socket: os.socket_t, data_buffer: []u8, bytes_recieved: *usize, overlapped: *os.windows.OVERLAPPED) !void {
    if (lp_accept_ex == null) {
        try loadAcceptEx(listen_socket);
    }

    const sockaddr_size = @sizeOf(os.sockaddr);
    const address_len = sockaddr_size + 16;

    const result = lp_accept_ex.?(listen_socket, accept_socket, @as(*anyopaque, @ptrCast(data_buffer.ptr)), 0, address_len, address_len, @as(*u32, @ptrCast(bytes_recieved)), overlapped);
    if (result == os.windows.TRUE) return;

    return switch (os.windows.ws2_32.WSAGetLastError()) {
        .WSA_IO_PENDING => error.IoPending,
        .WSAEWOULDBLOCK => error.WouldBlock,
        .WSAECONNRESET => error.ConnectionReset,
        .WSAECONNABORTED => error.ConnectionAborted,
        .WSAEDISCON => error.Disconnected,
        .WSAENETDOWN => error.NetworkDown,
        .WSAENETRESET => error.NetworkReset,
        .WSAENOTCONN => error.NotConnected,
        .WSAETIMEDOUT => error.TimedOut,
        .WSA_OPERATION_ABORTED => error.OperationAborted,
        else => error.GeneralError,
    };
}

const LPFN_DISCONNECTEX = *const fn (socket: os.windows.ws2_32.SOCKET, lpOverlapped: *os.windows.OVERLAPPED, dwFlags: u32, reserved: u32) callconv(os.windows.WINAPI) os.windows.BOOL;

var lp_disconnect_ex: ?LPFN_DISCONNECTEX = null;
pub fn disconnectEx(socket: os.socket_t, overlapped: *os.windows.OVERLAPPED, should_reuse_socket: bool) !void {
    if (lp_disconnect_ex == null) {
        try loadDisconnectEx(socket);
    }

    const result = lp_disconnect_ex.?(socket, overlapped, if (should_reuse_socket) os.windows.ws2_32.TF_REUSE_SOCKET else 0, 0);
    if (result == os.windows.TRUE) return;

    return switch (os.windows.ws2_32.WSAGetLastError()) {
        .WSA_IO_PENDING => error.IoPending,
        .WSAEWOULDBLOCK => error.WouldBlock,
        .WSAECONNRESET => error.ConnectionReset,
        .WSAECONNABORTED => error.ConnectionAborted,
        .WSAEDISCON => error.Disconnected,
        .WSAENETDOWN => error.NetworkDown,
        .WSAENETRESET => error.NetworkReset,
        .WSAENOTCONN => error.NotConnected,
        .WSAETIMEDOUT => error.TimedOut,
        .WSA_OPERATION_ABORTED => error.OperationAborted,
        else => error.GeneralError,
    };
}

fn loadAcceptEx(listen_socket: os.socket_t) !void {
    const guid_accept_ex = os.windows.ws2_32.WSAID_ACCEPTEX;

    var accept_ex_buf: [@sizeOf(@TypeOf(lp_accept_ex))]u8 = undefined;

    _ = try os.windows.WSAIoctl(listen_socket, os.windows.ws2_32.SIO_GET_EXTENSION_FUNCTION_POINTER, &std.mem.toBytes(guid_accept_ex), &accept_ex_buf, null, null);
    lp_accept_ex = std.mem.bytesToValue(os.windows.ws2_32.LPFN_ACCEPTEX, &accept_ex_buf);
}

pub const WSAID_DISCONNECTEX = os.windows.GUID{
    .Data1 = 0x7fda2e11,
    .Data2 = 0x8630,
    .Data3 = 0x436f,
    .Data4 = [8]u8{ 0xa0, 0x31, 0xf5, 0x36, 0xa6, 0xee, 0xc1, 0x57 },
};

fn loadDisconnectEx(socket: os.socket_t) !void {
    const guid_disconnect_ex = WSAID_DISCONNECTEX;
    var disconnect_ex_buf: [@sizeOf(@TypeOf(lp_disconnect_ex))]u8 = undefined;

    _ = os.windows.WSAIoctl(socket, os.windows.ws2_32.SIO_GET_EXTENSION_FUNCTION_POINTER, &std.mem.toBytes(guid_disconnect_ex), &disconnect_ex_buf, null, null) catch {
        return error.GeneralError;
    };
    lp_disconnect_ex = std.mem.bytesToValue(LPFN_DISCONNECTEX, &disconnect_ex_buf);
}
