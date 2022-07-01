const std = @import("std");
const os = std.os;
const windows = os.windows;

pub const OverlappedError = error {
    NotInitialized,
    NetworkDown,
    NotASocket,
    InvalidEventHandle,
    InvalidParameter,
    IoIncomplete,
    Fault,
    GeneralError,
};

pub const RecvError = error {
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

pub const SendError = error {
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
        .len = @truncate(u32, buffer.len),
    };

    var bytes_recieved: u32 = 0;
    var flags: u32 = 0;
    var result = windows.ws2_32.WSARecv(socket, @ptrCast([*]windows.ws2_32.WSABUF, &wsa_buf), 1, &bytes_recieved, &flags, overlapped, null);
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
        .buf = @intToPtr([*]u8, @ptrToInt(buffer.ptr)),
        .len = @truncate(u32, buffer.len),
    };

    var bytes_sent: u32 = 0;
    var flags: u32 = 0;
    var result = windows.ws2_32.WSASend(socket, @ptrCast([*]windows.ws2_32.WSABUF, &wsa_buf), 1, &bytes_sent, flags, overlapped, null);
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
        return @intCast(usize, bytes_recieved);
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
    const result = os.windows.kernel32.GetQueuedCompletionStatus(
        completion_port, 
        &bytes_transferred, 
        completion_key, 
        lp_overlapped, 
        if (should_block) windows.INFINITE else 0
    );

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