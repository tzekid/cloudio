# Third-party notices

Cloudio depends on the following third-party software:

## Passcay

- Project: [uzyn/passcay](https://github.com/uzyn/passcay)
- Version: 3.1.0
- Commit: `a448bfa5613b68897e12de11e784a1d7721233a4`
- License: MIT
- Copyright: © 2025-2026 Uzyn Chua

Passcay is used to verify WebAuthn registration and authentication
ceremonies. Cloudio pins the exact reviewed release in `build.zig.zon`.

The full license text is available in the upstream
[LICENSE](https://github.com/uzyn/passcay/blob/3.1.0/LICENSE) file.

## zbor

- Project: [r4gus/zbor](https://codeberg.org/r4gus/zbor)
- Version: 0.21.2
- Commit: `658c1c0ec607557b52d2e2a42acbfad31058ecee`
- License: MIT

zbor parses the algorithm identifier from the verified passkey's COSE public
key so Cloudio can enforce its deliberately narrow ES256/RS256 policy.
