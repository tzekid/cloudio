/* cloudio shared UI helpers: layout chrome, fetch wrapper, toasts, table rendering. */
(function () {
  "use strict";

  const NAV = [
    { href: "/index.html", label: "Dashboard", match: ["/", "/index.html"] },
    { href: "/apps.html", label: "Apps" },
    { href: "/routes.html", label: "Routes" },
    { href: "/dns.html", label: "DNS" },
    { href: "/vps.html", label: "VPS" },
    { href: "/docker.html", label: "Docker" },
    { href: "/audit.html", label: "Audit" },
  ];

  function esc(value) {
    return String(value == null ? "" : value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function injectLayout(title) {
    const path = window.location.pathname;
    const links = NAV.map((item) => {
      const active = (item.match || [item.href]).includes(path);
      return '<a href="' + item.href + '"' + (active ? ' class="active"' : "") + ">" + esc(item.label) + "</a>";
    }).join("");

    const body = document.body;
    const pageContent = document.createElement("div");
    while (body.firstChild) pageContent.appendChild(body.firstChild);

    body.innerHTML =
      '<div class="layout">' +
      '<aside class="sidebar"><div class="brand">cloud<span>io</span></div><nav>' + links + "</nav></aside>" +
      '<div class="main">' +
      '<div class="titlebar"><h1>' + esc(title) + "</h1>" +
      '<button id="refresh-data-btn" title="Trigger data re-collection (may take ~10s)">Refresh Data</button>' +
      "</div>" +
      '<div class="content" id="page-content"></div>' +
      "</div></div>" +
      '<div id="toasts"></div>';

    document.getElementById("page-content").appendChild(pageContent);

    document.getElementById("refresh-data-btn").addEventListener("click", async function () {
      const btn = this;
      btn.disabled = true;
      btn.textContent = "Refreshing...";
      try {
        await api("/api/refresh", { method: "POST" });
        toast("Data refreshed", "success");
        document.dispatchEvent(new CustomEvent("cloudio:reload"));
      } catch (err) {
        toast("Refresh failed: " + err.message, "error");
      } finally {
        btn.disabled = false;
        btn.textContent = "Refresh Data";
      }
    });
  }

  function toast(message, kind) {
    let holder = document.getElementById("toasts");
    if (!holder) {
      holder = document.createElement("div");
      holder.id = "toasts";
      document.body.appendChild(holder);
    }
    const el = document.createElement("div");
    el.className = "toast" + (kind ? " " + kind : "");
    el.textContent = message;
    holder.appendChild(el);
    setTimeout(() => el.remove(), 6000);
  }

  /* Fetch wrapper: JSON in/out, credentials, redirect-to-login on 401/302, useful errors. */
  async function api(url, options) {
    const opts = Object.assign({ credentials: "same-origin" }, options || {});
    if (opts.body && typeof opts.body !== "string") {
      opts.body = JSON.stringify(opts.body);
      opts.headers = Object.assign({ "Content-Type": "application/json" }, opts.headers || {});
    }
    let res;
    try {
      res = await fetch(url, opts);
    } catch (err) {
      throw new Error("network error (" + err.message + ")");
    }
    if (res.status === 401) {
      window.location.href = "/login.html";
      throw new Error("unauthorized");
    }
    const text = await res.text();
    let data = null;
    if (text) {
      try { data = JSON.parse(text); } catch (_) { /* non-JSON body */ }
    }
    if (!res.ok) {
      const msg = (data && data.error) || (res.status + " " + res.statusText);
      const err = new Error(msg);
      err.status = res.status;
      err.data = data;
      throw err;
    }
    return data;
  }

  /* Render rows into a tbody. columns: [{key|render(row), cls}] */
  function renderTable(tbody, rows, columns, emptyText) {
    if (typeof tbody === "string") tbody = document.getElementById(tbody);
    if (!rows || rows.length === 0) {
      tbody.innerHTML = '<tr><td class="empty" colspan="' + columns.length + '">' + esc(emptyText || "No data") + "</td></tr>";
      return;
    }
    tbody.innerHTML = rows
      .map(function (row) {
        const cells = columns
          .map(function (col) {
            const cls = col.cls ? ' class="' + col.cls + '"' : "";
            const value = col.render ? col.render(row) : esc(row[col.key]);
            return "<td" + cls + ">" + value + "</td>";
          })
          .join("");
        return "<tr>" + cells + "</tr>";
      })
      .join("");
  }

  function statusDot(color, label) {
    return '<span class="dot ' + color + '"></span>' + esc(label);
  }

  function badge(text, color) {
    return '<span class="badge ' + (color || "") + '">' + esc(text) + "</span>";
  }

  function fmtTime(value) {
    if (!value) return "";
    return String(value).replace("T", " ").replace(/(\.\d+)?(Z|[+-]\d\d:?\d\d)?$/, "");
  }

  function shortSha(sha) {
    return sha ? String(sha).slice(0, 8) : "";
  }

  /* Marks a section as unavailable when a contract endpoint is not wired yet. */
  function endpointUnavailable(container, name) {
    if (typeof container === "string") container = document.getElementById(container);
    if (container) {
      container.innerHTML = '<div class="empty">Endpoint ' + esc(name) + " not available yet.</div>";
    }
  }

  window.cloudio = {
    esc: esc,
    injectLayout: injectLayout,
    toast: toast,
    api: api,
    renderTable: renderTable,
    statusDot: statusDot,
    badge: badge,
    fmtTime: fmtTime,
    shortSha: shortSha,
    endpointUnavailable: endpointUnavailable,
  };
})();
