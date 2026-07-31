(function () {
  "use strict";

  const NAV_ITEMS = [
    { id: "dashboard", href: "/", label: "Dashboard", paths: ["/", "/index.html"] },
    { id: "apps", href: "/apps.html", label: "Apps" },
    { id: "routes", href: "/routes.html", label: "Routes" },
    { id: "dns", href: "/dns.html", label: "DNS" },
    { id: "vps", href: "/vps.html", label: "VPS" },
    { id: "docker", href: "/docker.html", label: "Docker" },
    { id: "audit", href: "/audit.html", label: "Audit" },
    { id: "security", href: "/security.html", label: "Security" },
    { id: "settings", href: "/settings.html", label: "Settings" },
  ];

  const statusTimers = new WeakMap();
  let dialogElements = null;
  let sessionPromise = null;

  function byId(id) {
    return document.getElementById(id);
  }

  function appendValue(parent, value) {
    if (value == null || value === false) return;
    if (value instanceof Node) {
      parent.appendChild(value);
      return;
    }
    if (Array.isArray(value)) {
      value.forEach(function (child) {
        appendValue(parent, child);
      });
      return;
    }
    parent.appendChild(document.createTextNode(String(value)));
  }

  function el(tag, options) {
    const node = document.createElement(tag);
    const opts = options || {};

    if (opts.className) node.className = opts.className;
    if (opts.text != null) node.textContent = String(opts.text);
    if (opts.id) node.id = opts.id;
    if (opts.type) node.type = opts.type;
    if (opts.href) node.href = opts.href;
    if (opts.value != null) node.value = String(opts.value);
    if (opts.title) node.title = opts.title;
    if (opts.role) node.setAttribute("role", opts.role);
    if (opts.tabIndex != null) node.tabIndex = opts.tabIndex;
    if (opts.checked != null) node.checked = Boolean(opts.checked);
    if (opts.disabled != null) node.disabled = Boolean(opts.disabled);

    Object.entries(opts.attrs || {}).forEach(function (entry) {
      const name = entry[0];
      const value = entry[1];
      if (value == null || value === false) return;
      node.setAttribute(name, value === true ? "" : String(value));
    });
    Object.entries(opts.dataset || {}).forEach(function (entry) {
      node.dataset[entry[0]] = String(entry[1]);
    });
    appendValue(node, opts.children);
    return node;
  }

  function clear(node) {
    node.replaceChildren();
    return node;
  }

  function toneClass(tone) {
    return tone ? " tone-" + tone : "";
  }

  function statusTone(value) {
    const normalized = String(value || "").toLowerCase();
    if (["healthy", "running", "active", "ok", "success", "deployed", "ready", "enabled", "up"].includes(normalized)) {
      return "success";
    }
    if (["degraded", "failed", "failure", "error", "dead", "exited", "invalid", "down"].includes(normalized)) {
      return "danger";
    }
    if (["pending", "deploying", "stopped", "inactive", "warning", "dns_only", "local_only", "project_only"].includes(normalized)) {
      return "warning";
    }
    if (["info", "manual", "app", "proxied"].includes(normalized)) return "info";
    return "";
  }

  function badge(text, tone) {
    return el("span", {
      className: "badge" + toneClass(tone || statusTone(text)),
      text: text == null || text === "" ? "unknown" : text,
    });
  }

  function status(text, tone) {
    return el("span", {
      className: "status" + toneClass(tone || statusTone(text)),
      text: text == null || text === "" ? "unknown" : text,
    });
  }

  function button(label, options) {
    const opts = Object.assign({}, options || {});
    const classes = ["button"];
    if (opts.kind) classes.push("button-" + opts.kind);
    if (opts.small) classes.push("button-small");
    if (opts.className) classes.push(opts.className);
    return el("button", {
      type: opts.type || "button",
      className: classes.join(" "),
      text: label,
      title: opts.title,
      disabled: opts.disabled,
      attrs: opts.attrs,
      dataset: opts.dataset,
    });
  }

  function createBrand() {
    const brand = el("a", {
      className: "brand",
      href: "/",
      attrs: { "aria-label": "Cloudio dashboard" },
    });
    brand.append("cloud", el("span", { text: "io" }));
    return brand;
  }

  function createDialog() {
    const dialog = el("dialog", { attrs: { "aria-labelledby": "confirm-dialog-title" } });
    const form = el("form", { className: "dialog-form", attrs: { method: "dialog" } });
    const title = el("h2", { id: "confirm-dialog-title", className: "dialog-title" });
    const message = el("div", { className: "dialog-body" });
    const cancel = button("Cancel", {
      type: "submit",
      attrs: { value: "cancel", autofocus: true },
    });
    const confirm = button("Confirm", {
      type: "submit",
      kind: "primary",
      attrs: { value: "confirm" },
    });
    form.append(
      el("div", { className: "dialog-header", children: title }),
      message,
      el("div", { className: "dialog-actions", children: [cancel, confirm] })
    );
    dialog.appendChild(form);
    dialogElements = { dialog: dialog, title: title, message: message, cancel: cancel, confirm: confirm };
    return dialog;
  }

  function mount(options) {
    const opts = options || {};
    const content = byId("page-content");
    if (!content) throw new Error("Missing #page-content");
    content.classList.add("page-content");
    content.tabIndex = -1;

    const path = window.location.pathname;
    const active = opts.active || (NAV_ITEMS.find(function (item) {
      return (item.paths || [item.href]).includes(path);
    }) || {}).id;

    const existingShell = byId("app-shell");
    if (existingShell) {
      const sidebar = byId("primary-sidebar");
      const menu = existingShell.querySelector(".menu-button");
      const scrim = document.querySelector(".sidebar-scrim");
      const titlebarActions = existingShell.querySelector(".titlebar-actions");
      const refresh = byId("refresh-data-button");
      const existingDialog = document.querySelector("dialog");
      if (existingDialog) existingDialog.remove();
      document.body.appendChild(createDialog());

      function setExistingMenu(open) {
        sidebar.dataset.open = String(open);
        scrim.dataset.open = String(open);
        menu.setAttribute("aria-expanded", String(open));
        if (open) {
          const current = sidebar.querySelector('[aria-current="page"]') || sidebar.querySelector("a");
          if (current) current.focus();
        } else {
          menu.focus();
        }
      }

      menu.addEventListener("click", function () {
        setExistingMenu(sidebar.dataset.open !== "true");
      });
      scrim.addEventListener("click", function () {
        setExistingMenu(false);
      });
      sidebar.addEventListener("click", function (event) {
        if (event.target.closest("a") && window.matchMedia("(max-width: 720px)").matches) {
          sidebar.dataset.open = "false";
          scrim.dataset.open = "false";
          menu.setAttribute("aria-expanded", "false");
        }
      });
      document.addEventListener("keydown", function (event) {
        if (event.key === "Escape" && sidebar.dataset.open === "true") setExistingMenu(false);
      });

      if (refresh) {
        refresh.addEventListener("click", async function () {
          await withBusy(refresh, "Refreshing…", async function () {
            try {
              await api("/api/refresh", { method: "POST" });
              toast("Data refresh completed.", "success");
              document.dispatchEvent(new CustomEvent("cloudio:reload"));
            } catch (error) {
              toast("Refresh failed: " + error.message, "danger");
            }
          });
        });
      }
      return { content: content, titlebarActions: titlebarActions };
    }

    const navList = el("ul");
    NAV_ITEMS.forEach(function (item) {
      const link = el("a", { href: item.href, text: item.label });
      if (item.id === active) link.setAttribute("aria-current", "page");
      navList.appendChild(el("li", { children: link }));
    });

    const sidebar = el("aside", {
      id: "primary-sidebar",
      className: "sidebar",
      attrs: { "aria-label": "Application navigation", "data-open": "false" },
      children: [
        createBrand(),
        el("nav", {
          className: "primary-nav",
          attrs: { "aria-label": "Primary" },
          children: navList,
        }),
        el("div", { className: "sidebar-meta", text: "Control plane" }),
      ],
    });

    const menu = button("Menu", {
      className: "menu-button",
      attrs: {
        "aria-controls": "primary-sidebar",
        "aria-expanded": "false",
      },
    });
    const heading = el("h1", { id: "page-title", text: opts.title || document.title });
    const titlebarActions = el("div", { className: "titlebar-actions" });

    if (opts.refresh !== false) {
      const refresh = button("Refresh data", {
        title: "Collect fresh provider and system data",
      });
      refresh.id = "refresh-data-button";
      refresh.addEventListener("click", async function () {
        await withBusy(refresh, "Refreshing…", async function () {
          try {
            await api("/api/refresh", { method: "POST" });
            toast("Data refresh completed.", "success");
            document.dispatchEvent(new CustomEvent("cloudio:reload"));
          } catch (error) {
            toast("Refresh failed: " + error.message, "danger");
          }
        });
      });
      titlebarActions.appendChild(refresh);
    }

    (opts.actions || []).forEach(function (action) {
      appendValue(titlebarActions, action);
    });

    const titlebar = el("header", {
      className: "titlebar",
      children: [
        menu,
        el("div", {
          className: "titlebar-heading",
          children: [
            el("div", { className: "titlebar-eyebrow", text: "Cloudio" }),
            heading,
          ],
        }),
        titlebarActions,
      ],
    });

    const workspace = el("div", {
      className: "workspace",
      children: [titlebar, content],
    });
    const shell = el("div", {
      className: "shell",
      children: [sidebar, workspace],
    });
    const scrim = button("Close navigation", {
      className: "sidebar-scrim",
      attrs: { "aria-label": "Close navigation", "data-open": "false" },
    });
    const toasts = el("div", {
      id: "toast-region",
      className: "toast-region",
      attrs: { "aria-live": "polite", "aria-label": "Notifications" },
    });
    const skip = el("a", {
      className: "skip-link",
      href: "#page-content",
      text: "Skip to content",
    });
    const dialog = createDialog();
    document.body.replaceChildren(skip, shell, scrim, toasts, dialog);

    function setMenu(open) {
      sidebar.dataset.open = String(open);
      scrim.dataset.open = String(open);
      menu.setAttribute("aria-expanded", String(open));
      if (open) {
        const current = sidebar.querySelector('[aria-current="page"]') || sidebar.querySelector("a");
        if (current) current.focus();
      } else {
        menu.focus();
      }
    }

    menu.addEventListener("click", function () {
      setMenu(sidebar.dataset.open !== "true");
    });
    scrim.addEventListener("click", function () {
      setMenu(false);
    });
    sidebar.addEventListener("click", function (event) {
      if (event.target.closest("a") && window.matchMedia("(max-width: 720px)").matches) {
        sidebar.dataset.open = "false";
        scrim.dataset.open = "false";
        menu.setAttribute("aria-expanded", "false");
      }
    });
    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape" && sidebar.dataset.open === "true") setMenu(false);
    });

    return { content: content, titlebarActions: titlebarActions };
  }

  function toast(message, tone) {
    let region = byId("toast-region");
    if (!region) {
      region = el("div", {
        id: "toast-region",
        className: "toast-region",
        attrs: { "aria-live": "polite" },
      });
      document.body.appendChild(region);
    }
    const item = el("div", {
      className: "toast" + toneClass(tone),
      text: message,
      role: tone === "danger" ? "alert" : "status",
    });
    region.appendChild(item);
    window.setTimeout(function () {
      item.remove();
    }, 6000);
  }

  async function api(url, options) {
    const opts = Object.assign({ credentials: "same-origin" }, options || {});
    const confirmed = opts.confirm === true;
    const actor = opts.actor || "web";
    const suppliedKey = opts.idempotencyKey;
    delete opts.confirm;
    delete opts.actor;
    delete opts.idempotencyKey;

    const method = String(opts.method || "GET").toUpperCase();
    opts.headers = Object.assign({ Accept: "application/json" }, opts.headers || {});
    const unsafe = !["GET", "HEAD", "OPTIONS"].includes(method);
    const mutation = unsafe &&
      !url.startsWith("/api/auth/") &&
      url !== "/api/actions/plan";

    if (unsafe) {
      const session = await authenticatedSession();
      opts.headers["X-Cloudio-CSRF"] = session.csrf_token;
    }

    if (mutation) {
      const randomPart = window.crypto && window.crypto.randomUUID
        ? window.crypto.randomUUID()
        : Date.now().toString(36) + "-" + Math.random().toString(36).slice(2);
      opts.headers["Idempotency-Key"] = suppliedKey || "web-" + randomPart;
      opts.headers["X-Cloudio-Actor"] = actor;
    }
    if (confirmed) opts.headers["X-Cloudio-Confirm"] = "confirmed";
    if (opts.body != null && typeof opts.body !== "string" && !(opts.body instanceof FormData)) {
      opts.body = JSON.stringify(opts.body);
      opts.headers["Content-Type"] = "application/json";
    }

    let response;
    try {
      response = await fetch(url, opts);
    } catch (error) {
      throw new Error("Network error: " + error.message);
    }

    if (response.status === 401 ||
        (response.redirected && new URL(response.url).pathname === "/login.html")) {
      sessionPromise = null;
      window.location.assign("/login.html");
      const authError = new Error("Authentication required");
      authError.status = 401;
      throw authError;
    }

    const text = await response.text();
    let data = null;
    if (text) {
      try {
        data = JSON.parse(text);
      } catch (_) {
        data = text;
      }
    }

    if (!response.ok) {
      const detail = data && typeof data === "object" && (data.error || data.detail);
      const error = new Error(detail || response.status + " " + response.statusText);
      error.status = response.status;
      error.data = data;
      throw error;
    }
    return data;
  }

  async function authenticatedSession() {
    if (!sessionPromise) {
      sessionPromise = fetch("/api/auth/session", {
        credentials: "same-origin",
        headers: { Accept: "application/json" },
      }).then(async function (response) {
        if (!response.ok) {
          sessionPromise = null;
          window.location.assign("/login.html");
          throw new Error("Authentication required");
        }
        return response.json();
      }).catch(function (error) {
        sessionPromise = null;
        throw error;
      });
    }
    return sessionPromise;
  }

  function renderTable(target, rows, columns, emptyText) {
    const tbody = typeof target === "string" ? byId(target) : target;
    clear(tbody);
    if (!rows || rows.length === 0) {
      const cell = el("td", {
        className: "empty-state",
        text: emptyText || "No data available.",
        attrs: { colspan: columns.length },
      });
      tbody.appendChild(el("tr", { children: cell }));
      return;
    }

    rows.forEach(function (row) {
      const tr = el("tr");
      columns.forEach(function (column) {
        const cell = el("td", {
          className: column.className || "",
          attrs: { "data-label": column.label || "" },
        });
        const value = column.render
          ? column.render(row, tr)
          : row[column.key];
        appendValue(cell, value == null ? "" : value);
        tr.appendChild(cell);
      });
      tbody.appendChild(tr);
    });
  }

  function tableEmpty(target, colspan, message, loading) {
    const tbody = typeof target === "string" ? byId(target) : target;
    if (loading &&
        document.body.classList.contains("server-rendered") &&
        !tbody.querySelector(".loading-state")) {
      return;
    }
    const cell = el("td", {
      className: "empty-state" + (loading ? " loading-state" : ""),
      text: message,
      attrs: { colspan: colspan },
    });
    tbody.replaceChildren(el("tr", { children: cell }));
  }

  function setNotice(target, message, tone) {
    const node = typeof target === "string" ? byId(target) : target;
    if (!message) {
      node.textContent = "";
      node.className = "notice hidden";
      return;
    }
    node.textContent = message;
    node.className = "notice" + toneClass(tone || "info");
    node.setAttribute("role", tone === "danger" ? "alert" : "status");
  }

  function setStatus(target, message, tone, timeout) {
    const node = typeof target === "string" ? byId(target) : target;
    const previous = statusTimers.get(node);
    if (previous) window.clearTimeout(previous);
    node.textContent = message || "";
    node.className = "status-message" + toneClass(tone);
    node.setAttribute("role", tone === "danger" ? "alert" : "status");
    if (message && timeout !== false) {
      const timer = window.setTimeout(function () {
        node.textContent = "";
        node.className = "status-message";
      }, typeof timeout === "number" ? timeout : 6000);
      statusTimers.set(node, timer);
    }
  }

  function confirmAction(options) {
    const opts = options || {};
    if (!dialogElements || typeof dialogElements.dialog.showModal !== "function") {
      return Promise.resolve(window.confirm(opts.message || "Continue?"));
    }

    const parts = dialogElements;
    parts.title.textContent = opts.title || "Confirm action";
    parts.message.textContent = opts.message || "Are you sure?";
    parts.confirm.textContent = opts.confirmLabel || "Confirm";
    parts.confirm.className = "button " + (opts.danger ? "button-danger" : "button-primary");
    parts.dialog.returnValue = "cancel";

    return new Promise(function (resolve) {
      function finish() {
        parts.dialog.removeEventListener("close", finish);
        resolve(parts.dialog.returnValue === "confirm");
      }
      parts.dialog.addEventListener("close", finish);
      parts.dialog.showModal();
      window.requestAnimationFrame(function () {
        parts.cancel.focus();
      });
    });
  }

  async function withBusy(control, busyLabel, work) {
    const original = control.textContent;
    control.disabled = true;
    control.setAttribute("aria-busy", "true");
    if (busyLabel) control.textContent = busyLabel;
    try {
      return await work();
    } finally {
      control.disabled = false;
      control.removeAttribute("aria-busy");
      control.textContent = original;
    }
  }

  function debounce(callback, wait) {
    let timer = null;
    return function () {
      const args = arguments;
      window.clearTimeout(timer);
      timer = window.setTimeout(function () {
        callback.apply(null, args);
      }, wait);
    };
  }

  function formatTime(value) {
    if (!value) return "";
    const date = new Date(value);
    if (!Number.isNaN(date.getTime())) {
      return date.toLocaleString([], {
        year: "numeric",
        month: "short",
        day: "2-digit",
        hour: "2-digit",
        minute: "2-digit",
        second: "2-digit",
      });
    }
    return String(value).replace("T", " ").replace(/(\.\d+)?(Z|[+-]\d\d:?\d\d)?$/, "");
  }

  function shortSha(value) {
    return value ? String(value).slice(0, 8) : "";
  }

  window.cloudio = {
    api: api,
    authenticatedSession: authenticatedSession,
    badge: badge,
    button: button,
    byId: byId,
    clear: clear,
    confirmAction: confirmAction,
    debounce: debounce,
    el: el,
    formatTime: formatTime,
    mount: mount,
    renderTable: renderTable,
    setNotice: setNotice,
    setStatus: setStatus,
    shortSha: shortSha,
    status: status,
    statusTone: statusTone,
    tableEmpty: tableEmpty,
    toast: toast,
    withBusy: withBusy,
  };
})();
