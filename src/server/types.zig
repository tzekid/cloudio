const std = @import("std");
const http = @import("http");
const context = @import("context.zig");

pub const BufferedHandler = *const fn (
    context.Context,
    http.Request,
    http.Params,
    *std.Io.Writer,
    *std.Io.Writer,
) anyerror!u16;

pub const StreamHandler = *const fn (
    context.Context,
    http.Request,
    http.Params,
    *std.Io.Writer,
) anyerror!void;

pub const Handler = union(enum) {
    buffered: BufferedHandler,
    stream: StreamHandler,
};

pub const Access = enum { authenticated, public };
pub const Mutation = enum { none, idempotent, destructive };

pub const Route = struct {
    method: []const u8,
    pattern: []const u8,
    handler: Handler,
    access: Access = .authenticated,
    mutation: Mutation = .none,
};
