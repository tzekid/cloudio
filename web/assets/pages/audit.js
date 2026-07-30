(function () {
  "use strict";

  const c = window.cloudio;
  c.mount({ title: "Audit log", active: "audit" });

  const auditBody = c.byId("audit-body");
  const limit = c.byId("audit-limit");
  const autoRefresh = c.byId("audit-auto");
  const reloadButton = c.byId("reload-audit");
  const updated = c.byId("audit-updated");
  const count = c.byId("audit-count");

  let actions = [];
  const expanded = new Set();
  let timer = null;

  function pretty(value) {
    if (value == null || value === "") return "";
    if (typeof value === "object") return JSON.stringify(value, null, 2);
    try {
      return JSON.stringify(JSON.parse(value), null, 2);
    } catch (_) {
      return String(value);
    }
  }

  function detailBlock(label, value) {
    return c.el("div", {
      className: "detail-block",
      children: [
        c.el("div", { className: "detail-label", text: label }),
        c.el("pre", { className: "code-block", text: pretty(value) }),
      ],
    });
  }

  function render() {
    auditBody.replaceChildren();
    count.textContent = actions.length + (actions.length === 1 ? " entry" : " entries");
    if (!actions.length) {
      c.tableEmpty(auditBody, 6, "No audit entries.");
      return;
    }

    actions.forEach(function (action) {
      const id = String(action.id);
      const hasDetail = action.request != null && action.request !== "" ||
        action.detail != null && action.detail !== "" ||
        Boolean(action.idempotency_key);
      const isExpanded = expanded.has(id);
      const expandControl = hasDetail
        ? c.button(isExpanded ? "Collapse" : "Expand", {
            kind: "quiet",
            small: true,
            dataset: { auditEntry: id },
            attrs: {
              "aria-expanded": String(isExpanded),
              "aria-label": (isExpanded ? "Collapse" : "Expand") + " audit entry " + id,
            },
          })
        : c.el("span", { className: "muted", text: "—" });
      auditBody.appendChild(c.el("tr", {
        children: [
          c.el("td", { className: "mono cell-nowrap", text: c.formatTime(action.created_at) }),
          c.el("td", { className: "mono", text: action.actor || "—" }),
          c.el("td", { text: action.action || "—" }),
          c.el("td", { className: "mono breakable", text: action.target || "—" }),
          c.el("td", { children: c.badge(action.result, action.result === "ok" ? "success" : "danger") }),
          c.el("td", { children: expandControl }),
        ],
      }));

      if (isExpanded) {
        const detail = c.el("div");
        if (action.request) detail.appendChild(detailBlock("Request", action.request));
        if (action.detail) detail.appendChild(detailBlock("Detail", action.detail));
        if (action.idempotency_key) detail.appendChild(detailBlock("Idempotency key", action.idempotency_key));
        auditBody.appendChild(c.el("tr", {
          className: "audit-detail",
          children: c.el("td", {
            attrs: { colspan: "6" },
            children: detail,
          }),
        }));
      }
    });
  }

  async function load() {
    try {
      const data = await c.api("/api/audit?limit=" + encodeURIComponent(limit.value));
      actions = data && data.actions ? data.actions : [];
      c.setNotice("audit-notice", "");
      updated.textContent = "Updated " + new Date().toLocaleTimeString();
      render();
    } catch (error) {
      c.setNotice("audit-notice", "Audit log unavailable: " + error.message, "danger");
    }
  }

  auditBody.addEventListener("click", function (event) {
    const control = event.target.closest("button[data-audit-entry]");
    if (!control) return;
    const id = control.dataset.auditEntry;
    if (expanded.has(id)) expanded.delete(id);
    else expanded.add(id);
    render();
    const replacement = auditBody.querySelector('button[data-audit-entry="' + CSS.escape(id) + '"]');
    if (replacement) replacement.focus();
  });

  reloadButton.addEventListener("click", function () {
    c.withBusy(reloadButton, "Loading…", load);
  });
  limit.addEventListener("change", load);
  autoRefresh.addEventListener("change", function () {
    if (autoRefresh.checked) {
      timer = window.setInterval(load, 10000);
    } else if (timer) {
      window.clearInterval(timer);
      timer = null;
    }
  });
  document.addEventListener("cloudio:reload", load);
  window.addEventListener("pagehide", function () {
    if (timer) window.clearInterval(timer);
  }, { once: true });
  load();
})();
