const std = @import("std");
const app_evidence = @import("app_evidence");
const cli_args = @import("cli_args");
const cli_render = @import("cli_render");
const db_store = @import("db_store");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const Io = std.Io;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    db: *Db,
};

const Parsed = struct {
    options: app_evidence.Options = .{},
    format: cli_render.RenderFormat = .text,
};

pub fn run(ctx: Context, args: []const []const u8) !void {
    const parsed = parse(args) catch |err| {
        std.debug.print("invalid evidence command: {s}\n", .{@errorName(err)});
        return err;
    };
    try cli_render.printFormatted(ctx.io, ctx.gpa, parsed.format, app_evidence.writeText, app_evidence.writeJson, .{ appContext(ctx), parsed.options });
}

fn appContext(ctx: Context) app_evidence.Context {
    return .{
        .gpa = ctx.gpa,
        .db = ctx.db,
    };
}

fn parse(args: []const []const u8) !Parsed {
    var parsed = Parsed{};
    var provider_seen = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        if (try cli_args.parseFormatOption(args, &index, &parsed.format, error.MissingFormat, error.InvalidFormat)) continue;
        if (try cli_args.parsePositiveI64Arg(args, &index, .{"--limit"}, error.MissingEvidenceLimit, error.InvalidEvidenceLimit)) |limit| {
            parsed.options.limit = limit;
            continue;
        }
        if (try cli_args.parseRequiredValueArg(args, &index, .{"--provider"}, error.MissingEvidenceProvider)) |value| {
            parsed.options.provider = app_evidence.ProviderFilter.parse(value) orelse return error.InvalidEvidenceProvider;
            provider_seen = true;
            continue;
        }

        const arg = args[index];
        if (!provider_seen) {
            if (app_evidence.ProviderFilter.parse(arg)) |provider| {
                parsed.options.provider = provider;
                provider_seen = true;
                continue;
            }
        }
        return error.UnexpectedEvidenceArgument;
    }
    return parsed;
}

test "evidence parser accepts provider limit and format" {
    const defaults_args = [_][]const u8{};
    const defaults = try parse(defaults_args[0..]);
    try std.testing.expectEqual(app_evidence.ProviderFilter.all, defaults.options.provider);
    try std.testing.expectEqual(@as(i64, app_evidence.default_limit), defaults.options.limit);
    try std.testing.expectEqual(cli_render.RenderFormat.text, defaults.format);

    const args = [_][]const u8{ "hostinger", "--limit=5", "--json" };
    const parsed = try parse(args[0..]);
    try std.testing.expectEqual(app_evidence.ProviderFilter.hostinger, parsed.options.provider);
    try std.testing.expectEqual(@as(i64, 5), parsed.options.limit);
    try std.testing.expectEqual(cli_render.RenderFormat.json, parsed.format);

    const flag_args = [_][]const u8{ "--provider", "cloudflare", "--format", "json" };
    const flags = try parse(flag_args[0..]);
    try std.testing.expectEqual(app_evidence.ProviderFilter.cloudflare, flags.options.provider);
    try std.testing.expectEqual(cli_render.RenderFormat.json, flags.format);
}

test "evidence parser rejects invalid options" {
    const invalid_provider = [_][]const u8{ "--provider", "other" };
    try std.testing.expectError(error.InvalidEvidenceProvider, parse(invalid_provider[0..]));

    const invalid_limit = [_][]const u8{"--limit=0"};
    try std.testing.expectError(error.InvalidEvidenceLimit, parse(invalid_limit[0..]));

    const unexpected = [_][]const u8{"extra"};
    try std.testing.expectError(error.UnexpectedEvidenceArgument, parse(unexpected[0..]));
}
