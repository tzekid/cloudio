import { readFileSync, existsSync } from "node:fs";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import process from "node:process";

const root = resolve(import.meta.dirname, "..");
const webRoot = join(root, "web");
const authenticatedPages = new Map([
  ["index.html", "dashboard.js"],
  ["apps.html", "apps.js"],
  ["routes.html", "routes.js"],
  ["dns.html", "dns.js"],
  ["vps.html", "vps.js"],
  ["docker.html", "docker.js"],
  ["audit.html", "audit.js"],
  ["security.html", "security.js"],
  ["settings.html", "settings.js"],
]);
const errors = [];

function check(condition, message) {
  if (!condition) errors.push(message);
}

function read(relativePath) {
  return readFileSync(join(root, relativePath), "utf8");
}

function checkHtmlBasics(filename, html) {
  check(/<title>[^<]+<\/title>/i.test(html), `${filename}: missing a non-empty title`);
  check(/<meta\s+name="viewport"\s+content="width=device-width,\s*initial-scale=1">/i.test(html), `${filename}: missing the standard viewport`);
  check(html.includes('href="/assets/app.css"'), `${filename}: missing the shared stylesheet`);
  check(!/<style\b/i.test(html), `${filename}: inline <style> is forbidden`);
  check(!/\sstyle\s*=/i.test(html), `${filename}: style attributes are forbidden`);
  check(!/<script\b(?![^>]*\bsrc\s*=)[^>]*>/i.test(html), `${filename}: inline scripts are forbidden`);
  check(!/\son[a-z]+\s*=/i.test(html), `${filename}: inline event handlers are forbidden`);
  check(!/data-(signals|bind|show|on|attr)/i.test(html), `${filename}: Datastar attributes are forbidden`);
  check(!/datastar/i.test(html), `${filename}: Datastar imports are forbidden`);

  const controls = html.matchAll(/<(input|select|textarea)\b([^>]*)>/gi);
  for (const match of controls) {
    const attributes = match[2];
    if (/\btype="hidden"/i.test(attributes)) continue;
    const idMatch = attributes.match(/\bid="([^"]+)"/i);
    check(Boolean(idMatch), `${filename}: every form control must have an id`);
    if (idMatch) {
      const escapedId = idMatch[1].replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      check(new RegExp(`<label\\b[^>]*\\bfor="${escapedId}"`, "i").test(html), `${filename}: #${idMatch[1]} has no associated label`);
    }
  }
}

for (const [filename, pageScript] of authenticatedPages) {
  const html = read(`web/${filename}`);
  checkHtmlBasics(filename, html);
  check(html.includes('defer src="/assets/app.js"'), `${filename}: missing deferred shared script`);
  check(html.includes(`defer src="/assets/pages/${pageScript}"`), `${filename}: missing deferred page script`);
  check(/<main\b[^>]*\bid="page-content"/i.test(html), `${filename}: missing #page-content`);
  check(!/<(?:aside|nav)\b/i.test(html), `${filename}: application navigation must come only from app.js`);
  check(!/\bclass="[^"]*\bsidebar\b/i.test(html), `${filename}: duplicated sidebar markup`);
}

const loginHtml = read("web/login.html");
checkHtmlBasics("login.html", loginHtml);
check(loginHtml.includes('defer src="/assets/pages/login.js"'), "login.html: missing deferred login script");
check(loginHtml.includes('defer src="/assets/passkeys.js"'), "login.html: missing shared passkey adapter");

const setupHtml = read("web/setup.html");
checkHtmlBasics("setup.html", setupHtml);
check(setupHtml.includes('defer src="/assets/passkeys.js"'), "setup.html: missing shared passkey adapter");
check(setupHtml.includes('defer src="/assets/pages/setup.js"'), "setup.html: missing deferred setup script");

const appScript = read("web/assets/app.js");
const pageRenderer = read("src/server/pages.zig");
check(/href:\s*"\/"/.test(appScript), "app.js: Cloudio brand must link to /");
check(/"aria-label":\s*"Cloudio dashboard"/.test(appScript), "app.js: Cloudio brand needs an accessible dashboard label");
check(/function\s+confirmAction/.test(appScript), "app.js: shared confirmation dialog helper is missing");
check(/function\s+api/.test(appScript), "app.js: shared API wrapper is missing");
check(/id="app-shell"/.test(pageRenderer), "pages.zig: server-rendered application shell is missing");
check(/injectPageData/.test(pageRenderer), "pages.zig: server-rendered first-view data adapter is missing");
check(/web_html\.text/.test(pageRenderer), "pages.zig: dynamic HTML must use context-safe escaping");

const pageScripts = [...authenticatedPages.values(), "login.js", "setup.js"].map((name) => `web/assets/pages/${name}`);
for (const relativePath of ["web/assets/app.js", "web/assets/passkeys.js", ...pageScripts]) {
  const source = read(relativePath);
  check(!/\.(innerHTML|outerHTML)\s*=|insertAdjacentHTML|document\.write\s*\(/.test(source), `${relativePath}: unsafe dynamic HTML construction is forbidden`);
  check(!/\bEventSource\b/.test(source), `${relativePath}: SSE/EventSource is outside the bounded frontend architecture`);
  const syntax = spawnSync(process.execPath, ["--check", join(root, relativePath)], { encoding: "utf8" });
  check(syntax.status === 0, `${relativePath}: JavaScript syntax check failed\n${syntax.stderr.trim()}`);
}

const css = read("web/assets/app.css");
check(css.includes(":focus-visible"), "app.css: visible keyboard focus styling is missing");
check(css.includes("dialog::backdrop"), "app.css: confirmation dialog styling is missing");
check(css.includes("@media (max-width: 720px)"), "app.css: mobile navigation breakpoint is missing");
check(css.includes("@media (prefers-reduced-motion: reduce)"), "app.css: reduced-motion handling is missing");
check(css.includes("html.theme-light"), "app.css: explicit light palette is missing");
check(css.includes("html.theme-dark"), "app.css: explicit dark palette is missing");
check(css.includes("html.theme-system"), "app.css: device palette is missing");
const componentCss = css.slice(css.indexOf("\n* {"));
check(!/(?:#[0-9a-f]{3,8}|rgba?\()/i.test(componentCss), "app.css: component colors must use semantic palette tokens");
check(!existsSync(join(webRoot, "assets", "datastar.js")), "web/assets/datastar.js must be removed");

if (errors.length) {
  for (const error of errors) process.stderr.write(`web-ui-check: ${error}\n`);
  process.exit(1);
}

process.stdout.write(`web-ui-check: ${authenticatedPages.size} authenticated pages, login/setup, shared UI, and ${pageScripts.length + 2} scripts passed\n`);
