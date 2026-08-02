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

  function discoveryLabel(value) {
    return {
      candidate: "Manifest needed",
      valid: "Ready",
      invalid: "Invalid manifest",
      conflict: "ID conflict",
      missing: "Missing",
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
    if (project.discovery_state === "valid" && project.manifest_sha256 && project.trust_state !== "trusted") {
      controls.appendChild(c.button("Approve", {
        small: true,
        kind: "primary",
        dataset: {
          nobAction: "trust",
          projectId: project.id,
          manifestDigest: project.manifest_sha256,
        },
      }));
    }
    if (project.trust_state === "trusted" || project.trust_state === "review-required") {
      controls.appendChild(c.button("Revoke", {
        small: true,
        kind: "danger",
        dataset: { nobAction: "revoke", projectId: project.id },
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
    detailTitle.textContent = project.display_name;
    detailMeta.textContent = project.root_path;
    facts.replaceChildren(
      fact("Project ID", project.project_id),
      fact("Kind", project.kind),
      fact("Declaration", discoveryLabel(project.discovery_state)),
      fact("Approval", trustLabel(project.trust_state)),
      fact("Status", project.status),
      fact("Runner", runnerLabel(project.runner_state)),
      fact("Manifest fingerprint", project.manifest_sha256)
    );
    c.renderTable(resourcesBody, data.resources || [], [
      { label: "Resource", render: function (row) { return row.label || row.id; } },
      { label: "Kind", render: function (row) { return c.badge(row.kind); } },
      { label: "Ownership", key: "ownership" },
      { label: "Status", render: function (row) { return c.status(row.status); } },
    ], "This project declares no resources.");
    c.renderTable(actionsBody, data.actions || [], [
      { label: "Action", render: function (row) { return row.label || row.id; } },
      { label: "Effect", render: function (row) { return c.badge(row.effect); } },
      { label: "Confirmation", key: "confirmation" },
      { label: "Available", render: function (row) { return c.badge(row.available ? "Available" : "Unavailable"); } },
    ], "This project declares no actions.");
    detailPanel.classList.remove("hidden");
    detailPanel.scrollIntoView({ block: "start" });
  }

  async function openDetails(projectId) {
    try {
      const data = await c.api("/api/nob/projects/" + encodeURIComponent(projectId));
      renderDetails(data);
    } catch (error) {
      c.toast("Project details unavailable: " + error.message, "danger");
    }
  }

  async function runTrustAction(button) {
    const action = button.dataset.nobAction;
    const projectId = button.dataset.projectId;
    const digest = button.dataset.manifestDigest;
    const approved = await c.confirmAction(action === "trust" ? {
      title: "Approve this project",
      message: "Cloudio will trust this exact manifest. If it changes, project actions will pause until you review it again.",
      confirmLabel: "Approve project",
    } : {
      title: "Revoke project approval",
      message: "Cloudio will stop allowing this project runner to be used.",
      confirmLabel: "Revoke approval",
      danger: true,
    });
    if (!approved) return;
    await c.withBusy(button, action === "trust" ? "Approving…" : "Revoking…", async function () {
      try {
        await c.api("/api/nob/projects/" + encodeURIComponent(projectId) + "/" + action, {
          method: "POST",
          body: action === "trust" ? { manifest_sha256: digest } : {},
        });
        c.toast(action === "trust" ? "Project approved." : "Project approval revoked.", "success");
        await loadProjects();
        if (!detailPanel.classList.contains("hidden")) await openDetails(projectId);
      } catch (error) {
        c.toast("Approval change failed: " + error.message, "danger");
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
    if (action) runTrustAction(action);
  });
  c.byId("nob-project-detail-close").addEventListener("click", function () {
    detailPanel.classList.add("hidden");
  });
  document.addEventListener("cloudio:reload", loadProjects);
})();
