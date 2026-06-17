const std = @import("std");
const cli_root = @import("cli_root");

pub fn main(init: std.process.Init) !void {
    try cli_root.run(init);
}
