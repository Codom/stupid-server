//
// content.zig
// Copyright (C) 2022 Christopher Odom christopher.r.odom@gmail.com
//
// Distributed under terms of the MIT license.
//

//!
//! Entrypoint to the stupid web server.
//!
//! This isn't designed for any purpose other than
//! to show prospective employers that I know how to
//! computers.
//!

const std = @import("std");
const StreamServer = std.net.StreamServer;
const Address = std.net.Address;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

const HttpReq = @import("http_req.zig");
const router = @import("router.zig");

var threads: [8]std.Thread = undefined;
var server: StreamServer = undefined;

// Global to signal keeping threads alive
var keep_alive: bool = true;

/// The main thread's one and only job is to orchestrate the
/// job threads. Everything else happens in the thread_main.
pub fn main() !void {
    server = StreamServer.init(.{});
    defer {
        server.deinit();
        std.log.info("Closed and cleaned up server resources", .{});
    }

    // Setup listener
    try server.listen(try Address.parseIp("0.0.0.0", 8089));
    defer server.close();

    // Setup threads
    for(threads) |*t, i| {
        t.* = try std.Thread.spawn(.{}, thread_main, .{i});
    }

    var act = std.os.Sigaction {
        .handler = .{.handler = signal_handler},
        .mask = [_]u32{0xffffffff} ** 32,
        .flags = std.os.SA.NODEFER | std.os.SA.RESETHAND,
    };
    std.os.sigaction(std.os.SIG.INT, &act, null);
    defer cleanup();

    // Process reqs
    var con: StreamServer.Connection = undefined;
    while(keep_alive and try_server_accept(&con)) {
        try push_con(con);
    }
    std.log.info("Main thread exiting", .{});
}

fn try_server_accept(con: *StreamServer.Connection) bool {
    con.* = server.accept() catch |e| {
        std.log.err("Server failed with error {s}, shutting down!", .{e});
        return false;
    };
    return true;
}

fn push_con(con: ?StreamServer.Connection) !void {
    var node = try JobAllocator.create(JobQueueT.Node);
    node.data = con;
    JobQueue.put(node);
}

fn signal_handler(sig: c_int) callconv(.C) void {
     _ = sig;
    std.log.info("In sighandler", .{});
    keep_alive = false;
    server.close();
}

fn cleanup() void {
    std.log.info("Closing server...", .{});
    for(threads) |_| {
        push_con(null) catch unreachable;
    }
    for(threads) |*t| {
        t.join();
    }
}
/// Job queue distributes connections
/// to the webserver threads that then dispatch
/// based off of routing rules defined in router.zig
const JobQueueT = std.atomic.Queue(?StreamServer.Connection);
var JobQueue = JobQueueT.init();
var JobAllocator = std.heap.page_allocator;

pub fn thread_main(id: usize) !void {
    while(keep_alive) {
        if (JobQueue.get()) |node| {
            defer JobAllocator.destroy(node);
            if(node.data) |con| {
                var con_arena = std.heap.ArenaAllocator.init(gpa.allocator());
                // Handle lifetime transfers
                defer { 
                    con_arena.deinit();
                    con.stream.close();
                    std.log.info("Closed connection on thead {d}", .{id});
                }
                var req = try HttpReq.parse(con);
                defer req.deinit();

                std.log.info("Thread {d} responding to {{ {s} {s} }}", .{id, req.method, req.path});
                const res = try router.get(req.path, con_arena.allocator());
                try process_response(res, con);
                // Arena cleanup should happen here
            } else {
                std.log.warn("Thread {d} shutting down", .{id});
                break;
            }
        } else {
        }
    }
    std.log.info("Thread exiting", .{});
}

fn process_response(res: router.ServerMedia, con: StreamServer.Connection) !void {
    var writer = con.stream.writer();
    try writer.print(
        \\HTTP/1.1 {s}
        \\Server: stupid server
        \\Content-length {d}
        \\Content-Type: {s}
        \\
        \\{s}
        , .{
            res.response_code,
            res.res.len,
            res.media_type,
            res.res,
    });
}

