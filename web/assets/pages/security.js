(function () {
  "use strict";

  const passkeys = window.cloudioPasskeys;

  function byId(id) {
    return document.getElementById(id);
  }

  const body = byId("passkeys-body");
  const addButton = byId("add-passkey");
  const csrf = byId("security-csrf");
  const toastRegion = byId("toast-region");
  const revokeDialog = document.querySelector('dialog[aria-labelledby="revoke-dialog-title"]');
  const revokeMessage = revokeDialog && revokeDialog.querySelector(".dialog-body");
  const revokeCancel = revokeDialog && revokeDialog.querySelector('button[value="cancel"]');
  if (!body || !addButton || !csrf || !toastRegion || !revokeDialog || !revokeMessage || !revokeCancel) {
    throw new Error("Incomplete security page");
  }

  function toast(message) {
    const item = document.createElement("div");
    item.className = "toast tone-danger";
    item.textContent = message;
    item.setAttribute("role", "alert");
    toastRegion.appendChild(item);
    window.setTimeout(function () { item.remove(); }, 6000);
  }

  async function api(url, options) {
    const opts = Object.assign({ credentials: "same-origin" }, options);
    const confirmed = opts.confirm === true;
    delete opts.confirm;
    opts.headers = {
      Accept: "application/json",
      "Content-Type": "application/json",
      "X-Cloudio-CSRF": csrf.value,
    };
    if (confirmed) opts.headers["X-Cloudio-Confirm"] = "confirmed";
    if (opts.body != null) opts.body = JSON.stringify(opts.body);

    let response;
    try {
      response = await fetch(url, opts);
    } catch (error) {
      throw new Error("Network error: " + error.message);
    }
    if (response.status === 401) {
      window.location.assign("/login.html");
      const error = new Error("Authentication required");
      error.status = 401;
      throw error;
    }

    const text = await response.text();
    let data = null;
    if (text) {
      try { data = JSON.parse(text); } catch (_) { data = text; }
    }
    if (!response.ok) {
      const detail = data && typeof data === "object" && (data.error || data.detail);
      const error = new Error(detail || response.status + " " + response.statusText);
      error.status = response.status;
      throw error;
    }
    return data;
  }

  function confirmRevocation(label) {
    revokeMessage.textContent = "Revoke “" + label + "”? It will no longer unlock Cloudio.";
    revokeDialog.returnValue = "cancel";
    return new Promise(function (resolve) {
      function finish() {
        revokeDialog.removeEventListener("close", finish);
        resolve(revokeDialog.returnValue === "confirm");
      }
      revokeDialog.addEventListener("close", finish);
      revokeDialog.showModal();
      window.requestAnimationFrame(function () { revokeCancel.focus(); });
    });
  }

  async function withBusy(control, busyLabel, work) {
    const original = control.textContent;
    control.disabled = true;
    control.setAttribute("aria-busy", "true");
    control.textContent = busyLabel;
    try {
      return await work();
    } finally {
      control.disabled = false;
      control.removeAttribute("aria-busy");
      control.textContent = original;
    }
  }

  addButton.addEventListener("click", function () {
    withBusy(addButton, "Waiting for your device…", async function () {
      if (!passkeys.supported()) throw new Error("Passkeys are unavailable in this browser.");
      const label = window.prompt("Name this passkey", "Additional passkey");
      if (label == null) {
        window.setTimeout(function () { addButton.focus(); }, 0);
        return;
      }
      const trimmed = label.trim();
      if (!trimmed) throw new Error("A passkey name is required.");
      const options = await api("/api/auth/credentials/options", { method: "POST", body: {} });
      const credential = await passkeys.create(options.publicKey);
      await api("/api/auth/credentials/verify", {
        method: "POST",
        body: passkeys.registrationPayload(options.challenge_id, credential, trimmed),
      });
      window.location.assign("/security.html?result=added");
    }).catch(function (error) {
      if (error.name !== "NotAllowedError") toast(error.message);
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
        await withBusy(button, "Saving…", function () {
          return api("/api/auth/credentials/" + id, {
            method: "PATCH",
            body: { label: label.trim() },
          });
        });
        window.location.assign("/security.html?result=renamed");
      } catch (error) {
        toast(error.message);
      }
      return;
    }

    const confirmed = await confirmRevocation(button.dataset.label);
    if (!confirmed) {
      button.focus();
      return;
    }
    try {
      await withBusy(button, "Revoking…", function () {
        return api("/api/auth/credentials/" + id, {
          method: "DELETE",
          confirm: true,
        });
      });
      window.location.assign("/security.html?result=revoked");
    } catch (error) {
      toast(error.status === 409 ? "The last passkey cannot be removed." : error.message);
    }
  });

})();
