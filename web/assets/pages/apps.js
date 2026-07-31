(function () {
  "use strict";

  const c = window.cloudio;
  c.mount({ title: "Apps", active: "apps" });

  const appForm = c.byId("app-form");
  const sourceKind = c.byId("source-kind");
  const repoField = c.byId("repo-field");
  const workdirField = c.byId("workdir-field");
  const repoUrl = c.byId("repo-url");
  const workdir = c.byId("workdir");
  const createButton = c.byId("create-app");
  const appsBody = c.byId("apps-body");
  const appsCount = c.byId("apps-count");
  const detailPanel = c.byId("detail-panel");
  const detailTitle = c.byId("detail-title");
  const detailMeta = c.byId("detail-meta");
  const deploysBody = c.byId("deploys-body");
  const deployLog = c.byId("deploy-log");
  const logStatus = c.byId("log-status");

  let apps = [];
  let selectedApp = null;
  let pollTimer = null;

  function toggleSource() {
    const usesWorkdir = sourceKind.value === "workdir";
    repoField.classList.toggle("hidden", usesWorkdir);
    workdirField.classList.toggle("hidden", !usesWorkdir);
    repoUrl.disabled = usesWorkdir;
    repoUrl.required = !usesWorkdir;
    workdir.disabled = !usesWorkdir;
    workdir.required = usesWorkdir;
  }

  function actionButton(label, action, name, kind) {
    return c.button(label, {
      kind: kind,
      small: true,
      dataset: { action: action, app: name },
    });
  }

  function appActions(row) {
    const normal = c.el("div", {
      className: "table-actions",
      children: [
        actionButton("Deploy", "deploy", row.name, "primary"),
        actionButton("Start", "start", row.name),
        actionButton("Stop", "stop", row.name),
        actionButton("Restart", "restart", row.name),
        actionButton("Rollback", "rollback", row.name),
      ],
    });
    normal.appendChild(c.el("div", {
      className: "table-actions table-actions-danger",
      children: actionButton("Delete", "delete", row.name, "danger"),
    }));
    return normal;
  }

  function lastDeploy(row) {
    const deploy = row.last_deploy;
    if (!deploy) return c.el("span", { className: "muted", text: "Never" });
    return [
      c.badge(deploy.status),
      " ",
      c.el("span", { className: "mono", text: c.shortSha(deploy.git_sha) }),
      " ",
      c.el("span", { className: "muted", text: c.formatTime(deploy.finished_at || deploy.started_at) }),
    ];
  }

  function appLink(row) {
    return c.el("button", {
      type: "button",
      className: "button-link mono",
      text: row.name,
      dataset: { openApp: row.name },
      attrs: { "aria-label": "Open details for " + row.name },
    });
  }

  function aliasLink(row) {
    if (!row.alias_host) return "";
    return c.el("a", {
      href: "https://" + row.alias_host,
      text: row.alias_host,
      attrs: { target: "_blank", rel: "noopener noreferrer" },
    });
  }

  function renderApps() {
    appsCount.textContent = apps.length + (apps.length === 1 ? " app" : " apps");
    c.renderTable(appsBody, apps, [
      { label: "Name", render: appLink },
      { label: "Status", render: function (row) { return c.status(row.status); } },
      { label: "Port", key: "port", className: "mono" },
      { label: "Alias", render: aliasLink, className: "breakable" },
      { label: "Toolchain", key: "toolchain", className: "muted" },
      { label: "Last deploy", render: lastDeploy },
      { label: "Actions", render: appActions, className: "cell-actions" },
    ], "No applications registered yet.");
  }

  async function loadApps() {
    try {
      const data = await c.api("/api/apps");
      apps = data && data.apps ? data.apps : [];
      renderApps();
      if (selectedApp && apps.some(function (app) { return app.name === selectedApp; })) {
        loadDetail(selectedApp);
      }
    } catch (error) {
      apps = [];
      appsCount.textContent = "";
      c.tableEmpty(appsBody, 7, "Applications unavailable: " + error.message);
    }
  }

  appForm.addEventListener("submit", function (event) {
    event.preventDefault();
    if (!appForm.reportValidity()) return;
    c.withBusy(createButton, "Creating…", async function () {
      const name = c.byId("app-name").value.trim();
      const body = { name: name };
      if (sourceKind.value === "workdir") {
        body.workdir = workdir.value.trim();
      } else {
        body.repo_url = repoUrl.value.trim();
      }
      try {
        await c.api("/api/apps", { method: "POST", body: body });
        c.toast("Application " + name + " created.", "success");
        appForm.reset();
        toggleSource();
        await loadApps();
      } catch (error) {
        c.toast("Application creation failed: " + error.message, "danger");
      }
    });
  });

  async function confirmForAction(action, name) {
    const details = {
      deploy: {
        title: "Deploy " + name,
        message: "Build the current source, install the release, and restart the application service?",
        label: "Deploy",
      },
      rollback: {
        title: "Roll back " + name,
        message: "Restore the previous release and restart the application service?",
        label: "Roll back",
      },
      delete: {
        title: "Delete " + name,
        message: "Delete this application, its service, releases, deploy history, and managed route? This cannot be undone.",
        label: "Delete app",
        danger: true,
      },
      start: {
        title: "Start " + name,
        message: "Start this application service?",
        label: "Start",
      },
      stop: {
        title: "Stop " + name,
        message: "Stop this application service?",
        label: "Stop",
        danger: true,
      },
      restart: {
        title: "Restart " + name,
        message: "Restart this application service?",
        label: "Restart",
      },
    };
    const detail = details[action];
    return c.confirmAction({
      title: detail.title,
      message: detail.message,
      confirmLabel: detail.label,
      danger: detail.danger,
    });
  }

  async function runAction(button, action, name) {
    if (!(await confirmForAction(action, name))) return;
    await c.withBusy(button, action === "deploy" ? "Deploying…" : "Working…", async function () {
      try {
        if (action === "deploy") {
          openDetail(name);
          startLiveLog(name);
          const result = await c.api("/api/apps/" + encodeURIComponent(name) + "/deploy", {
            method: "POST",
            confirm: true,
          });
          const ok = result && result.ok;
          c.toast(
            ok ? "Deploy completed: " + (result.status || "ok") : "Deploy failed: " + ((result && result.status) || "unknown"),
            ok ? "success" : "danger"
          );
        } else if (action === "rollback") {
          const result = await c.api("/api/apps/" + encodeURIComponent(name) + "/rollback", {
            method: "POST",
            body: { deploy_id: null },
            confirm: true,
          });
          c.toast(result && result.ok !== false ? "Rollback completed." : "Rollback failed.", result && result.ok !== false ? "success" : "danger");
        } else if (action === "delete") {
          await c.api("/api/apps/" + encodeURIComponent(name), {
            method: "DELETE",
            confirm: true,
          });
          c.toast("Application " + name + " deleted.", "success");
          if (selectedApp === name) closeDetail();
        } else {
          const result = await c.api("/api/apps/" + encodeURIComponent(name) + "/service", {
            method: "POST",
            body: { action: action },
            confirm: true,
          });
          const detail = result && (result.state || result.detail || (result.ok ? "ok" : "failed"));
          c.toast(name + " " + action + ": " + (detail || "unknown"), result && result.ok ? "success" : "danger");
        }
      } catch (error) {
        stopLiveLog();
        c.toast(action + " failed: " + error.message, "danger");
      }
      await loadApps();
      if (selectedApp === name) await loadDetail(name);
    });
  }

  function openDetail(name) {
    selectedApp = name;
    detailPanel.classList.remove("hidden");
    detailTitle.textContent = "App: " + name;
    loadDetail(name);
    detailPanel.scrollIntoView({ block: "start" });
  }

  function closeDetail() {
    selectedApp = null;
    stopLiveLog();
    detailPanel.classList.add("hidden");
  }

  async function loadDetail(name) {
    const app = apps.find(function (item) { return item.name === name; });
    detailMeta.textContent = app ? [app.workdir, app.repo_url].filter(Boolean).join(" · ") : "";
    try {
      const data = await c.api("/api/apps/" + encodeURIComponent(name) + "/deploys");
      const rows = data && (data.deploys || data.rows)
        ? data.deploys || data.rows
        : Array.isArray(data) ? data : [];
      c.renderTable(deploysBody, rows, [
        { label: "ID", key: "id", className: "mono" },
        { label: "Status", render: function (row) { return c.badge(row.status); } },
        { label: "SHA", render: function (row) { return c.shortSha(row.git_sha); }, className: "mono" },
        { label: "Started", render: function (row) { return c.formatTime(row.started_at); }, className: "muted" },
        { label: "Finished", render: function (row) { return c.formatTime(row.finished_at); }, className: "muted" },
        { label: "Detail", key: "detail", className: "muted breakable" },
        {
          label: "Log",
          render: function (row) {
            return c.button("View", {
              small: true,
              dataset: { logDeploy: row.id },
              attrs: { "aria-label": "View log for deploy " + row.id },
            });
          },
        },
      ], "No deploy history.");
    } catch (error) {
      c.tableEmpty(deploysBody, 7, "Deploy history unavailable: " + error.message);
    }
  }

  async function loadLog(name, deployId) {
    stopLiveLog();
    logStatus.textContent = "Deploy " + deployId;
    deployLog.dataset.state = "loading";
    deployLog.textContent = "Loading log…";
    try {
      const data = await c.api("/api/apps/" + encodeURIComponent(name) + "/log?deploy_id=" + encodeURIComponent(deployId));
      deployLog.textContent = data && data.log ? data.log : "(empty log)";
      deployLog.dataset.state = data && data.log ? "ready" : "empty";
    } catch (error) {
      deployLog.textContent = "Log unavailable: " + error.message;
      deployLog.dataset.state = "error";
    }
  }

  function startLiveLog(name) {
    stopLiveLog();
    deployLog.textContent = "";
    deployLog.dataset.state = "loading";
    logStatus.textContent = "Deploying · polling";
    pollLog(name);
  }

  function pollLog(name) {
    window.clearInterval(pollTimer);
    async function update() {
      try {
        const data = await c.api("/api/apps/" + encodeURIComponent(name) + "/log");
        if (data && data.log) {
          deployLog.textContent = data.log;
          deployLog.dataset.state = "ready";
          deployLog.scrollTop = deployLog.scrollHeight;
        }
        if (data && data.status && data.status !== "running" && data.status !== "pending") {
          window.clearInterval(pollTimer);
          pollTimer = null;
          logStatus.textContent = "Finished · " + data.status;
          await loadApps();
          if (selectedApp) await loadDetail(selectedApp);
        }
      } catch (_) {
        return;
      }
    }
    update();
    pollTimer = window.setInterval(update, 2000);
  }

  function stopLiveLog() {
    if (pollTimer) {
      window.clearInterval(pollTimer);
      pollTimer = null;
    }
  }

  sourceKind.addEventListener("change", toggleSource);
  appsBody.addEventListener("click", function (event) {
    const open = event.target.closest("button[data-open-app]");
    if (open) {
      openDetail(open.dataset.openApp);
      return;
    }
    const action = event.target.closest("button[data-action]");
    if (action) runAction(action, action.dataset.action, action.dataset.app);
  });
  deploysBody.addEventListener("click", function (event) {
    const logButton = event.target.closest("button[data-log-deploy]");
    if (logButton && selectedApp) loadLog(selectedApp, logButton.dataset.logDeploy);
  });
  c.byId("detail-close").addEventListener("click", closeDetail);
  document.addEventListener("cloudio:reload", loadApps);
  window.addEventListener("pagehide", stopLiveLog, { once: true });

  toggleSource();
})();
