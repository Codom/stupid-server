//
// content.zig
// Copyright (C) 2022 Christopher Odom christopher.r.odom@gmail.com
//
// Distributed under terms of the MIT license.
//

//! This simply packages all of the server conent directly
//! into the binary using the @embedfile() builtin and a
//! compile-time generated hash map.
const std = @import("std");

pub const server_content = std.ComptimeStringMap(ServerMedia, .{
    .{"/index.html", .{.media_type  = "text/html", .res = @embedFile("index.html")}},
    .{"/favicon.ico", .{.media_type = "image/", .res = @embedFile("favicon.ico")}},
});

pub const ServerMedia = struct {
    media_type: []const u8,
    res: []const u8,
};
