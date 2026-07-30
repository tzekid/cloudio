(function () {
  "use strict";

  const c = window.cloudio;
  c.mount({ title: "Routes", active: "routes" });

  const routeForm = c.byId("route-form");
  const addButton = c.byId("add-route");
  const routesBody = c.byId("routes-body");
  const routesCount = c.byId("routes-count");
  const importButton = c.byId("import-btn");
  const previewButton = c.byId("preview-btn");
  const applyButton = c.byId("apply-btn");
  const result = c.byId("caddy-result");
  const previewOutput = c.byId("preview-output");

  function enabledControl(row) {
    return c.el("input", {
      type: "checkbox",
      checked: row.enabled,
      dataset: { toggleHost: row.host },
      attrs: { "aria-label": (row.enabled ? "Disable " : "Enable ") + row.host },
    });
  }

  async function loadRoutes() {
    try {
      const data = await c.api("/api/caddy/routes");
      const routes = data && data.routes ? data.routes : [];
      routesCount.textContent = routes.length + (routes.length === 1 ? " route" : " routes");
      c.renderTable(routesBody, routes, [
        { label: "Enabled", render: enabledControl },
        { label: "Host", key: "host", className: "mono breakable" },
        { label: "Upstream", key: "upstream", className: "mono breakable" },
        { label: "Kind", render: function (row) { return c.badge(row.kind || "manual", row.kind === "app" ? "info" : ""); } },
        { label: "Updated", render: function (row) { return c.formatTime(row.updated_at); }, className: "muted" },
        {
          label: "Actions",
          className: "cell-actions",
          render: function (row) {
            if (row.kind === "app") return c.el("span", { className: "muted", text: "Managed by app" });
            return c.button("Delete", {
              kind: "danger",
              small: true,
              dataset: { deleteHost: row.host },
            });
          },
        },
      ], "No desired routes.");
    } catch (error) {
      routesCount.textContent = "";
      c.tableEmpty(routesBody, 6, "Routes unavailable: " + error.message);
    }
  }

  routeForm.addEventListener("submit", function (event) {
    event.preventDefault();
    if (!routeForm.reportValidity()) return;
    c.withBusy(addButton, "Adding…", async function () {
      const host = c.byId("route-host").value.trim();
      try {
        await c.api("/api/caddy/routes", {
          method: "POST",
          body: {
            host: host,
            upstream: c.byId("route-upstream").value.trim(),
            extra_directives: c.byId("route-extra").value.trim() || null,
          },
        });
        c.toast("Route " + host + " added.", "success");
        routeForm.reset();
        await loadRoutes();
      } catch (error) {
        c.toast("Route creation failed: " + error.message, "danger");
      }
    });
  });

  routesBody.addEventListener("change", async function (event) {
    const toggle = event.target.closest("input[data-toggle-host]");
    if (!toggle) return;
    toggle.disabled = true;
    try {
      await c.api("/api/caddy/routes/toggle", {
        method: "POST",
        body: { host: toggle.dataset.toggleHost, enabled: toggle.checked },
      });
      c.toast("Route " + toggle.dataset.toggleHost + (toggle.checked ? " enabled." : " disabled."), "success");
    } catch (error) {
      toggle.checked = !toggle.checked;
      c.toast("Route update failed: " + error.message, "danger");
    } finally {
      toggle.disabled = false;
    }
  });

  routesBody.addEventListener("click", async function (event) {
    const control = event.target.closest("button[data-delete-host]");
    if (!control) return;
    const host = control.dataset.deleteHost;
    const confirmed = await c.confirmAction({
      title: "Delete route",
      message: "Delete the desired route for " + host + "? The active Caddyfile is unchanged until you apply it.",
      confirmLabel: "Delete route",
      danger: true,
    });
    if (!confirmed) return;
    await c.withBusy(control, "Deleting…", async function () {
      try {
        await c.api("/api/caddy/routes?host=" + encodeURIComponent(host), {
          method: "DELETE",
          confirm: true,
        });
        c.toast("Route " + host + " deleted.", "success");
        await loadRoutes();
      } catch (error) {
        c.toast("Route deletion failed: " + error.message, "danger");
      }
    });
  });

  async function fetchPreview() {
    previewOutput.classList.remove("hidden");
    previewOutput.dataset.state = "loading";
    previewOutput.textContent = "Loading desired Caddyfile…";
    try {
      const data = await c.api("/api/caddy/preview");
      previewOutput.textContent = data && data.rendered ? data.rendered : "(empty Caddyfile)";
      previewOutput.dataset.state = data && data.rendered ? "ready" : "empty";
      return previewOutput.textContent;
    } catch (error) {
      previewOutput.textContent = "Preview unavailable: " + error.message;
      previewOutput.dataset.state = "error";
      return null;
    }
  }

  previewButton.addEventListener("click", function () {
    c.withBusy(previewButton, "Loading…", fetchPreview);
  });

  importButton.addEventListener("click", async function () {
    const confirmed = await c.confirmAction({
      title: "Import current Caddyfile",
      message: "Import routes and preserved raw blocks from the configured Caddyfile into Cloudio’s desired state?",
      confirmLabel: "Import",
    });
    if (!confirmed) return;
    await c.withBusy(importButton, "Importing…", async function () {
      try {
        const data = await c.api("/api/caddy/import", { method: "POST" });
        const message = "Imported " + (data.imported_manual || 0) + " manual and " +
          (data.imported_raw || 0) + " raw blocks; skipped " + (data.skipped_app || 0) + " app routes.";
        c.setStatus(result, message, "success", false);
        c.toast("Caddyfile imported.", "success");
        await loadRoutes();
      } catch (error) {
        c.setStatus(result, "Import failed: " + error.message, "danger", false);
      }
    });
  });

  applyButton.addEventListener("click", async function () {
    const rendered = await fetchPreview();
    if (rendered == null) return;
    const confirmed = await c.confirmAction({
      title: "Apply desired Caddyfile",
      message: "Validate this preview, replace the configured Caddyfile, and reload Caddy? A backup is created before replacement.",
      confirmLabel: "Apply and reload",
      danger: true,
    });
    if (!confirmed) return;
    await c.withBusy(applyButton, "Applying…", async function () {
      try {
        const data = await c.api("/api/caddy/apply", {
          method: "POST",
          confirm: true,
        });
        const parts = [
          data.ok ? "Applied" : "Failed",
          "validated: " + Boolean(data.validated),
          "reloaded: " + Boolean(data.reloaded),
          data.bytes != null ? data.bytes + " bytes" : "",
          data.backup_path ? "backup " + data.backup_path : "",
        ].filter(Boolean);
        c.setStatus(result, parts.join(" · "), data.ok ? "success" : "danger", false);
        c.toast(data.ok ? "Caddyfile applied and reloaded." : "Caddyfile apply failed.", data.ok ? "success" : "danger");
      } catch (error) {
        c.setStatus(result, "Apply failed: " + error.message, "danger", false);
      }
    });
  });

  document.addEventListener("cloudio:reload", loadRoutes);
  loadRoutes();
})();
