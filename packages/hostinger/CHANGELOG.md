# Changelog

## Unreleased

- Send empty-body POST actions such as VPS start, stop, and restart; they
  previously tripped a std.http assertion.
- Export `transport` from the package root.

## 0.1.0 - 2026-07-30

- Initial standalone package extracted from Cloudio.
- Raw bearer-authenticated Hostinger HTTP client.
- Typed route builders and parsers for the API families used by Cloudio.
- Standalone Zig 0.16 build and test suite.
