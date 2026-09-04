import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import process from "node:process";

const root = resolve(import.meta.dirname, "..");
const authenticatedPages = [
  "index.html",
  "projects.html",
  "routes.html",
  "dns.html",
  "browser.html",
  "vps.html",
  "docker.html",
  "audit.html",
  "security.html",
  "settings.html",
];
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

for (const filename of authenticatedPages) {
  const html = read(`web/${filename}`);
  checkHtmlBasics(filename, html);
  check(html.includes('defer src="/assets/app.js"'), `${filename}: missing deferred shared script`);
  if (filename === "security.html") {
    check(html.includes('defer src="/assets/passkeys.js"'), "security.html: missing shared passkey adapter");
    check(html.includes('defer src="/assets/pages/security.js"'), "security.html: missing bounded credential island");
  } else {
    check(!html.includes('defer src="/assets/pages/'), `${filename}: unnecessary page script must be removed`);
  }
  check(/<main\b[^>]*\bid="page-content"/i.test(html), `${filename}: missing #page-content`);
  check(!/<(?:aside|nav)\b/i.test(html), `${filename}: authored template must not duplicate the server shell`);
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
const loginScript = read("web/assets/pages/login.js");
const routesHtml = read("web/routes.html");
const securityHtml = read("web/security.html");
const securityScript = read("web/assets/pages/security.js");
const pageRenderer = read("src/server/pages.zig");
const routeSource = read("src/server/routes.zig");
const routeInventory = read("docs/http-route-inventory.md");
check(/class="brand" href="\/" aria-label="Cloudio dashboard"/.test(pageRenderer), "pages.zig: Cloudio brand must be an accessible dashboard link");
check(!/\bfetch\s*\(|window\.cloudio|\bdialog\b/.test(appScript), "app.js: shared shell must not own page-specific API or dialog behavior");
check(!/api\/auth\/session/.test(loginScript), "login.js: authenticated login redirects belong to the server, not a startup session probe");
check(/id="routes-empty" class="panel-body route-empty-state"/.test(routesHtml), "routes.html: purposeful zero-route state is missing");
check(/id="routes-adoption-panel" class="panel hidden"/.test(routesHtml), "routes.html: adoption must be hidden until candidates exist");
check(/id="routes-preview-panel" class="panel hidden"/.test(routesHtml), "routes.html: apply preview must be hidden until changes exist");
check(/class="route-form-actions span-2"/.test(routesHtml), "routes.html: route actions need a bounded grid column");
check(/X-Cloudio-CSRF/.test(securityScript), "security.js: credential mutations must use the server-rendered CSRF token");
check(!/window\.cloudio\b|window\.confirm\s*\(/.test(securityScript), "security.js: global app facade and native confirmation fallback are forbidden");
check(/id="toast-region"/.test(securityHtml), "security.html: credential notification region is missing");
check(/<dialog\b[^>]*aria-labelledby="revoke-dialog-title"/.test(securityHtml), "security.html: revoke dialog is missing");
check(/<form\b[^>]*method="dialog"/.test(securityHtml), "security.html: revoke dialog must use native dialog form behavior");
check(!/toast-region|confirm-dialog-title/.test(pageRenderer), "pages.zig: shared shell must not inject Security-only controls");
check(/id="app-shell"/.test(pageRenderer), "pages.zig: server-rendered application shell is missing");

const jsonRoutes = [...routeSource.matchAll(/(?:route|publicRoute|mutation)\("([A-Z]+)", "([^"]+)"/g)];
check(jsonRoutes.length > 0, "routes.zig: no JSON routes found");
for (const [, method, path] of jsonRoutes) {
  check(routeInventory.includes(`\`${method} ${path}\``), `http-route-inventory.md: missing ${method} ${path}`);
}

const pageScripts = ["security.js", "login.js", "setup.js"].map((name) => `web/assets/pages/${name}`);
for (const relativePath of ["web/assets/app.js", "web/assets/passkeys.js", ...pageScripts]) {
  const source = read(relativePath);
  check(!/\.(innerHTML|outerHTML)\s*=|insertAdjacentHTML|document\.write\s*\(/.test(source), `${relativePath}: unsafe dynamic HTML construction is forbidden`);
  check(!/\bEventSource\b/.test(source), `${relativePath}: SSE/EventSource is outside the bounded frontend architecture`);
  const syntax = spawnSync(process.execPath, ["--check", join(root, relativePath)], { encoding: "utf8" });
  check(syntax.status === 0, `${relativePath}: JavaScript syntax check failed\n${syntax.stderr.trim()}`);
}

check(!/api\("\/api\/auth\/credentials"\s*[,)]/.test(securityScript), "security.js: initial credential state must remain server-owned");

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

if (errors.length) {
  for (const error of errors) process.stderr.write(`web-ui-check: ${error}\n`);
  process.exit(1);
}

process.stdout.write(`web-ui-check: ${authenticatedPages.length} authenticated pages, login/setup, shared UI, and ${pageScripts.length + 2} scripts passed\n`);
