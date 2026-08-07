# Changelog

## Unreleased

- Add explicit Kitesurf and default-Chromium Browser Run clients.
- Add rendered-content and bounded binary-screenshot Quick Actions.
- Add Browser Run session and target lifecycle APIs over HTTP.
- Preserve response metadata for browser usage, rate limits, content type, and
  Cloudflare request tracing.
- Send authenticated headers without following redirects and support
  documented empty-body POST operations.
- Add local HTTP integration coverage and an explicit-token live test target.

## 0.1.0 - 2026-07-30

- Initial standalone package extracted from Cloudio.
- Raw Cloudflare v4 HTTP client with API-token and legacy authentication.
- Typed route builders and parsers for the API families used by Cloudio.
- Standalone Zig 0.16 build and test suite.
