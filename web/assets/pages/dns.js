(function () {
  "use strict";

  const c = window.cloudio;
  c.mount({ title: "DNS", active: "dns" });

  const domainInput = c.byId("domain");
  const sourceNote = c.byId("source-note");
  const recordsBody = c.byId("records-body");
  const recordCount = c.byId("record-count");
  const addForm = c.byId("add-record-form");
  const addButton = c.byId("add-record");

  let records = [];
  let zoneId = "";
  let writable = false;
  let editingId = null;

  function normalizeProxied(value) {
    if (typeof value === "boolean") return value;
    return ["true", "1", "proxied", "on"].includes(String(value || "").toLowerCase());
  }

  function setWriteAvailability(enabled) {
    addButton.disabled = !enabled;
    Array.from(addForm.elements).forEach(function (control) {
      if (control !== addButton) control.disabled = !enabled;
    });
  }

  async function loadZoneDomain() {
    try {
      const dashboard = await c.api("/api/dashboard?section=providers");
      const providers = dashboard && dashboard.sections ? dashboard.sections.providers || {} : {};
      const zones = providers.cloudflare ? providers.cloudflare.zones || [] : [];
      if (zones.length && !domainInput.value) domainInput.value = zones[0].name || "";
    } catch (_) {
      return;
    }
  }

  async function loadInventoryDomains() {
    try {
      const data = await c.api("/api/inventory?limit=500");
      const items = data && data.items ? data.items : [];
      const dnsItems = items.filter(function (item) { return item.kind === "dns-records"; });
      if (dnsItems.length && !domainInput.value) {
        domainInput.value = dnsItems[0].domain || dnsItems[0].display_name || "";
      }
      if (!domainInput.value) await loadZoneDomain();
      return dnsItems;
    } catch (_) {
      if (!domainInput.value) await loadZoneDomain();
      return [];
    }
  }

  function createRecordButton(label, className, recordId, kind) {
    return c.button(label, {
      kind: kind,
      small: true,
      className: className,
      dataset: { recordId: recordId },
    });
  }

  function renderEditRow(record) {
    const row = c.el("tr", { dataset: { editRecord: record.id } });
    const typeSelect = c.el("select", { attrs: { "aria-label": "Record type" } });
    ["A", "AAAA", "CNAME", "TXT", "MX"].forEach(function (type) {
      const option = c.el("option", { text: type, value: type });
      option.selected = type === record.type;
      typeSelect.appendChild(option);
    });
    typeSelect.className = "edit-record-type";

    const nameInput = c.el("input", {
      type: "text",
      value: record.name,
      className: "edit-record-name",
      attrs: { "aria-label": "Record name" },
    });
    const contentInput = c.el("input", {
      type: "text",
      value: record.content,
      className: "edit-record-content",
      attrs: { "aria-label": "Record content" },
    });
    const ttlInput = c.el("input", {
      type: "number",
      value: record.ttl || 1,
      className: "edit-record-ttl",
      attrs: { "aria-label": "Record TTL", min: "1" },
    });
    const proxyInput = c.el("input", {
      type: "checkbox",
      checked: record.proxied,
      className: "edit-record-proxied",
      attrs: { "aria-label": "Proxy this record" },
    });
    row.append(
      c.el("td", { children: typeSelect }),
      c.el("td", { children: nameInput }),
      c.el("td", { className: "cell-content", children: contentInput }),
      c.el("td", { children: ttlInput }),
      c.el("td", { children: proxyInput }),
      c.el("td", {
        className: "cell-actions",
        children: c.el("div", {
          className: "table-actions",
          children: [
            createRecordButton("Save", "save-record", record.id, "primary"),
            createRecordButton("Cancel", "cancel-record", record.id),
          ],
        }),
      })
    );
    return row;
  }

  function renderRecords() {
    recordsBody.replaceChildren();
    recordCount.textContent = records.length + (records.length === 1 ? " record" : " records");
    if (!records.length) {
      c.tableEmpty(recordsBody, 6, "No DNS records found.");
      return;
    }

    records.forEach(function (record) {
      if (String(editingId) === String(record.id)) {
        recordsBody.appendChild(renderEditRow(record));
        return;
      }
      const proxy = writable
        ? createRecordButton(record.proxied ? "Proxied" : "DNS only", "toggle-proxy", record.id, record.proxied ? "primary" : "")
        : c.badge(record.proxied ? "Proxied" : "DNS only", record.proxied ? "warning" : "");
      const actions = writable
        ? c.el("div", {
            className: "table-actions",
            children: [
              createRecordButton("Edit", "edit-record", record.id),
              createRecordButton("Delete", "delete-record", record.id, "danger"),
            ],
          })
        : c.el("span", { className: "muted", text: "Read-only" });
      recordsBody.appendChild(c.el("tr", {
        children: [
          c.el("td", { children: c.badge(record.type, "info") }),
          c.el("td", { className: "mono breakable", text: record.name }),
          c.el("td", { className: "mono cell-content", text: record.content }),
          c.el("td", { className: "mono", text: record.ttl }),
          c.el("td", { children: proxy }),
          c.el("td", { className: "cell-actions", children: actions }),
        ],
      }));
    });
  }

  async function loadRecords() {
    c.setNotice("dns-notice", "");
    c.tableEmpty(recordsBody, 6, "Loading DNS records…", true);
    const domain = domainInput.value.trim();
    try {
      const data = await c.api("/api/dns/records?domain=" + encodeURIComponent(domain));
      zoneId = data.zone_id || "";
      records = (data.records || []).map(function (record) {
        return {
          id: record.id,
          zone_id: record.zone_id || zoneId,
          name: record.name,
          type: record.type,
          content: record.content,
          ttl: record.ttl,
          proxied: normalizeProxied(record.proxied),
        };
      });
      writable = true;
      editingId = null;
      sourceNote.textContent = "Live Cloudflare data";
      setWriteAvailability(true);
      renderRecords();
      return;
    } catch (_) {
      writable = false;
    }

    const inventory = await loadInventoryDomains();
    const filtered = inventory.filter(function (item) {
      return !domain || item.domain === domain || String(item.display_name || "").endsWith(domain);
    });
    records = filtered.map(function (item) {
      return {
        id: item.resource_id,
        zone_id: item.zone_id,
        name: item.display_name,
        type: item.category,
        content: item.related_id,
        ttl: "",
        proxied: normalizeProxied(item.flag) || item.flag === "proxied",
      };
    });
    zoneId = filtered.length ? filtered[0].zone_id || "" : "";
    sourceNote.textContent = "Read-only inventory snapshot";
    setWriteAvailability(false);
    c.setNotice(
      "dns-notice",
      records.length
        ? "The live DNS endpoint is unavailable. Showing the latest read-only inventory snapshot."
        : "The live DNS endpoint is unavailable and no matching inventory records were found.",
      records.length ? "warning" : "danger"
    );
    renderRecords();
  }

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

  recordsBody.addEventListener("click", async function (event) {
    const control = event.target.closest("button[data-record-id]");
    if (!control) return;
    const record = records.find(function (item) {
      return String(item.id) === String(control.dataset.recordId);
    });
    if (!record) return;

    if (control.classList.contains("edit-record")) {
      editingId = record.id;
      renderRecords();
      return;
    }
    if (control.classList.contains("cancel-record")) {
      editingId = null;
      renderRecords();
      return;
    }
    if (control.classList.contains("delete-record")) {
      const confirmed = await c.confirmAction({
        title: "Delete DNS record",
        message: "Delete the " + record.type + " record for " + record.name + "? This changes public DNS.",
        confirmLabel: "Delete record",
        danger: true,
      });
      if (!confirmed) return;
      const ok = await write(
        "DELETE",
        "/api/dns/records?zone_id=" + encodeURIComponent(record.zone_id) +
          "&record_id=" + encodeURIComponent(record.id),
        null,
        "record-status",
        "Record deleted.",
        true
      );
      if (ok) await loadRecords();
      return;
    }
    if (control.classList.contains("toggle-proxy")) {
      const ok = await write("PUT", "/api/dns/records", {
        zone_id: record.zone_id,
        record_id: record.id,
        record: {
          type: record.type,
          name: record.name,
          content: record.content,
          ttl: Number(record.ttl) || 1,
          proxied: !record.proxied,
        },
      }, "record-status", "Proxy setting updated.");
      if (ok) await loadRecords();
      return;
    }
    if (control.classList.contains("save-record")) {
      const row = control.closest("tr");
      const ok = await write("PUT", "/api/dns/records", {
        zone_id: record.zone_id,
        record_id: record.id,
        record: {
          type: row.querySelector(".edit-record-type").value,
          name: row.querySelector(".edit-record-name").value.trim(),
          content: row.querySelector(".edit-record-content").value.trim(),
          ttl: Number(row.querySelector(".edit-record-ttl").value) || 1,
          proxied: row.querySelector(".edit-record-proxied").checked,
        },
      }, "record-status", "Record saved.");
      if (ok) {
        editingId = null;
        await loadRecords();
      }
    }
  });

  addForm.addEventListener("submit", function (event) {
    event.preventDefault();
    if (!addForm.reportValidity()) return;
    if (!zoneId) {
      c.setStatus("record-status", "No zone ID is available for this domain.", "danger");
      return;
    }
    c.withBusy(addButton, "Adding…", async function () {
      const ok = await write("POST", "/api/dns/records", {
        zone_id: zoneId,
        record: {
          type: c.byId("record-type").value,
          name: c.byId("record-name").value.trim(),
          content: c.byId("record-content").value.trim(),
          ttl: Number(c.byId("record-ttl").value) || 1,
          proxied: c.byId("record-proxied").checked,
        },
      }, "record-status", "Record added.");
      if (ok) {
        addForm.reset();
        c.byId("record-ttl").value = "1";
        await loadRecords();
      }
    });
  });

  c.byId("purge-cache").addEventListener("click", async function (event) {
    if (!zoneId) {
      c.setStatus("purge-status", "No zone ID is available.", "danger");
      return;
    }
    const confirmed = await c.confirmAction({
      title: "Purge zone cache",
      message: "Purge the entire Cloudflare cache for " + (domainInput.value.trim() || "this zone") + "?",
      confirmLabel: "Purge cache",
      danger: true,
    });
    if (!confirmed) return;
    await c.withBusy(event.currentTarget, "Purging…", function () {
      return write("POST", "/api/cache/purge", { zone_id: zoneId }, "purge-status", "Cache purged.", true);
    });
  });

  c.byId("apply-ssl").addEventListener("click", function (event) {
    if (!zoneId) {
      c.setStatus("ssl-status", "No zone ID is available.", "danger");
      return;
    }
    c.withBusy(event.currentTarget, "Applying…", function () {
      return write("POST", "/api/zone/setting", {
        zone_id: zoneId,
        setting: "ssl",
        value: c.byId("ssl-mode").value,
      }, "ssl-status", "SSL mode updated.");
    });
  });

  function setHttps(value, control) {
    if (!zoneId) {
      c.setStatus("https-status", "No zone ID is available.", "danger");
      return;
    }
    c.withBusy(control, "Applying…", function () {
      return write("POST", "/api/zone/setting", {
        zone_id: zoneId,
        setting: "always_use_https",
        value: value,
      }, "https-status", "Always use HTTPS " + (value === "on" ? "enabled." : "disabled."));
    });
  }

  c.byId("https-on").addEventListener("click", function (event) {
    setHttps("on", event.currentTarget);
  });
  c.byId("https-off").addEventListener("click", function (event) {
    setHttps("off", event.currentTarget);
  });
  document.addEventListener("cloudio:reload", loadRecords);
  setWriteAvailability(false);
})();
