(function () {
  "use strict";

  const passkeys = window.cloudioPasskeys;
  const errorMessage = document.getElementById("login-error");
  const submit = document.getElementById("login-button");

  function messageFor(error) {
    if (error && error.name === "NotAllowedError") {
      return "Sign-in was cancelled or timed out.";
    }
    return error && error.message ? error.message : "Passkey sign-in failed.";
  }

  async function post(url, body) {
    const response = await fetch(url, {
      method: "POST",
      credentials: "same-origin",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify(body || {}),
    });
    const data = await response.json().catch(function () { return {}; });
    if (!response.ok) {
      if (data.error === "passkey_setup_required") {
        throw new Error("No passkey is enrolled. Create a setup link from the Cloudio CLI.");
      }
      throw new Error(data.error || "Sign-in failed (" + response.status + ").");
    }
    return data;
  }

  submit.addEventListener("click", async function () {
    errorMessage.textContent = "";
    submit.disabled = true;
    submit.setAttribute("aria-busy", "true");
    submit.textContent = "Waiting for your device…";
    try {
      const options = await post("/api/auth/login/options", {});
      const credential = await passkeys.get(options.publicKey);
      await post(
        "/api/auth/login/verify",
        passkeys.authenticationPayload(options.challenge_id, credential)
      );
      window.location.replace("/");
    } catch (error) {
      errorMessage.textContent = messageFor(error);
    } finally {
      submit.disabled = false;
      submit.removeAttribute("aria-busy");
      submit.textContent = "Use a passkey";
    }
  });

  if (!passkeys.supported()) {
    submit.disabled = true;
    errorMessage.textContent = "Passkeys require a current browser and a secure connection.";
  } else {
    fetch("/api/auth/session", { credentials: "same-origin", headers: { Accept: "application/json" } })
      .then(function (response) {
        if (response.ok) window.location.replace("/");
      })
      .catch(function () {});
  }
})();
