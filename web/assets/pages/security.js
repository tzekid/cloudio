(function () {
  "use strict";

  const c = window.cloudio;
  const passkeys = window.cloudioPasskeys;
  c.mount({ title: "Security", active: "security", refresh: false });

  const body = c.byId("passkeys-body");
  const count = c.byId("passkey-count");
  const addButton = c.byId("add-passkey");
  const signOut = c.byId("sign-out");

  function epochTime(value) {
    return value ? c.formatTime(Number(value) * 1000) : "Never";
  }

  function passkeyType(row) {
    if (row.backup_eligible) return c.badge("Synced", "info");
    if (String(row.transports).includes("internal")) return c.badge("This device");
    return c.badge("Security key");
  }

  function actions(row) {
    const rename = c.button("Rename", { small: true, dataset: { action: "rename", id: row.id } });
    const revoke = c.button("Revoke", {
      small: true,
      kind: "danger",
      dataset: { action: "revoke", id: row.id, label: row.label },
    });
    return c.el("div", { className: "cluster", children: [rename, revoke] });
  }

  function render(rows) {
    count.textContent = rows.length;
    c.renderTable(body, rows, [
      { label: "Name", render: function (row) { return c.el("strong", { text: row.label }); } },
      { label: "Type", render: passkeyType },
      { label: "Created", render: function (row) { return epochTime(row.created_at); } },
      { label: "Last used", render: function (row) { return epochTime(row.last_used_at); } },
      { label: "Actions", className: "cell-actions", render: actions },
    ], "No passkeys are enrolled.");
    c.setNotice(
      "security-notice",
      rows.length < 2 ? "Add a second passkey before you need it. A phone plus a laptop or hardware key is a practical recovery pair." : "",
      "warning"
    );
  }

  async function load() {
    try {
      const data = await c.api("/api/auth/credentials");
      render(data.credentials || []);
    } catch (error) {
      c.tableEmpty(body, 5, "Could not load passkeys.");
      c.toast("Passkeys could not be loaded: " + error.message, "danger");
    }
  }

  addButton.addEventListener("click", function () {
    c.withBusy(addButton, "Waiting for your device…", async function () {
      if (!passkeys.supported()) throw new Error("Passkeys are unavailable in this browser.");
      const label = window.prompt("Name this passkey", "Additional passkey");
      if (label == null) return;
      const trimmed = label.trim();
      if (!trimmed) throw new Error("A passkey name is required.");
      const options = await c.api("/api/auth/credentials/options", { method: "POST", body: {} });
      const credential = await passkeys.create(options.publicKey);
      await c.api("/api/auth/credentials/verify", {
        method: "POST",
        body: passkeys.registrationPayload(options.challenge_id, credential, trimmed),
      });
      c.toast("Passkey added.", "success");
      await load();
    }).catch(function (error) {
      if (error.name !== "NotAllowedError") c.toast(error.message, "danger");
    });
  });

  body.addEventListener("click", async function (event) {
    const button = event.target.closest("button[data-action]");
    if (!button) return;
    const id = encodeURIComponent(button.dataset.id);
    if (button.dataset.action === "rename") {
      const label = window.prompt("Rename this passkey", button.closest("tr").querySelector("strong").textContent);
      if (label == null || !label.trim()) return;
      try {
        await c.withBusy(button, "Saving…", function () {
          return c.api("/api/auth/credentials/" + id, {
            method: "PATCH",
            body: { label: label.trim() },
          });
        });
        c.toast("Passkey renamed.", "success");
        await load();
      } catch (error) {
        c.toast(error.message, "danger");
      }
      return;
    }

    const confirmed = await c.confirmAction({
      title: "Revoke passkey",
      message: "Revoke “" + button.dataset.label + "”? It will no longer unlock Cloudio.",
      confirmLabel: "Revoke",
      danger: true,
    });
    if (!confirmed) return;
    try {
      await c.withBusy(button, "Revoking…", function () {
        return c.api("/api/auth/credentials/" + id, {
          method: "DELETE",
          confirm: true,
        });
      });
      c.toast("Passkey revoked.", "success");
      await load();
    } catch (error) {
      c.toast(
        error.status === 409 ? "The last passkey cannot be removed." : error.message,
        "danger"
      );
    }
  });

  signOut.addEventListener("click", function () {
    c.withBusy(signOut, "Signing out…", async function () {
      await c.api("/api/auth/logout", { method: "POST", body: {} });
      window.location.replace("/login.html");
    }).catch(function (error) {
      c.setStatus("security-status", error.message, "danger", false);
    });
  });

  load();
})();
