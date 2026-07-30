(function () {
  "use strict";

  const form = document.getElementById("login-form");
  const tokenInput = document.getElementById("platform-token");
  const errorMessage = document.getElementById("login-error");
  const submit = document.getElementById("login-button");

  form.addEventListener("submit", async function (event) {
    event.preventDefault();
    errorMessage.textContent = "";
    const token = tokenInput.value.trim();
    if (!token) {
      errorMessage.textContent = "Platform token is required.";
      tokenInput.focus();
      return;
    }

    submit.disabled = true;
    submit.setAttribute("aria-busy", "true");
    submit.textContent = "Signing in…";
    try {
      const response = await fetch("/api/login", {
        method: "POST",
        credentials: "same-origin",
        headers: { "Content-Type": "application/json", Accept: "application/json" },
        body: JSON.stringify({ token: token }),
      });
      if (response.ok) {
        window.location.assign("/");
      } else if (response.status === 401) {
        errorMessage.textContent = "The platform token is not valid.";
        tokenInput.select();
      } else {
        errorMessage.textContent = "Sign-in failed (" + response.status + ").";
      }
    } catch (error) {
      errorMessage.textContent = "Network error: " + error.message;
    } finally {
      submit.disabled = false;
      submit.removeAttribute("aria-busy");
      submit.textContent = "Sign in";
    }
  });
})();
