(function () {
  "use strict";

  const c = window.cloudio;
  c.mount({ title: "VPS", active: "vps" });

  const machines = c.byId("machines");
  const metrics = c.byId("metrics");
  const firewalls = c.byId("firewalls");
  const ruleForm = c.byId("rule-form");
  const addRuleButton = c.byId("add-rule");
  const updateRuleButton = c.byId("update-rule");
  let actionable = true;

  async function write(method, url, body, statusTarget, successMessage, confirmed) {
    try {
      const data = await c.api(url, {
        method: method,
        body: body,
        confirm: confirmed === true,
      });
      const ok = !data || data.ok !== false;
      c.setStatus(statusTarget, ok ? successMessage : "Operation failed.", ok ? "success" : "danger");
      return ok;
    } catch (error) {
      c.setStatus(statusTarget, "Operation failed: " + error.message, "danger");
      return false;
    }
  }

  function machineCard(machine) {
    const title = machine.name || machine.id || "Unnamed machine";
    const card = c.el("article", { className: "resource-card" });
    card.appendChild(c.el("div", {
      className: "resource-card-header",
      children: [
        c.el("h3", { className: "resource-card-title", text: title, title: title }),
        c.status(machine.status),
      ],
    }));
    const details = c.el("dl", { className: "kv-list" });
    [
      ["IPv4", machine.ipv4 || "—"],
      ["Plan", machine.plan || "—"],
      ["ID", machine.id || "—"],
    ].forEach(function (entry) {
      details.appendChild(c.el("div", {
        className: "kv-row",
        children: [
          c.el("dt", { text: entry[0] }),
          c.el("dd", { className: "mono", text: entry[1] }),
        ],
      }));
    });
    card.appendChild(details);

    if (actionable) {
      card.appendChild(c.el("div", {
        className: "resource-card-actions",
        children: [
          c.button("Start", { small: true, dataset: { machineAction: "start", machineId: machine.id } }),
          c.button("Stop", { small: true, kind: "danger", dataset: { machineAction: "stop", machineId: machine.id } }),
          c.button("Restart", { small: true, dataset: { machineAction: "restart", machineId: machine.id } }),
        ],
      }));
    } else {
      card.appendChild(c.el("div", { className: "resource-card-actions muted", text: "Actions unavailable for snapshot data." }));
    }
    return card;
  }

  function renderMachines(rows) {
    machines.replaceChildren();
    if (!rows.length) {
      machines.appendChild(c.el("div", { className: "resource-card empty-state", text: "No machines found." }));
      return;
    }
    rows.forEach(function (machine) {
      machines.appendChild(machineCard(machine));
    });
  }

  async function loadMachines() {
    c.setNotice("vps-notice", "");
    try {
      const data = await c.api("/api/vps");
      actionable = true;
      renderMachines(data.machines || []);
      return;
    } catch (_) {
      actionable = false;
    }
    try {
      const dashboard = await c.api("/api/dashboard?section=vps");
      const section = dashboard && dashboard.sections ? dashboard.sections.vps || {} : {};
      renderMachines(section.items || []);
      c.setNotice("vps-notice", "The live VPS endpoint is unavailable. Showing the latest read-only dashboard snapshot.", "warning");
    } catch (error) {
      machines.replaceChildren(c.el("div", { className: "resource-card empty-state", text: "No machine data available." }));
      c.setNotice("vps-notice", "VPS data unavailable: " + error.message, "danger");
    }
  }

  machines.addEventListener("click", async function (event) {
    const control = event.target.closest("button[data-machine-action]");
    if (!control) return;
    const action = control.dataset.machineAction;
    const id = control.dataset.machineId;
    const confirmed = await c.confirmAction({
      title: action.charAt(0).toUpperCase() + action.slice(1) + " machine",
      message: action.charAt(0).toUpperCase() + action.slice(1) + " machine " + id + "?",
      confirmLabel: action.charAt(0).toUpperCase() + action.slice(1),
      danger: action === "stop",
    });
    if (!confirmed) return;
    await c.withBusy(control, "Working…", async function () {
      const ok = await write("POST", "/api/vps/action", {
        vm_id: String(id),
        action: action,
      }, "machine-status", action + " requested.", true);
      if (ok) window.setTimeout(loadMachines, 1500);
    });
  });

  async function loadMetrics() {
    try {
      const dashboard = await c.api("/api/dashboard?section=vps");
      const section = dashboard && dashboard.sections ? dashboard.sections.vps || {} : {};
      const rows = section.metrics || [];
      if (!rows.length) {
        metrics.replaceChildren(c.el("div", { className: "empty-state", text: "No metric rows." }));
        return;
      }
      const table = c.el("table");
      table.appendChild(c.el("thead", {
        children: c.el("tr", {
          children: ["VM", "Metric", "Samples", "Latest captured"].map(function (label) {
            return c.el("th", { text: label, attrs: { scope: "col" } });
          }),
        }),
      }));
      const body = c.el("tbody");
      c.renderTable(body, rows, [
        { label: "VM", key: "vm_id", className: "mono" },
        { label: "Metric", key: "metric" },
        { label: "Samples", key: "count" },
        { label: "Latest captured", render: function (row) { return c.formatTime(row.latest_captured); }, className: "muted" },
      ], "No metric rows.");
      table.appendChild(body);
      metrics.replaceChildren(table);
    } catch (error) {
      metrics.replaceChildren(c.el("div", { className: "empty-state", text: "Metrics unavailable: " + error.message }));
    }
  }

  function valueText(value) {
    if (value == null) return "";
    return typeof value === "object" ? JSON.stringify(value) : String(value);
  }

  function objectTable(object) {
    const table = c.el("table");
    const body = c.el("tbody");
    Object.entries(object).forEach(function (entry) {
      body.appendChild(c.el("tr", {
        children: [
          c.el("td", { className: "muted cell-nowrap", text: entry[0] }),
          c.el("td", { className: "mono breakable", text: valueText(entry[1]) }),
        ],
      }));
    });
    table.appendChild(body);
    return c.el("div", { className: "table-scroll", children: table });
  }

  function rulesTable(firewallId, rules) {
    const table = c.el("table");
    table.appendChild(c.el("thead", {
      children: c.el("tr", {
        children: ["ID", "Protocol", "Port", "Source", "Action", "Actions"].map(function (label) {
          return c.el("th", { text: label, attrs: { scope: "col" } });
        }),
      }),
    }));
    const body = c.el("tbody");
    c.renderTable(body, rules, [
      { label: "ID", key: "id", className: "mono" },
      { label: "Protocol", key: "protocol" },
      { label: "Port", key: "port" },
      {
        label: "Source",
        render: function (rule) {
          return rule.source != null ? rule.source : rule.source_detail;
        },
        className: "breakable",
      },
      { label: "Action", render: function (rule) { return c.badge(rule.action, rule.action === "accept" ? "success" : "danger"); } },
      {
        label: "Actions",
        className: "cell-actions",
        render: function (rule) {
          return c.el("div", {
            className: "table-actions",
            children: [
              c.button("Edit", {
                small: true,
                dataset: {
                  editRule: rule.id,
                  firewallId: firewallId,
                  protocol: rule.protocol || "TCP",
                  port: rule.port || "",
                  source: rule.source || "",
                  ruleAction: rule.action || "accept",
                },
              }),
              c.button("Delete", {
                kind: "danger",
                small: true,
                dataset: { deleteRule: rule.id, firewallId: firewallId },
              }),
            ],
          });
        },
      },
    ], "No firewall rules.");
    table.appendChild(body);
    return c.el("div", { className: "table-scroll", children: table });
  }

  function firewallSection(firewall, index) {
    const firewallId = firewall.id == null ? "" : String(firewall.id);
    const syncInputId = "firewall-sync-machine-" + index;
    const syncInput = c.el("input", {
      id: syncInputId,
      type: "text",
      className: "firewall-sync-machine",
      attrs: { placeholder: "machine id", autocomplete: "off" },
    });
    const header = c.el("div", {
      className: "cluster cluster-spread",
      children: [
        c.el("h3", {
          className: "resource-card-title",
          text: "Firewall " + (firewall.name || firewallId || "unknown"),
        }),
        c.el("div", {
          className: "cluster",
          children: [
            c.el("label", { className: "sr-only", text: "Machine ID", attrs: { for: syncInputId } }),
            syncInput,
            c.button("Sync", {
              small: true,
              dataset: { syncFirewall: firewallId, syncInput: syncInputId },
            }),
          ],
        }),
      ],
    });
    const body = firewall.rules && firewall.rules.length
      ? rulesTable(firewallId, firewall.rules)
      : c.el("div", {
          className: "stack",
          children: [
            c.el("p", { className: "muted", text: "No expanded rule list is available; showing captured firewall fields." }),
            objectTable(firewall),
          ],
        });
    return c.el("section", {
      className: "resource-card stack",
      children: [header, body],
    });
  }

  async function loadFirewalls() {
    c.setNotice("firewall-notice", "");
    try {
      const data = await c.api("/api/firewalls");
      const rows = data.firewalls || [];
      if (!rows.length) {
        firewalls.replaceChildren(c.el("div", { className: "empty-state", text: "No firewalls found." }));
        return;
      }
      firewalls.replaceChildren.apply(firewalls, rows.map(firewallSection));
    } catch (error) {
      firewalls.replaceChildren();
      c.setNotice("firewall-notice", "Firewall data unavailable: " + error.message, "danger");
    }
  }

  firewalls.addEventListener("click", async function (event) {
    const deleteControl = event.target.closest("button[data-delete-rule]");
    if (deleteControl) {
      const confirmed = await c.confirmAction({
        title: "Delete firewall rule",
        message: "Delete rule " + deleteControl.dataset.deleteRule + " from firewall " + deleteControl.dataset.firewallId + "?",
        confirmLabel: "Delete rule",
        danger: true,
      });
      if (!confirmed) return;
      const ok = await write(
        "DELETE",
        "/api/firewall/rule?firewall_id=" + encodeURIComponent(deleteControl.dataset.firewallId) +
          "&rule_id=" + encodeURIComponent(deleteControl.dataset.deleteRule),
        null,
        "rule-status",
        "Rule deleted.",
        true
      );
      if (ok) await loadFirewalls();
      return;
    }

    const editControl = event.target.closest("button[data-edit-rule]");
    if (editControl) {
      c.byId("rule-firewall").value = editControl.dataset.firewallId;
      c.byId("rule-id").value = editControl.dataset.editRule;
      c.byId("rule-protocol").value = editControl.dataset.protocol || "TCP";
      c.byId("rule-port").value = editControl.dataset.port || "";
      c.byId("rule-source").value = editControl.dataset.source || "";
      c.byId("rule-action").value = editControl.dataset.ruleAction || "accept";
      ruleForm.scrollIntoView({ block: "center" });
      c.setStatus("rule-status", "Rule loaded into the form.", "success");
      return;
    }

    const syncControl = event.target.closest("button[data-sync-firewall]");
    if (syncControl) {
      const machineId = c.byId(syncControl.dataset.syncInput).value.trim();
      if (!machineId) {
        c.setStatus("rule-status", "Enter a machine ID to sync.", "danger");
        return;
      }
      const confirmed = await c.confirmAction({
        title: "Sync firewall",
        message: "Sync firewall " + syncControl.dataset.syncFirewall + " to machine " + machineId + "?",
        confirmLabel: "Sync firewall",
        danger: true,
      });
      if (!confirmed) return;
      await c.withBusy(syncControl, "Syncing…", function () {
        return write("POST", "/api/firewall/sync", {
          firewall_id: String(syncControl.dataset.syncFirewall),
          vm_id: machineId,
        }, "rule-status", "Firewall sync requested.", true);
      });
    }
  });

  function rulePayload() {
    return {
      protocol: c.byId("rule-protocol").value,
      port: c.byId("rule-port").value.trim(),
      source: c.byId("rule-source").value.trim(),
      action: c.byId("rule-action").value,
    };
  }

  ruleForm.addEventListener("submit", function (event) {
    event.preventDefault();
    if (!ruleForm.reportValidity()) return;
    c.withBusy(addRuleButton, "Adding…", async function () {
      const ok = await write("POST", "/api/firewall/rule", {
        firewall_id: c.byId("rule-firewall").value.trim(),
        rule: rulePayload(),
      }, "rule-status", "Rule added.");
      if (ok) await loadFirewalls();
    });
  });

  updateRuleButton.addEventListener("click", function () {
    const ruleId = c.byId("rule-id").value.trim();
    if (!ruleId) {
      c.setStatus("rule-status", "A rule ID is required for update.", "danger");
      return;
    }
    if (!ruleForm.reportValidity()) return;
    c.withBusy(updateRuleButton, "Updating…", async function () {
      const ok = await write("PUT", "/api/firewall/rule", {
        firewall_id: c.byId("rule-firewall").value.trim(),
        rule_id: ruleId,
        rule: rulePayload(),
      }, "rule-status", "Rule updated.");
      if (ok) await loadFirewalls();
    });
  });

  async function loadAll() {
    await Promise.all([loadMachines(), loadMetrics(), loadFirewalls()]);
  }

  document.addEventListener("cloudio:reload", loadAll);
})();
