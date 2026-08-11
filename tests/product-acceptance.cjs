const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const repoDir = path.resolve(__dirname, "..");
const { chromium } = require(path.join(
  repoDir,
  ".zig-cache/browser-e2e/node_modules/playwright-core",
));

const [origin, setupUrl, storageStatePath, fakeDockerStatePath, fakeDockerControlPath, fakeDockerCallsPath, fakeCloudflareStatePath, fakeCloudflareControlPath, fakeCloudflareCallsPath, fakeHostingerStatePath, fakeHostingerControlPath, fakeHostingerCallsPath, caddyOwnedPath, caddyControlPath, caddyCallsPath, nobProjectRoot, nobSecretFile, databasePath] = process.argv.slice(2);
if (!origin || !setupUrl || !storageStatePath || !fakeDockerStatePath || !fakeDockerControlPath || !fakeDockerCallsPath || !fakeCloudflareStatePath || !fakeCloudflareControlPath || !fakeCloudflareCallsPath || !fakeHostingerStatePath || !fakeHostingerControlPath || !fakeHostingerCallsPath || !caddyOwnedPath || !caddyControlPath || !caddyCallsPath || !nobProjectRoot || !nobSecretFile || !databasePath) {
  throw new Error("usage: node tests/product-acceptance.cjs ORIGIN SETUP_URL STORAGE_STATE DOCKER_STATE DOCKER_CONTROL DOCKER_CALLS CLOUDFLARE_STATE CLOUDFLARE_CONTROL CLOUDFLARE_CALLS HOSTINGER_STATE HOSTINGER_CONTROL HOSTINGER_CALLS CADDY_OWNED CADDY_CONTROL CADDY_CALLS NOB_PROJECT_ROOT NOB_SECRET_FILE DATABASE");
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
  ["/projects.html", "#nob-scan-button"],
  ["/routes.html", "#route-form"],
  ["/dns.html", 'form[method="get"][action="/dns.html"]'],
  ["/browser.html", '#browser-run-form'],
  ["/vps.html", '#vps-refresh-form[method="post"]'],
  ["/docker.html", 'form[method="post"][action="/docker/refresh"]'],
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
        (location.url.startsWith(`${origin}/api/caddy/routes`) && /\b(400|404|409)\b/.test(message.text())) ||
        (location.url === `${origin}/api/caddy/apply` && /\b(409|422|502|503)\b/.test(message.text())) ||
        (location.url === `${origin}/routes/apply` && /\b(409|422|428|502|503)\b/.test(message.text())) ||
        (location.url === `${origin}/api/containers/action` && /\b(400|404|409|502)\b/.test(message.text())) ||
        (location.url.startsWith(`${origin}/api/containers/logs?`) && /\b(400|503)\b/.test(message.text())) ||
        (location.url === `${origin}/api/containers/refresh` && message.text().includes("503")) ||
        (location.url.startsWith(`${origin}/api/dns/records`) && /\b(400|404|409|502|503)\b/.test(message.text())) ||
        (location.url === `${origin}/dns/record` && /\b(428|502)\b/.test(message.text())) ||
        (location.url === `${origin}/browser/run` && /\b(400|403|409|422|429|500|502|503)\b/.test(message.text())) ||
        (location.url === `${origin}/api/vps/action` && /\b(400|404|409|502|503)\b/.test(message.text())) ||
        (location.url === `${origin}/api/vps/refresh` && /\b(409|502|503)\b/.test(message.text())) ||
        (location.url === `${origin}/vps/action` && /\b(428|502)\b/.test(message.text())) ||
        (location.url.startsWith(`${origin}/api/nob/projects/`) && /\b(409|422|503)\b/.test(message.text())) ||
        (location.url === `${origin}/projects/action` && /\b(409|422|428|503)\b/.test(message.text())) ||
        (location.url.startsWith(`${origin}/api/auth/credentials/`) && message.text().includes("409")) ||
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

async function apiMutation(page, pathName, body, key, confirm = false, method = "POST") {
  return page.evaluate(async ({ pathName: target, body: payload, key: requestKey, confirm: needsConfirm, method: requestMethod }) => {
    const session = await fetch("/api/auth/session", { credentials: "same-origin" }).then((response) => response.json());
    const headers = {
      "Content-Type": "application/json",
      "X-Cloudio-CSRF": session.csrf_token,
      "Idempotency-Key": requestKey,
    };
    if (needsConfirm) headers["X-Cloudio-Confirm"] = "confirmed";
    const response = await fetch(target, {
      method: requestMethod,
      credentials: "same-origin",
      headers,
      body: JSON.stringify(payload || {}),
    });
    let responseBody = null;
    try {
      responseBody = await response.json();
    } catch (_) {
      responseBody = null;
    }
    return {
      status: response.status,
      body: responseBody,
      replayed: response.headers.get("Idempotency-Replayed"),
    };
  }, { pathName, body, key, confirm, method });
}

async function auditEntries(page) {
  const audit = await page.evaluate(() => fetch("/api/audit?limit=500", {
    credentials: "same-origin",
  }).then((response) => response.json()));
  return audit.entries || [];
}

async function auditCount(page, action, target, result = null) {
  return (await auditEntries(page)).filter((entry) => entry.action === action && entry.target === target &&
    (result === null || entry.result === result)).length;
}

async function dockerAuditCount(page, action, target) {
  return auditCount(page, action, target);
}

function cloudflareCallCount(method) {
  const prefix = `${method} /client/v4/zones/zone-fixture/dns_records`;
  return fs.readFileSync(fakeCloudflareCallsPath, "utf8").split("\n").filter((line) =>
    line.startsWith(prefix) && (method !== "POST" || line.startsWith(`${prefix} `))).length;
}

function cloudflareWriteCount() {
  return cloudflareCallCount("POST") + cloudflareCallCount("PUT") + cloudflareCallCount("DELETE");
}

function browserRunCallCount(action = "") {
  const prefix = "POST /client/v4/accounts/account-fixture/browser-run/";
  return fs.readFileSync(fakeCloudflareCallsPath, "utf8").split("\n").filter((line) =>
    line.startsWith(`${prefix}${action}`)).length;
}

function hostingerCallCount(method, suffix = "") {
  return fs.readFileSync(fakeHostingerCallsPath, "utf8").split("\n").filter((line) =>
    line.startsWith(`${method} /api/vps/v1/virtual-machines`) && (!suffix || line.endsWith(suffix))).length;
}

function hostingerWriteCount() {
  return hostingerCallCount("POST");
}

function caddyCallCount(prefix) {
  return fs.readFileSync(caddyCallsPath, "utf8").split("\n").filter((line) => line.startsWith(prefix)).length;
}

function caddyOwnedText() {
  return fs.existsSync(caddyOwnedPath) ? fs.readFileSync(caddyOwnedPath, "utf8") : "";
}

function projectForm(page, operation, scope = null) {
  const root = scope || page;
  return root.locator(`form[action="/projects/action"]:has(input[name="operation"][value="${operation}"])`).first();
}

async function submitProjectForm(page, form, expectedStatus = 303) {
  const [response] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/projects/action", { timeout: 120_000 }),
    page.waitForNavigation({ waitUntil: "load", timeout: 120_000 }),
    form.locator('button[type="submit"]').click({ noWaitAfter: true }),
  ]);
  assert.equal(response.status(), expectedStatus);
  return response;
}

async function waitForProjectRun(page, expectedState, timeoutMs = 30_000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const text = await page.locator("#nob-run-detail-content").innerText();
    if (new RegExp(`State\\s+${expectedState}\\b`, "i").test(text)) return text;
    await page.waitForTimeout(250);
    await page.reload({ waitUntil: "load" });
  }
  throw new Error(`project run did not reach ${expectedState}`);
}

async function planProjectAction(page, actionLabel, parameters = {}) {
  const row = page.locator("#nob-project-detail table tr", { hasText: actionLabel }).first();
  assert.equal(await row.count(), 1, `missing action row ${actionLabel}`);
  for (const [name, value] of Object.entries(parameters)) {
    const field = row.locator(`[name="param.${name}"]`);
    if (await field.evaluate((element) => element.tagName === "SELECT")) await field.selectOption(String(value));
    else await field.fill(String(value));
  }
  await submitProjectForm(page, projectForm(page, "plan", row));
  assert.equal(new URL(page.url()).searchParams.get("result"), "planned");
  const planId = new URL(page.url()).searchParams.get("plan");
  assert.ok(planId);
  return planId;
}

async function queueReviewedProjectPlan(page) {
  const form = projectForm(page, "run", page.locator("#nob-plan-review"));
  const review = form.locator('input[name="confirmation"]');
  if (await review.count()) await review.check();
  await submitProjectForm(page, form);
  const runId = new URL(page.url()).searchParams.get("run");
  assert.ok(runId);
  return runId;
}

async function checkProjectsEnhanced(page) {
  await page.goto(`${origin}/projects.html`, { waitUntil: "load" });
  const [scanResponse] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/projects/scan", { timeout: 120_000 }),
    page.locator('#nob-scan-button').click(),
  ]);
  assert.equal(scanResponse.status(), 303);
  await page.waitForURL((url) => url.pathname === "/projects.html" && url.searchParams.get("result") === "scanned");
  assert.match(await page.locator("#nob-projects-count").innerText(), /^2 projects$/);
  assert.equal(await page.locator("#nob-projects-body").getByText("Cloudio acceptance project").count(), 1);
  assert.equal(await page.locator("#nob-projects-body").getByText("needs-manifest").count(), 0);
  const needsManifestLink = page.locator("#project-view-links").getByRole("link", { name: /Needs manifest \(1\)/ });
  await needsManifestLink.click();
  await page.waitForURL((url) => url.searchParams.get("view") === "needs-manifest");
  assert.match(await page.locator("#nob-projects-body").innerText(), /needs-manifest.*Manifest needed/s);

  await page.goto(`${origin}/projects.html`, { waitUntil: "load" });
  await page.locator("#nob-projects-body").getByRole("link", { name: "Cloudio acceptance project" }).click();
  const projectId = new URL(page.url()).searchParams.get("project");
  assert.ok(projectId);
  assert.match(await page.locator("#nob-project-detail").innerText(), /Approval needed/);
  assert.match(await page.locator("#nob-project-detail").innerText(), /Approve and prepare this exact manifest first/);

  let blocked = await apiMutation(page, `/api/nob/projects/${projectId}/actions/check/plan`, { parameters: { channel: "fast" } }, "projects-unapproved-plan-0001");
  assert.equal(blocked.status, 409);
  assert.equal(blocked.body.error, "project_not_approved");

  await submitProjectForm(page, projectForm(page, "trust"));
  assert.equal(new URL(page.url()).searchParams.get("result"), "trusted");
  blocked = await apiMutation(page, `/api/nob/projects/${projectId}/actions/check/plan`, { parameters: { channel: "fast" } }, "projects-unprepared-plan-0001");
  assert.equal(blocked.status, 409);
  assert.equal(blocked.body.error, "runner_not_ready");

  const secretRow = page.locator("#nob-project-detail table tr", { hasText: "fixture-token" });
  const bindForm = projectForm(page, "secret-bind", secretRow);
  await bindForm.locator('select[name="source_kind"]').selectOption("file");
  await bindForm.locator('input[name="source_ref"]').fill(nobSecretFile);
  await submitProjectForm(page, bindForm);
  assert.equal(new URL(page.url()).searchParams.get("result"), "secret_bound");
  const secretPageText = await page.locator("#page-content").innerText();
  assert.doesNotMatch(secretPageText, /acceptance-secret-value-that-must-never-appear/);
  assert.equal(secretPageText.includes(nobSecretFile), false, "secret source references must not be rendered");

  await submitProjectForm(page, projectForm(page, "prepare"));
  assert.equal(new URL(page.url()).searchParams.get("result"), "prepared");
  assert.match(await page.locator("#nob-project-detail").innerText(), /Runner\s+Ready/);
  assert.match(await page.locator("#nob-project-detail").innerText(), /Observed-only resources cannot be changed/);
  assert.match(await page.locator("#nob-project-detail").innerText(), /System-scope services are outside/);
  assert.match(await page.locator("#nob-project-detail").innerText(), /global kill switch/);

  blocked = await apiMutation(page, `/api/nob/projects/${projectId}/resources/observed-service/start/plan`, {}, "projects-observed-control-0001");
  assert.equal(blocked.status, 422);
  assert.equal(blocked.body.error, "resource_control_unavailable");
  blocked = await apiMutation(page, `/api/nob/projects/${projectId}/resources/system-service/start/plan`, {}, "projects-system-control-0001");
  assert.equal(blocked.status, 422);
  assert.equal(blocked.body.error, "resource_control_unavailable");
  blocked = await apiMutation(page, `/api/nob/projects/${projectId}/resources/user-service/start/plan`, {}, "projects-killswitch-control-0001");
  assert.equal(blocked.status, 409);
  assert.equal(blocked.body.error, "system_mutation_disabled");

  const observeResponse = await submitProjectForm(page, projectForm(page, "observe"));
  assert.equal(observeResponse.status(), 303);

  const sourcePath = path.join(nobProjectRoot, "src/library.zig");
  const originalSource = fs.readFileSync(sourcePath, "utf8");
  await planProjectAction(page, "Check fixture", { channel: "fast", attempts: 2, note: "enhanced" });
  const planText = await page.locator("#nob-plan-review").innerText();
  assert.match(planText, /Plan digest\s+[a-f0-9]{64}/i);
  assert.match(planText, /workspace-write/);
  assert.match(planText, /1 seconds/);
  assert.match(planText, /Rollback\s+none/);
  assert.match(planText, /"channel": "fast"/);
  fs.appendFileSync(sourcePath, "\npub const changed_after_plan = true;\n");
  const staleForm = projectForm(page, "run", page.locator("#nob-plan-review"));
  await staleForm.locator('input[name="confirmation"]').check();
  await submitProjectForm(page, staleForm, 409);
  assert.match(await page.locator("#projects-feedback").innerText(), /plan is no longer current/i);
  fs.writeFileSync(sourcePath, originalSource);

  await planProjectAction(page, "Check fixture", { channel: "full", attempts: 3, note: "retained" });
  await queueReviewedProjectPlan(page);
  let terminalText = await waitForProjectRun(page, "succeeded", 60_000);
  assert.match(terminalText, /check-result/);
  assert.match(terminalText, /fixture inputs accepted/);
  const successfulRunUrl = page.url();
  await page.reload({ waitUntil: "load" });
  assert.equal(page.url(), successfulRunUrl);
  assert.match(await page.locator("#nob-run-detail").innerText(), /check-result/);

  await planProjectAction(page, "Intentional failure");
  await queueReviewedProjectPlan(page);
  terminalText = await waitForProjectRun(page, "failed", 60_000);
  assert.match(terminalText, /IntentionalFixtureFailure|runner_reported_failure/);

  await planProjectAction(page, "Cancelable work");
  await queueReviewedProjectPlan(page);
  await waitForProjectRun(page, "running", 30_000);
  await submitProjectForm(page, projectForm(page, "cancel", page.locator("#nob-run-detail")));
  terminalText = await waitForProjectRun(page, "canceled", 60_000);
  assert.match(terminalText, /cancel-marker/);

  await page.goto(`${origin}/projects.html?project=${projectId}`, { waitUntil: "load" });
  const currentSecretRow = page.locator("#nob-project-detail table tr", { hasText: "fixture-token" });
  await submitProjectForm(page, projectForm(page, "secret-unbind", currentSecretRow));
  assert.equal(new URL(page.url()).searchParams.get("result"), "secret_unbound");
  const secretActionRow = page.locator("#nob-project-detail table tr", { hasText: "Use logical secret" });
  await submitProjectForm(page, projectForm(page, "plan", secretActionRow), 503);
  assert.match(await page.locator("#projects-feedback").innerText(), /required logical secret/i);

  await page.goto(`${origin}/projects.html?project=${projectId}`, { waitUntil: "load" });
  const staleManifestPlan = await planProjectAction(page, "Check fixture", { channel: "fast" });
  const manifestPath = path.join(nobProjectRoot, "nob.json");
  const originalManifest = fs.readFileSync(manifestPath, "utf8");
  fs.appendFileSync(manifestPath, "\n");
  const [rescanResponse] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/projects/scan", { timeout: 120_000 }),
    page.locator("#nob-scan-button").click(),
  ]);
  assert.equal(rescanResponse.status(), 303);
  await page.goto(`${origin}/projects.html?project=${projectId}`, { waitUntil: "load" });
  assert.match(await page.locator("#nob-project-detail").innerText(), /Changed — review/);
  assert.match(await page.locator("#nob-project-detail").innerText(), /Not prepared/);
  const staleRun = await apiMutation(page, `/api/nob/projects/${projectId}/actions/check/run`, { plan_id: staleManifestPlan }, "projects-stale-manifest-run-0001", true);
  assert.equal(staleRun.status, 409);
  assert.equal(staleRun.body.error, "plan_no_longer_current");
  fs.writeFileSync(manifestPath, originalManifest);
  const [restoreScanResponse] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/projects/scan", { timeout: 120_000 }),
    page.locator("#nob-scan-button").click(),
  ]);
  assert.equal(restoreScanResponse.status(), 303);

  const finalText = await page.locator("#page-content").innerText();
  assert.doesNotMatch(finalText, /acceptance-secret-value-that-must-never-appear/);
}

async function checkProjectsBaseline(page) {
  await page.goto(`${origin}/projects.html`, { waitUntil: "load" });
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth), true);
  await page.locator("#nob-projects-body").getByRole("link", { name: "Cloudio acceptance project" }).click();
  const projectId = new URL(page.url()).searchParams.get("project");
  assert.ok(projectId);
  await submitProjectForm(page, projectForm(page, "trust"));
  const secretRow = page.locator("#nob-project-detail table tr", { hasText: "fixture-token" });
  const bindForm = projectForm(page, "secret-bind", secretRow);
  await bindForm.locator('select[name="source_kind"]').selectOption("file");
  await bindForm.locator('input[name="source_ref"]').fill(nobSecretFile);
  await submitProjectForm(page, bindForm);
  assert.equal((await page.locator("#page-content").innerText()).includes(nobSecretFile), false);
  await submitProjectForm(page, projectForm(page, "prepare"));
  await planProjectAction(page, "Use logical secret");
  await queueReviewedProjectPlan(page);
  const terminalText = await waitForProjectRun(page, "succeeded", 60_000);
  assert.match(terminalText, /logical secret was delivered without exposing it/);
  assert.doesNotMatch(terminalText, /acceptance-secret-value-that-must-never-appear/);
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth), true);
}

async function checkSecurityLifecycle(page, cdp, firstAuthenticatorId) {
  assert.equal(await page.locator("#passkey-count").innerText(), "1");
  assert.match(await page.locator("#security-notice").innerText(), /Add a second passkey/);
  assert.equal(await page.locator("#passkeys-body tr").count(), 1);

  page.once("dialog", (dialog) => dialog.dismiss());
  await page.locator("#add-passkey").click();
  await page.waitForTimeout(50);
  assert.equal(await page.locator("#passkeys-body tr").count(), 1, "cancelled enrollment must preserve credential state");
  assert.equal(await page.locator("#add-passkey").evaluate((element) => element === document.activeElement), true);

  await cdp.send("WebAuthn.removeVirtualAuthenticator", { authenticatorId: firstAuthenticatorId });
  await cdp.send("WebAuthn.addVirtualAuthenticator", {
    options: {
      protocol: "ctap2",
      transport: "usb",
      hasResidentKey: true,
      hasUserVerification: true,
      isUserVerified: true,
      automaticPresenceSimulation: true,
    },
  });
  page.once("dialog", (dialog) => dialog.accept("Recovery key"));
  await Promise.all([
    page.waitForURL(`${origin}/security.html?result=added`),
    page.locator("#add-passkey").click(),
  ]);
  assert.equal(await page.locator("#passkey-count").innerText(), "2");
  assert.equal(await page.locator("#passkeys-body tr", { hasText: "Recovery key" }).count(), 1);
  assert.match(await page.locator("#security-notice").innerText(), /Passkey added/);

  let recoveryRow = page.locator("#passkeys-body tr", { hasText: "Recovery key" });
  page.once("dialog", (dialog) => dialog.accept("Travel key"));
  await Promise.all([
    page.waitForURL(`${origin}/security.html?result=renamed`),
    recoveryRow.getByRole("button", { name: "Rename" }).click(),
  ]);
  assert.equal(await page.locator("#passkeys-body tr", { hasText: "Travel key" }).count(), 1);

  recoveryRow = page.locator("#passkeys-body tr", { hasText: "Travel key" });
  const recoveryRevoke = recoveryRow.getByRole("button", { name: "Revoke" });
  await recoveryRevoke.click();
  const cancel = page.locator("dialog[open]").getByRole("button", { name: "Cancel" });
  assert.equal(await cancel.evaluate((element) => element === document.activeElement), true);
  await cancel.click();
  assert.equal(await recoveryRow.count(), 1, "cancelled revocation must preserve credential state");
  assert.equal(await recoveryRevoke.evaluate((element) => element === document.activeElement), true);

  const originalRow = page.locator("#passkeys-body tr").filter({ hasNotText: "Travel key" }).first();
  await originalRow.getByRole("button", { name: "Revoke" }).click();
  await Promise.all([
    page.waitForURL(`${origin}/security.html?result=revoked`),
    page.locator("dialog[open]").getByRole("button", { name: "Revoke" }).click(),
  ]);
  assert.equal(await page.locator("#passkey-count").innerText(), "1");
  assert.equal(await page.locator("#passkeys-body tr", { hasText: "Travel key" }).count(), 1);

  recoveryRow = page.locator("#passkeys-body tr", { hasText: "Travel key" });
  await recoveryRow.getByRole("button", { name: "Revoke" }).click();
  const [lastKeyResponse] = await Promise.all([
    page.waitForResponse((response) => response.request().method() === "DELETE" && new URL(response.url()).pathname.startsWith("/api/auth/credentials/")),
    page.locator("dialog[open]").getByRole("button", { name: "Revoke" }).click(),
  ]);
  assert.equal(lastKeyResponse.status(), 409);
  await page.getByText("The last passkey cannot be removed.").waitFor();
  assert.equal(await page.locator("#passkey-count").innerText(), "1");
  assert.equal(await page.locator("#passkeys-body tr", { hasText: "Travel key" }).count(), 1);
}

async function checkBrowserRun(page, context) {
  await page.goto(`${origin}/browser.html`, { waitUntil: "load" });
  assert.match(await page.locator("#browser-capability-status").innerText(), /Available/);
  assert.equal(await page.locator("#browser-account").inputValue(), "account-fixture");
  assert.match(await page.locator("#browser-run-idempotency").inputValue(), /^browser-run-[A-Za-z0-9_-]{32}$/);
  const browserFieldWidths = await page.evaluate(() => ({
    account: document.querySelector("#browser-account").parentElement.getBoundingClientRect().width,
    url: document.querySelector("#browser-url").parentElement.getBoundingClientRect().width,
  }));
  assert.ok(browserFieldWidths.url > browserFieldWidths.account * 1.7, "the URL field must own the wider form column");

  const callsBeforeDeniedTarget = browserRunCallCount();
  await page.locator("#browser-url").fill("http://127.0.0.1/private");
  const [deniedTargetResponse] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/browser/run"),
    page.locator("#browser-content-submit").click(),
  ]);
  assert.equal(deniedTargetResponse.status(), 403);
  assert.match(await page.locator("#browser-notice").innerText(), /outside the configured Browser Run host policy/i);
  assert.equal(browserRunCallCount(), callsBeforeDeniedTarget, "rejected private targets must not reach Cloudflare");

  await page.goto(`${origin}/browser.html`, { waitUntil: "load" });
  await page.locator("#browser-url").fill("https://example.com/browser-run?fixture=secret");
  const [contentResponse] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/browser/run"),
    page.locator("#browser-content-submit").click(),
  ]);
  assert.equal(contentResponse.status(), 303);
  await page.waitForURL((url) => url.pathname === "/browser.html" && url.searchParams.has("run"));
  assert.match(await page.locator("#browser-result-status").innerText(), /succeeded/i);
  assert.equal((await page.locator("#browser-result-target").innerText()).trim(), "https://example.com/browser-run");
  assert.match(await page.locator(".browser-html-preview").innerText(), /Rendered fixture/);
  assert.equal(await page.evaluate(() => window.__browserRunArtifactExecuted), undefined);
  assert.doesNotMatch(await page.locator("#page-content").innerText(), /fixture=secret/);
  assert.equal(browserRunCallCount("content"), 1);

  const htmlArtifactHref = await page.locator('#browser-result-output a[href*="/browser/artifact"]').getAttribute("href");
  assert.ok(htmlArtifactHref);
  const htmlArtifact = await context.request.get(`${origin}${htmlArtifactHref}`);
  assert.equal(htmlArtifact.status(), 200);
  assert.match(htmlArtifact.headers()["content-type"], /^text\/html/);
  assert.match(htmlArtifact.headers()["content-disposition"], /^attachment;/);
  assert.match(await htmlArtifact.text(), /window\.__browserRunArtifactExecuted=true/);

  await page.reload({ waitUntil: "load" });
  assert.equal(browserRunCallCount("content"), 1, "refreshing a result must not repeat a Browser Run");

  await page.goto(`${origin}/browser.html`, { waitUntil: "load" });
  await page.locator("#browser-url").fill("https://example.com/browser-run?fixture=secret");
  const [screenshotResponse] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/browser/run"),
    page.locator("#browser-screenshot-submit").click(),
  ]);
  assert.equal(screenshotResponse.status(), 303);
  await page.waitForURL((url) => url.pathname === "/browser.html" && url.searchParams.has("run"));
  const screenshotSrc = await page.locator('#browser-result-output img[src*="/browser/artifact"]').getAttribute("src");
  assert.ok(screenshotSrc);
  const screenshotArtifact = await context.request.get(`${origin}${screenshotSrc}`);
  assert.equal(screenshotArtifact.status(), 200);
  assert.match(screenshotArtifact.headers()["content-type"], /^image\/png/);
  assert.deepEqual((await screenshotArtifact.body()).subarray(0, 8), Buffer.from("89504e470d0a1a0a", "hex"));
  assert.equal(browserRunCallCount("screenshot"), 1);

  fs.writeFileSync(fakeCloudflareControlPath, "reject\n");
  try {
    await page.goto(`${origin}/browser.html`, { waitUntil: "load" });
    await page.locator("#browser-url").fill("https://example.com/browser-run?fixture=secret");
    const [rejectedResponse] = await Promise.all([
      page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/browser/run"),
      page.locator("#browser-content-submit").click(),
    ]);
    assert.equal(rejectedResponse.status(), 403);
    assert.match(await page.locator("#browser-result-status").innerText(), /failed/i);
    assert.match(await page.locator("#browser-result-output").innerText(), /lacks Browser Rendering - Edit/i);
  } finally {
    fs.writeFileSync(fakeCloudflareControlPath, "");
  }

  await page.goto(`${origin}/audit.html?category=browser&window=all&limit=500`, { waitUntil: "load" });
  const browserAuditRow = page.locator('tr[data-audit-category="browser"]', { hasText: "browser.run.content" }).first();
  assert.equal(await browserAuditRow.count(), 1);
  assert.doesNotMatch(await browserAuditRow.innerText(), /fixture=secret/);
  await browserAuditRow.locator('td[data-label="Action"] a').click();
  await page.waitForURL((url) => url.pathname === "/browser.html");
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
  const firstAuthenticator = await cdp.send("WebAuthn.addVirtualAuthenticator", {
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
  await checkSecurityLifecycle(page, cdp, firstAuthenticator.authenticatorId);

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

  await page.goto(`${origin}/`, { waitUntil: "load" });
  assert.match(await page.locator("#storage-warning").innerText(), /disk budget.*safe maintenance/i);
  assert.match(await page.locator("#storage-recovery").innerText(), /cloudio maintenance status/);
  assert.match(await page.locator("#storage-recovery").innerText(), /maintenance run --apply --backup/);
  assert.match(await page.locator("#storage-recovery").innerText(), /never prunes files/i);

  await checkProjectsEnhanced(page);

  await page.goto(`${origin}/audit.html`, { waitUntil: "load" });
  const importantAuditText = await page.locator("#audit-body").textContent();
  assert.match(importantAuditText, /cloudflare\.collect.*permission denied/s);
  assert.doesNotMatch(importantAuditText, /fixture provider refresh succeeded/);
  assert.doesNotMatch(await page.locator("#page-content").textContent(), /fixture-super-secret/);
  assert.equal(await page.locator('tr[data-audit-source="event"]').count() > 0, true);

  await page.goto(`${origin}/settings.html`, { waitUntil: "load" });
  assert.match(
    await page.locator("#settings-csrf").inputValue(),
    /^[A-Za-z0-9_-]{43}$/,
    "settings form must contain the authenticated session CSRF token",
  );
  await page.locator("#theme-dark").check();
  const [themeResponse] = await Promise.all([
    page.waitForResponse((response) => new URL(response.url()).pathname === "/settings/theme"),
    page.locator('.settings-form button[type="submit"]').click(),
  ]);
  assert.equal(await themeResponse.request().headerValue("origin"), origin);
  assert.equal(themeResponse.status(), 303, "saving appearance must use the native redirect flow");
  await page.waitForURL(`${origin}/settings.html?saved=1`);
  assert.equal(await page.locator("html").evaluate((element) => element.classList.contains("theme-dark")), true);
  assert.match(await page.locator("#settings-status").innerText(), /Appearance saved/);
  const themeCookie = (await context.cookies()).find((cookie) => cookie.name === "cloudio_theme");
  assert.equal(themeCookie?.value, "dark");
  const settingsCsrf = await page.locator("#settings-csrf").inputValue();
  const rejectedSettings = [
    {
      label: "origin",
      expected: 403,
      headers: { Origin: "http://wrong.example.test", "Content-Type": "application/x-www-form-urlencoded" },
      data: `csrf_token=${settingsCsrf}&theme=light`,
    },
    {
      label: "csrf",
      expected: 403,
      headers: { Origin: origin, "Content-Type": "application/x-www-form-urlencoded" },
      data: "csrf_token=wrong&theme=light",
    },
    {
      label: "content type",
      expected: 400,
      headers: { Origin: origin, "Content-Type": "application/json" },
      data: JSON.stringify({ csrf_token: settingsCsrf, theme: "light" }),
    },
    {
      label: "unknown field",
      expected: 400,
      headers: { Origin: origin, "Content-Type": "application/x-www-form-urlencoded" },
      data: `csrf_token=${settingsCsrf}&theme=light&provider_token=nope`,
    },
    {
      label: "invalid value",
      expected: 400,
      headers: { Origin: origin, "Content-Type": "application/x-www-form-urlencoded" },
      data: `csrf_token=${settingsCsrf}&theme=neon`,
    },
  ];
  for (const candidate of rejectedSettings) {
    const rejectedResponse = await page.request.post(`${origin}/settings/theme`, {
      headers: candidate.headers,
      data: candidate.data,
    });
    assert.equal(rejectedResponse.status(), candidate.expected, `settings must reject invalid ${candidate.label}`);
  }
  assert.equal((await context.cookies()).find((cookie) => cookie.name === "cloudio_theme")?.value, "dark");

  assert.equal((await page.request.get(`${origin}/apps.html`)).status(), 404);
  assert.equal((await page.request.get(`${origin}/api/apps`)).status(), 404);
  assert.equal((await page.request.get(`${origin}/api/topology`)).status(), 404);
  assert.equal((await page.request.get(`${origin}/api/topology/changes`)).status(), 404);
  assert.equal((await page.request.post(`${origin}/api/actions/plan`)).status(), 404);
  assert.equal(await page.locator('a[href="/apps.html"]').count(), 0);

  await page.goto(`${origin}/`, { waitUntil: "load" });
  assert.equal(await page.locator('[data-source="cloudflare"]').getAttribute("data-freshness"), "current");
  assert.equal(await page.locator('[data-source="hostinger"]').getAttribute("data-freshness"), "unavailable");
  assert.equal(await page.locator('[data-source="system"]').getAttribute("data-freshness"), "stale");
  assert.equal(await page.locator('[data-source="projects"]').getAttribute("data-freshness"), "current");
  assert.match(await page.locator('[data-source="system"]').innerText(), /Failed.*fixture command failed/s);
  const diagnoses = page.locator(".diagnosis");
  assert.ok(await diagnoses.count() >= 3);
  for (let index = 0; index < await diagnoses.count(); index += 1) {
    const diagnosis = diagnoses.nth(index);
    assert.equal(await diagnosis.locator("strong").count(), 1);
    assert.equal(await diagnosis.locator("span").count(), 1);
    assert.equal(await diagnosis.locator("a").count(), 1, "each diagnosis must have exactly one owner destination");
    assert.doesNotMatch(await diagnosis.innerText(), /(?:dns|caddy|upstream|project|service|container)_(?:without|not)_/);
  }
  await page.locator('[data-issue="upstream_without_socket"] a').click();
  await page.waitForURL((url) => url.pathname === "/routes.html" && url.searchParams.get("host") === "broken.example.test");

  await page.goto(`${origin}/`, { waitUntil: "load" });
  assert.match(await page.locator('#dashboard-refresh-form input[name="idempotency_key"]').inputValue(), /^dashboard-refresh-[A-Za-z0-9_-]{32}$/);
  const refreshForm = page.locator("#dashboard-refresh-form");
  assert.deepEqual(await refreshForm.evaluate((form) => ({
    action: new URL(form.action).pathname,
    method: form.method,
    valid: form.checkValidity(),
  })), { action: "/dashboard/refresh", method: "post", valid: true });
  fs.writeFileSync(fakeCloudflareControlPath, "read-reject\n");
  const [dashboardRefreshResponse] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/dashboard/refresh"),
    page.locator('#dashboard-refresh-form button[type="submit"]').click(),
  ]);
  assert.equal(dashboardRefreshResponse.status(), 207, "provider-unavailable refresh must report a partial result");
  assert.match(await page.locator("#dashboard-feedback").innerText(), /source failures.*Last-good observations were retained/i);
  assert.equal(await page.locator('[data-source="cloudflare"]').getAttribute("data-freshness"), "stale");
  assert.ok(await page.locator('[data-issue="dns_without_local_target"]').count(), "failed Cloudflare refresh must retain old topology");
  fs.writeFileSync(fakeCloudflareControlPath, "");

  await page.goto(`${origin}/routes.html`, { waitUntil: "load" });
  assert.equal((await page.locator("#routes-freshness").innerText()).trim(), "Unavailable");
  assert.match(await page.locator("#routes-root").textContent(), /Caddyfile$/);
  assert.match(await page.locator("#routes-fragment").innerText(), /cloudio\.caddy$/);
  assert.equal(await page.locator("#add-route").isDisabled(), true);
  assert.equal(await page.locator('#apply-btn[aria-disabled="true"]').count(), 1);
  assert.match(await page.locator("#caddy-apply-capability").innerText(), /refresh the owned fragment/i);
  const [routesRefreshResponse] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/routes/refresh"),
    page.locator('#routes-refresh-form button[type="submit"]').click(),
  ]);
  assert.equal(routesRefreshResponse.status(), 303);
  await page.waitForURL((url) => url.pathname === "/routes.html" && url.searchParams.get("result") === "refresh");
  assert.equal((await page.locator("#routes-freshness").innerText()).trim(), "Current");
  assert.equal(await page.locator("#add-route").isDisabled(), false);
  assert.equal(await page.locator("#add-route").evaluate((button) => button.scrollWidth <= button.clientWidth), true, "route submit label must not clip");
  assert.equal(await page.locator('[data-route-host="fixture.example.test"]').count(), 1);
  assert.equal(await page.locator("#routes-table").isVisible(), true);
  assert.equal(await page.locator("#routes-preview-panel").isVisible(), true);
  assert.match(await page.locator("#routes-diff-summary").innerText(), /1 additions/);

  fs.writeFileSync(caddyControlPath, "adapt-fail\n");
  fs.writeFileSync(fakeCloudflareControlPath, "read-reject\n");
  await page.goto(`${origin}/`, { waitUntil: "load" });
  const [failedCaddyRefresh] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/dashboard/refresh"),
    page.locator('#dashboard-refresh-form button[type="submit"]').click(),
  ]);
  assert.equal(failedCaddyRefresh.status(), 207);
  fs.writeFileSync(caddyControlPath, "");
  fs.writeFileSync(fakeCloudflareControlPath, "");
  await page.goto(`${origin}/routes.html`, { waitUntil: "load" });
  assert.equal(await page.locator('[data-route-host="fixture.example.test"]').count(), 1, "failed Caddy collection must retain last-good routes");

  const caddyCallsBeforeInvalid = fs.readFileSync(caddyCallsPath, "utf8");
  const invalidRoute = await apiMutation(page, "/api/caddy/routes", {
    action: "create", host: "INVALID HOST", upstream: "127.0.0.1:9000",
  }, "browser-caddy-invalid-route-0001");
  assert.equal(invalidRoute.status, 400);
  assert.equal(invalidRoute.body.error, "invalid_caddy_route");
  const missingRoute = await apiMutation(page, "/api/caddy/routes?host=missing.example.test", {}, "browser-caddy-missing-route-0001", true, "DELETE");
  assert.equal(missingRoute.status, 404);
  assert.equal(fs.readFileSync(caddyCallsPath, "utf8"), caddyCallsBeforeInvalid, "invalid and unobserved routes must not invoke Caddy");

  await page.locator("#route-host").fill("app.example.test");
  await page.locator("#route-upstream").fill("127.0.0.1:9100");
  const [routeCreateResponse] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/routes/route"),
    page.locator('#route-form button[type="submit"]').click(),
  ]);
  assert.equal(routeCreateResponse.status(), 303);
  await page.waitForURL((url) => url.pathname === "/routes.html" && url.searchParams.get("result") === "create");
  let appRouteRow = page.locator('[data-route-host="app.example.test"]');
  assert.equal(await appRouteRow.count(), 1);
  await appRouteRow.getByRole("link", { name: "Edit" }).click();
  assert.equal(await page.locator("#route-action").inputValue(), "update");
  assert.equal(await page.locator("#route-host").inputValue(), "app.example.test");
  await page.locator("#route-upstream").fill("127.0.0.1:9101");
  const [routeUpdateResponse] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/routes/route"),
    page.locator('#route-form button[type="submit"]').click(),
  ]);
  assert.equal(routeUpdateResponse.status(), 303);

  const initialApplyKey = "browser-caddy-initial-apply-0001";
  const reloadsBeforeInitialApply = caddyCallCount("reload ");
  const initialApply = await apiMutation(page, "/api/caddy/apply", {}, initialApplyKey, true);
  assert.equal(initialApply.status, 200);
  assert.equal(initialApply.body.verified, true);
  assert.match(caddyOwnedText(), /^# Managed by Cloudio/m);
  assert.match(caddyOwnedText(), /app\.example\.test \{\n\treverse_proxy 127\.0\.0\.1:9101/);
  assert.equal(caddyCallCount("reload "), reloadsBeforeInitialApply + 1);
  const initialApplyAuditCount = await auditCount(page, "caddy.apply", caddyOwnedPath, "ok");
  const replayedInitialApply = await apiMutation(page, "/api/caddy/apply", {}, initialApplyKey, true);
  assert.equal(replayedInitialApply.status, 200);
  assert.equal(replayedInitialApply.replayed, "true");
  assert.equal(caddyCallCount("reload "), reloadsBeforeInitialApply + 1);
  assert.equal(await auditCount(page, "caddy.apply", caddyOwnedPath, "ok"), initialApplyAuditCount);

  await page.goto(`${origin}/routes.html?edit=app.example.test`, { waitUntil: "load" });
  await page.locator("#route-upstream").fill("127.0.0.1:9199");
  await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/routes/route"),
    page.locator('#route-form button[type="submit"]').click(),
  ]);
  const activeBeforeFailures = caddyOwnedText();
  const failedApplyAuditBefore = await auditCount(page, "caddy.apply", caddyOwnedPath, "error");

  fs.writeFileSync(caddyControlPath, "validate-fail\n");
  const invalidApply = await apiMutation(page, "/api/caddy/apply", {}, "browser-caddy-invalid-apply-0001", true);
  assert.equal(invalidApply.status, 422);
  assert.equal(invalidApply.body.error, "caddy_validation_failed");
  assert.equal(caddyOwnedText(), activeBeforeFailures);
  fs.writeFileSync(caddyControlPath, "");
  assert.equal((await apiMutation(page, "/api/caddy/refresh", {}, "browser-caddy-refresh-after-invalid-0001")).status, 200);

  fs.writeFileSync(caddyControlPath, "reload-fail\n");
  const reloadFailure = await apiMutation(page, "/api/caddy/apply", {}, "browser-caddy-reload-fail-0001", true);
  assert.equal(reloadFailure.status, 502);
  assert.equal(reloadFailure.body.error, "caddy_apply_failed");
  assert.equal(caddyOwnedText(), activeBeforeFailures, "reload failure must restore the previous fragment");
  assert.equal((await apiMutation(page, "/api/caddy/refresh", {}, "browser-caddy-refresh-after-reload-0001")).status, 200);

  fs.writeFileSync(caddyControlPath, "verify-fail\n");
  const verifyFailure = await apiMutation(page, "/api/caddy/apply", {}, "browser-caddy-verify-fail-0001", true);
  assert.equal(verifyFailure.status, 502);
  assert.equal(verifyFailure.body.error, "caddy_apply_failed");
  assert.equal(caddyOwnedText(), activeBeforeFailures, "verification failure must restore the previous fragment");
  assert.equal((await apiMutation(page, "/api/caddy/refresh", {}, "browser-caddy-refresh-after-verify-0001")).status, 200);

  fs.chmodSync(caddyOwnedPath, 0o440);
  await page.goto(`${origin}/routes.html`, { waitUntil: "load" });
  assert.equal(await page.locator('#apply-btn[aria-disabled="true"]').count(), 1);
  assert.match(await page.locator("#caddy-apply-capability").innerText(), /cannot replace/i);
  const writeDenied = await apiMutation(page, "/api/caddy/apply", {}, "browser-caddy-write-denied-0001", true);
  assert.equal(writeDenied.status, 409);
  assert.equal(writeDenied.body.error, "caddy_write_unavailable");
  assert.equal(caddyOwnedText(), activeBeforeFailures);
  assert.equal(await auditCount(page, "caddy.apply", caddyOwnedPath, "error"), failedApplyAuditBefore + 4,
    "validation, reload, verification, and permission failures must each be audited once");
  fs.chmodSync(caddyOwnedPath, 0o640);
  assert.equal((await apiMutation(page, "/api/caddy/refresh", {}, "browser-caddy-refresh-after-permission-0001")).status, 200);

  await page.goto(`${origin}/routes.html?confirm=apply`, { waitUntil: "load" });
  assert.equal(await page.locator("#apply-confirmation-panel").isVisible(), true);
  await page.locator("#routes-apply-confirmation").fill("wrong");
  const [wrongApplyConfirmation] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/routes/apply"),
    page.locator('#routes-apply-form button[type="submit"]').click(),
  ]);
  assert.equal(wrongApplyConfirmation.status(), 428);
  assert.equal(await page.locator("#routes-apply-confirmation").inputValue(), "wrong");
  await page.locator("#routes-apply-confirmation").fill("APPLY");
  const [successfulApplyResponse] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/routes/apply"),
    page.locator('#routes-apply-form button[type="submit"]').click(),
  ]);
  assert.equal(successfulApplyResponse.status(), 303);
  await page.waitForURL((url) => url.pathname === "/routes.html" && url.searchParams.get("result") === "apply");
  assert.match(caddyOwnedText(), /reverse_proxy 127\.0\.0\.1:9199/);

  fs.appendFileSync(caddyOwnedPath, "\nadopted.example.test {\n\treverse_proxy 127.0.0.1:9200\n}\n");
  assert.equal((await apiMutation(page, "/api/caddy/refresh", {}, "browser-caddy-adopt-refresh-0001")).status, 200);
  await page.goto(`${origin}/routes.html`, { waitUntil: "load" });
  assert.equal(await page.locator('#apply-btn[aria-disabled="true"]').count(), 1);
  const adoptForm = page.locator('#adopt-routes form', { hasText: "adopted.example.test" });
  assert.equal(await adoptForm.count(), 1);
  const [adoptResponse] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/routes/adopt"),
    adoptForm.locator('button[type="submit"]').click(),
  ]);
  assert.equal(adoptResponse.status(), 303);
  await page.waitForURL((url) => url.pathname === "/routes.html" && url.searchParams.get("result") === "adopt");
  await page.waitForLoadState("load");
  assert.equal(await page.locator('[data-route-host="adopted.example.test"]').count(), 1);
  assert.equal((await page.request.post(`${origin}/api/caddy/import`)).status(), 404);

  await page.goto(`${origin}/audit.html?category=routes&result=failure&window=all&limit=500`, { waitUntil: "load" });
  const caddyFailureRow = page.locator('tr[data-audit-category="routes"]', { hasText: "caddy.apply" }).first();
  assert.equal(await caddyFailureRow.count(), 1);
  assert.equal(new URL(await caddyFailureRow.locator("a").getAttribute("href"), origin).pathname, "/routes.html");
  assert.doesNotMatch(await caddyFailureRow.innerText(), /supersecret|api[_-]?token/i);

  await page.goto(`${origin}/dns.html?domain=fixture.example.test`, { waitUntil: "load" });
  assert.equal((await page.locator("#dns-freshness").innerText()).trim(), "Unavailable");
  assert.equal(await page.locator("#dns-refresh-form button").isDisabled(), false);
  assert.equal(await page.locator("#add-record").isDisabled(), true);
  assert.equal(await page.locator('[data-dns-record="record-initial"]').count(), 0);
  const [dnsRefreshResponse] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/dns/refresh"),
    page.locator('#dns-refresh-form button[type="submit"]').click(),
  ]);
  assert.equal(dnsRefreshResponse.status(), 303);
  await page.waitForURL((url) => url.pathname === "/dns.html" && url.searchParams.get("refreshed") === "1");
  assert.equal((await page.locator("#dns-freshness").innerText()).trim(), "Current");
  assert.notEqual(await page.locator("#dns-observed-at").innerText(), "Never");
  assert.match(await page.locator("#dns-capability").innerText(), /exact zone identity were confirmed/i);
  assert.equal(await page.locator("#add-record").isDisabled(), false);
  assert.equal(await page.locator('[data-dns-record="record-initial"]').count(), 1);

  const beforeInvalidDnsWrites = cloudflareWriteCount();
  const invalidDns = await apiMutation(page, "/api/dns/records", {
    domain: "fixture.example.test",
    record: { type: "A", name: "invalid", content: "999.0.2.10", ttl: 60, proxied: false },
  }, "browser-dns-invalid-create-0001");
  assert.equal(invalidDns.status, 400);
  assert.equal(invalidDns.body.error, "invalid_dns_request");
  assert.equal(cloudflareWriteCount(), beforeInvalidDnsWrites, "invalid input must be rejected before provider I/O");

  await page.goto(`${origin}/dns.html?domain=fixture.example.test`, { waitUntil: "load" });
  await page.locator("#record-name").fill("www");
  await page.locator("#record-content").fill("192.0.2.44");
  await page.locator("#record-ttl").fill("60");
  await page.locator("#record-proxied").check();
  const [nativeDnsCreateResponse] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/dns/record"),
    page.locator('#add-record-form button[type="submit"]').click(),
  ]);
  assert.equal(nativeDnsCreateResponse.status(), 303);
  await page.waitForURL((url) => url.pathname === "/dns.html" && url.searchParams.get("result") === "create");
  let wwwRow = page.locator("tr[data-dns-record]", { hasText: "www.fixture.example.test" });
  assert.equal(await wwwRow.count(), 1);
  const wwwRecordId = await wwwRow.getAttribute("data-dns-record");
  assert.ok(wwwRecordId);
  assert.match(await wwwRow.innerText(), /Proxied/);

  const createAuditBefore = await auditCount(page, "cf.dns.create", "zone-fixture");
  const providerCreatesBefore = cloudflareCallCount("POST");
  const apiCreateKey = "browser-dns-api-create-0001";
  const apiCreateBody = {
    domain: "fixture.example.test",
    record: { type: "A", name: "api", content: "192.0.2.55", ttl: 60, proxied: false },
  };
  const apiCreate = await apiMutation(page, "/api/dns/records", apiCreateBody, apiCreateKey);
  assert.equal(apiCreate.status, 200);
  assert.equal(apiCreate.body.result, "confirmed");
  const apiCreateReplay = await apiMutation(page, "/api/dns/records", apiCreateBody, apiCreateKey);
  assert.equal(apiCreateReplay.status, 200);
  assert.equal(apiCreateReplay.replayed, "true");
  assert.equal(cloudflareCallCount("POST"), providerCreatesBefore + 1, "idempotent replay must not repeat provider I/O");
  assert.equal(await auditCount(page, "cf.dns.create", "zone-fixture"), createAuditBefore + 1, "idempotent replay must not duplicate audit rows");

  await page.goto(`${origin}/dns.html?domain=fixture.example.test`, { waitUntil: "load" });
  wwwRow = page.locator(`tr[data-dns-record="${wwwRecordId}"]`);
  await wwwRow.getByRole("link", { name: "Edit" }).click();
  await page.waitForURL((url) => url.pathname === "/dns.html" && url.searchParams.get("edit") === wwwRecordId);
  await page.locator("#edit-record-content").fill("192.0.2.45");
  const [nativeDnsUpdateResponse] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/dns/record"),
    page.locator('#edit-record-form button[type="submit"]').click(),
  ]);
  assert.equal(nativeDnsUpdateResponse.status(), 303);
  await page.waitForURL((url) => url.pathname === "/dns.html" && url.searchParams.get("result") === "update");
  wwwRow = page.locator(`tr[data-dns-record="${wwwRecordId}"]`);
  assert.match(await wwwRow.innerText(), /192\.0\.2\.45/);

  const [nativeDnsToggleResponse] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/dns/record"),
    wwwRow.getByRole("button", { name: "Set DNS only" }).click(),
  ]);
  assert.equal(nativeDnsToggleResponse.status(), 303);
  await page.waitForURL((url) => url.pathname === "/dns.html" && url.searchParams.get("result") === "toggle");
  wwwRow = page.locator(`tr[data-dns-record="${wwwRecordId}"]`);
  assert.match(await wwwRow.innerText(), /DNS only/);

  fs.writeFileSync(fakeCloudflareControlPath, "reject\n");
  const rejectedAuditBefore = await auditCount(page, "cf.dns.create", "zone-fixture", "error");
  await page.locator("#record-name").fill("preserved");
  await page.locator("#record-content").fill("192.0.2.77");
  await page.locator("#record-ttl").fill("300");
  const [rejectedDnsResponse] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/dns/record"),
    page.locator('#add-record-form button[type="submit"]').click(),
  ]);
  assert.equal(rejectedDnsResponse.status(), 502);
  assert.match(await page.locator("#dns-notice").innerText(), /Cloudflare rejected.*retained/i);
  assert.equal(await page.locator("#record-name").inputValue(), "preserved");
  assert.equal(await page.locator("#record-content").inputValue(), "192.0.2.77");
  assert.equal(await page.locator("#record-ttl").inputValue(), "300");
  assert.equal(await page.locator(`tr[data-dns-record="${wwwRecordId}"]`).count(), 1);
  assert.equal(await auditCount(page, "cf.dns.create", "zone-fixture", "error"), rejectedAuditBefore + 1);
  fs.writeFileSync(fakeCloudflareControlPath, "");

  await page.goto(`${origin}/dns.html?domain=fixture.example.test`, { waitUntil: "load" });
  fs.writeFileSync(fakeCloudflareControlPath, "accept-unconfirmed\n");
  wwwRow = page.locator(`tr[data-dns-record="${wwwRecordId}"]`);
  const [unconfirmedDnsResponse] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/dns/record"),
    wwwRow.getByRole("button", { name: "Enable proxy" }).click(),
  ]);
  assert.equal(unconfirmedDnsResponse.status(), 202);
  assert.match(await page.locator("#dns-notice").innerText(), /accepted.*confirmation read failed.*read-only/i);
  assert.equal((await page.locator("#dns-freshness").innerText()).trim(), "Stale");
  assert.equal(await page.locator("#add-record").isDisabled(), true);
  assert.equal(await page.locator("[data-dns-record] form").count(), 0);
  const stalePutCount = cloudflareCallCount("PUT");
  const staleWrite = await apiMutation(page, "/api/dns/records", {
    domain: "fixture.example.test",
    record_id: wwwRecordId,
    record: { type: "A", name: "www", content: "192.0.2.99", ttl: 60, proxied: true },
  }, "browser-dns-stale-update-0001", false, "PUT");
  assert.equal(staleWrite.status, 409);
  assert.equal(staleWrite.body.error, "dns_write_unavailable");
  assert.equal(cloudflareCallCount("PUT"), stalePutCount);

  fs.writeFileSync(fakeCloudflareControlPath, "");
  const [dnsRecoveryResponse] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/dns/refresh"),
    page.locator('#dns-refresh-form button[type="submit"]').click(),
  ]);
  assert.equal(dnsRecoveryResponse.status(), 303);
  await page.waitForURL((url) => url.pathname === "/dns.html" && url.searchParams.get("refreshed") === "1");
  assert.equal((await page.locator("#dns-freshness").innerText()).trim(), "Current");
  wwwRow = page.locator(`tr[data-dns-record="${wwwRecordId}"]`);
  assert.match(await wwwRow.innerText(), /Proxied/);

  const missingPutCount = cloudflareCallCount("PUT");
  const unobservedDns = await apiMutation(page, "/api/dns/records", {
    domain: "fixture.example.test",
    record_id: "record-not-observed",
    record: { type: "A", name: "missing", content: "192.0.2.90", ttl: 60, proxied: false },
  }, "browser-dns-unobserved-update-0001", false, "PUT");
  assert.equal(unobservedDns.status, 404);
  assert.equal(unobservedDns.body.error, "dns_record_not_observed");
  assert.equal(cloudflareCallCount("PUT"), missingPutCount);
  assert.equal((await page.request.post(`${origin}/api/cache/purge`)).status(), 404);
  assert.equal((await page.request.post(`${origin}/api/zone/setting`)).status(), 404);

  await page.goto(`${origin}/dns.html?domain=fixture.example.test`, { waitUntil: "load" });
  wwwRow = page.locator(`tr[data-dns-record="${wwwRecordId}"]`);
  await wwwRow.getByRole("link", { name: "Delete" }).click();
  await page.waitForURL((url) => url.pathname === "/dns.html" && url.searchParams.get("confirm") === "delete");
  const deletesBefore = cloudflareCallCount("DELETE");
  await page.locator("#dns-delete-confirmation").fill("wrong.fixture.example.test");
  const [wrongDeleteResponse] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/dns/record"),
    page.locator('#delete-record-form button[type="submit"]').click(),
  ]);
  assert.equal(wrongDeleteResponse.status(), 428);
  assert.match(await page.locator("#dns-notice").innerText(), /did not exactly match/i);
  assert.equal(await page.locator("#dns-delete-confirmation").inputValue(), "wrong.fixture.example.test");
  assert.equal(cloudflareCallCount("DELETE"), deletesBefore);
  await page.locator("#dns-delete-confirmation").fill("www.fixture.example.test");
  const [nativeDnsDeleteResponse] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/dns/record"),
    page.locator('#delete-record-form button[type="submit"]').click(),
  ]);
  assert.equal(nativeDnsDeleteResponse.status(), 303);
  await page.waitForURL((url) => url.pathname === "/dns.html" && url.searchParams.get("result") === "delete");
  assert.equal(await page.locator(`tr[data-dns-record="${wwwRecordId}"]`).count(), 0);
  assert.equal(cloudflareCallCount("DELETE"), deletesBefore + 1);

  await page.goto(`${origin}/audit.html?category=dns&window=all&limit=500`, { waitUntil: "load" });
  const dnsAuditRow = page.locator('tr[data-audit-category="dns"]', { hasText: "cf.dns.create" }).first();
  assert.equal(await dnsAuditRow.count(), 1);
  await dnsAuditRow.locator('td[data-label="Action"] a').click();
  await page.waitForURL((url) => url.pathname === "/dns.html");

  await checkBrowserRun(page, context);

  await page.goto(`${origin}/vps.html`, { waitUntil: "load" });
  assert.equal((await page.locator("#vps-freshness").innerText()).trim(), "Current");
  assert.notEqual(await page.locator("#vps-observed-at").innerText(), "Never");
  assert.match(await page.locator("#vps-capability").innerText(), /exact observed machine identities were confirmed/i);
  assert.equal(await page.locator('[data-vps-action="stop"][data-vps-id="vm-running"]').count(), 1);
  assert.equal(await page.locator('[data-vps-action="restart"][data-vps-id="vm-running"]').count(), 1);
  assert.equal(await page.locator('[data-vps-action="start"][data-vps-id="vm-running"]').count(), 0);
  assert.equal(await page.locator('[data-vps-action="start"][data-vps-id="vm-stopped"]').count(), 1);
  assert.equal(await page.locator('[data-vps-action="stop"][data-vps-id="vm-stopped"]').count(), 0);
  assert.equal(await page.locator("#rule-form").count(), 0);
  assert.doesNotMatch(await page.locator("#page-content").innerText(), /firewall/i);

  const [nativeVpsRefreshResponse] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/vps/refresh"),
    page.locator('#vps-refresh-form button[type="submit"]').click(),
  ]);
  assert.equal(nativeVpsRefreshResponse.status(), 303);
  await page.waitForURL((url) => url.pathname === "/vps.html" && url.searchParams.get("refreshed") === "1");
  assert.match(await page.locator("#vps-notice").innerText(), /refreshed successfully/i);

  const writesBeforeUnobserved = hostingerWriteCount();
  const unobservedVps = await apiMutation(page, "/api/vps/action", {
    vm_id: "vm-not-observed",
    action: "start",
  }, "browser-vps-unobserved-0001", true);
  assert.equal(unobservedVps.status, 404);
  assert.equal(unobservedVps.body.error, "vps_not_observed");
  assert.equal(hostingerWriteCount(), writesBeforeUnobserved, "unobserved IDs must not reach Hostinger");

  const invalidStateVps = await apiMutation(page, "/api/vps/action", {
    vm_id: "vm-running",
    action: "start",
  }, "browser-vps-invalid-state-0001", true);
  assert.equal(invalidStateVps.status, 409);
  assert.equal(invalidStateVps.body.error, "vps_action_unavailable");
  assert.equal(hostingerWriteCount(), writesBeforeUnobserved, "invalid state transitions must not reach Hostinger");

  await page.locator('[data-vps-action="start"][data-vps-id="vm-stopped"]').click();
  await page.waitForURL((url) => url.pathname === "/vps.html" && url.searchParams.get("confirm") === "start" && url.searchParams.get("machine") === "vm-stopped");
  assert.match(await page.locator('#vps-action-form input[name="idempotency_key"]').inputValue(), /^vps-action-[A-Za-z0-9_-]{32}$/);
  const writesBeforeWrongConfirmation = hostingerWriteCount();
  await page.locator("#vps-confirmation-value").fill("wrong-machine");
  const [wrongVpsConfirmationResponse] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/vps/action"),
    page.locator('#vps-action-form button[type="submit"]').click(),
  ]);
  assert.equal(wrongVpsConfirmationResponse.status(), 428);
  assert.match(await page.locator("#vps-notice").innerText(), /exact observed machine ID/i);
  assert.equal(await page.locator("#vps-confirmation-value").inputValue(), "wrong-machine");
  assert.equal(hostingerWriteCount(), writesBeforeWrongConfirmation);
  await page.locator("#vps-confirmation-value").fill("vm-stopped");
  assert.equal(await page.locator("#vps-action-form").evaluate((form) => form.checkValidity()), true);
  const [nativeVpsStartResponse] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/vps/action"),
    page.locator('#vps-action-form button[type="submit"]').click(),
  ]);
  assert.equal(nativeVpsStartResponse.status(), 303);
  await page.waitForURL((url) => url.pathname === "/vps.html" && url.searchParams.get("result") === "start");
  assert.match(await page.locator("#vps-notice").innerText(), /running state was confirmed.*Provider job: job-/s);
  assert.equal(await page.locator('[data-vps-action="stop"][data-vps-id="vm-stopped"]').count(), 1);

  const vpsRestartKey = "browser-vps-restart-running-0001";
  const providerRestartsBefore = hostingerCallCount("POST", "/restart");
  const restartAuditBefore = await auditCount(page, "hostinger.vps.restart", "vm-running");
  const restartedVps = await apiMutation(page, "/api/vps/action", {
    vm_id: "vm-running",
    action: "restart",
  }, vpsRestartKey, true);
  assert.equal(restartedVps.status, 200);
  assert.equal(restartedVps.body.result, "confirmed");
  assert.equal(restartedVps.body.state, "running");
  assert.match(restartedVps.body.provider_job_id, /^job-/);
  const replayedVpsRestart = await apiMutation(page, "/api/vps/action", {
    vm_id: "vm-running",
    action: "restart",
  }, vpsRestartKey, true);
  assert.equal(replayedVpsRestart.status, 200);
  assert.equal(replayedVpsRestart.replayed, "true");
  assert.equal(hostingerCallCount("POST", "/restart"), providerRestartsBefore + 1);
  assert.equal(await auditCount(page, "hostinger.vps.restart", "vm-running"), restartAuditBefore + 1);

  const stoppedVps = await apiMutation(page, "/api/vps/action", {
    vm_id: "vm-running",
    action: "stop",
  }, "browser-vps-stop-running-0001", true);
  assert.equal(stoppedVps.status, 200);
  assert.equal(stoppedVps.body.state, "stopped");
  await page.goto(`${origin}/vps.html`, { waitUntil: "load" });
  assert.equal(await page.locator('[data-vps-action="start"][data-vps-id="vm-running"]').count(), 1);

  await page.locator('[data-vps-action="start"][data-vps-id="vm-running"]').click();
  await page.waitForURL((url) => url.pathname === "/vps.html" && url.searchParams.get("confirm") === "start" && url.searchParams.get("machine") === "vm-running");
  await page.locator("#vps-confirmation-value").fill("vm-running");
  fs.writeFileSync(fakeHostingerControlPath, "reject\n");
  const rejectedVpsAuditBefore = await auditCount(page, "hostinger.vps.start", "vm-running", "error");
  const [rejectedVpsResponse] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/vps/action"),
    page.locator('#vps-action-form button[type="submit"]').click(),
  ]);
  assert.equal(rejectedVpsResponse.status(), 502);
  assert.match(await page.locator("#vps-notice").innerText(), /Hostinger rejected.*last observed state was retained/i);
  assert.equal(await page.locator("#vps-confirmation-value").inputValue(), "vm-running");
  assert.equal(await auditCount(page, "hostinger.vps.start", "vm-running", "error"), rejectedVpsAuditBefore + 1);
  assert.match(await page.locator('[data-vps-machine="vm-running"]').innerText(), /stopped/i);
  fs.writeFileSync(fakeHostingerControlPath, "");

  fs.writeFileSync(fakeHostingerControlPath, "pending\n");
  const pendingVps = await apiMutation(page, "/api/vps/action", {
    vm_id: "vm-stopped",
    action: "restart",
  }, "browser-vps-pending-restart-0001", true);
  assert.equal(pendingVps.status, 202);
  assert.equal(pendingVps.body.result, "accepted_pending");
  assert.equal(pendingVps.body.reconciled, false);
  await page.goto(`${origin}/vps.html?result=accepted_pending&machine=vm-stopped&job=${encodeURIComponent(pendingVps.body.provider_job_id)}`, { waitUntil: "load" });
  assert.match(await page.locator("#vps-notice").innerText(), /accepted.*still pending.*read-only.*Provider job: job-/s);
  assert.equal(await page.locator('[data-vps-machine="vm-stopped"] [data-vps-action]').count(), 0);
  assert.match(await page.locator('[data-vps-machine="vm-stopped"]').innerText(), /accepted but not yet confirmed/i);

  fs.writeFileSync(fakeHostingerControlPath, "");
  const recoveryVps = await apiMutation(page, "/api/vps/refresh", {}, "browser-vps-recovery-0001");
  assert.equal(recoveryVps.status, 200);
  await page.goto(`${origin}/vps.html`, { waitUntil: "load" });
  assert.equal(await page.locator('[data-vps-action="restart"][data-vps-id="vm-stopped"]').count(), 1);

  fs.writeFileSync(fakeHostingerControlPath, "timeout\n");
  const timedOutVps = await apiMutation(page, "/api/vps/action", {
    vm_id: "vm-stopped",
    action: "restart",
  }, "browser-vps-timeout-restart-0001", true);
  assert.equal(timedOutVps.status, 202);
  assert.equal(timedOutVps.body.result, "accepted_pending");
  fs.writeFileSync(fakeHostingerControlPath, "");
  assert.equal((await apiMutation(page, "/api/vps/refresh", {}, "browser-vps-timeout-recovery-0001")).status, 200);

  fs.writeFileSync(fakeHostingerControlPath, "malformed-read\n");
  const malformedVpsRead = await apiMutation(page, "/api/vps/refresh", {}, "browser-vps-malformed-read-0001");
  assert.equal(malformedVpsRead.status, 502);
  assert.equal(malformedVpsRead.body.error, "vps_provider_rejected");
  await page.goto(`${origin}/vps.html`, { waitUntil: "load" });
  assert.equal((await page.locator("#vps-freshness").innerText()).trim(), "Stale");
  assert.equal(await page.locator('[data-vps-machine="vm-running"]').count(), 1, "invalid reads must retain last-good machines");
  assert.equal(await page.locator("[data-vps-action]").count(), 0);
  fs.writeFileSync(fakeHostingerControlPath, "");
  assert.equal((await apiMutation(page, "/api/vps/refresh", {}, "browser-vps-malformed-recovery-0001")).status, 200);

  assert.equal((await page.request.get(`${origin}/api/firewalls`)).status(), 404);
  assert.equal((await page.request.post(`${origin}/api/firewall/rule`)).status(), 404);
  assert.equal((await page.request.put(`${origin}/api/firewall/rule`)).status(), 404);
  assert.equal((await page.request.delete(`${origin}/api/firewall/rule`)).status(), 404);
  assert.equal((await page.request.post(`${origin}/api/firewall/sync`)).status(), 404);

  await page.goto(`${origin}/audit.html?category=vps&window=all&limit=500`, { waitUntil: "load" });
  const vpsAuditRow = page.locator('tr[data-audit-category="vps"]', { hasText: "hostinger.vps.start" }).first();
  assert.equal(await vpsAuditRow.count(), 1);
  await vpsAuditRow.locator('td[data-label="Action"] a').click();
  await page.waitForURL((url) => url.pathname === "/vps.html");

  await page.goto(`${origin}/docker.html`, { waitUntil: "load" });
  assert.equal(await page.locator("#docker-freshness").innerText(), "current");
  assert.notEqual(await page.locator("#docker-observed-at").innerText(), "Never");
  assert.match(await page.locator("#docker-capability").innerText(), /access was confirmed/i);
  assert.equal(await page.locator('[data-select-container="fixture-running"]').count(), 1);
  assert.equal(await page.locator('[data-select-container="fixture-stopped"]').count(), 1);
  assert.equal(await page.locator('[data-container-action="start"][data-container-name="fixture-running"]').count(), 0);
  assert.equal(await page.locator('[data-container-action="stop"][data-container-name="fixture-running"]').count(), 1);
  assert.equal(await page.locator('[data-container-action="restart"][data-container-name="fixture-running"]').count(), 1);
  assert.equal(await page.locator('[data-container-action="start"][data-container-name="fixture-stopped"]').count(), 1);
  assert.equal(await page.locator('[data-container-action="stop"][data-container-name="fixture-stopped"]').count(), 0);

  await page.goto(`${origin}/docker.html?container=fixture-running&tail=100`, { waitUntil: "load" });
  assert.match(await page.locator("#container-logs").innerText(), /fixture-running log tail=100/);
  assert.match(await page.locator("#logs-status").innerText(), /Logs updated/);

  await page.goto(`${origin}/docker.html`, { waitUntil: "load" });
  await page.locator('[data-container-action="start"][data-container-name="fixture-stopped"]').click();
  await page.waitForURL((url) => url.pathname === "/docker.html" && url.searchParams.get("confirm") === "start" && url.searchParams.get("container") === "fixture-stopped");
  assert.equal(await page.locator("#docker-action-form").count(), 1);
  assert.match(await page.locator('#docker-action-form input[name="idempotency_key"]').inputValue(), /^docker-action-[A-Za-z0-9_-]{32}$/);
  await page.locator("#container-confirmation-value").fill("fixture-stopped");
  const [nativeStartResponse] = await Promise.all([
    page.waitForResponse((response) => response.request().method() === "POST" && new URL(response.url()).pathname === "/docker/action"),
    page.locator('#docker-action-form button[type="submit"]').click(),
  ]);
  assert.equal(nativeStartResponse.status(), 303);
  await page.waitForURL((url) => url.pathname === "/docker.html" && url.searchParams.get("result") === "start");
  assert.match(await page.locator("#docker-feedback").innerText(), /running state was confirmed/i);
  assert.equal(await page.locator('[data-container-action="start"][data-container-name="fixture-stopped"]').count(), 0);
  assert.equal(await page.locator('[data-container-action="stop"][data-container-name="fixture-stopped"]').count(), 1);
  assert.equal(await dockerAuditCount(page, "docker.start", "fixture-stopped"), 1);

  const restartKey = "browser-docker-restart-running-0001";
  const restart = await apiMutation(page, "/api/containers/action", {
    name: "fixture-running",
    action: "restart",
  }, restartKey, true);
  assert.equal(restart.status, 200);
  assert.equal(restart.body.state, "running");
  const replayedRestart = await apiMutation(page, "/api/containers/action", {
    name: "fixture-running",
    action: "restart",
  }, restartKey, true);
  assert.equal(replayedRestart.status, 200);
  assert.equal(replayedRestart.replayed, "true");
  assert.equal(await dockerAuditCount(page, "docker.restart", "fixture-running"), 1);

  const stopped = await apiMutation(page, "/api/containers/action", {
    name: "fixture-running",
    action: "stop",
  }, "browser-docker-stop-running-0001", true);
  assert.equal(stopped.status, 200);
  assert.equal(stopped.body.state, "exited");
  const invalidForState = await apiMutation(page, "/api/containers/action", {
    name: "fixture-running",
    action: "stop",
  }, "browser-docker-stop-again-0001", true);
  assert.equal(invalidForState.status, 409);
  assert.equal(invalidForState.body.error, "container_action_unavailable");

  const missing = await apiMutation(page, "/api/containers/action", {
    name: "fixture-missing",
    action: "start",
  }, "browser-docker-missing-0001", true);
  assert.equal(missing.status, 404);
  assert.equal(missing.body.error, "container_not_observed");
  const optionShaped = await apiMutation(page, "/api/containers/action", {
    name: "-not-an-option",
    action: "start",
  }, "browser-docker-option-name-0001", true);
  assert.equal(optionShaped.status, 400);
  assert.equal(optionShaped.body.error, "invalid_container_request");
  const commandFailure = await apiMutation(page, "/api/containers/action", {
    name: "fixture-command-fail",
    action: "start",
  }, "browser-docker-command-fail-0001", true);
  assert.equal(commandFailure.status, 502);
  assert.equal(commandFailure.body.error, "container_command_failed");
  assert.equal(await dockerAuditCount(page, "docker.start", "fixture-command-fail"), 1);

  await page.goto(`${origin}/audit.html?category=docker&window=all&limit=500`, { waitUntil: "load" });
  const dockerAuditRow = page.locator('tr[data-audit-category="docker"]', { hasText: "fixture-stopped" }).filter({ hasText: "docker.start" }).first();
  assert.equal(await dockerAuditRow.count(), 1);
  await dockerAuditRow.locator('td[data-label="Action"] a').click();
  await page.waitForURL((url) => url.pathname === "/docker.html" && url.searchParams.get("container") === "fixture-stopped");

  const logsFailure = await page.evaluate(() => fetch("/api/containers/logs?name=fixture-logs-fail&tail=200", {
    credentials: "same-origin",
  }).then(async (response) => ({ status: response.status, body: await response.json() })));
  assert.equal(logsFailure.status, 503);
  assert.equal(logsFailure.body.error, "container_runtime_unavailable");
  const invalidTail = await page.evaluate(() => fetch("/api/containers/logs?name=fixture-logs-fail&tail=501", {
    credentials: "same-origin",
  }).then(async (response) => ({ status: response.status, body: await response.json() })));
  assert.equal(invalidTail.status, 400);

  fs.writeFileSync(fakeDockerControlPath, "daemon-unavailable\n");
  const unavailable = await apiMutation(page, "/api/containers/refresh", {}, "browser-docker-daemon-down-0001");
  assert.equal(unavailable.status, 503);
  assert.equal(unavailable.body.error, "container_runtime_unavailable");
  await page.goto(`${origin}/docker.html`, { waitUntil: "load" });
  assert.equal(await page.locator("#docker-freshness").innerText(), "stale");
  assert.match(await page.locator("#docker-capability").innerText(), /latest collection failed/i);
  assert.equal(await page.locator('[data-select-container="fixture-stopped"]').count(), 1, "last-good rows must survive a failed refresh");
  assert.equal(await page.locator("[data-container-action]").count(), 0, "failed collection must make lifecycle controls read-only");

  fs.writeFileSync(fakeDockerControlPath, "");
  const [nativeRefreshResponse] = await Promise.all([
    page.waitForResponse((response) => response.request().method() === "POST" && new URL(response.url()).pathname === "/docker/refresh"),
    page.locator('#refresh-containers-form button[type="submit"]').click(),
  ]);
  assert.equal(nativeRefreshResponse.status(), 303);
  await page.waitForURL((url) => url.pathname === "/docker.html" && url.searchParams.get("refreshed") === "1");
  assert.equal(await page.locator("#docker-freshness").innerText(), "current");
  assert.ok(fs.readFileSync(fakeDockerCallsPath, "utf8").split("\n").some((line) => /^ps -a(?: |$)/.test(line)));

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
  assert.equal(await page.locator("html.theme-dark").count(), 1, "appearance must survive logout and login in this browser");
  await page.goto(`${origin}/login.html`, { waitUntil: "load" });
  assert.equal(page.url(), `${origin}/`, "the server must redirect authenticated login requests without a startup fetch");
  assert.equal(await page.locator("#page-title").textContent(), "Dashboard");
  await context.storageState({ path: storageStatePath });
  assert.deepEqual(errors, []);
  await context.close();
}

async function checkBaseline(browser) {
  const context = await browser.newContext({
    javaScriptEnabled: false,
    storageState: storageStatePath,
    viewport: { width: 390, height: 844 },
  });
  const page = await context.newPage();
  for (const [urlPath, control] of privatePages) {
    const response = await page.goto(`${origin}${urlPath}`, { waitUntil: "load" });
    assert.equal(response.status(), 200, urlPath);
    await assertRendered(page, control);
  }

  await checkProjectsBaseline(page);

  await page.goto(`${origin}/routes.html`, { waitUntil: "load" });
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth), true);
  await page.locator("#route-host").fill("baseline.example.test");
  await page.locator("#route-upstream").fill("127.0.0.1:9300");
  const [baselineRouteCreate] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/routes/route"),
    page.locator('#route-form button[type="submit"]').click(),
  ]);
  assert.equal(baselineRouteCreate.status(), 303);
  await page.waitForURL((url) => url.pathname === "/routes.html" && url.searchParams.get("result") === "create");
  let baselineRouteRow = page.locator('[data-route-host="baseline.example.test"]');
  assert.equal(await baselineRouteRow.count(), 1);
  await page.locator("#apply-btn").click();
  await page.waitForURL((url) => url.pathname === "/routes.html" && url.searchParams.get("confirm") === "apply");
  await page.locator("#routes-apply-confirmation").fill("APPLY");
  const [baselineRouteApply] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/routes/apply"),
    page.locator('#routes-apply-form button[type="submit"]').click(),
  ]);
  assert.equal(baselineRouteApply.status(), 303);
  await page.waitForURL((url) => url.pathname === "/routes.html" && url.searchParams.get("result") === "apply");
  assert.match(caddyOwnedText(), /baseline\.example\.test/);

  baselineRouteRow = page.locator('[data-route-host="baseline.example.test"]');
  const [baselineRouteToggle] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/routes/route"),
    baselineRouteRow.getByRole("button", { name: "Disable" }).click(),
  ]);
  assert.equal(baselineRouteToggle.status(), 303);
  await page.waitForURL((url) => url.pathname === "/routes.html" && url.searchParams.get("result") === "toggle");
  baselineRouteRow = page.locator('[data-route-host="baseline.example.test"]');
  assert.match(await baselineRouteRow.innerText(), /disabled/i);
  const [baselineRouteEnable] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/routes/route"),
    baselineRouteRow.getByRole("button", { name: "Enable" }).click(),
  ]);
  assert.equal(baselineRouteEnable.status(), 303);

  baselineRouteRow = page.locator('[data-route-host="baseline.example.test"]');
  await baselineRouteRow.getByRole("link", { name: "Remove" }).click();
  await page.waitForURL((url) => url.pathname === "/routes.html" && url.searchParams.get("confirm") === "delete");
  await page.locator("#route-delete-confirmation").fill("baseline.example.test");
  const [baselineRouteDelete] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/routes/route"),
    page.locator('#route-delete-form button[type="submit"]').click(),
  ]);
  assert.equal(baselineRouteDelete.status(), 303);
  await page.waitForURL((url) => url.pathname === "/routes.html" && url.searchParams.get("result") === "delete");
  assert.match(await page.locator('[data-route-host="baseline.example.test"]').innerText(), /pending removal/i);
  await page.locator("#apply-btn").click();
  await page.waitForURL((url) => url.pathname === "/routes.html" && url.searchParams.get("confirm") === "apply");
  await page.locator("#routes-apply-confirmation").fill("APPLY");
  await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/routes/apply"),
    page.locator('#routes-apply-form button[type="submit"]').click(),
  ]);
  await page.waitForURL((url) => url.pathname === "/routes.html" && url.searchParams.get("result") === "apply");
  assert.equal(await page.locator('[data-route-host="baseline.example.test"]').count(), 0);
  assert.doesNotMatch(caddyOwnedText(), /baseline\.example\.test/);

  await page.goto(`${origin}/dns.html`, { waitUntil: "load" });
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth), true);
  await page.locator("#domain").selectOption("fixture.example.test");
  await Promise.all([
    page.waitForURL((url) => url.pathname === "/dns.html" && url.searchParams.get("domain") === "fixture.example.test"),
    page.locator("#load-domain").click(),
  ]);
  await page.locator("#record-name").fill("baseline");
  await page.locator("#record-content").fill("192.0.2.80");
  await page.locator("#record-ttl").fill("60");
  const [baselineCreateResponse] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/dns/record"),
    page.locator('#add-record-form button[type="submit"]').click(),
  ]);
  assert.equal(baselineCreateResponse.status(), 303);
  await page.waitForURL((url) => url.pathname === "/dns.html" && url.searchParams.get("result") === "create");
  let baselineDnsRow = page.locator("tr[data-dns-record]", { hasText: "baseline.fixture.example.test" });
  assert.equal(await baselineDnsRow.count(), 1);
  const baselineDnsId = await baselineDnsRow.getAttribute("data-dns-record");
  assert.ok(baselineDnsId);

  await baselineDnsRow.getByRole("link", { name: "Edit" }).click();
  await page.waitForURL((url) => url.pathname === "/dns.html" && url.searchParams.get("edit") === baselineDnsId);
  await page.locator("#edit-record-content").fill("192.0.2.81");
  const [baselineUpdateResponse] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/dns/record"),
    page.locator('#edit-record-form button[type="submit"]').click(),
  ]);
  assert.equal(baselineUpdateResponse.status(), 303);
  await page.waitForURL((url) => url.pathname === "/dns.html" && url.searchParams.get("result") === "update");
  baselineDnsRow = page.locator(`tr[data-dns-record="${baselineDnsId}"]`);
  assert.match(await baselineDnsRow.innerText(), /192\.0\.2\.81/);

  const [baselineToggleResponse] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/dns/record"),
    baselineDnsRow.getByRole("button", { name: "Enable proxy" }).click(),
  ]);
  assert.equal(baselineToggleResponse.status(), 303);
  await page.waitForURL((url) => url.pathname === "/dns.html" && url.searchParams.get("result") === "toggle");
  baselineDnsRow = page.locator(`tr[data-dns-record="${baselineDnsId}"]`);
  assert.match(await baselineDnsRow.innerText(), /Proxied/);

  await baselineDnsRow.getByRole("link", { name: "Delete" }).click();
  await page.waitForURL((url) => url.pathname === "/dns.html" && url.searchParams.get("confirm") === "delete");
  await page.locator("#dns-delete-confirmation").fill("baseline.fixture.example.test");
  const [baselineDeleteResponse] = await Promise.all([
    page.waitForResponse((candidate) => candidate.request().method() === "POST" && new URL(candidate.url()).pathname === "/dns/record"),
    page.locator('#delete-record-form button[type="submit"]').click(),
  ]);
  assert.equal(baselineDeleteResponse.status(), 303);
  await page.waitForURL((url) => url.pathname === "/dns.html" && url.searchParams.get("result") === "delete");
  assert.equal(await page.locator(`tr[data-dns-record="${baselineDnsId}"]`).count(), 0);

  await page.goto(`${origin}/vps.html`, { waitUntil: "load" });
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth), true);
  await page.locator('[data-vps-action="start"][data-vps-id="vm-baseline-stopped"]').click();
  await page.waitForURL((url) => url.pathname === "/vps.html" && url.searchParams.get("confirm") === "start" && url.searchParams.get("machine") === "vm-baseline-stopped");
  await page.locator("#vps-confirmation-value").fill("vm-baseline-stopped");
  const [baselineVpsStartResponse] = await Promise.all([
    page.waitForResponse((response) => response.request().method() === "POST" && new URL(response.url()).pathname === "/vps/action"),
    page.locator('#vps-action-form button[type="submit"]').click(),
  ]);
  assert.equal(baselineVpsStartResponse.status(), 303);
  await page.waitForURL((url) => url.pathname === "/vps.html" && url.searchParams.get("result") === "start");
  assert.equal(await page.locator('[data-vps-action="stop"][data-vps-id="vm-baseline-stopped"]').count(), 1);

  await page.goto(`${origin}/docker.html`, { waitUntil: "load" });
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth), true);
  await page.locator('[data-container-action="start"][data-container-name="fixture-baseline-stopped"]').click();
  await page.waitForURL((url) => url.pathname === "/docker.html" && url.searchParams.get("confirm") === "start" && url.searchParams.get("container") === "fixture-baseline-stopped");
  await page.locator("#container-confirmation-value").fill("fixture-baseline-stopped");
  const [nativeStartResponse] = await Promise.all([
    page.waitForResponse((response) => response.request().method() === "POST" && new URL(response.url()).pathname === "/docker/action"),
    page.locator('#docker-action-form button[type="submit"]').click(),
  ]);
  assert.equal(nativeStartResponse.status(), 303);
  await page.waitForURL((url) => url.pathname === "/docker.html" && url.searchParams.get("result") === "start");
  assert.equal(await page.locator('[data-container-action="stop"][data-container-name="fixture-baseline-stopped"]').count(), 1);

  await page.locator("#log-container").selectOption("fixture-baseline-stopped");
  await page.locator("#log-tail").selectOption("500");
  await Promise.all([
    page.waitForURL((url) => url.pathname === "/docker.html" && url.searchParams.get("container") === "fixture-baseline-stopped" && url.searchParams.get("tail") === "500"),
    page.locator('#reload-logs').click(),
  ]);
  assert.match(await page.locator("#container-logs").innerText(), /fixture-baseline-stopped log tail=500/);

  await page.goto(`${origin}/`, { waitUntil: "load" });
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth), true);
  const baselineDnsDiagnosis = page.locator('[data-issue="dns_without_local_target"] a').first();
  assert.equal(await baselineDnsDiagnosis.count(), 1);
  const diagnosisTarget = new URL(await baselineDnsDiagnosis.getAttribute("href"), origin).searchParams.get("host");
  assert.ok(diagnosisTarget);
  await baselineDnsDiagnosis.click();
  await page.waitForURL((url) => url.pathname === "/routes.html" && url.searchParams.get("host") === diagnosisTarget);

  await page.goto(`${origin}/`, { waitUntil: "load" });
  await page.locator("#domain-filter").fill("first.example");
  await page.locator("#issues-only").check();
  await Promise.all([
    page.waitForURL((url) => url.pathname === "/" && url.searchParams.get("domain") === "first.example" && url.searchParams.get("issues") === "1"),
    page.locator("#dashboard-reload").click(),
  ]);
  assert.equal(await page.locator("#domain-filter").inputValue(), "first.example");
  assert.equal(await page.locator("#issues-only").isChecked(), true);

  await page.goto(`${origin}/audit.html`, { waitUntil: "load" });
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth), true);
  await page.locator("#audit-view").selectOption("all");
  await page.locator("#audit-category").selectOption("other");
  await page.locator("#audit-result").selectOption("success");
  await page.locator("#audit-window").selectOption("all");
  await page.locator("#audit-target").fill("fixture-0");
  await page.locator("#audit-actor").fill("browser-fixture");
  await page.locator("#audit-limit").selectOption("50");
  await Promise.all([
    page.waitForURL((url) => url.pathname === "/audit.html" &&
      url.searchParams.get("view") === "all" &&
      url.searchParams.get("category") === "other" &&
      url.searchParams.get("result") === "success" &&
      url.searchParams.get("window") === "all" &&
      url.searchParams.get("target") === "fixture-0" &&
      url.searchParams.get("actor") === "browser-fixture" &&
      url.searchParams.get("limit") === "50"),
    page.locator("#reload-audit").click(),
  ]);
  assert.equal(await page.locator("#audit-view").inputValue(), "all");
  assert.equal(await page.locator("#audit-category").inputValue(), "other");
  assert.equal(await page.locator("#audit-result").inputValue(), "success");
  assert.equal(await page.locator("#audit-window").inputValue(), "all");
  assert.equal(await page.locator("#audit-target").inputValue(), "fixture-0");
  assert.equal(await page.locator("#audit-actor").inputValue(), "browser-fixture");
  assert.equal(await page.locator("#audit-body > tr").count(), 50);
  await page.locator("#audit-limit").selectOption("100");
  await Promise.all([
    page.waitForURL((url) => url.pathname === "/audit.html" && url.searchParams.get("limit") === "100"),
    page.locator("#reload-audit").click(),
  ]);
  const expandedAuditCount = await page.locator("#audit-body > tr").count();
  assert.equal(expandedAuditCount, 75);
  await page.locator("#audit-limit").selectOption("50");
  await Promise.all([
    page.waitForURL((url) => url.pathname === "/audit.html" && url.searchParams.get("limit") === "50"),
    page.locator("#reload-audit").click(),
  ]);
  assert.equal(await page.locator("#audit-body > tr").count(), 50);

  await page.goto(`${origin}/settings.html`, { waitUntil: "load" });
  await page.locator("#theme-light").check();
  const [lightResponse] = await Promise.all([
    page.waitForResponse((response) => response.request().method() === "POST" && new URL(response.url()).pathname === "/settings/theme"),
    page.locator('.settings-form button[type="submit"]').click(),
  ]);
  assert.equal(lightResponse.status(), 303);
  await page.waitForURL(`${origin}/settings.html?saved=1`);
  assert.equal(await page.locator("html.theme-light").count(), 1);
  await page.locator("#theme-system").check();
  await Promise.all([
    page.waitForResponse((response) => response.request().method() === "POST" && new URL(response.url()).pathname === "/settings/theme"),
    page.locator('.settings-form button[type="submit"]').click(),
  ]);
  await page.waitForURL(`${origin}/settings.html?saved=1`);
  assert.equal(await page.locator("html.theme-system").count(), 1);

  await page.goto(`${origin}/security.html`, { waitUntil: "load" });
  assert.equal(await page.locator("#passkey-count").innerText(), "1");
  assert.match(await page.locator("#security-notice").innerText(), /Add a second passkey/);
  assert.match(await page.locator("#security-csrf").inputValue(), /^[A-Za-z0-9_-]{43}$/);
  const [logoutResponse] = await Promise.all([
    page.waitForResponse((response) => response.request().method() === "POST" && new URL(response.url()).pathname === "/security/logout"),
    page.locator("#sign-out").click(),
  ]);
  assert.equal(logoutResponse.status(), 303);
  await page.waitForURL(`${origin}/login.html`);
  await context.close();
}

async function checkSecurityMobile(browser) {
  const context = await browser.newContext({
    storageState: storageStatePath,
    viewport: { width: 390, height: 844 },
  });
  const page = await context.newPage();
  await page.goto(`${origin}/security.html`, { waitUntil: "load" });
  assert.equal(await page.locator("html.theme-dark").count(), 1);
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth), true);
  assert.equal(await page.locator("#passkey-count").innerText(), "1");
  page.once("dialog", (dialog) => dialog.dismiss());
  await page.locator("#add-passkey").click();
  await page.waitForTimeout(50);
  assert.equal(await page.locator("#passkey-count").innerText(), "1");
  assert.equal(await page.locator("#add-passkey").evaluate((element) => element === document.activeElement), true);
  await context.close();
}

async function checkFreshBrowserTheme(browser) {
  const context = await browser.newContext();
  const page = await context.newPage();
  const response = await page.goto(`${origin}/login.html`, { waitUntil: "load" });
  assert.equal(response.status(), 200);
  assert.equal(await page.locator("html.theme-light").count(), 1, "a new browser must use the documented default");
  await context.close();
}

(async () => {
  const browser = await chromium.launch({ executablePath, headless: true });
  try {
    await enrollAndCheckEnhanced(browser);
    await checkFreshBrowserTheme(browser);
    await checkSecurityMobile(browser);
    await checkBaseline(browser);
  } finally {
    await browser.close();
  }
  console.log("Cloudio product acceptance checks passed");
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
