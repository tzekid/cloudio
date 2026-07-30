const std = @import("std");
const response = @import("response.zig");

pub const default_max_file_bytes = 8 * 1024 * 1024;

pub fn serve(
    io: std.Io,
    gpa: std.mem.Allocator,
    root: []const u8,
    request_path: []const u8,
    max_file_bytes: usize,
    out: *std.Io.Writer,
) !void {
    if (!isSafePath(request_path)) {
        try response.write(out, 403, "application/json", "", "{\"error\":\"forbidden\"}\n");
        return;
    }
    const relative = if (std.mem.eql(u8, request_path, "/")) "/index.html" else request_path;
    const full = try std.fmt.allocPrint(gpa, "{s}{s}", .{ root, relative });
    defer gpa.free(full);
    const data = std.Io.Dir.cwd().readFileAlloc(io, full, gpa, .limited(max_file_bytes)) catch |err| switch (err) {
        error.FileNotFound, error.IsDir, error.AccessDenied => {
            try response.write(out, 404, "application/json", "", "{\"error\":\"not_found\"}\n");
            return;
        },
        else => |e| return e,
    };
    defer gpa.free(data);
    try response.write(out, 200, contentType(relative), "", data);
}

pub fn isSafePath(path: []const u8) bool {
    return std.mem.indexOf(u8, path, "..") == null;
}

pub fn contentType(path: []const u8) []const u8 {
    const ext = std.fs.path.extension(path);
    const map = .{
        .{ ".html", "text/html; charset=utf-8" },
        .{ ".css", "text/css" },
        .{ ".js", "text/javascript" },
        .{ ".svg", "image/svg+xml" },
        .{ ".png", "image/png" },
        .{ ".ico", "image/x-icon" },
        .{ ".json", "application/json" },
    };
    inline for (map) |entry| {
        if (std.mem.eql(u8, ext, entry[0])) return entry[1];
    }
    return "application/octet-stream";
}

test "static path and content type policies are generic" {
    try std.testing.expect(isSafePath("/assets/app.js"));
    try std.testing.expect(!isSafePath("/../secret"));
    try std.testing.expectEqualStrings("text/javascript", contentType("/app.js"));
}
