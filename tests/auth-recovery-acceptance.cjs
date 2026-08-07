const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const repoDir = path.resolve(__dirname, "..");
const { chromium } = require(path.join(
  repoDir,
  ".zig-cache/browser-e2e/node_modules/playwright-core",
));

const [origin, setupUrl, oldStorageState] = process.argv.slice(2);
if (!origin || !setupUrl || !oldStorageState) {
  throw new Error("usage: node tests/auth-recovery-acceptance.cjs ORIGIN SETUP_URL OLD_STORAGE_STATE");
}

const browserCandidates = [
  process.env.CLOUDIO_CHROMIUM_PATH,
  "/usr/bin/google-chrome",
  "/usr/bin/google-chrome-stable",
  "/usr/bin/chromium",
  "/usr/bin/chromium-browser",
].filter(Boolean);
const executablePath = browserCandidates.find((candidate) => fs.existsSync(candidate));
if (!executablePath) throw new Error("set CLOUDIO_CHROMIUM_PATH to an installed Chromium executable");

function bootstrapToken(url) {
  const fragment = new URL(url).hash;
  assert.ok(fragment.startsWith("#token="));
  return decodeURIComponent(fragment.slice("#token=".length));
}

(async () => {
  const browser = await chromium.launch({ executablePath, headless: true });
  try {
    const staleContext = await browser.newContext({ storageState: oldStorageState });
    const stalePage = await staleContext.newPage();
    await stalePage.goto(`${origin}/`, { waitUntil: "load" });
    assert.equal(stalePage.url(), `${origin}/login.html`, "reset must invalidate every old session");
    await staleContext.close();

    const context = await browser.newContext();
    const page = await context.newPage();
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

    const setupResponse = await page.goto(setupUrl, { waitUntil: "load" });
    assert.equal(setupResponse.status(), 200);
    await page.locator("#passkey-label").fill("Recovered passkey");
    await Promise.all([
      page.waitForURL(`${origin}/security.html`),
      page.locator("#setup-button").click(),
    ]);
    assert.equal(await page.locator("#passkey-count").innerText(), "1");
    assert.equal(await page.locator("#passkeys-body tr", { hasText: "Recovered passkey" }).count(), 1);
    assert.match(await page.locator("#security-notice").innerText(), /Add a second passkey/);

    const reused = await page.request.post(`${origin}/api/auth/setup/options`, {
      headers: {
        Origin: origin,
        "Content-Type": "application/json",
        "X-Cloudio-Bootstrap": bootstrapToken(setupUrl),
      },
      data: {},
    });
    assert.equal(reused.status(), 401, "the recovery setup token must be one-use");

    const [logoutResponse] = await Promise.all([
      page.waitForResponse((response) => response.request().method() === "POST" && new URL(response.url()).pathname === "/security/logout"),
      page.locator("#sign-out").click(),
    ]);
    assert.equal(logoutResponse.status(), 303);
    await page.waitForURL(`${origin}/login.html`);
    await Promise.all([
      page.waitForURL(`${origin}/`),
      page.locator("#login-button").click(),
    ]);
    assert.equal(await page.locator("#page-title").innerText(), "Dashboard");
    await context.close();
  } finally {
    await browser.close();
  }
  console.log("Cloudio auth recovery acceptance checks passed");
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
