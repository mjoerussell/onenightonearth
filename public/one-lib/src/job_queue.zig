const std = @import("std");
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
const Mutex = std.Mutex;
const parseFloat = std.fmt.parseFloat;

/// This is supposed to be a thread-safe list
pub fn SafeList(comptime T: type) type {
    return struct {
        const Self = @This();

        items: []T,
        capacity: usize,
        current_len: usize,
        allocator: *Allocator,
        mutex: Mutex,

        pub fn init(allocator: *Allocator, capacity: usize) !SafeList(T) {
            return SafeList(T){
                .items = try allocator.alloc(T, capacity),
                .capacity = capacity,
                .current_len = 0,
                .allocator = allocator,
                .mutex = Mutex{},
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.items);
        }

        pub fn insert(self: *Self, item: T) !void {
            var lock = self.mutex.acquire();
            defer lock.release();

            if (self.current_len + 1 == self.capacity) {
                self.items = try self.allocator.realloc(self.items, self.capacity + (self.capacity / 2));
            }

            // std.debug.warn("[SafeList] Inserting item at index {}\n", .{self.current_len});

            self.items[self.current_len] = item;
            self.current_len += 1;
        }

        pub fn get_items(self: *Self) []T {
            return self.items[0..self.current_len];
        }

        pub fn get(self: *Self, index: usize) ?T {
            var lock = self.mutex.acquire();
            defer lock.release();

            if (index < self.current_len) {
                return self.items[index];
            }
            return null;
        }
    };
}

/// Standard queue data structure
pub fn Queue(comptime T: type) type {
    return struct {
        const Self = @This();

        const ResizeError = error{ IncorrectCapacity, OutOfMemory };

        items: []T,
        starting_pos: usize,
        ending_pos: usize,

        current_len: usize,
        capacity: usize,

        mutex: Mutex,
        allocator: *Allocator,

        pub fn init(allocator: *Allocator, capacity: usize) !Queue(T) {
            return Queue(T){
                .items = try allocator.alloc(T, capacity),
                .starting_pos = 0,
                .ending_pos = 0,
                .current_len = 0,
                .capacity = capacity,
                .allocator = allocator,
                .mutex = Mutex{},
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.items);
        }

        pub fn enqueue(self: *Self, item: T) void {
            var lock = self.mutex.acquire();
            defer lock.release();

            if (self.is_full()) return;

            self.items[self.ending_pos] = item;
            self.current_len += 1;
            self.increment_end();
        }

        pub fn dequeue(self: *Self) ?T {
            var lock = self.mutex.acquire();
            defer lock.release();

            if (self.current_len == 0) {
                return null;
            }
            defer self.increment_start();
            self.current_len -= 1;
            return self.items[self.starting_pos];
        }

        pub fn grow(self: *Self, new_capacity: usize) ResizeError!void {
            var lock = self.mutex.acquire();
            defer lock.release();

            if (new_capacity < self.capacity) return error.IncorrectCapacity;
            if (new_capacity == self.capacity) return;
            self.items = self.allocator.realloc(self.items, new_capacity) catch |err| return error.OutOfMemory;
            self.capacity = new_capacity;
        }

        fn increment_end(self: *Self) void {
            if (self.is_full()) return;

            if (self.ending_pos == self.capacity) {
                self.ending_pos = 0;
            } else {
                self.ending_pos += 1;
            }
        }

        fn increment_start(self: *Self) void {
            if (self.is_full()) return;

            if (self.starting_pos == self.capacity) {
                self.starting_pos = 0;
            } else {
                self.starting_pos += 1;
            }
        }

        fn is_full(self: *Self) bool {
            return (self.starting_pos == 0 and self.ending_pos == self.capacity) or (self.ending_pos + 1 == self.starting_pos);
        }
    };
}

pub fn JobQueue(comptime T: type, comptime R: type, comptime num_jobs: usize) type {
    return struct {
        const Self = @This();

        const ThreadContext = struct {
            job_queue: *Self, queue_index: usize
        };

        const Job = fn (T) R;

        const ThreadFn = struct {
            fn run(ctx: ThreadContext) void {
                var q = ctx.job_queue;
                // const handle = q.job_threads[ctx.queue_index].handle();
                q.jobs_started[ctx.queue_index] = true;
                // Run thread for as long as there are (or could be) pending jobs
                while (true) {
                    if (q.item_queues[ctx.queue_index].dequeue()) |item| {
                        const res: R = q.job_handler(item);
                        // Insert the result of the job into the JobQueue's results array
                        // std.debug.warn("Thread {} handled job\n", .{ctx.queue_index});
                        q.job_results.insert(res) catch |_| {};
                        // std.debug.warn("Thread {} inserted result\n", .{ctx.queue_index});
                    } else {
                        // If the queue is empty and the job queue is done accepting new items, break the loop
                        if (q.is_done) {
                            std.debug.warn("Emptied queue {} and the queue is closed.\n", .{ctx.queue_index});
                            break;
                        }
                    }
                }
            }
        };

        item_queues: [num_jobs]Queue(T),
        job_threads: [num_jobs]*Thread,

        jobs_started: [num_jobs]bool,

        job_results: SafeList(R),

        job_handler: Job,

        allocator: *Allocator,

        is_done: bool = false,

        pub fn init(allocator: *Allocator, queue_capacity: usize, job_handler: Job) !*Self {
            var this_queue = try allocator.create(Self);
            this_queue.* = Self{
                .item_queues = undefined,
                .job_threads = undefined,
                .job_results = try SafeList(R).init(allocator, queue_capacity * num_jobs),
                .jobs_started = [_]bool{false} ** num_jobs,
                .job_handler = job_handler,
                .allocator = allocator,
            };

            // Initialize the queues with the desired capacity
            for (this_queue.item_queues) |*q| {
                q.* = try Queue(T).init(allocator, queue_capacity);
            }
            // Spawn threads to do jobs
            for (this_queue.job_threads) |*t, index| {
                const context: ThreadContext = .{
                    .job_queue = this_queue,
                    .queue_index = index,
                };
                std.debug.warn("Starting thread with index {}\n", .{context.queue_index});
                t.* = try Thread.spawn(context, ThreadFn.run);
            }
            return this_queue;
        }

        pub fn deinit(self: *Self) void {
            for (self.item_queues) |*queue| {
                queue.deinit();
            }
            self.job_results.deinit();
            self.allocator.destroy(self);
        }

        const InsertError = error.QueueIsClosed;
        pub fn enqueue_job_input(self: *Self, item: T) !void {
            if (self.is_done) return error.QueueIsClosed;
            while (!self.all_jobs_started()) {}

            var smallest_queue_size: i32 = @intCast(i32, self.item_queues[0].current_len);
            var smallest_queue_index: usize = 0;
            for (self.item_queues) |q, index| {
                if (q.current_len < smallest_queue_size) {
                    smallest_queue_size = @intCast(i32, q.current_len);
                    smallest_queue_index = index;
                }
            }
            // std.debug.warn("Adding line to Q{}\n", .{smallest_queue_index});
            self.item_queues[smallest_queue_index].enqueue(item);
        }

        fn all_jobs_started(self: *Self) bool {
            return for (self.jobs_started) |is_started| {
                if (!is_started) break false;
            } else true;
        }

        fn close_job_queue(self: *Self) void {
            self.is_done = true;
        }

        pub fn finish_jobs(self: *Self) []R {
            self.close_job_queue();
            for (self.job_threads) |thread| {
                thread.wait();
            }
            return self.job_results.get_items();
        }
    };
}

pub fn TokenIterator(comptime token: []const u8) type {
    return struct {
        const Self = @This();
        data: []const u8,
        current_pos: usize,

        pub fn create(data: []const u8) Self {
            return .{
                .data = data,
                .current_pos = 0,
            };
        }

        pub fn next_line(it: *Self) ?[]const u8 {
            const starting_pos = it.current_pos;
            var end_pos = starting_pos;
            while (end_pos + token.len < it.data.len) : (end_pos += 1) {
                if (std.mem.eql(u8, it.data[end_pos..end_pos + token.len], token)) {
                    it.current_pos = end_pos + token.len;
                    return it.data[starting_pos..end_pos];
                }
            }
            return null;
        }
    };
}

pub const LineIterator = TokenIterator("\n");

test "Line Iterator" {
    const expectEqualStrings = std.testing.expectEqualStrings;
    const first = "First line";
    const second = "  Second line ";
    const third = "Third 2122343   asdfds  line  ";
    const data = first ++ "\n" ++ second ++ "\n" ++ third;
    var it = LineIterator.create(data);
    var index: usize = 0;
    while (it.next_line()) |line| : (index += 1)  {
        switch (index) {
            0 => expectEqualStrings(first, line),
            1 => expectEqualStrings(second, line),
            2 => expectEqualStrings(third, line),
            else => std.debug.panic("Should only have 3 lines", .{})
        }
    }
}

test "Single-Char Token Iterator" {
    const expectEqualStrings = std.testing.expectEqualStrings;
    const data = "one|two|three";
    var it = TokenIterator("|").create(data);
    var index: usize = 0;
    while (it.next_line()) |line| : (index += 1)  {
        switch (index) {
            0 => expectEqualStrings("one", line),
            1 => expectEqualStrings("two", line),
            2 => expectEqualStrings("three", line),
            else => std.debug.panic("Should only have 3 lines", .{})
        }
    }
}

test "Multi-Char Token Iterator" {
    const expectEqualStrings = std.testing.expectEqualStrings;
    const data = "oneabctwoabcthree";
    var it = TokenIterator("abc").create(data);
    var index: usize = 0;
    while (it.next_line()) |line| : (index += 1)  {
        switch (index) {
            0 => expectEqualStrings("one", line),
            1 => expectEqualStrings("two", line),
            2 => expectEqualStrings("three", line),
            else => std.debug.panic("Should only have 3 lines", .{})
        }
    }
}