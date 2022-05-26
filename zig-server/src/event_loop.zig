const builtin = @import("builtin");
const std = @import("std");
const os = std.os;
const linux = os.linux;
const windows = os.windows;
const Allocator = std.mem.Allocator;

const winsock = @import("winsock.zig");

/// Async event management abstraction for Windows/Linux platforms. Provides a common API for handling async operations.
/// Uses IO_Uring on Linux and IO Completion Ports on Windows.
pub const EventLoop = switch (builtin.os.tag) {
    .windows => WindowsEventLoop,
    .linux => LinuxEventLoop,
    else => @compileError("OS Not Supported"),
};

pub const EventLoopOptions = struct {
    extra_thread_count: usize = if (builtin.single_threaded) 0 else switch (builtin.os.tag) {
        .windows => 4,
        // The default worker thread count on Linux is 0 because I was having issues with double-resuming frames with multiple
        // threads concurrently dequeueing from io_uring. Not sure if I'm using io_uring incorrectly, or if that's normal and I need to
        // implement some kind of locking around it
        else => 1,
    },
};

const WindowsEventLoop = struct {
    pub const ResumeNode = struct {
        frame: anyframe,
        overlapped: windows.OVERLAPPED,
        is_resumed: bool = false,
    };

    worker_threads: ?[]std.Thread = null,
    io_port: windows.HANDLE = undefined,
    is_running: bool = false,

    /// Initialize the event loop by creating a new IO completion port. If `options.extra_thread_count` > 0, then some worker threads
    /// will be allocated and spawned. 
    pub fn init(loop: *WindowsEventLoop, allocator: Allocator, comptime options: EventLoopOptions) !void {
        loop.is_running = true;
        loop.io_port = try windows.CreateIoCompletionPort(windows.INVALID_HANDLE_VALUE, null, undefined, undefined);

        if (options.extra_thread_count > 0) {
            loop.worker_threads = try allocator.alloc(std.Thread, options.extra_thread_count);
            for (loop.worker_threads.?) |*thread| {
                thread.* = try std.Thread.spawn(.{}, WindowsEventLoop.run, .{loop});
            }
        }
    }

    pub fn deinit(loop: *WindowsEventLoop, allocator: Allocator) void {
        @atomicStore(bool, &loop.is_running, false, .Acquire);
        // loop.is_running = false;
        if (loop.worker_threads) |workers| {
            for (workers) |*thread| thread.join();
            allocator.free(workers);
        }
        os.windows.CloseHandle(loop.io_port);
    }
    
    /// Thread function for the worker threads. Continuously tries to get a new async event completion.
    fn run(loop: *WindowsEventLoop) !void {
        while (@atomicLoad(bool, &loop.is_running, .Acquire)) {
            loop.getCompletion() catch {};
        }
    }

    /// Get a new completion event if one is available. If one is found, then resume the async frame associated with the event to continue
    /// whatever process was suspended.
    pub fn getCompletion(loop: *WindowsEventLoop) !void {
        var completion_key: usize = undefined;
        var overlapped: ?*windows.OVERLAPPED = undefined;
        _ = winsock.getQueuedCompletionStatus(loop.io_port, &completion_key, &overlapped) catch |err| switch (err) {
            error.WouldBlock => {},
            error.Eof => {},
            else => {
                std.log.warn("Unexpected error when getting queued completion status: {}", .{err});
                return;
            },
        };

        if (overlapped) |o| {
            var resume_node = @fieldParentPtr(ResumeNode, "overlapped", o);
            if (@cmpxchgStrong(bool, &resume_node.is_resumed, false, true, .SeqCst, .SeqCst) == null) {
                resume resume_node.frame;
            }
        }
    }

    /// Create an association between a socket and the event loop's IO completion port. This function **must be called** before starting
    /// any overlapped IO processes on the socket, otherwise the io port will not be signaled when they are complete.
    pub fn register(loop: *WindowsEventLoop, socket: os.socket_t) !void {
        _ = try windows.CreateIoCompletionPort(socket, loop.io_port, undefined, 0);
    }

    /// Initialize a ResumeNode with the given frame and a default OVERLAPPED structure.
    pub inline fn createResumeNode(frame: anyframe) ResumeNode {
        return .{ 
            .frame = frame,
            .overlapped = windows.OVERLAPPED{
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

const LinuxEventLoop = struct {
    pub const ResumeNode = struct {
        frame: anyframe,
        bytes_worked: usize = 0,
        is_resumed: bool = false,
    };

    worker_threads: ?[]std.Thread,
    io_uring: linux.IO_Uring,
    is_running: bool = false,

    /// Initialize the event loop by creating a new IO_uring instance. If `options.extra_thread_count` > 0, also allocates and spawns 
    /// some worker threads.
    pub fn init(loop: *LinuxEventLoop, allocator: Allocator, comptime options: EventLoopOptions) !void {
        loop.is_running = true;
        // This values for entries is arbitrary, currently. The only qualifier being intentionally met is that it's a power of 2
        loop.io_uring = linux.IO_Uring.init(1024, 0) catch |err| {
            std.log.err("Error occurred while trying to initialize io_uring: {}", .{err});
            return err;
        };

        if (options.extra_thread_count > 0) {
            loop.worker_threads = try allocator.alloc(std.Thread, options.extra_thread_count);
            for (loop.worker_threads.?) |*thread| {
                thread.* = try std.Thread.spawn(.{}, LinuxEventLoop.run, .{loop});
            }
        }
    }

    pub fn deinit(loop: *LinuxEventLoop, allocator: Allocator) void {
        @atomicStore(bool, &loop.is_running, false, .SeqCst);
        if (loop.worker_threads) |workers| {
            for (workers) |*thread| thread.join();
            allocator.free(workers);
        }
        loop.io_uring.deinit();
    }

    /// Thread function for the worker threads. Continuously tries to dequeue a completion event.
    fn run(loop: *LinuxEventLoop) !void {
        while (@atomicLoad(bool, &loop.is_running, .Acquire)) {
            try loop.getCompletion();    
        }
    }

    /// Dequeue a completion event, if one is available. If none are available then this returns immediately. If one is found, then it tries to
    /// acquire the async frame associated with the ResumeNode and try to resume it.
    pub fn getCompletion(loop: *LinuxEventLoop) !void {
        var cqes: [1]linux.io_uring_cqe = undefined;    
        // Wait for 0 completion queue events so we don't block in single-threaded mode
        const count = try loop.io_uring.copy_cqes(&cqes, 0);
        if (count > 0) {
            switch (cqes[0].err()) {
                .SUCCESS => {
                    var resume_node = @intToPtr(?*ResumeNode, @intCast(usize, cqes[0].user_data));
                    if (resume_node) |rn| {
                        // cqe.res can't be negative because cqe.err() only returns .SUCCESS if cqe.res >= 0
                        rn.bytes_worked = @intCast(usize, cqes[0].res);
                        if (@cmpxchgStrong(bool, &rn.is_resumed, false, true, .SeqCst, .SeqCst) == null) {
                            resume rn.frame;
                        }
                    }
                },
                else => |err| {
                    std.log.err("Error on cqe: {}", .{err});
                },
            }
        }
    }

    pub inline fn createResumeNode(frame: anyframe) ResumeNode {
        return .{ .frame = frame };
    }
};