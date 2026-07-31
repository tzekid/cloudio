(function () {
  "use strict";

  const c = window.cloudio;
  c.mount({ title: "Docker", active: "docker" });

  const containersBody = c.byId("containers-body");
  const reloadContainers = c.byId("reload-containers");
  const logsTarget = c.byId("logs-target");
  const logTail = c.byId("log-tail");
  const reloadLogs = c.byId("reload-logs");
  const logOutput = c.byId("container-logs");

  let containerRows = [];
  let selected = null;
  let actionable = true;

  function containerActions(row) {
    if (!actionable) return c.el("span", { className: "muted", text: "Read-only" });
    return c.el("div", {
      className: "table-actions",
      children: [
        c.button("Start", {
          small: true,
          dataset: { containerAction: "start", containerName: row.name },
        }),
        c.button("Stop", {
          small: true,
          kind: "danger",
          dataset: { containerAction: "stop", containerName: row.name },
        }),
        c.button("Restart", {
          small: true,
          dataset: { containerAction: "restart", containerName: row.name },
        }),
      ],
    });
  }

  function containerName(row) {
    return c.el("button", {
      type: "button",
      className: "button-link mono",
      text: row.name,
      dataset: { selectContainer: row.name },
      attrs: { "aria-label": "View logs for container " + row.name },
    });
  }

  function renderContainers() {
    c.renderTable(containersBody, containerRows, [
      {
        label: "Name",
        render: function (row, tableRow) {
          tableRow.classList.toggle("is-selected", selected === row.name);
          tableRow.setAttribute("aria-selected", String(selected === row.name));
          return containerName(row);
        },
      },
      { label: "Image", key: "image", className: "mono breakable" },
      { label: "Status", render: function (row) { return c.status(row.status); } },
      { label: "Ports", key: "ports", className: "mono breakable" },
      { label: "Actions", render: containerActions, className: "cell-actions" },
    ], "No containers found.");
  }

  async function loadContainers() {
    c.setNotice("docker-notice", "");
    c.tableEmpty(containersBody, 5, "Loading containers…", true);
    try {
      const data = await c.api("/api/containers");
      actionable = true;
      containerRows = data.containers || [];
    } catch (_) {
      try {
        const dashboard = await c.api("/api/dashboard?section=system");
        const section = dashboard && dashboard.sections ? dashboard.sections.system || {} : {};
        actionable = false;
        containerRows = (section.containers || []).map(function (row) {
          return { name: row.name, image: "", status: row.value, ports: "" };
        });
        c.setNotice("docker-notice", "The live container endpoint is unavailable. Showing the latest read-only system snapshot.", "warning");
      } catch (error) {
        containerRows = [];
        c.setNotice("docker-notice", "Container data unavailable: " + error.message, "danger");
      }
    }
    if (selected && !containerRows.some(function (row) { return row.name === selected; })) {
      selected = null;
      logsTarget.textContent = "Select a container to view its logs.";
      logOutput.textContent = "No logs loaded.";
      logOutput.dataset.state = "empty";
    }
    renderContainers();
  }

  function selectContainer(name) {
    selected = name;
    logsTarget.textContent = "Container: " + name;
    if (containerRows.length) renderContainers();
    loadLogs();
  }

  async function runContainerAction(control) {
    const action = control.dataset.containerAction;
    const name = control.dataset.containerName;
    const confirmed = await c.confirmAction({
      title: action.charAt(0).toUpperCase() + action.slice(1) + " container",
      message: action.charAt(0).toUpperCase() + action.slice(1) + " container " + name + "?",
      confirmLabel: action.charAt(0).toUpperCase() + action.slice(1),
      danger: action === "stop",
    });
    if (!confirmed) return;
    await c.withBusy(control, "Working…", async function () {
      try {
        const data = await c.api("/api/containers/action", {
          method: "POST",
          body: { name: name, action: action },
          confirm: true,
        });
        const ok = data && data.ok !== false;
        c.setStatus(
          "container-status",
          ok ? name + " " + (data.state || action + " requested") : "Container action failed.",
          ok ? "success" : "danger"
        );
        if (ok) window.setTimeout(loadContainers, 1200);
      } catch (error) {
        c.setStatus("container-status", "Container action failed: " + error.message, "danger");
      }
    });
  }

  containersBody.addEventListener("click", function (event) {
    const action = event.target.closest("button[data-container-action]");
    if (action) {
      runContainerAction(action);
      return;
    }
    const select = event.target.closest("button[data-select-container]");
    if (select) selectContainer(select.dataset.selectContainer);
  });

  async function loadLogs() {
    if (!selected) {
      c.setStatus("logs-status", "Select a container first.", "danger");
      return;
    }
    logOutput.textContent = "Loading logs…";
    logOutput.dataset.state = "loading";
    try {
      const data = await c.api(
        "/api/containers/logs?name=" + encodeURIComponent(selected) +
          "&tail=" + encodeURIComponent(logTail.value)
      );
      if (data && data.ok !== false) {
        logOutput.textContent = data.logs || "(empty log)";
        logOutput.dataset.state = data.logs ? "ready" : "empty";
        c.setStatus("logs-status", "Logs updated.", "success");
      } else {
        logOutput.textContent = "Failed to fetch logs.";
        logOutput.dataset.state = "error";
      }
    } catch (error) {
      logOutput.textContent = "Logs unavailable: " + error.message;
      logOutput.dataset.state = "error";
      c.setStatus("logs-status", "Logs unavailable.", "danger");
    }
  }

  reloadContainers.addEventListener("click", function () {
    c.withBusy(reloadContainers, "Loading…", loadContainers);
  });
  reloadLogs.addEventListener("click", function () {
    c.withBusy(reloadLogs, "Loading…", loadLogs);
  });
  logTail.addEventListener("change", function () {
    if (selected) loadLogs();
  });
  document.addEventListener("cloudio:reload", loadContainers);
})();
