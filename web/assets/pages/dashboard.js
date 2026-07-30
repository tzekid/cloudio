(function () {
  "use strict";

  const c = window.cloudio;
  c.mount({ title: "Dashboard", active: "dashboard" });

  const summaryCards = c.byId("summary-cards");
  const topologyBody = c.byId("topology-body");
  const domainFilter = c.byId("domain-filter");
  const issuesOnly = c.byId("issues-only");
  const lastRefresh = c.byId("last-refresh");
  const reloadButton = c.byId("dashboard-reload");
  let requestSequence = 0;

  function textWithDetail(primary, detail) {
    const content = document.createDocumentFragment();
    content.append(primary || "—");
    if (detail) {
      content.append(" ", c.el("span", { className: "muted", text: "(" + detail + ")" }));
    }
    return content;
  }

  function issueBadges(issues) {
    const list = c.el("div", { className: "badge-list" });
    (issues || []).forEach(function (issue) {
      list.appendChild(c.badge(issue, "danger"));
    });
    return list;
  }

  function renderSummary(summary) {
    const statuses = summary.statuses || {};
    const issueCounts = summary.issues || {};
    const issueTotal = Object.values(issueCounts).reduce(function (total, value) {
      return total + Number(value || 0);
    }, 0);
    const cards = [
      { label: "Hosts", value: summary.total || 0 },
      { label: "Healthy", value: statuses.healthy || 0, tone: "success" },
      { label: "Degraded", value: statuses.degraded || 0, tone: statuses.degraded ? "danger" : "" },
      { label: "DNS only", value: statuses.dns_only || 0, tone: statuses.dns_only ? "warning" : "" },
      { label: "Local only", value: statuses.local_only || 0, tone: statuses.local_only ? "warning" : "" },
      { label: "Project only", value: statuses.project_only || 0, tone: statuses.project_only ? "warning" : "" },
      { label: "Issues", value: issueTotal, tone: issueTotal ? "danger" : "success" },
    ];
    summaryCards.replaceChildren.apply(summaryCards, cards.map(function (card) {
      return c.el("article", {
        className: "stat-card" + (card.tone ? " tone-" + card.tone : ""),
        children: [
          c.el("div", { className: "stat-value", text: card.value }),
          c.el("div", { className: "stat-label", text: card.label }),
        ],
      });
    }));
  }

  function renderTopology(rows) {
    c.renderTable(topologyBody, rows, [
      {
        label: "Status",
        render: function (row) {
          return c.status(row.status);
        },
        className: "cell-nowrap",
      },
      {
        label: "Host",
        render: function (row) {
          return row.host || row.project || "(unnamed)";
        },
        className: "mono cell-nowrap",
      },
      {
        label: "DNS match",
        render: function (row) {
          if (!row.dns_match || row.dns_match === "none") {
            return c.el("span", { className: "muted", text: "none" });
          }
          return c.badge(row.dns_match, row.dns_match === "direct" ? "success" : "info");
        },
      },
      { label: "Exposure", key: "exposure", className: "muted" },
      { label: "Upstream", key: "upstream", className: "mono cell-nowrap" },
      {
        label: "Service",
        render: function (row) {
          return textWithDetail(row.service, row.service_state);
        },
      },
      {
        label: "Container",
        render: function (row) {
          return textWithDetail(row.container, row.container_status);
        },
      },
      {
        label: "Issues",
        render: function (row) {
          return issueBadges(row.issues);
        },
      },
    ], "No topology rows match this view.");
  }

  async function load() {
    const sequence = ++requestSequence;
    const params = new URLSearchParams({ section: "domains" });
    const domain = domainFilter.value.trim();
    if (domain) params.set("domain", domain);
    if (issuesOnly.checked) params.set("issues", "1");

    try {
      const data = await c.api("/api/dashboard?" + params.toString());
      if (sequence !== requestSequence) return;
      const summary = data && data.summary ? data.summary : {};
      renderSummary(summary.topology || {});
      const refresh = summary.last_refresh;
      lastRefresh.textContent = refresh && refresh.created_at
        ? "Data refreshed " + c.formatTime(refresh.created_at)
        : "No completed refresh recorded";
      const rows = data && data.sections && data.sections.domains
        ? data.sections.domains.topology || []
        : [];
      renderTopology(rows);
    } catch (error) {
      if (sequence !== requestSequence) return;
      c.tableEmpty(topologyBody, 8, "Dashboard unavailable: " + error.message);
      c.toast("Dashboard failed to load: " + error.message, "danger");
    }
  }

  domainFilter.addEventListener("input", c.debounce(load, 250));
  issuesOnly.addEventListener("change", load);
  reloadButton.addEventListener("click", function () {
    c.withBusy(reloadButton, "Reloading…", load);
  });
  document.addEventListener("cloudio:reload", load);

  const stopWatching = c.watchChanges(load);
  window.addEventListener("pagehide", stopWatching, { once: true });
  load();
})();
