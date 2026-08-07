# cloudflare-zig

A small, dependency-free Zig client for the Cloudflare v4 API. It exposes:

- authenticated raw HTTP requests through `Client`;
- typed route builders for the API surface used by Cloudio;
- typed parsers in `cloudflare.models`;
- API-token and legacy email/key authentication;
- Browser Run Quick Actions and HTTP session lifecycle control, including an
  explicit Kitesurf beta engine selection.

The package targets Zig 0.16 and is pre-1.0. Its current scope is deliberately
limited to proven Cloudio callers; additions should follow real use cases.

## Install

Add the repository as a Zig dependency:

```sh
zig fetch --save git+https://github.com/tzekid/cloudflare-zig
```

Then import its public module:

```zig
const dependency = b.dependency("cloudflare", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("cloudflare", dependency.module("cloudflare"));
```

## Use

```zig
const std = @import("std");
const cloudflare = @import("cloudflare");

pub fn main(init: std.process.Init) !void {
    const client = cloudflare.Client.init(.{ .token = "replace-me" });
    const response = try client.getAccounts(init.io, init.gpa);
    defer response.deinit(init.gpa);

    var accounts = try cloudflare.models.parseAccountRows(init.gpa, response.body);
    defer accounts.deinit(init.gpa);
}
```

Credentials are caller-owned slices and are never logged by the library.
Callers must check `response.status` before interpreting response bodies.

## Browser Run and Kitesurf

Kitesurf is Cloudflare's beta, agent-oriented browser engine. Select it
explicitly; the library never changes engines or falls back to Chromium:

```zig
const std = @import("std");
const cloudflare = @import("cloudflare");

pub fn render(io: std.Io, allocator: std.mem.Allocator) !void {
    const client = cloudflare.Client.init(.{ .token = "replace-me" });
    const browser = try client.browserRun("account-id", .kitesurf);

    var content = try browser.content(io, allocator, .{
        .source = .{ .url = "https://example.com" },
    });
    defer content.deinit(allocator);

    switch (content) {
        .ok => |response| std.debug.print("rendered {d} bytes\n", .{response.value.html.len}),
        .api_error => |failure| std.debug.print("Cloudflare returned HTTP {d}\n", .{@intFromEnum(failure.status)}),
    }
}
```

`browser_run.Client` supports rendered HTML, bounded binary screenshots,
session create/list/get/close, and target list/create. An API token with
`Browser Rendering - Edit` permission is required; legacy email/global-key
authentication is intentionally rejected for these new APIs. Returned values
own their strings and byte buffers and must be deinitialized with the same
allocator. Client configuration and request slices are borrowed.

The default target policy rejects non-HTTP schemes, credentials in URLs,
localhost names, and private/reserved IP literals. It cannot prevent DNS
rebinding because Cloudflare resolves the destination remotely; applications
with untrusted URLs should enforce their own hostname allowlist. Quick Action
caching defaults to `0` to avoid credential- or user-specific response reuse.

The package does not implement CDP WebSockets. It returns Cloudflare's session
and target WebSocket URLs, which should be treated as secrets and passed to a
dedicated CDP/WebSocket client. See [the Browser Run guide](docs/browser-run.md)
for screenshot streaming, errors, session cleanup, beta limitations, and the
opt-in live verification command.

## Development

```sh
zig build test
```

The canonical source lives under `packages/cloudflare` in the Cloudio
monorepo. This repository is a one-way, history-preserving mirror; changes are
made in the monorepo and published to `master`.

Licensed under MIT. See `LICENSE`.
