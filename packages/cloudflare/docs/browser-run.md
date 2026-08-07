# Browser Run and Kitesurf

This package supports the parts of Cloudflare Browser Run that fit a small,
dependency-free HTTP library:

- rendered HTML through `/content`;
- PNG, JPEG, or WebP screenshots through `/screenshot`;
- browser session creation, listing, lookup, and closure;
- target listing and creation within a session.

Kitesurf was announced on August 6, 2026 as a beta browser engine built for
agent workloads. It runs in Workers/V8 isolates and is not Chromium. Cloudflare
describes it as ephemeral, isolated, and efficient for compatible one-shot
rendering and extraction work, but not yet a full-featured or pixel-perfect
browser. Video, WebGL, bot-challenge handshakes that depend on real TLS browser
fingerprints, and long-lived authenticated state are specifically unsuitable.
Kitesurf implements a changing subset of CDP.

Cloudflare's [Kitesurf announcement](https://blog.cloudflare.com/kitesurf/)
documents the new `/browser-run` path and `browser=kitesurf` query parameter.
As of August 7, 2026, the general [API reference](https://developers.cloudflare.com/api/resources/browser_rendering/)
and most [Quick Action documentation](https://developers.cloudflare.com/browser-run/quick-actions/)
still publish the older `/browser-rendering` paths and do not expose Kitesurf
in their generated schemas. The library therefore keeps both choices explicit:

```zig
const kitesurf = try client.browserRun(account_id, .kitesurf);
const chromium = try client.browserRun(account_id, .chromium_default);
```

There is no engine fallback. `.kitesurf` uses `/browser-run` plus
`browser=kitesurf`; `.chromium_default` uses `/browser-rendering` without an
engine query.

## Authentication and ownership

Create a Cloudflare API token with `Browser Rendering - Edit` permission.
Browser Run methods require a non-empty API token and do not fall back to the
legacy email/global-key scheme.

`Client`, credentials, account IDs, request URLs, HTML, cookies, and headers
are borrowed for the duration of a call. Successful results and API failures
own all returned strings, buffers, and selected response headers. Always call
`deinit` with the allocator used for the request.

The following response metadata is retained when Cloudflare sends it:

- `content_type` and `content_length`;
- `X-Browser-Ms-Used` as `browser_ms_used`;
- integer `Retry-After` as `retry_after_seconds`;
- `cf-ray` for request correlation.

The library never logs tokens, destination credentials, cookies, request
headers, response bodies, DevTools URLs, or WebSocket debugger URLs.

## Quick Actions

Rendered content is buffered under the package's 12 MiB JSON response limit:

```zig
var result = try browser.content(io, allocator, .{
    .source = .{ .url = "https://example.com" },
    .options = .{
        .goto = .{ .wait_until = .networkidle2, .timeout_ms = 45_000 },
        .wait_for_selector = .{ .selector = "main", .timeout_ms = 10_000 },
    },
});
defer result.deinit(allocator);
```

Screenshots should normally stream to a file or another bounded sink:

```zig
var result = try browser.screenshotTo(
    io,
    allocator,
    .{
        .source = .{ .html = "<h1>Hello</h1>" },
        .screenshot = .{ .format = .png, .full_page = true },
    },
    writer,
    8 * 1024 * 1024,
);
defer result.deinit(allocator);
```

`screenshotAlloc` provides explicit bounded buffering when the caller needs an
owned byte slice. Binary success bodies are streamed only for documented image
content types. JSON error bodies remain buffered so the caller can inspect
them. A streaming failure can leave partial bytes in the caller's writer;
write to a temporary file first when atomic publication is required.

The common request options intentionally cover the stable, high-value controls:
navigation and action timeouts, selector/time waits, viewport, HTTP basic auth,
cookies, destination headers, user agent, and JavaScript enablement. Screenshot
options cover binary format, quality, full-page capture, transparent background,
viewport overflow, and speed optimization. Cache TTL is validated from 0 to
86,400 seconds and defaults to 0. Timeouts and format/quality combinations are
validated before a network request.

PDF, Markdown, snapshot, accessibility tree, scrape, structured JSON, links,
and crawl are not included yet. They use the same REST model but add substantial
response schemas and product-specific behavior. They should be added from a
real caller rather than exposing an untested mirror of the rapidly changing
beta surface.

## Sessions and CDP boundary

The HTTP lifecycle is available without a WebSocket dependency:

```zig
var created = try browser.createSession(io, allocator, .{
    .keep_alive_ms = 60_000,
});
defer created.deinit(allocator);
```

The module exposes:

- `createSession` (`POST .../devtools/browser`);
- `listSessions` and `getSession`;
- `listTargets` and `newTarget`;
- `closeSession` (`DELETE .../devtools/browser/{session_id}`).

Session and target success bodies use the API reference's bare JSON objects or
arrays; unlike `/content`, they are not Cloudflare `success`/`result` envelopes.
Keep-alive is validated from 10,000 to 600,000 milliseconds. This is a
deliberately conservative beta contract: the generated
[create-session API reference](https://developers.cloudflare.com/api/resources/browser_rendering/subresources/devtools/subresources/browser/methods/create)
currently permits 1,200,000 milliseconds, while the
[Browser Run session guide](https://developers.cloudflare.com/browser-run/cdp/session-management/)
and Puppeteer guide document a ten-minute/600,000-millisecond inactivity
window. The cap can be raised after Cloudflare reconciles those sources and a
live Kitesurf test proves the larger value. Pagination uses the documented
`limit` and `offset` query parameters. Session IDs are escaped as individual
path segments. Callers should close sessions explicitly and use an error-path
cleanup guard after creation.

Full CDP control is intentionally outside this package. The selected Zig
standard library has a WebSocket server but no WebSocket client, and a correct
CDP client needs command-ID correlation, event dispatch, target/session
multiplexing, timeouts, cancellation, message-size limits, backpressure, and
well-defined close behavior. Use a dedicated WebSocket/CDP layer, Puppeteer,
Playwright, or an MCP client with the returned debugger URL. Those consumers
must not assume Kitesurf implements the complete Chromium CDP surface and
should not reconnect or switch engines automatically after protocol failures.

## Security and operations

`TargetPolicy.public_http` is the default. It rejects malformed URLs,
non-HTTP schemes, embedded URL credentials, localhost-like names, and
private/reserved IP literals. This is only local preflight validation. It does
not resolve hostnames and cannot prevent a public name from resolving or
rebinding to a private address at Cloudflare. Enforce an application-specific
allowlist for untrusted destinations and keep Cloudflare-side network controls
in place.

Cookies, basic-auth passwords, destination authorization headers, page content,
and CDP URLs are secrets. Do not include them in audit logs. Log operation,
engine, account alias, duration/usage, HTTP status, byte counts, and `cf-ray`
instead. Browser content is untrusted input; callers feeding it to an AI model
must treat page instructions as data and maintain tool/credential boundaries.

The client does not retry. In particular, it returns HTTP 429 with the raw API
body and parsed integer `Retry-After` value. Retrying browser work can duplicate
billable actions or sessions, so queueing, jitter, quotas, and idempotency policy
belong to the application. Authenticated HTTP requests do not follow redirects,
which prevents credentials from being forwarded to another origin.

Browser Run always identifies its outgoing traffic as automation; changing the
user agent does not bypass bot controls. Respect site policy and applicable
robots rules. Cloudflare documents non-configurable Browser Run headers and
[Web Bot Auth signatures](https://developers.cloudflare.com/browser-run/reference/robots-txt/)
for destination operators, but these are attached by Cloudflare and are not
caller-set request headers.

## Verification

The default suite performs local real-socket integration tests without external
credentials:

```sh
zig build test
```

It verifies authorization, exact paths and query parameters, JSON payloads,
response ownership, PNG streaming, metadata, rate-limit errors, session and
target routes, cleanup responses, and allocator leak checks.

The live test is never run by default. It renders inline HTML, validates PNG
bytes, creates and lists a Kitesurf session and target, and closes the session:

```sh
CLOUDFLARE_BROWSER_RUN_LIVE=1 \
CLOUDFLARE_API_TOKEN=... \
CLOUDFLARE_ACCOUNT_ID=... \
zig build test-browser-run-live
```

It prints only a bounded operational summary and does not print tokens,
response bodies, or debugger URLs.
