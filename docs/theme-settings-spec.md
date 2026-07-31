# Cloudio Light Theme and Appearance Settings Specification

Status: implemented 2026-07-31 (native form path; HTMX enhancement remains tied to the HTMX port)

Scope: all Cloudio HTML surfaces, including login and passkey setup

Implementation branch: `master`

Related specification: `docs/htmx-port-spec.md`

## 1. Outcome

Cloudio will support three explicit appearance preferences:

| Preference | User-facing meaning | Rendering behavior |
| --- | --- | --- |
| Light | Dark mode off | Always use the light palette |
| Dark | Dark mode on | Always use the dark palette |
| Device | Follow this device | Use the browser/operating-system color preference |

Light is the product default. If the preference is missing, expired, malformed,
or unsupported, Cloudio renders Light. This makes the new white interface the
predictable baseline rather than silently following a dark device.

An authenticated Settings page will expose the three choices as one radio
group. The preference is applied by the server on the next response and is
available on every Cloudio HTML surface, including the login and bootstrap
setup pages.

The implementation must not flash the wrong theme, depend on client-side state,
or require JavaScript to save or apply the preference.

## 2. Design decisions

### 2.1 Use a three-option radio group, not a switch

A binary switch cannot accurately express Light, Dark, and Device. The Settings
page therefore uses a fieldset with three radio controls:

```text
Appearance

(*) Light   Dark mode off. This is Cloudio's default.
( ) Dark    Dark mode on.
( ) Device  Follow this device's appearance setting.

[Save appearance]
```

The visible labels are Light, Dark, and Device. Supporting copy may explain
them in terms of dark mode being off, on, or controlled by the device.

Selection is not persisted until the user submits the form. This avoids
surprising reloads while moving through radio controls and leaves a complete
keyboard/no-JavaScript path.

### 2.2 Persist in a preference cookie, not the database

The first version stores the preference in a small host-only cookie. This is
intentional:

- Cloudio currently has one owner.
- Appearance is naturally browser/device-specific.
- A cookie is available before page rendering.
- No database migration or settings repository is needed.
- Device mode can react to the local device rather than another device's
  preference.

Cross-device synchronization and per-user settings storage are out of scope.
If Cloudio becomes multi-user and measured demand exists, the preference may
move to the user profile later.

### 2.3 Resolve the theme before CSS is parsed

The server parses the preference cookie before rendering any HTML document and
emits one of these trusted root classes:

```html
<html lang="en" class="theme-light">
<html lang="en" class="theme-dark">
<html lang="en" class="theme-system">
```

The class comes from a closed Zig enum, never from raw cookie input.

This is the no-flash boundary. Do not add a local-storage bootstrap script,
inline script, blocking JavaScript, or client-side class correction.

To preserve the shared HTML envelope, add an optional escaped `html_class`
field to `web_html.DocumentOptions` in `web.zig`. Its default is null, so the
change is backward-compatible. Publish that `web.zig` commit and update
Cloudio's exact dependency pin. Do not add an arbitrary trusted-attributes
escape hatch.

Login and setup must also pass through a small server renderer so their root
class can be selected from the cookie before the stylesheet link. Their
WebAuthn behavior remains unchanged.

### 2.4 Device mode is CSS-owned

`theme-system` uses the standards-based media query:

```css
@media (prefers-color-scheme: dark) {
  html.theme-system {
    /* dark semantic tokens */
  }
}
```

Outside that media query, `theme-system` inherits the light palette. A browser
that does not support `prefers-color-scheme` therefore falls back to Light.

The media query responds live when the device preference changes. It requires
no request, event listener, or page reload.

Set the CSS `color-scheme` property alongside each palette so browser-provided
form controls and scrollbars use the correct scheme:

```css
:root,
html.theme-light {
  color-scheme: light;
}

html.theme-dark {
  color-scheme: dark;
}

@media (prefers-color-scheme: dark) {
  html.theme-system {
    color-scheme: dark;
  }
}
```

## 3. Preference contract

### 3.1 Typed representation

Add an application-owned module, preferably `src/server/theme.zig`:

```zig
pub const Preference = enum {
    light,
    dark,
    system,
};
```

Required helpers:

- parse a cookie value into `Preference`;
- return `.light` for absent or invalid values;
- return the fixed root class;
- return the user-facing label and description;
- write/set/clear the preference cookie;
- render the selected radio state.

Do not use arbitrary strings after parsing. Do not add theme behavior to the
domain/application-service layers; appearance belongs at the HTTP/rendering
edge.

### 3.2 Cookie

Production name:

```text
__Host-cloudio_theme
```

Local-development name:

```text
cloudio_theme
```

Allowed values:

```text
light
dark
system
```

Attributes:

```text
Path=/; HttpOnly; SameSite=Strict; Max-Age=31536000; Secure
```

`Secure` is omitted only for the existing localhost/plain-HTTP development
mode. Do not emit `Domain`. The `__Host-` prefix is used only with `Secure` and
`Path=/`.

The cookie is `HttpOnly` because JavaScript never needs it. It contains no
secret, but keeping it unavailable to scripts maintains the existing cookie
discipline.

An absent preference and `light` have the same visual result. Store the
explicit `light` value for clear round-trip behavior and future default
migrations. Invalid values are ignored and treated as Light; they are not
reflected into HTML or CSS.

The preference survives logout because appearance is browser-scoped rather
than session-scoped. Clearing sessions must not clear the theme cookie.

### 3.3 Request timing

Theme parsing happens before:

- authentication redirect decisions;
- authenticated page rendering;
- login rendering;
- bootstrap setup rendering;
- error-page rendering where an HTML document is available.

Theme selection must not affect authorization, route existence, cache keys for
private pages, or API responses. JSON and CLI clients receive no theme data.

## 4. Settings page

### 4.1 Navigation and route

Add Settings to the authenticated primary navigation after Security:

```text
Dashboard
Apps
Routes
DNS
VPS
Docker
Audit
Security
Settings
```

The Cloudio brand remains linked to Dashboard. Settings uses the existing
shell, spacing, typography, focus treatment, panels, and responsive layout.

Routes:

```text
GET  /settings.html
POST /settings/theme
```

`GET /settings.html` is an authenticated, server-rendered page. The current
preference is selected in the returned form. The page does not show the global
provider refresh action.

`POST /settings/theme` is an authenticated HTML form route. It accepts only
`application/x-www-form-urlencoded` and a bounded body. The only preference
field is `theme=light|dark|system`.

### 4.2 Page content

The first version contains one Appearance panel only. Do not add placeholder
account, notification, API token, or advanced sections.

Required content:

- page title: `Settings`;
- intro: `Choose how Cloudio looks in this browser.`;
- panel heading: `Appearance`;
- one radio group with a visible legend;
- Light description: `Dark mode off. Cloudio's default.`;
- Dark description: `Dark mode on.`;
- Device description: `Follow this device's light or dark appearance.`;
- submit button: `Save appearance`;
- concise success/error status region;
- note that the setting applies to this browser.

Each choice should be a full-width clickable label/card on small screens, but
must remain a native radio control. Do not build a custom ARIA radio widget.

No live preview is required. The entire product UI is the preview after save.

### 4.3 Save behavior

The form includes the authenticated session's CSRF token. The handler:

1. requires authentication;
2. requires exact-origin validation;
3. validates the CSRF token in constant time;
4. validates the form content type and bounded body;
5. accepts one closed-enum theme value;
6. writes the preference cookie;
7. returns `303 See Other` to `/settings.html` for a native request.

This preference mutation is naturally idempotent and does not touch provider,
process, or database state. It does not require `app/writes.zig`, an
idempotency record, an audit event, or destructive confirmation.

Use a minimal URL-encoded form decoder shared with the planned HTML/HTMX form
adapter. It must handle percent decoding, `+` as space, duplicate-key policy,
and bounded allocation. Do not introduce a general form framework for three
values.

### 4.4 HTMX enhancement

The native form is authoritative. When the HTMX foundation from
`docs/htmx-port-spec.md` is present, add the enhancement to the same form.

Because changing the root class affects the entire document, a successful HTMX
request returns a `2xx` response with:

```http
HX-Refresh: true
Set-Cookie: __Host-cloudio_theme=...
```

Do not try to patch individual components or run JavaScript to change CSS
variables. The refreshed request carries the new cookie and the server emits
the correct root class before CSS.

Validation/CSRF errors replace only the Settings status/form region and do not
change the cookie. An expired session uses the HTMX authentication redirect
contract from the port specification.

The Settings feature may ship before HTMX. In that sequence, native
Post/Redirect/Get is complete, and HTMX attributes/response handling are added
when the shared UI adapter lands.

## 5. Palette architecture

### 5.1 Semantic tokens

Refactor `web/assets/app.css` so components consume semantic variables only.
The current dark palette becomes the `theme-dark` palette. The new light
palette becomes `:root` and `theme-light`.

Keep the current semantic names where they are sufficient:

```text
--bg
--bg-subtle
--surface
--surface-raised
--surface-hover
--border
--border-strong
--text
--text-muted
--text-subtle
--accent
--accent-hover
--accent-soft
--success
--success-soft
--warning
--warning-soft
--danger
--danger-soft
--shadow
```

Add tokens for dark-specific literals currently embedded in component rules:

```text
--selection-text
--titlebar-bg
--table-divider
--row-hover
--primary-border
--primary-bg
--primary-hover
--danger-border
--danger-hover
--danger-text
--success-text
--warning-text
--info-text
--code-bg
--code-text
--overlay
--login-glow
```

After the refactor, component rules must not contain theme-specific hex or
RGBA colors. Literal colors belong only in palette declarations, apart from
transparent and reviewed browser/system-color fallbacks.

### 5.2 Initial light palette

Use this as the implementation baseline, then adjust only when contrast or
visual regression testing demonstrates a problem:

| Token | Light value |
| --- | --- |
| `--bg` | `#f6f8fa` |
| `--bg-subtle` | `#f0f3f6` |
| `--surface` | `#ffffff` |
| `--surface-raised` | `#ffffff` |
| `--surface-hover` | `#f3f6f9` |
| `--border` | `#d0d7de` |
| `--border-strong` | `#afb8c1` |
| `--text` | `#1f2328` |
| `--text-muted` | `#59636e` |
| `--text-subtle` | `#636c76` |
| `--accent` | `#0969da` |
| `--accent-hover` | `#0550ae` |
| `--accent-soft` | `rgba(9, 105, 218, 0.10)` |
| `--success` | `#1a7f37` |
| `--success-soft` | `rgba(26, 127, 55, 0.10)` |
| `--warning` | `#9a6700` |
| `--warning-soft` | `rgba(154, 103, 0, 0.11)` |
| `--danger` | `#cf222e` |
| `--danger-soft` | `rgba(207, 34, 46, 0.09)` |
| `--shadow` | `0 16px 44px rgba(31, 35, 40, 0.14)` |
| `--titlebar-bg` | `rgba(255, 255, 255, 0.94)` |
| `--table-divider` | `rgba(208, 215, 222, 0.78)` |
| `--row-hover` | `rgba(9, 105, 218, 0.045)` |
| `--code-bg` | `#f6f8fa` |
| `--code-text` | `#24292f` |
| `--overlay` | `rgba(31, 35, 40, 0.36)` |
| `--login-glow` | `rgba(9, 105, 218, 0.08)` |

Primary buttons remain blue with white text. Success, warning, danger, and
information tones must have theme-specific foregrounds rather than reusing the
brighter dark-theme colors on white.

### 5.3 Dark palette

Preserve the current visual design as closely as possible. Move the existing
`:root` values into `html.theme-dark` and the dark branch of
`html.theme-system`. Replace existing component literals with the new semantic
tokens without changing their visual intent.

Dark mode is a compatibility target: screenshots before and after tokenization
should be visually equivalent except for intentional contrast fixes.

### 5.4 Surfaces requiring explicit review

Review every use of color, especially the current raw values in:

- titlebar translucency;
- primary and danger buttons;
- table dividers and hover/selected rows;
- badges and status pills;
- notices, validation, and toast messages;
- log/code viewers;
- dialogs and mobile navigation scrims;
- login/setup gradient and passkey mark;
- focus rings, text selection, placeholders, and disabled controls.

Do not implement Light by applying `filter`, inversion, opacity, or a global
blend mode. Every semantic state gets a deliberate palette.

## 6. Server and file impact

Expected implementation changes:

| File/module | Responsibility |
| --- | --- |
| `web.zig/src/html.zig` | Add optional escaped `html_class` to the document envelope |
| `build.zig.zon` | Pin the reviewed `web.zig` commit containing that field |
| `src/server/theme.zig` | Preference enum, cookie parsing/writing, root class |
| `src/server/pages.zig` | Add Settings page/nav, render selected preference, pass root class |
| `src/server/pipeline.zig` | Resolve theme early; route GET/POST; attach preference cookie |
| `src/server/auth.zig` | Reuse cookie parsing and secure/local naming conventions |
| `src/server/form.zig` | Minimal bounded URL-encoded form parsing if not supplied by UI adapter |
| `src/http/response.zig` | Add the correct `303 See Other` status text used by native PRG |
| `web/settings.html` | Authored Settings page and native form |
| `web/login.html` | Remain source markup but become theme-aware through server rendering |
| `web/setup.html` | Remain source markup but become theme-aware through server rendering |
| `web/assets/app.css` | Light default, preserved dark palette, Device media query |
| `docs/architecture.md` | Document presentation preference at the HTTP/rendering edge |
| `docs/htmx-port-spec.md` | Include Settings as the ninth authenticated page |

Do not add a database repository, application service, JSON settings API,
frontend framework, or theme JavaScript.

## 7. Accessibility requirements

Both palettes must meet WCAG 2.2 AA:

- normal text contrast of at least `4.5:1`;
- large text contrast of at least `3:1`;
- meaningful component boundaries and focus indicators of at least `3:1`
  against adjacent colors;
- visible keyboard focus in every theme;
- no state conveyed by color alone;
- readable placeholders, muted text, badges, notices, and log output;
- usable native controls at 200% zoom;
- no loss of functionality in forced-colors mode.

The theme picker uses native radio semantics, a `<fieldset>`, and `<legend>`.
The selected state remains apparent without relying only on the card border
color.

Do not add animated theme transitions. Large background/color transitions can
cause distracting full-page flashes and make theme changes feel slower.

## 8. Performance and first-view requirements

- No theme JavaScript is loaded.
- No theme API request occurs after first paint.
- No inline style block is generated per request.
- Theme selection adds only a small cookie and one root class.
- CSS remains one cacheable stylesheet.
- Device changes are handled by CSS without network traffic.
- The correct explicit theme is present in the first HTML bytes before the
  stylesheet reference.
- Missing/invalid state renders Light immediately.

The feature must not regress Cloudio's complete server-rendered first view or
introduce a flash of dark/light content.

## 9. Security requirements

- Settings routes are authenticated and default-deny.
- The POST requires exact origin and session CSRF validation.
- The theme cookie is closed-enum, bounded, host-only, `HttpOnly`,
  `SameSite=Strict`, and `Secure` in production.
- Invalid cookie/form values are never reflected.
- Root classes are returned from enum constants and escaped by `web_html`.
- The Content Security Policy remains `script-src 'self'`; no inline script or
  style exception is added.
- Theme selection does not modify session lifetime or WebAuthn policy.
- Error responses do not reveal authentication or cookie internals.

## 10. Verification plan

### 10.1 Unit and contract tests

- missing cookie resolves to Light;
- `light`, `dark`, and `system` resolve to the correct enum/root class;
- malformed, mixed-case, oversized, duplicated, and encoded-invalid values
  resolve to Light or a bounded form error as appropriate;
- secure and local cookie names/attributes are exact;
- theme cookie is not cleared on logout;
- all full documents emit exactly one trusted theme root class;
- the class appears before the stylesheet reference;
- Settings is in the authenticated page allowlist and active navigation;
- anonymous Settings GET/POST is denied consistently;
- POST rejects wrong origin, missing/incorrect CSRF, wrong content type, and
  unsupported theme;
- successful native POST returns `303 /settings.html` and the cookie;
- successful HTMX POST returns `2xx`, the cookie, and `HX-Refresh: true`;
- JSON API output is unchanged;
- no schema migration is added.

### 10.2 CSS audit

- component rules contain no unapproved theme-specific color literals;
- both palette branches define every semantic token;
- Light is the `:root` fallback;
- Device is Light outside the dark media query;
- `color-scheme` matches the active palette;
- contrast checks pass for text, muted text, links, focus, inputs, buttons,
  badges, notices, and statuses;
- print and forced-colors output remain legible.

### 10.3 Visual matrix

Capture desktop and mobile screenshots for Light and Dark, plus Device under
emulated light and dark preferences:

```text
Login
Passkey setup
Dashboard
Apps and deploy detail/log
Routes and preview
DNS and zone tools
VPS and firewalls
Docker and logs
Audit
Security
Settings
Dialog, toast, validation, empty, loading, warning, danger, success states
```

Test the same matrix at 200% zoom and with keyboard-only navigation. Verify
that changing the device preference while Device is selected updates an open
page without reload.

### 10.4 No-flash checks

Under slow network/CPU throttling:

- Light/default never paints dark first;
- explicit Dark never paints light first;
- Device dark never paints light first after CSS is available;
- login/setup honor the same stored choice;
- navigation and HTMX full refreshes do not reset the preference.

### 10.5 Existing gates

The existing repository gates remain mandatory:

```text
zig build test
zig build architecture-check
zig build deploy-smoke
```

Add a focused theme smoke check for the root class, cookie headers, Settings
route, stylesheet availability, and anonymous denial.

## 11. Implementation milestones

### Milestone A: theme foundation

1. Add the typed theme module and cookie tests.
2. Add the minimal `web_html.DocumentOptions.html_class` capability and pin it.
3. Resolve theme before all HTML rendering.
4. Make authenticated, login, and setup documents emit the root class.

Definition of done:

- default and invalid preferences render Light;
- all HTML surfaces render the chosen class before CSS;
- no JavaScript or database change exists;
- cookie/security tests pass.

### Milestone B: light palette

1. Move current dark colors into a dark palette.
2. Add the light default palette.
3. replace component color literals with semantic tokens;
4. add Device media-query behavior and `color-scheme`;
5. complete contrast and visual review.

Definition of done:

- every current component/state is intentional in both palettes;
- existing Dark remains visually coherent;
- Light is the default and looks finished rather than inverted;
- accessibility and no-flash checks pass.

### Milestone C: Settings page

1. Add the page, navigation entry, and selected-state renderer.
2. Add the native authenticated POST with origin/CSRF validation.
3. persist the cookie and redirect back to Settings;
4. add HTMX `HX-Refresh` enhancement when the shared adapter is available;
5. document and smoke-test production behavior.

Definition of done:

- all three choices round-trip correctly;
- preference survives logout and restart;
- native and HTMX paths are complete;
- no unrelated settings or abstractions were added.

## 12. Rollout and rollback

Roll out on `master` in the milestone order above. Deploy the theme foundation
and palette together so no root class references a missing palette. Settings
may land in the same release or immediately after.

Production smoke checks:

1. anonymous Login is Light without a cookie;
2. authenticated Settings shows Light selected initially;
3. Dark save reloads into Dark;
4. Device follows both emulated/device modes;
5. Light save returns to Light;
6. logout/login retains the chosen appearance;
7. API and passkey flows remain unchanged.

Rollback requires no database operation. Revert the Settings route/root class
and restore the previous dark `:root` palette together. The ignored preference
cookie is harmless and can remain until it expires.

## 13. Complete definition of done

The feature is complete only when:

- Light, Dark, and Device are available from an authenticated Settings page;
- Light is the default for missing or invalid state;
- the light palette covers every existing Cloudio surface and interaction
  state;
- the current dark design remains complete and coherent;
- Device follows `prefers-color-scheme` live and falls back to Light;
- the server emits the correct root class before CSS on authenticated, login,
  setup, and HTML error pages;
- no theme flash, client state, theme script, or post-paint theme request
  exists;
- the preference cookie is secure, host-only, typed, and browser-scoped;
- Settings POST enforces authentication, origin, and CSRF;
- native form behavior works without JavaScript;
- HTMX uses a full refresh after persistence rather than patching theme state;
- both palettes pass WCAG 2.2 AA contrast and keyboard/zoom checks;
- no database migration, JSON API, frontend framework, or unnecessary settings
  abstraction was added;
- repository, smoke, deployment, and production checks pass;
- architecture and operations documentation describes the implemented state.

## References

- [W3C Media Queries Level 5: `prefers-color-scheme`](https://www.w3.org/TR/mediaqueries-5/#prefers-color-scheme)
- [W3C CSS Color Adjustment: `color-scheme`](https://www.w3.org/TR/css-color-adjust-1/#color-scheme-prop)
- [WCAG 2.2 contrast requirements](https://www.w3.org/TR/WCAG22/#contrast-minimum)
- [WCAG 2.2 non-text contrast](https://www.w3.org/TR/WCAG22/#non-text-contrast)
