// Static checks the browser acceptance test cannot see: authored templates
// keep labelled controls and no inline code, and browser scripts parse and
// never build HTML from strings.
import { readdirSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import process from "node:process";

const root = resolve(import.meta.dirname, "..");
const errors = [];

function check(condition, message) {
  if (!condition) errors.push(message);
}

for (const filename of readdirSync(join(root, "web")).filter((name) => name.endsWith(".html"))) {
  const html = readFileSync(join(root, "web", filename), "utf8");
  check(/<title>[^<]+<\/title>/i.test(html), `${filename}: missing a non-empty title`);
  check(!/<style\b|\sstyle\s*=/i.test(html), `${filename}: inline styles are forbidden by the CSP`);
  check(!/<script\b(?![^>]*\bsrc\s*=)[^>]*>|\son[a-z]+\s*=/i.test(html), `${filename}: inline scripts are forbidden by the CSP`);
  for (const [, attributes] of html.matchAll(/<(?:input|select|textarea)\b([^>]*)>/gi)) {
    if (/\btype="hidden"/i.test(attributes)) continue;
    const id = attributes.match(/\bid="([^"]+)"/i)?.[1];
    check(Boolean(id) && html.includes(`for="${id}"`), `${filename}: every visible form control needs a label`);
  }
}

const scripts = ["web/assets/app.js", "web/assets/passkeys.js", ...readdirSync(join(root, "web/assets/pages")).map((name) => `web/assets/pages/${name}`)];
for (const relativePath of scripts) {
  const source = readFileSync(join(root, relativePath), "utf8");
  check(!/\.(innerHTML|outerHTML)\s*=|insertAdjacentHTML|document\.write\s*\(/.test(source), `${relativePath}: unsafe dynamic HTML construction is forbidden`);
  const syntax = spawnSync(process.execPath, ["--check", join(root, relativePath)], { encoding: "utf8" });
  check(syntax.status === 0, `${relativePath}: JavaScript syntax check failed\n${syntax.stderr.trim()}`);
}

if (errors.length) {
  for (const error of errors) process.stderr.write(`web-ui-check: ${error}\n`);
  process.exit(1);
}
console.log(`web-ui-check: ${scripts.length} scripts and all templates passed`);
