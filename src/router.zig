//
// router.zig
// Copyright (C) 2022 Christopher Odom christopher.r.odom@gmail.com
//
// Distributed under terms of the MIT license.
//

//! Defines routes for the media server.
const std = @import("std");
const KB = 1024;
const MB = 1024 * KB;
const GB = 1024 * MB;

pub fn get(uri: []const u8, allocator: std.mem.Allocator) !ServerMedia {
    const content = read_file(uri, allocator) catch |e| {
        return error_404(e);
    };
    const media_type = infer_media(uri) catch |e| {
        return error_404(e);
    };
    return ServerMedia {
        .media_type = media_type,
        .res = content,
    };
}


fn error_404(e: anyerror) ServerMedia {
    return ServerMedia {.response_code = "404 Not Foud", .media_type = "text/text", .res = @errorName(e)};
}

const extension_map = [_][2][]const u8 {
    .{"html", "text/html"},
    .{"txt",  "text/text"},
    .{"ico",  "image/"},
};

fn infer_media(uri: []const u8) ![]const u8 {
    var i: usize = uri.len - 1;
    while(i != 0 and uri[i] != '.') : (i-=1) { }
    const extension = uri[i+1..];
    for(extension_map) |mapping| {
        if(std.mem.eql(u8, extension, mapping[0])) {
            return mapping[0];
        }
    }

    std.log.warn("UnknownMediaType {s}", .{extension});
    return error.UnknownMediaType;
}

// Splats entire file into memory, caller responsible for mem
// Won't work over 3gb
fn read_file(uri: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    const relative_path = try std.mem.concat(allocator, u8, &.{"src/", uri});
    defer allocator.destroy(relative_path.ptr);
    var file_obj = try std.fs.cwd().openFile(relative_path, .{});
    defer file_obj.close();

    var file_contents = try file_obj.readToEndAlloc(allocator, 3 * GB);
    return file_contents;
}

pub const ServerMedia = struct {
    response_code: []const u8 = "200 Ok",
    media_type:    []const u8,
    res:           []const u8,
};
