# cloudflare-zig

A small, dependency-free Zig client for the Cloudflare v4 API. It exposes:

- authenticated raw HTTP requests through `Client`;
- typed route builders for the API surface used by Cloudio;
- typed parsers in `cloudflare.models`;
- API-token and legacy email/key authentication.

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

## Development

```sh
zig build test
```

The canonical source lives under `packages/cloudflare` in the Cloudio
monorepo. This repository is a one-way, history-preserving mirror; changes are
made in the monorepo and published to `master`.

Licensed under MIT. See `LICENSE`.
