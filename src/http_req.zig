//
// http_req.zig
// Copyright (C) 2022 MYNAME <EMAIL>
//
// Distributed under terms of the MIT license.
//
const std = @import("std");
const StreamServer = std.net.StreamServer;
const Address = std.net.Address;


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
    var buf = try std.heap.page_allocator.alloc(u8, 2048);
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
