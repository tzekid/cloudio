(function () {
  "use strict";

  const passkeys = window.cloudioPasskeys;
  const form = document.getElementById("setup-form");
  const label = document.getElementById("passkey-label");
  const errorMessage = document.getElementById("setup-error");
  const submit = document.getElementById("setup-button");
  let bootstrapToken = "";

  function takeFragmentToken() {
    const fragment = window.location.hash.startsWith("#token=")
      ? window.location.hash.slice("#token=".length)
      : "";
    try {
      bootstrapToken = decodeURIComponent(fragment);
    } catch (_) {
      bootstrapToken = "";
    }
    window.history.replaceState(null, document.title, window.location.pathname);
  }

  async function post(url, body) {
    const response = await fetch(url, {
      method: "POST",
      credentials: "same-origin",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-Cloudio-Bootstrap": bootstrapToken,
      },
      body: JSON.stringify(body || {}),
    });
    const data = await response.json().catch(function () { return {}; });
    if (!response.ok) {
      throw new Error(
        response.status === 401
          ? "This setup link is invalid, expired, or already used."
          : data.error || "Setup failed (" + response.status + ")."
      );
    }
    return data;
  }

  form.addEventListener("submit", async function (event) {
    event.preventDefault();
    errorMessage.textContent = "";
    submit.disabled = true;
    submit.setAttribute("aria-busy", "true");
    submit.textContent = "Waiting for your device…";
    try {
      const options = await post("/api/auth/setup/options", {});
      const credential = await passkeys.create(options.publicKey);
      await post(
        "/api/auth/setup/verify",
        passkeys.registrationPayload(options.challenge_id, credential, label.value.trim())
      );
      bootstrapToken = "";
      window.location.replace("/security.html");
    } catch (error) {
      errorMessage.textContent = error && error.name === "NotAllowedError"
        ? "Passkey creation was cancelled or timed out."
        : error.message;
    } finally {
      submit.disabled = false;
      submit.removeAttribute("aria-busy");
      submit.textContent = "Create passkey";
    }
  });

  takeFragmentToken();
  if (!bootstrapToken) {
    submit.disabled = true;
    errorMessage.textContent = "Open the complete setup link printed by the Cloudio CLI.";
  } else if (!passkeys.supported()) {
    submit.disabled = true;
    errorMessage.textContent = "Passkeys require a current browser and a secure connection.";
  }
})();
