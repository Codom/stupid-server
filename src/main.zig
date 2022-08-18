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

/// The main thread's one and only job is to init the server.
/// The rest is handled with child threads. StreamServer utilizes
/// an event look internally so this (should) justwerk™️
pub fn main() !void {
    var server = StreamServer.init(.{});
    defer {
        server.deinit();
        std.log.info("Closed and cleaned up server resources", .{});
    }

    // Setup listener
    try server.listen(try Address.parseIp("0.0.0.0", 8089));

    // Setup threads
    var threads: [8]std.Thread = undefined;
    for(threads) |*t, i| {
        t.* = try std.Thread.spawn(.{}, thread_main, .{i, &server});
    }
    std.log.info("Press enter to quit...", .{});
    var stdin = std.io.getStdIn().reader();
    _ = try stdin.readUntilDelimiterOrEofAlloc(gpa.allocator(), '\n', 1024);
    keep_alive = false;
    server.close();
    std.log.info("Closing server...", .{});
    for(threads) |*t| {
        t.join();
    }
}

var keep_alive: bool = true;
pub fn thread_main(id: usize, server: *StreamServer) !void {
    while(keep_alive) {
        var con_arena = std.heap.ArenaAllocator.init(gpa.allocator());
        defer con_arena.deinit();
        // Process reqs
        var con = try server.accept();
        defer { 
            con.stream.close();
            std.log.info("Closed connection on thead {d}", .{id});
        }
        var req = try HttpReq.parse(con);
        defer req.deinit();

        std.log.info("Thread {d} responding to {{ {s} {s} }}", .{id, req.method, req.path});
        const res = try router.get(req.path, con_arena.allocator());
        try process_response(res, con);
        con_arena.allocator().destroy(res.res.ptr);
    }
}

/// Only supports plain text for now
fn process_response(res: router.ServerMedia, con: StreamServer.Connection) !void {
    // const date = "Wed, 17 Aug 2021 16:48:48 GMT";
    const len = res.res.len;
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
            len,
            res.media_type,
            res.res,
    });
}

