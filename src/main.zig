//
// content.zig
// Copyright (C) 2022 Christopher Odom christopher.r.odom@gmail.com
//
// Distributed under terms of the MIT license.
//

//! Entrypoint to the stupid web server.
//! Also contains req processing primitives
//!
//! This isn't designed for any purpose other than
//! to show prospective employers that I know how to
//! computers.
//!

const std = @import("std");
const resources = @import("content.zig").server_content;


const StreamServer = std.net.StreamServer;
const Address = std.net.Address;

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
    _ = try stdin.readUntilDelimiterOrEofAlloc(std.heap.page_allocator, '\n', 1024);
    keep_alive = false;
    server.close();
    std.log.info("Closing server...", .{});
    for(threads) |*t| {
        t.join();
    }
}

/// Only supports plain text for now
fn process_ok_response(content_type: []const u8, content: []const u8, con: StreamServer.Connection) !void {
    // const date = "Wed, 17 Aug 2021 16:48:48 GMT";
    const len = content.len;
    var writer = con.stream.writer();
    try writer.print(
        \\HTTP/1.1 200 OK
        \\Server: stupid server
        \\Content-length {d}
        \\Content-Type: {s}
        \\
        \\{s}
        , .{
            len,
            content_type,
            content,
    });
}

fn process_404(con: StreamServer.Connection) !void {
    var writer = con.stream.writer();
    try writer.print(
        \\HTTP/1.1 404 Not Found
        \\Server: stupid server
        \\Content-length 0 
        \\Content-Type: text/plain
        , .{
        });
} 

var keep_alive: bool = true;
pub fn thread_main(id: usize, server: *StreamServer) !void {
    while(keep_alive) {
        // Process reqs
        var con = try server.accept();
        defer { 
            con.stream.close();
            std.log.info("Closed connection on thead {d}", .{id});
        }
        var req = try HttpReq.parse(con);
        defer req.deinit();

        std.log.info("Thread {d} responding to {{ {s} {s} }}", .{id, req.method, req.path});
        const res = resources.get(req.path) orelse {
            try process_404(con);
            continue;
        };
        try process_ok_response(res.media_type, res.res, con);
    }
}

const HttpReq = struct {
    buf: []const u8,
    header: []const u8,

    // Parsed attributes from the header
    method: []const u8,
    path: []const u8,

    /// Parses from an open connection and returns a single request
    /// Upon return it is the callers responsibility
    /// to free (ie through deinit())
    pub fn parse(con: StreamServer.Connection) !@This() {
        var reader = con.stream.reader();
        var buf = try std.heap.page_allocator.alloc(u8, 1024*1024);
        errdefer std.heap.page_allocator.destroy(buf.ptr);
        var req_size = try reader.read(buf);

        // Request line parsing
        var i: usize = 0;
        // Method
        while(buf[i] == ' ') : (i+=1) {}
        const method_start = i;
        while(buf[i] != ' ') : (i+=1) {}
        const method_end = i;
        const method_string = buf[method_start..method_end];
        // Uri
        while(buf[i] == ' ') : (i+=1) {}
        const uri_start = i;
        while(buf[i] != ' ') : (i+=1) {}
        const uri_end = i;
        const uri_string = buf[uri_start..uri_end];
        // Version
        // Probably shouldn't ignore the rest but lazy

        return @This() {
            .buf = buf,
            .header = buf[0..req_size],
            .method = method_string,
            .path = uri_string,
        };
    }

    pub fn deinit(self: *@This()) void {
        std.heap.page_allocator.destroy(self.buf.ptr);
    }
};

test "Test" {
    return;
}
