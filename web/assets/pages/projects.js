(function () {
  "use strict";

  const c = window.cloudio;
  c.mount({ title: "Projects", active: "projects" });

  const projectsBody = c.byId("nob-projects-body");
  const projectsCount = c.byId("nob-projects-count");
  const scanButton = c.byId("nob-scan-button");
  const detailPanel = c.byId("nob-project-detail");
  const detailTitle = c.byId("nob-project-detail-title");
  const detailMeta = c.byId("nob-project-detail-meta");
  const facts = c.byId("nob-project-facts");
  const resourcesBody = c.byId("nob-resources-body");
  const actionsBody = c.byId("nob-actions-body");
  const secretsBody = c.byId("nob-secrets-body");
  const runsBody = c.byId("nob-runs-body");
  const runsRefresh = c.byId("nob-runs-refresh");
  const runDetail = c.byId("nob-run-detail");
  let activeProject = null;

  function discoveryLabel(value) {
    return {
      candidate: "Manifest needed",
      valid: "Ready",
      invalid: "Invalid manifest",
      conflict: "ID conflict",
      missing: "Missing",
      ignored: "Forgotten",
    }[value] || value || "Unknown";
  }

  function trustLabel(value) {
    return {
      discovered: "Approval needed",
      trusted: "Approved",
      "review-required": "Changed — review",
      revoked: "Revoked",
    }[value] || value || "Unknown";
  }

  function runnerLabel(value) {
    return {
      "not-built": "Not prepared",
      building: "Preparing",
      ready: "Ready",
      failed: "Failed",
    }[value] || value || "Unknown";
  }

  function projectName(project) {
    return c.el("button", {
      type: "button",
      className: "button-link",
      text: project.display_name,
      dataset: { openNobProject: project.id },
      attrs: { "aria-label": "Open details for " + project.display_name },
    });
  }

  function projectIdentity(project) {
    return [
      projectName(project),
      c.el("div", { className: "muted mono", text: project.project_id || "Not enrolled" }),
    ];
  }

  function projectActions(project) {
    const controls = c.el("div", { className: "table-actions" });
    controls.appendChild(c.button("Details", {
      small: true,
      dataset: { openNobProject: project.id },
    }));
    const restorable = project.discovery_state === "ignored" && project.last_scan_state === "valid";
    if ((project.discovery_state === "valid" || restorable) && project.manifest_sha256 && project.trust_state !== "trusted") {
      controls.appendChild(c.button(restorable ? "Restore approval" : "Approve", {
        small: true,
        kind: "primary",
        dataset: {
          nobAction: "trust",
          projectId: project.id,
          projectDeclaredId: project.project_id,
          manifestDigest: project.manifest_sha256,
        },
      }));
    }
    if (project.discovery_state === "valid" && project.trust_state === "trusted") {
      if (project.runner_state === "ready") {
        controls.appendChild(c.button("Refresh status", {
          small: true,
          dataset: { nobAction: "observe", projectId: project.id },
        }));
      } else if (project.runner_state !== "building") {
        controls.appendChild(c.button("Prepare", {
          small: true,
          kind: "primary",
          dataset: { nobAction: "prepare", projectId: project.id },
        }));
      }
    }
    if (project.trust_state === "trusted" || project.trust_state === "review-required") {
      controls.appendChild(c.button("Revoke", {
        small: true,
        kind: "danger",
        dataset: { nobAction: "revoke", projectId: project.id },
      }));
    }
    if (project.discovery_state !== "ignored") {
      controls.appendChild(c.button("Forget", {
        small: true,
        kind: "danger",
        dataset: { nobAction: "forget", projectId: project.id },
      }));
    }
    return controls;
  }

  function renderProjects(projects) {
    projectsCount.textContent = projects.length + (projects.length === 1 ? " project" : " projects");
    c.renderTable(projectsBody, projects, [
      { label: "Project", render: projectIdentity },
      { label: "Kind", render: function (row) { return c.badge(row.kind); } },
      { label: "Declaration", render: function (row) { return c.badge(discoveryLabel(row.discovery_state)); } },
      { label: "Approval", render: function (row) { return c.badge(trustLabel(row.trust_state)); } },
      { label: "Status", render: function (row) { return c.status(row.status); } },
      { label: "Runner", render: function (row) { return c.badge(runnerLabel(row.runner_state)); } },
      { label: "Actions", render: projectActions, className: "cell-actions" },
    ], "No projects discovered yet. Scan the projects folder to begin.");
  }

  async function loadProjects() {
    try {
      const data = await c.api("/api/nob/projects");
      renderProjects(data && data.items ? data.items : []);
    } catch (error) {
      projectsCount.textContent = "";
      c.tableEmpty(projectsBody, 7, "Projects unavailable: " + error.message);
    }
  }

  function fact(label, value) {
    return c.el("div", {
      className: "kv-row",
      children: [c.el("dt", { text: label }), c.el("dd", { text: value || "—" })],
    });
  }

  function renderDetails(data) {
    const project = data.project;
    activeProject = project;
    detailTitle.textContent = project.display_name;
    detailMeta.textContent = project.root_path;
    facts.replaceChildren(
      fact("Project ID", project.project_id),
      fact("Kind", project.kind),
      fact("Declaration", discoveryLabel(project.discovery_state)),
      fact("Approval", trustLabel(project.trust_state)),
      fact("Status", project.status),
      fact("Status detail", project.status_summary),
      fact("Runner", runnerLabel(project.runner_state)),
      fact("Manifest fingerprint", project.manifest_sha256),
      fact("Source revision", project.head_revision),
      fact("Source fingerprint", project.source_fingerprint),
      fact("Uncommitted changes", project.source_dirty === null ? null : (project.source_dirty ? "Yes" : "No"))
    );
    c.renderTable(resourcesBody, data.resources || [], [
      { label: "Resource", render: function (row) {
        return [
          c.el("span", { text: row.label || row.id }),
          c.el("div", { className: "muted", text: row.summary || "No observation yet" }),
        ];
      } },
      { label: "Kind", render: function (row) { return c.badge(row.kind); } },
      { label: "Ownership", key: "ownership" },
      { label: "Status", render: function (row) { return c.status(row.status); } },
      { label: "Controls", render: resourceControls, className: "cell-actions" },
    ], "This project declares no resources.");
    c.renderTable(actionsBody, data.actions || [], [
      { label: "Action", render: function (row) { return row.label || row.id; } },
      { label: "Effect", render: function (row) { return c.badge(row.effect); } },
      { label: "Confirmation", key: "confirmation" },
      { label: "Available", render: function (row) { return c.badge(row.available ? "Available" : "Unavailable"); } },
      { label: "Operate", render: function (row) {
        return c.button("Plan and run", {
          small: true,
          kind: "primary",
          disabled: !row.available || project.runner_state !== "ready" || project.trust_state !== "trusted",
          dataset: { nobRunAction: row.id },
          title: row.unavailable_reason || "Review a plan before this action runs",
        });
      }, className: "cell-actions" },
    ], "This project declares no actions.");
    detailPanel.classList.remove("hidden");
    detailPanel.scrollIntoView({ block: "start" });
    loadSecrets(project.id);
    loadRuns(project.id);
  }

  function secretStatus(secret) {
    if (!secret.bound) return c.badge("Not bound");
    return c.status(secret.present ? "Available" : "Unavailable");
  }

  function secretControls(secret) {
    const controls = c.el("div", { className: "table-actions" });
    controls.appendChild(c.button(secret.bound ? "Replace" : "Bind", {
      small: true,
      kind: secret.bound ? "secondary" : "primary",
      disabled: !activeProject || activeProject.trust_state !== "trusted",
      dataset: { nobSecretBind: secret.secret_id },
    }));
    if (secret.bound) controls.appendChild(c.button("Remove", {
      small: true,
      kind: "danger",
      disabled: !activeProject || activeProject.trust_state !== "trusted",
      dataset: { nobSecretUnbind: secret.secret_id },
    }));
    return controls;
  }

  function renderSecrets(items) {
    c.renderTable(secretsBody, items, [
      { label: "Secret", render: function (secret) {
        return [
          c.el("span", { className: "mono", text: secret.secret_id }),
          c.el("div", { className: "muted", text: secret.purpose }),
        ];
      } },
      { label: "Required for", render: function (secret) { return (secret.required_for || []).join(", ") || "Optional"; } },
      { label: "Status", render: secretStatus },
      { label: "Source", render: function (secret) { return secret.bound ? (secret.source_kind || "Configured") : "—"; } },
      { label: "Manage", render: secretControls, className: "cell-actions" },
    ], "This project declares no secrets.");
  }

  async function loadSecrets(projectId) {
    try {
      const result = await c.api("/api/nob/projects/" + encodeURIComponent(projectId) + "/secrets");
      renderSecrets(result.items || []);
    } catch (error) {
      c.tableEmpty(secretsBody, 5, "Secrets unavailable: " + error.message);
    }
  }

  async function bindSecret(secretId) {
    if (!activeProject) return;
    const sourceKind = c.el("select", {
      children: [
        c.el("option", { value: "file", text: "Local file" }),
        c.el("option", { value: "process-environment", text: "Cloudio process environment" }),
      ],
    });
    const sourceRef = c.el("input", {
      type: "text",
      attrs: { required: true, autocomplete: "off", placeholder: "/run/secrets/example" },
    });
    sourceKind.addEventListener("change", function () {
      sourceRef.placeholder = sourceKind.value === "file" ? "/run/secrets/example" : "EXAMPLE_TOKEN";
    });
    const form = c.el("div", { className: "stack compact-stack", children: [
      c.el("p", { text: "Choose where Cloudio should read this value. The reference is stored locally but is never returned by the API or shown again." }),
      c.el("div", { className: "field", children: [c.el("label", { text: "Source type" }), sourceKind] }),
      c.el("div", { className: "field", children: [c.el("label", { text: "Source reference" }), sourceRef] }),
    ] });
    const accepted = await c.confirmAction({
      title: "Bind " + secretId,
      message: form,
      confirmLabel: "Save binding",
    });
    if (!accepted || !sourceRef.reportValidity()) return;
    await c.api(
      "/api/nob/projects/" + encodeURIComponent(activeProject.id) + "/secrets/" + encodeURIComponent(secretId),
      { method: "PUT", confirm: true, body: { source_kind: sourceKind.value, source_ref: sourceRef.value } }
    );
    sourceRef.value = "";
    c.toast("Secret binding saved. Its reference and value remain hidden.", "success");
    await loadSecrets(activeProject.id);
  }

  async function unbindSecret(secretId) {
    if (!activeProject) return;
    if (!await c.confirmAction({
      title: "Remove " + secretId + " binding",
      message: "Future runs that require this secret will remain unavailable until another source is bound.",
      confirmLabel: "Remove binding",
      danger: true,
    })) return;
    await c.api(
      "/api/nob/projects/" + encodeURIComponent(activeProject.id) + "/secrets/" + encodeURIComponent(secretId),
      { method: "DELETE", confirm: true, body: {} }
    );
    c.toast("Secret binding removed.", "success");
    await loadSecrets(activeProject.id);
  }

  function resourceControls(resource) {
    const controls = c.el("div", { className: "table-actions" });
    const scope = resource.declaration && resource.declaration.spec && resource.declaration.spec.scope;
    (resource.controls || []).forEach(function (control) {
      if (control === "logs") {
        controls.appendChild(c.button("Logs", {
          small: true,
          disabled: !activeProject || activeProject.trust_state !== "trusted",
          dataset: { nobResourceLogs: resource.id },
        }));
        return;
      }
      controls.appendChild(c.button(control.charAt(0).toUpperCase() + control.slice(1), {
        small: true,
        kind: control === "stop" || control === "disable" ? "danger" : "secondary",
        disabled: !activeProject || activeProject.trust_state !== "trusted" || activeProject.runner_state !== "ready" || scope !== "user" || resource.ownership === "observed",
        dataset: { nobResourceControl: control, nobResourceId: resource.id },
        title: scope !== "user" ? "System-scope mutation is intentionally unavailable" : "Review an exact resource-control plan",
      }));
    });
    return controls;
  }

  function parameterEditor(action) {
    const parameters = (action.declaration && action.declaration.parameters) || [];
    const fields = [];
    const node = c.el("div", { className: "stack compact-stack" });
    node.appendChild(c.el("p", { text: action.declaration && action.declaration.description || "Provide the action inputs Cloudio should use to create a reviewable plan." }));
    parameters.forEach(function (parameter) {
      const id = "nob-param-" + parameter.name.replace(/[^a-zA-Z0-9_-]/g, "-");
      const label = c.el("label", { attrs: { for: id }, text: parameter.name + (parameter.required ? " (required)" : "") });
      let input;
      if (parameter.type === "boolean") {
        input = c.el("input", { id: id, type: "checkbox", checked: parameter.default === true });
      } else if (parameter.type === "enum") {
        input = c.el("select", { id: id });
        if (!parameter.required && parameter.default == null) input.appendChild(c.el("option", { value: "", text: "Choose…" }));
        (parameter.values || []).forEach(function (value) {
          input.appendChild(c.el("option", { value: value, text: value }));
        });
        if (parameter.default != null) input.value = String(parameter.default);
      } else {
        input = c.el("input", {
          id: id,
          type: parameter.type === "integer" ? "number" : "text",
          value: parameter.default == null ? "" : parameter.default,
          attrs: {
            required: parameter.required,
            min: parameter.minimum,
            max: parameter.maximum,
            minlength: parameter.min_length,
            maxlength: parameter.max_length,
          },
        });
      }
      fields.push({ declaration: parameter, input: input });
      node.appendChild(c.el("div", { className: "field", children: [label, input] }));
    });
    return {
      node: node,
      values: function () {
        const values = {};
        fields.forEach(function (field) {
          const declaration = field.declaration;
          const input = field.input;
          if (declaration.type === "boolean") {
            values[declaration.name] = input.checked;
          } else if (input.value !== "" || declaration.required) {
            values[declaration.name] = declaration.type === "integer" ? Number(input.value) : input.value;
          }
        });
        return values;
      },
      valid: function () {
        return fields.every(function (field) { return field.input.reportValidity(); });
      },
      count: fields.length,
    };
  }

  function labeledValue(label, value) {
    return c.el("div", {
      className: "plan-review-row",
      children: [c.el("strong", { text: label }), c.el("span", { text: value == null || value === "" ? "—" : String(value) })],
    });
  }

  function planReview(planned) {
    const plan = planned.plan || {};
    const node = c.el("div", { className: "stack compact-stack plan-review" });
    node.append(
      labeledValue("Effect", planned.effect),
      labeledValue("Expected downtime", (plan.expected_downtime_seconds || 0) + " seconds"),
      labeledValue("Source", plan.source && (plan.source.revision || plan.source.fingerprint)),
      labeledValue("Rollback", plan.rollback && plan.rollback.mode),
      labeledValue("Affected resources", (plan.affected_resources || []).join(", ") || "None")
    );
    if ((plan.preconditions || []).length) {
      node.appendChild(c.el("h3", { className: "section-heading", text: "Preconditions" }));
      const list = c.el("ul", { className: "review-list" });
      plan.preconditions.forEach(function (item) {
        list.appendChild(c.el("li", { children: [c.status(item.status), " ", item.summary] }));
      });
      node.appendChild(list);
    }
    if ((plan.stages || []).length) {
      node.appendChild(c.el("h3", { className: "section-heading", text: "Stages" }));
      const stages = c.el("ol", { className: "review-list" });
      plan.stages.forEach(function (stage) {
        stages.appendChild(c.el("li", { text: stage.label + (stage.reversible ? " — reversible" : " — irreversible") }));
      });
      node.appendChild(stages);
    }
    if ((plan.notes || []).length) {
      node.appendChild(c.el("p", { className: "notice tone-warning", text: plan.notes.join(" ") }));
    }
    let typedInput = null;
    if (planned.confirmation === "type-project-id") {
      typedInput = c.el("input", {
        type: "text",
        attrs: { autocomplete: "off", placeholder: activeProject.project_id, "aria-label": "Type project ID to confirm" },
      });
      node.appendChild(c.el("div", {
        className: "field danger-field",
        children: [c.el("label", { text: "Type " + activeProject.project_id + " to confirm" }), typedInput],
      }));
    }
    return { node: node, typedInput: typedInput };
  }

  async function planAndRun(actionId, button) {
    if (!activeProject) return;
    const details = await c.api("/api/nob/projects/" + encodeURIComponent(activeProject.id));
    const action = (details.actions || []).find(function (candidate) { return candidate.id === actionId; });
    if (!action) throw new Error("Action is no longer declared");
    const editor = parameterEditor(action);
    if (editor.count) {
      const accepted = await c.confirmAction({
        title: action.label + " inputs",
        message: editor.node,
        confirmLabel: "Create review plan",
      });
      if (!accepted) return;
      if (!editor.valid()) return;
    }
    const planned = await c.api(
      "/api/nob/projects/" + encodeURIComponent(activeProject.id) + "/actions/" + encodeURIComponent(actionId) + "/plan",
      { method: "POST", body: { parameters: editor.values() } }
    );
    const review = planReview(planned);
    const confirmed = await c.confirmAction({
      title: "Review " + action.label + " plan",
      message: review.node,
      confirmLabel: "Queue run",
      danger: planned.effect === "data-destructive" || planned.effect === "host-destructive",
    });
    if (!confirmed) return;
    let typedProjectId = null;
    if (review.typedInput) {
      typedProjectId = review.typedInput.value.trim();
      if (typedProjectId !== activeProject.project_id) {
        c.toast("The project ID did not match. Nothing was queued.", "danger");
        return;
      }
    }
    const queued = await c.api(
      "/api/nob/projects/" + encodeURIComponent(activeProject.id) + "/actions/" + encodeURIComponent(actionId) + "/run",
      {
        method: "POST",
        confirm: true,
        body: { plan_id: planned.id, confirm_project_id: typedProjectId },
      }
    );
    c.toast("Run queued.", "success");
    await loadRuns(activeProject.id);
    await showRun(queued.operation.id);
    pollRun(queued.operation.id, activeProject.id);
  }

  async function planAndRunResource(resourceId, controlName) {
    if (!activeProject) return;
    const base = "/api/nob/projects/" + encodeURIComponent(activeProject.id) +
      "/resources/" + encodeURIComponent(resourceId) + "/" + encodeURIComponent(controlName);
    const planned = await c.api(base + "/plan", { method: "POST", body: {} });
    const review = planReview(planned);
    const confirmed = await c.confirmAction({
      title: "Review " + controlName + " plan",
      message: review.node,
      confirmLabel: "Queue " + controlName,
      danger: controlName === "stop" || controlName === "disable",
    });
    if (!confirmed) return;
    const queued = await c.api(base + "/run", {
      method: "POST",
      confirm: true,
      body: { plan_id: planned.id },
    });
    c.toast("Resource control queued.", "success");
    await loadRuns(activeProject.id);
    await showRun(queued.operation.id);
    pollRun(queued.operation.id, activeProject.id);
  }

  async function showResourceLogs(resourceId) {
    if (!activeProject) return;
    const result = await c.api(
      "/api/nob/projects/" + encodeURIComponent(activeProject.id) + "/resources/" + encodeURIComponent(resourceId) + "/logs?tail=200"
    );
    const block = c.el("pre", { className: "log-output", text: result.text || "No journal entries." });
    await c.confirmAction({ title: "Recent resource logs", message: block, confirmLabel: "Done" });
  }

  function formatEpoch(seconds) {
    return seconds ? new Date(seconds * 1000).toLocaleString() : "—";
  }

  function runControls(run) {
    const controls = c.el("div", { className: "table-actions" });
    controls.appendChild(c.button("View", { small: true, dataset: { nobRunView: run.id } }));
    if (run.state === "queued" || run.state === "running") {
      controls.appendChild(c.button("Cancel", { small: true, kind: "danger", dataset: { nobRunCancel: run.id } }));
    }
    return controls;
  }

  async function loadRuns(projectId) {
    if (!projectId) return;
    try {
      const result = await c.api("/api/nob/operations?limit=200");
      const runs = (result.items || []).filter(function (run) { return run.project_id === Number(projectId); });
      c.renderTable(runsBody, runs, [
        { label: "Run", render: function (run) { return [c.el("span", { className: "mono", text: run.id.slice(0, 10) + "…" }), c.el("div", { className: "muted", text: formatEpoch(run.queued_at) })]; } },
        { label: "Action", key: "action_id" },
        { label: "State", render: function (run) { return c.status(run.state); } },
        { label: "Summary", render: function (run) { return run.summary || "Waiting to start"; } },
        { label: "Controls", render: runControls, className: "cell-actions" },
      ], "No runs have been queued for this project.");
    } catch (error) {
      c.tableEmpty(runsBody, 5, "Runs unavailable: " + error.message);
    }
  }

  async function showRun(operationId) {
    const result = await c.api("/api/nob/operations/" + encodeURIComponent(operationId));
    const run = result.operation;
    const events = result.events || [];
    const artifacts = result.artifacts || [];
    const eventList = c.el("ol", { className: "run-timeline" });
    events.forEach(function (event) {
      let payload = {};
      try { payload = JSON.parse(event.payload_json); } catch (_) {}
      eventList.appendChild(c.el("li", {
        children: [
          c.status(event.event_type),
          c.el("span", { text: payload.label || payload.message || payload.summary || payload.stage_id || "" }),
        ],
      }));
    });
    const content = [
      c.el("div", { className: "panel-header compact-header", children: [
        c.el("div", { children: [c.el("h3", { className: "section-heading", text: "Run " + run.id }), c.el("p", { text: run.summary || "In progress" })] }),
        c.status(run.state),
      ] }),
      eventList
    ];
    if (artifacts.length) {
      const artifactList = c.el("ul", { className: "review-list" });
      artifacts.forEach(function (artifact) {
        artifactList.appendChild(c.el("li", {
          children: [
            c.el("strong", { text: artifact.artifact_id }),
            " — " + artifact.role + (artifact.size_bytes == null ? "" : " (" + artifact.size_bytes + " bytes)"),
          ],
        }));
      });
      content.push(c.el("h3", { className: "section-heading", text: "Artifacts" }), artifactList);
    }
    runDetail.replaceChildren.apply(runDetail, content);
    runDetail.classList.remove("hidden");
    return run;
  }

  async function cancelRun(operationId) {
    if (!await c.confirmAction({ title: "Cancel this run", message: "Cloudio will ask the runner to stop, then force it to exit if it does not cooperate.", confirmLabel: "Request cancellation", danger: true })) return;
    await c.api("/api/nob/operations/" + encodeURIComponent(operationId) + "/cancel", { method: "POST", confirm: true, body: {} });
    c.toast("Cancellation requested.", "success");
    await loadRuns(activeProject && activeProject.id);
    await showRun(operationId);
  }

  function pollRun(operationId, projectId) {
    let remaining = 300;
    async function poll() {
      if (remaining-- <= 0) return;
      try {
        const run = await showRun(operationId);
        await loadRuns(projectId);
        if (["queued", "running"].includes(run.state)) window.setTimeout(poll, 1000);
      } catch (error) {
        c.toast("Run status unavailable: " + error.message, "danger");
      }
    }
    window.setTimeout(poll, 500);
  }

  async function openDetails(projectId) {
    try {
      const data = await c.api("/api/nob/projects/" + encodeURIComponent(projectId));
      renderDetails(data);
    } catch (error) {
      c.toast("Project details unavailable: " + error.message, "danger");
    }
  }

  async function runProjectAction(button) {
    const action = button.dataset.nobAction;
    const projectId = button.dataset.projectId;
    const digest = button.dataset.manifestDigest;
    const declaredId = button.dataset.projectDeclaredId;
    let prompt = null;
    if (action === "trust") prompt = {
      title: "Approve this project",
      message: "Cloudio will trust this exact manifest. If it changes, project actions will pause until you review it again.",
      confirmLabel: "Approve project",
    };
    if (action === "revoke") prompt = {
      title: "Revoke project approval",
      message: "Cloudio will stop allowing this project runner to be used.",
      confirmLabel: "Revoke approval",
      danger: true,
    };
    if (action === "forget") prompt = {
      title: "Forget this project",
      message: "Cloudio will remove its approval, runner cache, pending plans, and secret bindings. Operation history and host resources will be retained, and future scans will leave it forgotten.",
      confirmLabel: "Forget project",
      danger: true,
    };
    if (action === "prepare") prompt = {
      title: "Prepare this project",
      message: "Cloudio will build and run the project-owned nob.zig helper for the exact manifest you approved.",
      confirmLabel: "Prepare project",
    };
    if (prompt && !await c.confirmAction(prompt)) return;
    const busy = { trust: "Approving…", revoke: "Revoking…", forget: "Forgetting…", prepare: "Preparing…", observe: "Refreshing…" }[action] || "Working…";
    await c.withBusy(button, busy, async function () {
      try {
        await c.api("/api/nob/projects/" + encodeURIComponent(projectId) + "/" + action, {
          method: "POST",
          confirm: action === "trust" || action === "revoke" || action === "forget",
          body: action === "trust" ? { manifest_sha256: digest, confirm_declared_id: declaredId } : {},
        });
        const message = {
          trust: "Project approved.",
          revoke: "Project approval revoked.",
          forget: "Project forgotten. History and host resources were retained.",
          prepare: "Project prepared and status refreshed.",
          observe: "Project status refreshed.",
        }[action] || "Project updated.";
        c.toast(message, "success");
        await loadProjects();
        if (!detailPanel.classList.contains("hidden")) await openDetails(projectId);
      } catch (error) {
        c.toast("Project update failed: " + error.message, "danger");
      }
    });
  }

  scanButton.addEventListener("click", function () {
    c.withBusy(scanButton, "Scanning…", async function () {
      try {
        const result = await c.api("/api/nob/scan", { method: "POST", body: {} });
        c.toast("Scan complete: " + result.projects_seen + " projects found.", "success");
        await loadProjects();
      } catch (error) {
        c.toast("Project scan failed: " + error.message, "danger");
      }
    });
  });

  projectsBody.addEventListener("click", function (event) {
    const open = event.target.closest("button[data-open-nob-project]");
    if (open) {
      openDetails(open.dataset.openNobProject);
      return;
    }
    const action = event.target.closest("button[data-nob-action]");
    if (action) runProjectAction(action);
  });
  actionsBody.addEventListener("click", function (event) {
    const button = event.target.closest("button[data-nob-run-action]");
    if (!button) return;
    c.withBusy(button, "Planning…", async function () {
      try {
        await planAndRun(button.dataset.nobRunAction, button);
      } catch (error) {
        c.toast("Action could not be queued: " + error.message, "danger");
      }
    });
  });
  resourcesBody.addEventListener("click", function (event) {
    const control = event.target.closest("button[data-nob-resource-control]");
    if (control) {
      c.withBusy(control, "Planning…", async function () {
        try {
          await planAndRunResource(control.dataset.nobResourceId, control.dataset.nobResourceControl);
        } catch (error) {
          c.toast("Resource control could not be queued: " + error.message, "danger");
        }
      });
      return;
    }
    const logs = event.target.closest("button[data-nob-resource-logs]");
    if (logs) showResourceLogs(logs.dataset.nobResourceLogs).catch(function (error) {
      c.toast("Resource logs unavailable: " + error.message, "danger");
    });
  });
  secretsBody.addEventListener("click", function (event) {
    const bind = event.target.closest("button[data-nob-secret-bind]");
    if (bind) {
      c.withBusy(bind, "Saving…", function () {
        return bindSecret(bind.dataset.nobSecretBind).catch(function (error) {
          c.toast("Secret binding failed: " + error.message, "danger");
        });
      });
      return;
    }
    const unbind = event.target.closest("button[data-nob-secret-unbind]");
    if (unbind) {
      c.withBusy(unbind, "Removing…", function () {
        return unbindSecret(unbind.dataset.nobSecretUnbind).catch(function (error) {
          c.toast("Secret removal failed: " + error.message, "danger");
        });
      });
    }
  });
  runsBody.addEventListener("click", function (event) {
    const view = event.target.closest("button[data-nob-run-view]");
    if (view) {
      showRun(view.dataset.nobRunView).catch(function (error) { c.toast("Run unavailable: " + error.message, "danger"); });
      return;
    }
    const cancel = event.target.closest("button[data-nob-run-cancel]");
    if (cancel) cancelRun(cancel.dataset.nobRunCancel).catch(function (error) { c.toast("Cancellation failed: " + error.message, "danger"); });
  });
  runsRefresh.addEventListener("click", function () {
    if (activeProject) loadRuns(activeProject.id);
  });
  c.byId("nob-project-detail-close").addEventListener("click", function () {
    detailPanel.classList.add("hidden");
    runDetail.classList.add("hidden");
    activeProject = null;
  });
  document.addEventListener("cloudio:reload", loadProjects);
})();
