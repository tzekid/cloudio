(function () {
  "use strict";

  function supported() {
    return Boolean(
      window.isSecureContext &&
      window.PublicKeyCredential &&
      navigator.credentials
    );
  }

  function fromBase64url(value) {
    const base64 = String(value).replace(/-/g, "+").replace(/_/g, "/");
    const padded = base64 + "=".repeat((4 - base64.length % 4) % 4);
    const binary = window.atob(padded);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) {
      bytes[index] = binary.charCodeAt(index);
    }
    return bytes.buffer;
  }

  function toBase64url(value) {
    const bytes = new Uint8Array(value);
    let binary = "";
    for (let index = 0; index < bytes.length; index += 1) {
      binary += String.fromCharCode(bytes[index]);
    }
    return window.btoa(binary)
      .replace(/\+/g, "-")
      .replace(/\//g, "_")
      .replace(/=+$/, "");
  }

  function creationOptions(publicKey) {
    const options = Object.assign({}, publicKey, {
      challenge: fromBase64url(publicKey.challenge),
      user: Object.assign({}, publicKey.user, {
        id: fromBase64url(publicKey.user.id),
      }),
    });
    options.excludeCredentials = (publicKey.excludeCredentials || []).map(function (credential) {
      return Object.assign({}, credential, { id: fromBase64url(credential.id) });
    });
    return options;
  }

  function requestOptions(publicKey) {
    const options = Object.assign({}, publicKey, {
      challenge: fromBase64url(publicKey.challenge),
    });
    options.allowCredentials = (publicKey.allowCredentials || []).map(function (credential) {
      return Object.assign({}, credential, { id: fromBase64url(credential.id) });
    });
    return options;
  }

  async function create(publicKey) {
    if (!supported()) throw new Error("Passkeys require a current browser and a secure connection.");
    const credential = await navigator.credentials.create({
      publicKey: creationOptions(publicKey),
    });
    if (!credential) throw new Error("Passkey creation was cancelled.");
    return credential;
  }

  async function get(publicKey) {
    if (!supported()) throw new Error("Passkeys require a current browser and a secure connection.");
    const credential = await navigator.credentials.get({
      publicKey: requestOptions(publicKey),
    });
    if (!credential) throw new Error("Passkey sign-in was cancelled.");
    return credential;
  }

  function registrationPayload(challengeId, credential, label) {
    const transports = typeof credential.response.getTransports === "function"
      ? credential.response.getTransports()
      : [];
    return {
      challenge_id: challengeId,
      credential_id: toBase64url(credential.rawId),
      client_data_json: toBase64url(credential.response.clientDataJSON),
      attestation_object: toBase64url(credential.response.attestationObject),
      transports: transports.join(","),
      label: label || "Passkey",
    };
  }

  function authenticationPayload(challengeId, credential) {
    return {
      challenge_id: challengeId,
      credential_id: toBase64url(credential.rawId),
      client_data_json: toBase64url(credential.response.clientDataJSON),
      authenticator_data: toBase64url(credential.response.authenticatorData),
      signature: toBase64url(credential.response.signature),
    };
  }

  window.cloudioPasskeys = {
    authenticationPayload: authenticationPayload,
    create: create,
    get: get,
    registrationPayload: registrationPayload,
    supported: supported,
  };
})();
