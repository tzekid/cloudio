# hostinger-zig

A small, dependency-free Zig client for the Hostinger public API. It exposes:

- bearer-authenticated raw HTTP requests through `Client`;
- typed route builders for the API surface used by Cloudio;
- typed parsers in `hostinger.models`.

The package targets Zig 0.16 and is pre-1.0. Its current scope is deliberately
limited to proven Cloudio callers; additions should follow real use cases.

## Install

Add the repository as a Zig dependency:

```sh
zig fetch --save git+https://github.com/tzekid/hostinger-zig
```

Then import its public module:

```zig
const dependency = b.dependency("hostinger", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("hostinger", dependency.module("hostinger"));
```

## Use

```zig
const std = @import("std");
const hostinger = @import("hostinger");

pub fn main(init: std.process.Init) !void {
    const client = hostinger.Client.init("replace-me");
    const response = try client.getVirtualMachines(init.io, init.gpa);
    defer response.deinit(init.gpa);

    var machines = try hostinger.models.parseVpsRows(init.gpa, response.body);
    defer machines.deinit(init.gpa);
}
```

Credentials are caller-owned slices and are never logged by the library.
Callers must check `response.status` before interpreting response bodies.

## Development

```sh
zig build test
```

The canonical source lives under `packages/hostinger` in the Cloudio
monorepo. This repository is a one-way, history-preserving mirror; changes are
made in the monorepo and published to `master`.

Licensed under MIT. See `LICENSE`.
