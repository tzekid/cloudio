const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const repoDir = path.resolve(__dirname, "..");
const { chromium } = require(path.join(
  repoDir,
  ".zig-cache/browser-e2e/node_modules/playwright-core",
));

const [origin, setupUrl, storageStatePath] = process.argv.slice(2);
if (!origin || !setupUrl || !storageStatePath) {
  throw new Error("usage: node tests/browser-smoke.cjs ORIGIN SETUP_URL STORAGE_STATE");
}

const browserCandidates = [
  process.env.CLOUDIO_CHROMIUM_PATH,
  "/usr/bin/google-chrome",
  "/usr/bin/google-chrome-stable",
  "/usr/bin/chromium",
  "/usr/bin/chromium-browser",
].filter(Boolean);
const executablePath = browserCandidates.find((candidate) => fs.existsSync(candidate));
if (!executablePath) {
  throw new Error("set CLOUDIO_CHROMIUM_PATH to an installed Chromium executable");
}

const privatePages = [
  ["/", 'form[method="get"][action="/"]'],
  ["/apps.html", "#app-form"],
  ["/routes.html", "#route-form"],
  ["/dns.html", 'form[method="get"][action="/dns.html"]'],
  ["/vps.html", "#rule-form"],
  ["/docker.html", "#reload-containers"],
  ["/audit.html", 'form[method="get"][action="/audit.html"]'],
  ["/security.html", "#add-passkey"],
  ["/settings.html", 'form[action="/settings/theme"]'],
];

function observePage(page, errors) {
  page.on("console", (message) => {
    if (message.type() === "error") {
      const location = message.location();
      const expectedHttpRejection =
        (location.url === `${origin}/api/refresh` && message.text().includes("403")) ||
        (location.url === `${origin}/api/auth/session` && message.text().includes("401"));
      if (expectedHttpRejection) return;
      errors.push(`console: ${location.url || "unknown"} ${message.text()}`);
    }
  });
  page.on("pageerror", (error) => errors.push(`page: ${error.message}`));
  page.on("requestfailed", (request) => {
    errors.push(`request: ${request.url()} ${request.failure()?.errorText || "failed"}`);
  });
}

async function assertRendered(page, controlSelector) {
  assert.equal(await page.locator("#app-shell").count(), 1);
  assert.equal(await page.locator("#page-content").isVisible(), true);
  assert.equal(await page.locator(".loading-state").count(), 0);
  assert.ok((await page.locator("#page-content").innerText()).trim().length > 20);
  assert.equal(await page.locator(controlSelector).count() > 0, true, `missing native control ${controlSelector}`);
  assert.deepEqual(await page.evaluate(() => window.__cspViolations || []), []);
}

async function enrollAndCheckEnhanced(browser) {
  const context = await browser.newContext();
  await context.addInitScript(() => {
    window.__cspViolations = [];
    document.addEventListener("securitypolicyviolation", (event) => {
      window.__cspViolations.push(`${event.violatedDirective}: ${event.blockedURI}`);
    });
  });
  const page = await context.newPage();
  const errors = [];
  observePage(page, errors);
  const cdp = await context.newCDPSession(page);
  await cdp.send("WebAuthn.enable");
  await cdp.send("WebAuthn.addVirtualAuthenticator", {
    options: {
      protocol: "ctap2",
      transport: "internal",
      hasResidentKey: true,
      hasUserVerification: true,
      isUserVerified: true,
      automaticPresenceSimulation: true,
    },
  });

  let response = await page.goto(setupUrl, { waitUntil: "load" });
  assert.equal(response.status(), 200);
  await Promise.all([
    page.waitForURL(`${origin}/security.html`),
    page.locator("#setup-button").click(),
  ]);
  assert.equal(await page.locator('[data-action="rename"]').count(), 1);
  assert.equal(await page.locator('[data-action="revoke"]').count(), 1);

  let startupRequests = null;
  page.on("request", (request) => {
    if (!startupRequests || !["fetch", "xhr"].includes(request.resourceType())) return;
    startupRequests.push(request.url());
  });
  for (const [urlPath, control] of privatePages) {
    startupRequests = [];
    response = await page.goto(`${origin}${urlPath}`, { waitUntil: "load" });
    assert.equal(response.status(), 200, urlPath);
    await page.waitForTimeout(75);
    const observed = startupRequests;
    startupRequests = null;
    assert.deepEqual(observed, [], `${urlPath} performed a startup API request`);
    await assertRendered(page, control);
  }

  await page.goto(`${origin}/apps.html`, { waitUntil: "load" });
  assert.ok(await page.locator('[data-action="deploy"][data-app="fixture-app"]').count());
  await page.goto(`${origin}/routes.html`, { waitUntil: "load" });
  assert.ok(await page.locator('[data-toggle-host="fixture.example.test"]').count());
  assert.ok(await page.locator('[data-delete-host="fixture.example.test"]').count());
  await page.goto(`${origin}/docker.html`, { waitUntil: "load" });
  assert.ok(await page.locator('[data-select-container="fixture-web"]').count());
  assert.ok(await page.locator('[data-container-action="restart"][data-container-name="fixture-web"]').count());

  const rejected = await page.evaluate(() => fetch("/api/refresh", {
    method: "POST",
    credentials: "same-origin",
    headers: { Accept: "application/json" },
  }).then((result) => result.status));
  assert.equal(rejected, 403, "unsafe requests without CSRF must remain rejected");

  await page.goto(`${origin}/security.html`, { waitUntil: "load" });
  await Promise.all([
    page.waitForURL(`${origin}/login.html`),
    page.locator("#sign-out").click(),
  ]);
  await Promise.all([
    page.waitForURL(`${origin}/`),
    page.locator("#login-button").click(),
  ]);
  assert.equal(await page.locator("#page-title").textContent(), "Dashboard");
  await context.storageState({ path: storageStatePath });
  assert.deepEqual(errors, []);
  await context.close();
}

async function checkBaseline(browser) {
  const context = await browser.newContext({
    javaScriptEnabled: false,
    storageState: storageStatePath,
  });
  const page = await context.newPage();
  for (const [urlPath, control] of privatePages) {
    const response = await page.goto(`${origin}${urlPath}`, { waitUntil: "load" });
    assert.equal(response.status(), 200, urlPath);
    await assertRendered(page, control);
  }

  await page.goto(`${origin}/`, { waitUntil: "load" });
  await page.locator("#domain-filter").fill("first.example");
  await page.locator("#issues-only").check();
  await Promise.all([
    page.waitForURL((url) => url.pathname === "/" && url.searchParams.get("domain") === "first.example" && url.searchParams.get("issues") === "1"),
    page.locator("#dashboard-reload").click(),
  ]);
  assert.equal(await page.locator("#domain-filter").inputValue(), "first.example");
  assert.equal(await page.locator("#issues-only").isChecked(), true);

  await page.goto(`${origin}/audit.html?limit=50`, { waitUntil: "load" });
  assert.equal(await page.locator("#audit-body > tr").count(), 50);
  await page.locator("#audit-limit").selectOption("100");
  await Promise.all([
    page.waitForURL((url) => url.pathname === "/audit.html" && url.searchParams.get("limit") === "100"),
    page.locator("#reload-audit").click(),
  ]);
  assert.equal(await page.locator("#audit-body > tr").count(), 75);
  await page.locator("#audit-limit").selectOption("50");
  await Promise.all([
    page.waitForURL((url) => url.pathname === "/audit.html" && url.searchParams.get("limit") === "50"),
    page.locator("#reload-audit").click(),
  ]);
  assert.equal(await page.locator("#audit-body > tr").count(), 50);
  await context.close();
}

(async () => {
  const browser = await chromium.launch({ executablePath, headless: true });
  try {
    await enrollAndCheckEnhanced(browser);
    await checkBaseline(browser);
  } finally {
    await browser.close();
  }
  console.log("Cloudio browser smoke checks passed");
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
