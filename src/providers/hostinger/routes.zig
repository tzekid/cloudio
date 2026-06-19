const std = @import("std");
const core_time = @import("core_time");
const typed_routes = @import("provider_typed_routes");

const Allocator = std.mem.Allocator;

const DryRunPlan = typed_routes.DryRunPlan;
pub const pathEscape = typed_routes.pathEscape;
pub const appendQueryParam = typed_routes.appendQueryParam;

pub const base_url = "https://developers.hostinger.com";
pub const virtual_machines_path = "/api/vps/v1/virtual-machines";
pub const data_centers_path = "/api/vps/v1/data-centers";
pub const firewall_path = "/api/vps/v1/firewall";
pub const public_keys_path = "/api/vps/v1/public-keys";
pub const templates_path = "/api/vps/v1/templates";
pub const post_install_scripts_path = "/api/vps/v1/post-install-scripts";
pub const billing_catalog_path = "/api/billing/v1/catalog";
pub const billing_payment_methods_path = "/api/billing/v1/payment-methods";
pub const billing_subscriptions_path = "/api/billing/v1/subscriptions";
pub const dns_zones_path = "/api/dns/v1/zones";
pub const dns_snapshots_path = "/api/dns/v1/snapshots";
pub const domains_availability_path = "/api/domains/v1/availability";
pub const domains_portfolio_path = "/api/domains/v1/portfolio";
pub const domains_forwarding_path = "/api/domains/v1/forwarding";
pub const domains_whois_path = "/api/domains/v1/whois";
pub const hosting_accounts_path = "/api/hosting/v1/accounts";
pub const hosting_datacenters_path = "/api/hosting/v1/datacenters";
pub const hosting_domains_path = "/api/hosting/v1/domains";
pub const hosting_orders_path = "/api/hosting/v1/orders";
pub const hosting_websites_path = "/api/hosting/v1/websites";
pub const hosting_wordpress_installations_path = "/api/hosting/v1/wordpress/installations";
pub const ecommerce_stores_path = "/api/ecommerce/v1/stores";
pub const horizons_websites_path = "/api/horizons/v1/websites";
pub const reach_contacts_path = "/api/reach/v1/contacts";
pub const reach_profiles_path = "/api/reach/v1/profiles";
pub const reach_segments_path = "/api/reach/v1/segmentation/segments";

pub const VmEndpoint = enum {
    metrics,
    actions,
    public_keys,
    backups,
    snapshot,
    monarx,
    docker,

    pub fn label(self: VmEndpoint) []const u8 {
        return switch (self) {
            .metrics => "metrics",
            .actions => "actions",
            .public_keys => "public-keys",
            .backups => "backups",
            .snapshot => "snapshot",
            .monarx => "monarx",
            .docker => "docker",
        };
    }

    pub fn parse(value: []const u8) ?VmEndpoint {
        if (std.mem.eql(u8, value, "metrics")) return .metrics;
        if (std.mem.eql(u8, value, "actions")) return .actions;
        if (std.mem.eql(u8, value, "public-keys")) return .public_keys;
        if (std.mem.eql(u8, value, "backups")) return .backups;
        if (std.mem.eql(u8, value, "snapshot")) return .snapshot;
        if (std.mem.eql(u8, value, "monarx")) return .monarx;
        if (std.mem.eql(u8, value, "docker")) return .docker;
        return null;
    }
};

pub const VpsMutationEndpoint = enum {
    purchase,
    set_hostname,
    reset_hostname,
    set_nameservers,
    set_panel_password,
    recreate,
    restart,
    set_root_password,
    setup,
    start,
    stop,
    start_recovery,
    stop_recovery,
    create_ptr,
    delete_ptr,
    restore_backup,
    create_snapshot,
    delete_snapshot,
    restore_snapshot,
    install_monarx,
    uninstall_monarx,

    pub fn parse(value: []const u8) ?VpsMutationEndpoint {
        if (std.mem.eql(u8, value, "purchase")) return .purchase;
        if (std.mem.eql(u8, value, "set-hostname")) return .set_hostname;
        if (std.mem.eql(u8, value, "reset-hostname")) return .reset_hostname;
        if (std.mem.eql(u8, value, "set-nameservers")) return .set_nameservers;
        if (std.mem.eql(u8, value, "set-panel-password")) return .set_panel_password;
        if (std.mem.eql(u8, value, "recreate")) return .recreate;
        if (std.mem.eql(u8, value, "restart")) return .restart;
        if (std.mem.eql(u8, value, "set-root-password")) return .set_root_password;
        if (std.mem.eql(u8, value, "setup")) return .setup;
        if (std.mem.eql(u8, value, "start")) return .start;
        if (std.mem.eql(u8, value, "stop")) return .stop;
        if (std.mem.eql(u8, value, "start-recovery")) return .start_recovery;
        if (std.mem.eql(u8, value, "stop-recovery")) return .stop_recovery;
        if (std.mem.eql(u8, value, "create-ptr")) return .create_ptr;
        if (std.mem.eql(u8, value, "delete-ptr")) return .delete_ptr;
        if (std.mem.eql(u8, value, "restore-backup")) return .restore_backup;
        if (std.mem.eql(u8, value, "create-snapshot")) return .create_snapshot;
        if (std.mem.eql(u8, value, "delete-snapshot")) return .delete_snapshot;
        if (std.mem.eql(u8, value, "restore-snapshot")) return .restore_snapshot;
        if (std.mem.eql(u8, value, "install-monarx") or std.mem.eql(u8, value, "install-malware-scanner")) return .install_monarx;
        if (std.mem.eql(u8, value, "uninstall-monarx") or std.mem.eql(u8, value, "uninstall-malware-scanner")) return .uninstall_monarx;
        return null;
    }

    pub fn commandName(self: VpsMutationEndpoint) []const u8 {
        return switch (self) {
            .purchase => "purchase",
            .set_hostname => "set-hostname",
            .reset_hostname => "reset-hostname",
            .set_nameservers => "set-nameservers",
            .set_panel_password => "set-panel-password",
            .recreate => "recreate",
            .restart => "restart",
            .set_root_password => "set-root-password",
            .setup => "setup",
            .start => "start",
            .stop => "stop",
            .start_recovery => "start-recovery",
            .stop_recovery => "stop-recovery",
            .create_ptr => "create-ptr",
            .delete_ptr => "delete-ptr",
            .restore_backup => "restore-backup",
            .create_snapshot => "create-snapshot",
            .delete_snapshot => "delete-snapshot",
            .restore_snapshot => "restore-snapshot",
            .install_monarx => "install-monarx",
            .uninstall_monarx => "uninstall-monarx",
        };
    }

    pub fn group(self: VpsMutationEndpoint) []const u8 {
        return switch (self) {
            .start_recovery, .stop_recovery => "VPS: Recovery",
            .create_ptr, .delete_ptr => "VPS: PTR records",
            .restore_backup => "VPS: Backups",
            .create_snapshot, .delete_snapshot, .restore_snapshot => "VPS: Snapshots",
            .install_monarx, .uninstall_monarx => "VPS: Malware scanner",
            else => "VPS: Virtual machine",
        };
    }

    pub fn method(self: VpsMutationEndpoint) []const u8 {
        return switch (self) {
            .purchase, .recreate, .restart, .setup, .start, .stop, .start_recovery, .create_ptr, .restore_backup, .create_snapshot, .restore_snapshot, .install_monarx => "POST",
            .set_hostname, .set_nameservers, .set_panel_password, .set_root_password => "PUT",
            .reset_hostname, .stop_recovery, .delete_ptr, .delete_snapshot, .uninstall_monarx => "DELETE",
        };
    }

    pub fn operationId(self: VpsMutationEndpoint) []const u8 {
        return switch (self) {
            .purchase => "VPS_purchaseNewVirtualMachineV1",
            .set_hostname => "VPS_setHostnameV1",
            .reset_hostname => "VPS_resetHostnameV1",
            .set_nameservers => "VPS_setNameserversV1",
            .set_panel_password => "VPS_setPanelPasswordV1",
            .recreate => "VPS_recreateVirtualMachineV1",
            .restart => "VPS_restartVirtualMachineV1",
            .set_root_password => "VPS_setRootPasswordV1",
            .setup => "VPS_setupPurchasedVirtualMachineV1",
            .start => "VPS_startVirtualMachineV1",
            .stop => "VPS_stopVirtualMachineV1",
            .start_recovery => "VPS_startRecoveryModeV1",
            .stop_recovery => "VPS_stopRecoveryModeV1",
            .create_ptr => "VPS_createPTRRecordV1",
            .delete_ptr => "VPS_deletePTRRecordV1",
            .restore_backup => "VPS_restoreBackupV1",
            .create_snapshot => "VPS_createSnapshotV1",
            .delete_snapshot => "VPS_deleteSnapshotV1",
            .restore_snapshot => "VPS_restoreSnapshotV1",
            .install_monarx => "VPS_installMonarxV1",
            .uninstall_monarx => "VPS_uninstallMonarxV1",
        };
    }

    pub fn summary(self: VpsMutationEndpoint) []const u8 {
        return switch (self) {
            .purchase => "Purchase new virtual machine",
            .set_hostname => "Set hostname",
            .reset_hostname => "Reset hostname",
            .set_nameservers => "Set nameservers",
            .set_panel_password => "Set panel password",
            .recreate => "Recreate virtual machine",
            .restart => "Restart virtual machine",
            .set_root_password => "Set root password",
            .setup => "Setup purchased virtual machine",
            .start => "Start virtual machine",
            .stop => "Stop virtual machine",
            .start_recovery => "Start recovery mode",
            .stop_recovery => "Stop recovery mode",
            .create_ptr => "Create PTR record",
            .delete_ptr => "Delete PTR record",
            .restore_backup => "Restore backup",
            .create_snapshot => "Create snapshot",
            .delete_snapshot => "Delete snapshot",
            .restore_snapshot => "Restore snapshot",
            .install_monarx => "Install Monarx",
            .uninstall_monarx => "Uninstall Monarx",
        };
    }

    pub fn requestBodySchemaRef(self: VpsMutationEndpoint) ?[]const u8 {
        return switch (self) {
            .purchase => "#/components/schemas/VPS.V1.VirtualMachine.PurchaseRequest",
            .set_hostname => "#/components/schemas/VPS.V1.VirtualMachine.HostnameUpdateRequest",
            .set_nameservers => "#/components/schemas/VPS.V1.VirtualMachine.NameserversUpdateRequest",
            .set_panel_password => "#/components/schemas/VPS.V1.VirtualMachine.PanelPasswordUpdateRequest",
            .recreate => "#/components/schemas/VPS.V1.VirtualMachine.RecreateRequest",
            .set_root_password => "#/components/schemas/VPS.V1.VirtualMachine.RootPasswordUpdateRequest",
            .setup => "#/components/schemas/VPS.V1.VirtualMachine.SetupRequest",
            .start_recovery => "#/components/schemas/VPS.V1.VirtualMachine.Recovery.StartRequest",
            .create_ptr => "#/components/schemas/VPS.V1.VirtualMachine.PTR.StoreRequest",
            .reset_hostname, .restart, .start, .stop, .stop_recovery, .delete_ptr, .restore_backup, .create_snapshot, .delete_snapshot, .restore_snapshot, .install_monarx, .uninstall_monarx => null,
        };
    }

    pub fn requiresVmId(self: VpsMutationEndpoint) bool {
        return self != .purchase;
    }

    pub fn requiresIpAddressId(self: VpsMutationEndpoint) bool {
        return self == .create_ptr or self == .delete_ptr;
    }

    pub fn requiresBackupId(self: VpsMutationEndpoint) bool {
        return self == .restore_backup;
    }

    pub fn suffix(self: VpsMutationEndpoint) ?[]const u8 {
        return switch (self) {
            .purchase => null,
            .set_hostname, .reset_hostname => "hostname",
            .set_nameservers => "nameservers",
            .set_panel_password => "panel-password",
            .recreate => "recreate",
            .restart => "restart",
            .set_root_password => "root-password",
            .setup => "setup",
            .start => "start",
            .stop => "stop",
            .start_recovery, .stop_recovery => "recovery",
            .create_ptr, .delete_ptr => "ptr",
            .restore_backup => "backups",
            .create_snapshot, .delete_snapshot => "snapshot",
            .restore_snapshot => "snapshot/restore",
            .install_monarx, .uninstall_monarx => "monarx",
        };
    }
};

pub const VpsMutationArgs = struct {
    vm_id: ?[]const u8 = null,
    ip_address_id: ?[]const u8 = null,
    backup_id: ?[]const u8 = null,
};

pub const VpsInventoryEndpoint = enum {
    data_centers,
    firewalls,
    public_keys,
    templates,
    post_install_scripts,

    pub fn label(self: VpsInventoryEndpoint) []const u8 {
        return switch (self) {
            .data_centers => "data-centers",
            .firewalls => "firewalls",
            .public_keys => "public-keys-global",
            .templates => "templates",
            .post_install_scripts => "post-install-scripts",
        };
    }

    pub fn path(self: VpsInventoryEndpoint) []const u8 {
        return switch (self) {
            .data_centers => data_centers_path,
            .firewalls => firewall_path,
            .public_keys => public_keys_path,
            .templates => templates_path,
            .post_install_scripts => post_install_scripts_path,
        };
    }

    pub fn parse(value: []const u8) ?VpsInventoryEndpoint {
        if (std.mem.eql(u8, value, "data-centers")) return .data_centers;
        if (std.mem.eql(u8, value, "firewalls") or std.mem.eql(u8, value, "firewall")) return .firewalls;
        if (std.mem.eql(u8, value, "public-keys") or std.mem.eql(u8, value, "public-keys-global")) return .public_keys;
        if (std.mem.eql(u8, value, "templates")) return .templates;
        if (std.mem.eql(u8, value, "post-install-scripts")) return .post_install_scripts;
        return null;
    }
};

pub const VpsInventoryDetailEndpoint = enum {
    firewall,
    template,
    post_install_script,

    pub fn label(self: VpsInventoryDetailEndpoint) []const u8 {
        return switch (self) {
            .firewall => "firewall-detail",
            .template => "template-detail",
            .post_install_script => "post-install-script-detail",
        };
    }

    pub fn pathPrefix(self: VpsInventoryDetailEndpoint) []const u8 {
        return switch (self) {
            .firewall => firewall_path,
            .template => templates_path,
            .post_install_script => post_install_scripts_path,
        };
    }

    pub fn commandName(self: VpsInventoryDetailEndpoint) []const u8 {
        return switch (self) {
            .firewall => "firewall",
            .template => "template",
            .post_install_script => "post-install-script",
        };
    }

    pub fn idName(self: VpsInventoryDetailEndpoint) []const u8 {
        return switch (self) {
            .firewall => "firewall id",
            .template => "template id",
            .post_install_script => "post-install script id",
        };
    }

    pub fn parse(value: []const u8) ?VpsInventoryDetailEndpoint {
        if (std.mem.eql(u8, value, "firewall")) return .firewall;
        if (std.mem.eql(u8, value, "template")) return .template;
        if (std.mem.eql(u8, value, "post-install-script") or std.mem.eql(u8, value, "post-install")) return .post_install_script;
        return null;
    }
};

pub const VpsResourceMutationEndpoint = enum {
    create_public_key,
    delete_public_key,
    attach_public_key,
    create_post_install_script,
    update_post_install_script,
    delete_post_install_script,

    pub fn parse(value: []const u8) ?VpsResourceMutationEndpoint {
        if (std.mem.eql(u8, value, "create-public-key")) return .create_public_key;
        if (std.mem.eql(u8, value, "delete-public-key")) return .delete_public_key;
        if (std.mem.eql(u8, value, "attach-public-key")) return .attach_public_key;
        if (std.mem.eql(u8, value, "create-post-install-script") or std.mem.eql(u8, value, "create-post-install")) return .create_post_install_script;
        if (std.mem.eql(u8, value, "update-post-install-script") or std.mem.eql(u8, value, "update-post-install")) return .update_post_install_script;
        if (std.mem.eql(u8, value, "delete-post-install-script") or std.mem.eql(u8, value, "delete-post-install")) return .delete_post_install_script;
        return null;
    }

    pub fn parseScoped(target: []const u8, operation: []const u8) ?VpsResourceMutationEndpoint {
        if (std.mem.eql(u8, target, "public-key") or std.mem.eql(u8, target, "public-keys")) {
            if (std.mem.eql(u8, operation, "create")) return .create_public_key;
            if (std.mem.eql(u8, operation, "delete")) return .delete_public_key;
            if (std.mem.eql(u8, operation, "attach")) return .attach_public_key;
        }
        if (std.mem.eql(u8, target, "post-install-script") or std.mem.eql(u8, target, "post-install-scripts") or std.mem.eql(u8, target, "post-install")) {
            if (std.mem.eql(u8, operation, "create")) return .create_post_install_script;
            if (std.mem.eql(u8, operation, "update")) return .update_post_install_script;
            if (std.mem.eql(u8, operation, "delete")) return .delete_post_install_script;
        }
        return null;
    }

    pub fn commandName(self: VpsResourceMutationEndpoint) []const u8 {
        return switch (self) {
            .create_public_key => "create-public-key",
            .delete_public_key => "delete-public-key",
            .attach_public_key => "attach-public-key",
            .create_post_install_script => "create-post-install-script",
            .update_post_install_script => "update-post-install-script",
            .delete_post_install_script => "delete-post-install-script",
        };
    }

    pub fn group(self: VpsResourceMutationEndpoint) []const u8 {
        return switch (self) {
            .create_public_key, .delete_public_key, .attach_public_key => "VPS: Public Keys",
            .create_post_install_script, .update_post_install_script, .delete_post_install_script => "VPS: Post-install scripts",
        };
    }

    pub fn method(self: VpsResourceMutationEndpoint) []const u8 {
        return switch (self) {
            .create_public_key, .attach_public_key, .create_post_install_script => "POST",
            .update_post_install_script => "PUT",
            .delete_public_key, .delete_post_install_script => "DELETE",
        };
    }

    pub fn operationId(self: VpsResourceMutationEndpoint) []const u8 {
        return switch (self) {
            .create_public_key => "VPS_createPublicKeyV1",
            .delete_public_key => "VPS_deletePublicKeyV1",
            .attach_public_key => "VPS_attachPublicKeyV1",
            .create_post_install_script => "VPS_createPostInstallScriptV1",
            .update_post_install_script => "VPS_updatePostInstallScriptV1",
            .delete_post_install_script => "VPS_deletePostInstallScriptV1",
        };
    }

    pub fn summary(self: VpsResourceMutationEndpoint) []const u8 {
        return switch (self) {
            .create_public_key => "Create public key",
            .delete_public_key => "Delete public key",
            .attach_public_key => "Attach public key",
            .create_post_install_script => "Create post-install script",
            .update_post_install_script => "Update post-install script",
            .delete_post_install_script => "Delete post-install script",
        };
    }

    pub fn requestBodySchemaRef(self: VpsResourceMutationEndpoint) ?[]const u8 {
        return switch (self) {
            .create_public_key => "#/components/schemas/VPS.V1.PublicKey.StoreRequest",
            .attach_public_key => "#/components/schemas/VPS.V1.PublicKey.AttachRequest",
            .create_post_install_script, .update_post_install_script => "#/components/schemas/VPS.V1.PostInstallScript.StoreRequest",
            .delete_public_key, .delete_post_install_script => null,
        };
    }

    pub fn requiresPublicKeyId(self: VpsResourceMutationEndpoint) bool {
        return self == .delete_public_key;
    }

    pub fn requiresPostInstallScriptId(self: VpsResourceMutationEndpoint) bool {
        return self == .update_post_install_script or self == .delete_post_install_script;
    }

    pub fn requiresVmId(self: VpsResourceMutationEndpoint) bool {
        return self == .attach_public_key;
    }
};

pub const VpsResourceMutationArgs = struct {
    public_key_id: ?[]const u8 = null,
    post_install_script_id: ?[]const u8 = null,
    vm_id: ?[]const u8 = null,
};

pub const DockerEndpoint = enum {
    projects,
    contents,
    containers,
    logs,

    pub fn label(self: DockerEndpoint) []const u8 {
        return switch (self) {
            .projects => "docker",
            .contents => "docker-contents",
            .containers => "docker-containers",
            .logs => "docker-logs",
        };
    }

    pub fn suffix(self: DockerEndpoint) ?[]const u8 {
        return switch (self) {
            .projects, .contents => null,
            .containers => "containers",
            .logs => "logs",
        };
    }

    pub fn parse(value: []const u8) ?DockerEndpoint {
        if (std.mem.eql(u8, value, "docker") or std.mem.eql(u8, value, "docker-projects")) return .projects;
        if (std.mem.eql(u8, value, "docker-contents") or std.mem.eql(u8, value, "docker-project")) return .contents;
        if (std.mem.eql(u8, value, "docker-containers")) return .containers;
        if (std.mem.eql(u8, value, "docker-logs")) return .logs;
        return null;
    }

    pub fn requiresProject(self: DockerEndpoint) bool {
        return self != .projects;
    }
};

pub const DockerMutationEndpoint = enum {
    create_project,
    delete_project,
    restart_project,
    start_project,
    stop_project,
    update_project,

    pub fn parse(value: []const u8) ?DockerMutationEndpoint {
        if (std.mem.eql(u8, value, "create") or std.mem.eql(u8, value, "create-project")) return .create_project;
        if (std.mem.eql(u8, value, "delete") or std.mem.eql(u8, value, "delete-project") or std.mem.eql(u8, value, "down")) return .delete_project;
        if (std.mem.eql(u8, value, "restart") or std.mem.eql(u8, value, "restart-project")) return .restart_project;
        if (std.mem.eql(u8, value, "start") or std.mem.eql(u8, value, "start-project")) return .start_project;
        if (std.mem.eql(u8, value, "stop") or std.mem.eql(u8, value, "stop-project")) return .stop_project;
        if (std.mem.eql(u8, value, "update") or std.mem.eql(u8, value, "update-project")) return .update_project;
        return null;
    }

    pub fn commandName(self: DockerMutationEndpoint) []const u8 {
        return switch (self) {
            .create_project => "create",
            .delete_project => "delete",
            .restart_project => "restart",
            .start_project => "start",
            .stop_project => "stop",
            .update_project => "update",
        };
    }

    pub fn group(self: DockerMutationEndpoint) []const u8 {
        _ = self;
        return "VPS: Docker Manager";
    }

    pub fn method(self: DockerMutationEndpoint) []const u8 {
        return switch (self) {
            .create_project, .restart_project, .start_project, .stop_project, .update_project => "POST",
            .delete_project => "DELETE",
        };
    }

    pub fn operationId(self: DockerMutationEndpoint) []const u8 {
        return switch (self) {
            .create_project => "VPS_createNewProjectV1",
            .delete_project => "VPS_deleteProjectV1",
            .restart_project => "VPS_restartProjectV1",
            .start_project => "VPS_startProjectV1",
            .stop_project => "VPS_stopProjectV1",
            .update_project => "VPS_updateProjectV1",
        };
    }

    pub fn summary(self: DockerMutationEndpoint) []const u8 {
        return switch (self) {
            .create_project => "Create new project",
            .delete_project => "Delete project",
            .restart_project => "Restart project",
            .start_project => "Start project",
            .stop_project => "Stop project",
            .update_project => "Update project",
        };
    }

    pub fn requestBodySchemaRef(self: DockerMutationEndpoint) ?[]const u8 {
        return switch (self) {
            .create_project => "#/components/schemas/VPS.V1.VirtualMachine.DockerManager.UpRequest",
            .delete_project, .restart_project, .start_project, .stop_project, .update_project => null,
        };
    }

    pub fn requiresProject(self: DockerMutationEndpoint) bool {
        return self != .create_project;
    }

    pub fn suffix(self: DockerMutationEndpoint) ?[]const u8 {
        return switch (self) {
            .create_project => null,
            .delete_project => "down",
            .restart_project => "restart",
            .start_project => "start",
            .stop_project => "stop",
            .update_project => "update",
        };
    }
};

pub const DockerMutationArgs = struct {
    vm_id: []const u8,
    project_name: ?[]const u8 = null,
};

pub const FirewallMutationEndpoint = enum {
    create,
    delete,
    activate,
    deactivate,
    sync,
    create_rule,
    update_rule,
    delete_rule,

    pub fn parse(value: []const u8) ?FirewallMutationEndpoint {
        if (std.mem.eql(u8, value, "create") or std.mem.eql(u8, value, "create-firewall")) return .create;
        if (std.mem.eql(u8, value, "delete") or std.mem.eql(u8, value, "delete-firewall")) return .delete;
        if (std.mem.eql(u8, value, "activate")) return .activate;
        if (std.mem.eql(u8, value, "deactivate")) return .deactivate;
        if (std.mem.eql(u8, value, "sync")) return .sync;
        if (std.mem.eql(u8, value, "create-rule")) return .create_rule;
        if (std.mem.eql(u8, value, "update-rule")) return .update_rule;
        if (std.mem.eql(u8, value, "delete-rule")) return .delete_rule;
        return null;
    }

    pub fn commandName(self: FirewallMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "create",
            .delete => "delete",
            .activate => "activate",
            .deactivate => "deactivate",
            .sync => "sync",
            .create_rule => "create-rule",
            .update_rule => "update-rule",
            .delete_rule => "delete-rule",
        };
    }

    pub fn group(self: FirewallMutationEndpoint) []const u8 {
        _ = self;
        return "VPS: Firewall";
    }

    pub fn method(self: FirewallMutationEndpoint) []const u8 {
        return switch (self) {
            .create, .activate, .deactivate, .sync, .create_rule => "POST",
            .update_rule => "PUT",
            .delete, .delete_rule => "DELETE",
        };
    }

    pub fn operationId(self: FirewallMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "VPS_createNewFirewallV1",
            .delete => "VPS_deleteFirewallV1",
            .activate => "VPS_activateFirewallV1",
            .deactivate => "VPS_deactivateFirewallV1",
            .sync => "VPS_syncFirewallV1",
            .create_rule => "VPS_createFirewallRuleV1",
            .update_rule => "VPS_updateFirewallRuleV1",
            .delete_rule => "VPS_deleteFirewallRuleV1",
        };
    }

    pub fn summary(self: FirewallMutationEndpoint) []const u8 {
        return switch (self) {
            .create => "Create new firewall",
            .delete => "Delete firewall",
            .activate => "Activate firewall",
            .deactivate => "Deactivate firewall",
            .sync => "Sync firewall",
            .create_rule => "Create firewall rule",
            .update_rule => "Update firewall rule",
            .delete_rule => "Delete firewall rule",
        };
    }

    pub fn requestBodySchemaRef(self: FirewallMutationEndpoint) ?[]const u8 {
        return switch (self) {
            .create => "#/components/schemas/VPS.V1.Firewall.StoreRequest",
            .create_rule, .update_rule => "#/components/schemas/VPS.V1.Firewall.Rules.StoreRequest",
            .delete, .activate, .deactivate, .sync, .delete_rule => null,
        };
    }

    pub fn requiresFirewallId(self: FirewallMutationEndpoint) bool {
        return self != .create;
    }

    pub fn requiresVmId(self: FirewallMutationEndpoint) bool {
        return self == .activate or self == .deactivate or self == .sync;
    }

    pub fn requiresRuleId(self: FirewallMutationEndpoint) bool {
        return self == .update_rule or self == .delete_rule;
    }
};

pub const FirewallMutationArgs = struct {
    firewall_id: ?[]const u8 = null,
    vm_id: ?[]const u8 = null,
    rule_id: ?[]const u8 = null,
};

pub const BillingEndpoint = enum {
    catalog,
    payment_methods,
    subscriptions,

    pub fn label(self: BillingEndpoint) []const u8 {
        return switch (self) {
            .catalog => "billing-catalog",
            .payment_methods => "billing-payment-methods",
            .subscriptions => "billing-subscriptions",
        };
    }

    pub fn path(self: BillingEndpoint) []const u8 {
        return switch (self) {
            .catalog => billing_catalog_path,
            .payment_methods => billing_payment_methods_path,
            .subscriptions => billing_subscriptions_path,
        };
    }

    pub fn parse(value: []const u8) ?BillingEndpoint {
        if (std.mem.eql(u8, value, "billing-catalog")) return .catalog;
        if (std.mem.eql(u8, value, "billing-payment-methods") or std.mem.eql(u8, value, "billing-payments")) return .payment_methods;
        if (std.mem.eql(u8, value, "billing-subscriptions")) return .subscriptions;
        return null;
    }
};

pub const BillingMutationEndpoint = enum {
    set_default_payment_method,
    delete_payment_method,
    enable_auto_renewal,
    disable_auto_renewal,

    pub fn parse(value: []const u8) ?BillingMutationEndpoint {
        if (std.mem.eql(u8, value, "set-default-payment-method") or std.mem.eql(u8, value, "set-default-payment")) return .set_default_payment_method;
        if (std.mem.eql(u8, value, "delete-payment-method") or std.mem.eql(u8, value, "delete-payment")) return .delete_payment_method;
        if (std.mem.eql(u8, value, "enable-auto-renewal")) return .enable_auto_renewal;
        if (std.mem.eql(u8, value, "disable-auto-renewal")) return .disable_auto_renewal;
        return null;
    }

    pub fn commandName(self: BillingMutationEndpoint) []const u8 {
        return switch (self) {
            .set_default_payment_method => "set-default-payment-method",
            .delete_payment_method => "delete-payment-method",
            .enable_auto_renewal => "enable-auto-renewal",
            .disable_auto_renewal => "disable-auto-renewal",
        };
    }

    pub fn group(self: BillingMutationEndpoint) []const u8 {
        return switch (self) {
            .set_default_payment_method, .delete_payment_method => "Billing: Payment methods",
            .enable_auto_renewal, .disable_auto_renewal => "Billing: Subscriptions",
        };
    }

    pub fn method(self: BillingMutationEndpoint) []const u8 {
        return switch (self) {
            .set_default_payment_method => "POST",
            .delete_payment_method, .disable_auto_renewal => "DELETE",
            .enable_auto_renewal => "PATCH",
        };
    }

    pub fn operationId(self: BillingMutationEndpoint) []const u8 {
        return switch (self) {
            .set_default_payment_method => "billing_setDefaultPaymentMethodV1",
            .delete_payment_method => "billing_deletePaymentMethodV1",
            .enable_auto_renewal => "billing_enableAutoRenewalV1",
            .disable_auto_renewal => "billing_disableAutoRenewalV1",
        };
    }

    pub fn summary(self: BillingMutationEndpoint) []const u8 {
        return switch (self) {
            .set_default_payment_method => "Set default payment method",
            .delete_payment_method => "Delete payment method",
            .enable_auto_renewal => "Enable auto-renewal",
            .disable_auto_renewal => "Disable auto-renewal",
        };
    }

    pub fn requestBodySchemaRef(self: BillingMutationEndpoint) ?[]const u8 {
        _ = self;
        return null;
    }

    pub fn requiresPaymentMethodId(self: BillingMutationEndpoint) bool {
        return self == .set_default_payment_method or self == .delete_payment_method;
    }

    pub fn requiresSubscriptionId(self: BillingMutationEndpoint) bool {
        return self == .enable_auto_renewal or self == .disable_auto_renewal;
    }
};

pub const BillingMutationArgs = struct {
    payment_method_id: ?[]const u8 = null,
    subscription_id: ?[]const u8 = null,
};

pub const DnsEndpoint = enum {
    zone,
    snapshots,
    snapshot,

    pub fn label(self: DnsEndpoint) []const u8 {
        return switch (self) {
            .zone => "dns-zone",
            .snapshots => "dns-snapshots",
            .snapshot => "dns-snapshot",
        };
    }

    pub fn parse(value: []const u8) ?DnsEndpoint {
        if (std.mem.eql(u8, value, "dns")) return .zone;
        if (std.mem.eql(u8, value, "dns-zone")) return .zone;
        if (std.mem.eql(u8, value, "dns-snapshots")) return .snapshots;
        if (std.mem.eql(u8, value, "dns-snapshot")) return .snapshot;
        return null;
    }

    pub fn requiresSnapshotId(self: DnsEndpoint) bool {
        return self == .snapshot;
    }
};

pub const DnsMutationEndpoint = enum {
    restore_snapshot,
    update_zone,
    delete_zone,
    reset_zone,
    validate_zone,

    pub fn parse(value: []const u8) ?DnsMutationEndpoint {
        if (std.mem.eql(u8, value, "restore-snapshot")) return .restore_snapshot;
        if (std.mem.eql(u8, value, "update") or std.mem.eql(u8, value, "update-zone")) return .update_zone;
        if (std.mem.eql(u8, value, "delete") or std.mem.eql(u8, value, "delete-zone")) return .delete_zone;
        if (std.mem.eql(u8, value, "reset") or std.mem.eql(u8, value, "reset-zone")) return .reset_zone;
        if (std.mem.eql(u8, value, "validate") or std.mem.eql(u8, value, "validate-zone")) return .validate_zone;
        return null;
    }

    pub fn commandName(self: DnsMutationEndpoint) []const u8 {
        return switch (self) {
            .restore_snapshot => "restore-snapshot",
            .update_zone => "update",
            .delete_zone => "delete",
            .reset_zone => "reset",
            .validate_zone => "validate",
        };
    }

    pub fn group(self: DnsMutationEndpoint) []const u8 {
        return switch (self) {
            .restore_snapshot => "DNS: Snapshot",
            .update_zone, .delete_zone, .reset_zone, .validate_zone => "DNS: Zone",
        };
    }

    pub fn method(self: DnsMutationEndpoint) []const u8 {
        return switch (self) {
            .restore_snapshot, .reset_zone, .validate_zone => "POST",
            .update_zone => "PUT",
            .delete_zone => "DELETE",
        };
    }

    pub fn operationId(self: DnsMutationEndpoint) []const u8 {
        return switch (self) {
            .restore_snapshot => "DNS_restoreDNSSnapshotV1",
            .update_zone => "DNS_updateDNSRecordsV1",
            .delete_zone => "DNS_deleteDNSRecordsV1",
            .reset_zone => "DNS_resetDNSRecordsV1",
            .validate_zone => "DNS_validateDNSRecordsV1",
        };
    }

    pub fn summary(self: DnsMutationEndpoint) []const u8 {
        return switch (self) {
            .restore_snapshot => "Restore DNS snapshot",
            .update_zone => "Update DNS records",
            .delete_zone => "Delete DNS records",
            .reset_zone => "Reset DNS records",
            .validate_zone => "Validate DNS records",
        };
    }

    pub fn requestBodySchemaRef(self: DnsMutationEndpoint) ?[]const u8 {
        return switch (self) {
            .restore_snapshot => null,
            .update_zone, .validate_zone => "#/components/schemas/DNS.V1.Zone.UpdateRequest",
            .delete_zone => "#/components/schemas/DNS.V1.Zone.DestroyRequest",
            .reset_zone => "#/components/schemas/DNS.V1.Zone.ResetRequest",
        };
    }

    pub fn requiresSnapshotId(self: DnsMutationEndpoint) bool {
        return self == .restore_snapshot;
    }

    pub fn suffix(self: DnsMutationEndpoint) ?[]const u8 {
        return switch (self) {
            .restore_snapshot => "restore",
            .update_zone, .delete_zone => null,
            .reset_zone => "reset",
            .validate_zone => "validate",
        };
    }
};

pub const DnsMutationArgs = struct {
    domain: []const u8,
    snapshot_id: ?[]const u8 = null,
};

pub const DomainEndpoint = enum {
    portfolio,
    portfolio_detail,
    forwarding,
    whois_profiles,
    whois_profile,
    whois_usage,

    pub fn label(self: DomainEndpoint) []const u8 {
        return switch (self) {
            .portfolio => "domains",
            .portfolio_detail => "domain",
            .forwarding => "domain-forwarding",
            .whois_profiles => "whois",
            .whois_profile => "whois-profile",
            .whois_usage => "whois-usage",
        };
    }

    pub fn parse(value: []const u8) ?DomainEndpoint {
        if (std.mem.eql(u8, value, "domains")) return .portfolio;
        if (std.mem.eql(u8, value, "domain")) return .portfolio_detail;
        if (std.mem.eql(u8, value, "domain-forwarding")) return .forwarding;
        if (std.mem.eql(u8, value, "whois") or std.mem.eql(u8, value, "whois-profiles")) return .whois_profiles;
        if (std.mem.eql(u8, value, "whois-profile")) return .whois_profile;
        if (std.mem.eql(u8, value, "whois-usage")) return .whois_usage;
        return null;
    }

    pub fn pathArgName(self: DomainEndpoint) ?[]const u8 {
        return switch (self) {
            .portfolio, .whois_profiles => null,
            .portfolio_detail, .forwarding => "domain",
            .whois_profile, .whois_usage => "whois id",
        };
    }
};

pub const DomainMutationEndpoint = enum {
    check_availability,
    create_forwarding,
    delete_forwarding,
    purchase_domain,
    enable_domain_lock,
    disable_domain_lock,
    update_nameservers,
    enable_privacy_protection,
    disable_privacy_protection,
    create_whois_profile,
    delete_whois_profile,

    pub fn parse(value: []const u8) ?DomainMutationEndpoint {
        if (std.mem.eql(u8, value, "availability") or std.mem.eql(u8, value, "check-availability")) return .check_availability;
        if (std.mem.eql(u8, value, "create-forwarding") or std.mem.eql(u8, value, "forwarding-create")) return .create_forwarding;
        if (std.mem.eql(u8, value, "delete-forwarding") or std.mem.eql(u8, value, "forwarding-delete")) return .delete_forwarding;
        if (std.mem.eql(u8, value, "purchase") or std.mem.eql(u8, value, "purchase-domain")) return .purchase_domain;
        if (std.mem.eql(u8, value, "enable-domain-lock")) return .enable_domain_lock;
        if (std.mem.eql(u8, value, "disable-domain-lock")) return .disable_domain_lock;
        if (std.mem.eql(u8, value, "update-nameservers")) return .update_nameservers;
        if (std.mem.eql(u8, value, "enable-privacy-protection")) return .enable_privacy_protection;
        if (std.mem.eql(u8, value, "disable-privacy-protection")) return .disable_privacy_protection;
        if (std.mem.eql(u8, value, "create-whois-profile") or std.mem.eql(u8, value, "create-whois")) return .create_whois_profile;
        if (std.mem.eql(u8, value, "delete-whois-profile") or std.mem.eql(u8, value, "delete-whois")) return .delete_whois_profile;
        return null;
    }

    pub fn commandName(self: DomainMutationEndpoint) []const u8 {
        return switch (self) {
            .check_availability => "check-availability",
            .create_forwarding => "create-forwarding",
            .delete_forwarding => "delete-forwarding",
            .purchase_domain => "purchase-domain",
            .enable_domain_lock => "enable-domain-lock",
            .disable_domain_lock => "disable-domain-lock",
            .update_nameservers => "update-nameservers",
            .enable_privacy_protection => "enable-privacy-protection",
            .disable_privacy_protection => "disable-privacy-protection",
            .create_whois_profile => "create-whois-profile",
            .delete_whois_profile => "delete-whois-profile",
        };
    }

    pub fn group(self: DomainMutationEndpoint) []const u8 {
        return switch (self) {
            .check_availability => "Domains: Availability",
            .create_forwarding, .delete_forwarding => "Domains: Forwarding",
            .purchase_domain, .enable_domain_lock, .disable_domain_lock, .update_nameservers, .enable_privacy_protection, .disable_privacy_protection => "Domains: Portfolio",
            .create_whois_profile, .delete_whois_profile => "Domains: WHOIS",
        };
    }

    pub fn method(self: DomainMutationEndpoint) []const u8 {
        return switch (self) {
            .check_availability, .create_forwarding, .purchase_domain, .create_whois_profile => "POST",
            .delete_forwarding, .disable_domain_lock, .disable_privacy_protection, .delete_whois_profile => "DELETE",
            .enable_domain_lock, .update_nameservers, .enable_privacy_protection => "PUT",
        };
    }

    pub fn operationId(self: DomainMutationEndpoint) []const u8 {
        return switch (self) {
            .check_availability => "domains_checkDomainAvailabilityV1",
            .create_forwarding => "domains_createDomainForwardingV1",
            .delete_forwarding => "domains_deleteDomainForwardingV1",
            .purchase_domain => "domains_purchaseNewDomainV1",
            .enable_domain_lock => "domains_enableDomainLockV1",
            .disable_domain_lock => "domains_disableDomainLockV1",
            .update_nameservers => "domains_updateDomainNameserversV1",
            .enable_privacy_protection => "domains_enablePrivacyProtectionV1",
            .disable_privacy_protection => "domains_disablePrivacyProtectionV1",
            .create_whois_profile => "domains_createWHOISProfileV1",
            .delete_whois_profile => "domains_deleteWHOISProfileV1",
        };
    }

    pub fn summary(self: DomainMutationEndpoint) []const u8 {
        return switch (self) {
            .check_availability => "Check domain availability",
            .create_forwarding => "Create domain forwarding",
            .delete_forwarding => "Delete domain forwarding",
            .purchase_domain => "Purchase new domain",
            .enable_domain_lock => "Enable domain lock",
            .disable_domain_lock => "Disable domain lock",
            .update_nameservers => "Update domain nameservers",
            .enable_privacy_protection => "Enable privacy protection",
            .disable_privacy_protection => "Disable privacy protection",
            .create_whois_profile => "Create WHOIS profile",
            .delete_whois_profile => "Delete WHOIS profile",
        };
    }

    pub fn requestBodySchemaRef(self: DomainMutationEndpoint) ?[]const u8 {
        return switch (self) {
            .check_availability => "#/components/schemas/Domains.V1.Availability.AvailabilityRequest",
            .create_forwarding => "#/components/schemas/Domains.V1.Forwarding.StoreRequest",
            .purchase_domain => "#/components/schemas/Domains.V1.Portfolio.PurchaseRequest",
            .update_nameservers => "#/components/schemas/Domains.V1.Portfolio.UpdateNameserversRequest",
            .create_whois_profile => "#/components/schemas/Domains.V1.WHOIS.StoreRequest",
            .delete_forwarding, .enable_domain_lock, .disable_domain_lock, .enable_privacy_protection, .disable_privacy_protection, .delete_whois_profile => null,
        };
    }

    pub fn requiresDomain(self: DomainMutationEndpoint) bool {
        return switch (self) {
            .delete_forwarding, .enable_domain_lock, .disable_domain_lock, .update_nameservers, .enable_privacy_protection, .disable_privacy_protection => true,
            else => false,
        };
    }

    pub fn requiresWhoisId(self: DomainMutationEndpoint) bool {
        return self == .delete_whois_profile;
    }
};

pub const DomainMutationArgs = struct {
    domain: ?[]const u8 = null,
    whois_id: ?[]const u8 = null,
};

pub const HostingArgs = struct {
    username: ?[]const u8 = null,
    domain: ?[]const u8 = null,
    name: ?[]const u8 = null,
    uuid: ?[]const u8 = null,
    order_id: ?[]const u8 = null,
    from_line: ?[]const u8 = null,
};

pub const HostingEndpoint = enum {
    orders,
    websites,
    wordpress,
    datacenters,
    databases,
    phpmyadmin_link,
    parked_domains,
    subdomains,
    nodejs_builds,
    nodejs_logs,

    pub fn label(self: HostingEndpoint) []const u8 {
        return switch (self) {
            .orders => "hosting-orders",
            .websites => "hosting-websites",
            .wordpress => "hosting-wordpress",
            .datacenters => "hosting-datacenters",
            .databases => "hosting-databases",
            .phpmyadmin_link => "hosting-phpmyadmin",
            .parked_domains => "hosting-parked-domains",
            .subdomains => "hosting-subdomains",
            .nodejs_builds => "hosting-node-builds",
            .nodejs_logs => "hosting-node-logs",
        };
    }

    pub fn parse(value: []const u8) ?HostingEndpoint {
        if (std.mem.eql(u8, value, "hosting-orders")) return .orders;
        if (std.mem.eql(u8, value, "hosting-websites")) return .websites;
        if (std.mem.eql(u8, value, "hosting-wordpress") or std.mem.eql(u8, value, "hosting-wordpress-installations")) return .wordpress;
        if (std.mem.eql(u8, value, "hosting-datacenters")) return .datacenters;
        if (std.mem.eql(u8, value, "hosting-databases")) return .databases;
        if (std.mem.eql(u8, value, "hosting-phpmyadmin") or std.mem.eql(u8, value, "hosting-phpmyadmin-link")) return .phpmyadmin_link;
        if (std.mem.eql(u8, value, "hosting-parked-domains")) return .parked_domains;
        if (std.mem.eql(u8, value, "hosting-subdomains")) return .subdomains;
        if (std.mem.eql(u8, value, "hosting-node-builds")) return .nodejs_builds;
        if (std.mem.eql(u8, value, "hosting-node-logs")) return .nodejs_logs;
        return null;
    }
};

pub const HostingMutationEndpoint = enum {
    create_website,
    install_wordpress,
    create_database,
    delete_database,
    change_database_password,
    repair_database,
    generate_free_subdomain,
    verify_domain_ownership,
    create_parked_domain,
    delete_parked_domain,
    create_subdomain,
    delete_subdomain,
    create_nodejs_build_from_archive,

    pub fn parse(value: []const u8) ?HostingMutationEndpoint {
        if (std.mem.eql(u8, value, "create-website")) return .create_website;
        if (std.mem.eql(u8, value, "install-wordpress")) return .install_wordpress;
        if (std.mem.eql(u8, value, "create-database")) return .create_database;
        if (std.mem.eql(u8, value, "delete-database")) return .delete_database;
        if (std.mem.eql(u8, value, "change-database-password")) return .change_database_password;
        if (std.mem.eql(u8, value, "repair-database")) return .repair_database;
        if (std.mem.eql(u8, value, "generate-free-subdomain") or std.mem.eql(u8, value, "free-subdomain")) return .generate_free_subdomain;
        if (std.mem.eql(u8, value, "verify-domain-ownership") or std.mem.eql(u8, value, "verify-ownership")) return .verify_domain_ownership;
        if (std.mem.eql(u8, value, "create-parked-domain") or std.mem.eql(u8, value, "parked-domain-create")) return .create_parked_domain;
        if (std.mem.eql(u8, value, "delete-parked-domain") or std.mem.eql(u8, value, "parked-domain-delete")) return .delete_parked_domain;
        if (std.mem.eql(u8, value, "create-subdomain") or std.mem.eql(u8, value, "subdomain-create")) return .create_subdomain;
        if (std.mem.eql(u8, value, "delete-subdomain") or std.mem.eql(u8, value, "subdomain-delete")) return .delete_subdomain;
        if (std.mem.eql(u8, value, "create-nodejs-build") or std.mem.eql(u8, value, "create-nodejs-build-from-archive") or std.mem.eql(u8, value, "nodejs-build-from-archive")) return .create_nodejs_build_from_archive;
        return null;
    }

    pub fn commandName(self: HostingMutationEndpoint) []const u8 {
        return switch (self) {
            .create_website => "create-website",
            .install_wordpress => "install-wordpress",
            .create_database => "create-database",
            .delete_database => "delete-database",
            .change_database_password => "change-database-password",
            .repair_database => "repair-database",
            .generate_free_subdomain => "generate-free-subdomain",
            .verify_domain_ownership => "verify-domain-ownership",
            .create_parked_domain => "create-parked-domain",
            .delete_parked_domain => "delete-parked-domain",
            .create_subdomain => "create-subdomain",
            .delete_subdomain => "delete-subdomain",
            .create_nodejs_build_from_archive => "create-nodejs-build-from-archive",
        };
    }

    pub fn group(self: HostingMutationEndpoint) []const u8 {
        return switch (self) {
            .create_website => "Hosting: Websites",
            .install_wordpress => "Hosting: Wordpress",
            .create_database, .delete_database, .change_database_password, .repair_database => "Hosting: Databases",
            .generate_free_subdomain, .verify_domain_ownership, .create_parked_domain, .delete_parked_domain, .create_subdomain, .delete_subdomain => "Hosting: Domains",
            .create_nodejs_build_from_archive => "Hosting: NodeJS",
        };
    }

    pub fn method(self: HostingMutationEndpoint) []const u8 {
        return switch (self) {
            .create_website, .install_wordpress, .create_database, .generate_free_subdomain, .verify_domain_ownership, .create_parked_domain, .create_subdomain, .create_nodejs_build_from_archive => "POST",
            .delete_database, .delete_parked_domain, .delete_subdomain => "DELETE",
            .change_database_password, .repair_database => "PATCH",
        };
    }

    pub fn operationId(self: HostingMutationEndpoint) []const u8 {
        return switch (self) {
            .create_website => "hosting_createWebsiteV1",
            .install_wordpress => "hosting_installWordPressV1",
            .create_database => "hosting_createAccountDatabaseV1",
            .delete_database => "hosting_deleteAccountDatabaseV1",
            .change_database_password => "hosting_changeDatabasePasswordV1",
            .repair_database => "hosting_repairDatabaseV1",
            .generate_free_subdomain => "hosting_generateAFreeSubdomainV1",
            .verify_domain_ownership => "hosting_verifyDomainOwnershipV1",
            .create_parked_domain => "hosting_createWebsiteParkedDomainV1",
            .delete_parked_domain => "hosting_deleteWebsiteParkedDomainV1",
            .create_subdomain => "hosting_createWebsiteSubdomainV1",
            .delete_subdomain => "hosting_deleteWebsiteSubdomainV1",
            .create_nodejs_build_from_archive => "hosting_createNodeJSBuildFromArchiveV1",
        };
    }

    pub fn summary(self: HostingMutationEndpoint) []const u8 {
        return switch (self) {
            .create_website => "Create website",
            .install_wordpress => "Install WordPress",
            .create_database => "Create account database",
            .delete_database => "Delete account database",
            .change_database_password => "Change database password",
            .repair_database => "Repair database",
            .generate_free_subdomain => "Generate a free subdomain",
            .verify_domain_ownership => "Verify domain ownership",
            .create_parked_domain => "Create website parked domain",
            .delete_parked_domain => "Delete website parked domain",
            .create_subdomain => "Create website subdomain",
            .delete_subdomain => "Delete website subdomain",
            .create_nodejs_build_from_archive => "Create NodeJS build from archive",
        };
    }

    pub fn requestBodySchemaRef(self: HostingMutationEndpoint) ?[]const u8 {
        return switch (self) {
            .create_website => "#/components/schemas/Hosting.V1.Websites.CreateWebsiteRequest",
            .install_wordpress => "#/components/schemas/Hosting.V1.Wordpress.InstallWordpressRequest",
            .create_database => "#/components/schemas/Hosting.V1.Databases.CreateDatabaseRequest",
            .change_database_password => "#/components/schemas/Hosting.V1.Databases.ChangeDatabasePasswordRequest",
            .verify_domain_ownership => "#/components/schemas/Hosting.V1.Domains.VerifyOwnershipRequest",
            .create_parked_domain => "#/components/schemas/Hosting.V1.Domains.CreateParkedDomainRequest",
            .create_subdomain => "#/components/schemas/Hosting.V1.Domains.CreateSubdomainRequest",
            .create_nodejs_build_from_archive => "#/components/schemas/Hosting.V1.NodeJs.CreateFromArchiveRequest",
            .delete_database, .repair_database, .generate_free_subdomain, .delete_parked_domain, .delete_subdomain => null,
        };
    }

    pub fn requiresUsername(self: HostingMutationEndpoint) bool {
        return switch (self) {
            .install_wordpress, .create_database, .delete_database, .change_database_password, .repair_database, .create_parked_domain, .delete_parked_domain, .create_subdomain, .delete_subdomain, .create_nodejs_build_from_archive => true,
            else => false,
        };
    }

    pub fn requiresDomain(self: HostingMutationEndpoint) bool {
        return switch (self) {
            .create_parked_domain, .delete_parked_domain, .create_subdomain, .delete_subdomain, .create_nodejs_build_from_archive => true,
            else => false,
        };
    }

    pub fn requiresDatabaseName(self: HostingMutationEndpoint) bool {
        return self == .delete_database or self == .change_database_password or self == .repair_database;
    }

    pub fn requiresParkedDomain(self: HostingMutationEndpoint) bool {
        return self == .delete_parked_domain;
    }

    pub fn requiresSubdomain(self: HostingMutationEndpoint) bool {
        return self == .delete_subdomain;
    }
};

pub const HostingMutationArgs = struct {
    username: ?[]const u8 = null,
    domain: ?[]const u8 = null,
    database_name: ?[]const u8 = null,
    parked_domain: ?[]const u8 = null,
    subdomain: ?[]const u8 = null,
};

pub const EcommerceEndpoint = enum {
    stores,

    pub fn label(self: EcommerceEndpoint) []const u8 {
        return switch (self) {
            .stores => "ecommerce-stores",
        };
    }

    pub fn path(self: EcommerceEndpoint) []const u8 {
        return switch (self) {
            .stores => ecommerce_stores_path,
        };
    }

    pub fn parse(value: []const u8) ?EcommerceEndpoint {
        if (std.mem.eql(u8, value, "ecommerce-stores")) return .stores;
        return null;
    }
};

pub const EcommerceMutationEndpoint = enum {
    create_store,

    pub fn parse(value: []const u8) ?EcommerceMutationEndpoint {
        if (std.mem.eql(u8, value, "create-store") or std.mem.eql(u8, value, "create")) return .create_store;
        return null;
    }

    pub fn commandName(self: EcommerceMutationEndpoint) []const u8 {
        return switch (self) {
            .create_store => "create-store",
        };
    }

    pub fn group(self: EcommerceMutationEndpoint) []const u8 {
        _ = self;
        return "Ecommerce: Stores";
    }

    pub fn method(self: EcommerceMutationEndpoint) []const u8 {
        _ = self;
        return "POST";
    }

    pub fn operationId(self: EcommerceMutationEndpoint) []const u8 {
        return switch (self) {
            .create_store => "ecommerce_createStoreV1",
        };
    }

    pub fn summary(self: EcommerceMutationEndpoint) []const u8 {
        return switch (self) {
            .create_store => "Create store",
        };
    }

    pub fn requestBodySchemaRef(self: EcommerceMutationEndpoint) ?[]const u8 {
        return switch (self) {
            .create_store => "#/components/schemas/Ecommerce.V1.Store.StoreRequest",
        };
    }
};

pub const HorizonsEndpoint = enum {
    website,

    pub fn label(self: HorizonsEndpoint) []const u8 {
        return switch (self) {
            .website => "horizons-website",
        };
    }

    pub fn parse(value: []const u8) ?HorizonsEndpoint {
        if (std.mem.eql(u8, value, "horizons-website")) return .website;
        return null;
    }
};

pub const HorizonsMutationEndpoint = enum {
    create_website,

    pub fn parse(value: []const u8) ?HorizonsMutationEndpoint {
        if (std.mem.eql(u8, value, "create-website") or std.mem.eql(u8, value, "create")) return .create_website;
        return null;
    }

    pub fn commandName(self: HorizonsMutationEndpoint) []const u8 {
        return switch (self) {
            .create_website => "create-website",
        };
    }

    pub fn group(self: HorizonsMutationEndpoint) []const u8 {
        _ = self;
        return "Horizons: Websites";
    }

    pub fn method(self: HorizonsMutationEndpoint) []const u8 {
        _ = self;
        return "POST";
    }

    pub fn operationId(self: HorizonsMutationEndpoint) []const u8 {
        return switch (self) {
            .create_website => "horizons_createWebsiteV1",
        };
    }

    pub fn summary(self: HorizonsMutationEndpoint) []const u8 {
        return switch (self) {
            .create_website => "Create website",
        };
    }

    pub fn requestBodySchemaRef(self: HorizonsMutationEndpoint) ?[]const u8 {
        return switch (self) {
            .create_website => "#/components/schemas/Horizons.V1.Websites.CreateWebsiteRequest",
        };
    }
};

pub const ReachArgs = struct {
    segment_uuid: ?[]const u8 = null,
    profile_uuid: ?[]const u8 = null,
};

pub const ReachEndpoint = enum {
    contacts,
    profiles,
    segments,
    segment,
    segment_contacts,
    profile_segment_contacts,

    pub fn label(self: ReachEndpoint) []const u8 {
        return switch (self) {
            .contacts => "reach-contacts",
            .profiles => "reach-profiles",
            .segments => "reach-segments",
            .segment => "reach-segment",
            .segment_contacts => "reach-segment-contacts",
            .profile_segment_contacts => "reach-profile-segment-contacts",
        };
    }

    pub fn parse(value: []const u8) ?ReachEndpoint {
        if (std.mem.eql(u8, value, "reach-contacts")) return .contacts;
        if (std.mem.eql(u8, value, "reach-profiles")) return .profiles;
        if (std.mem.eql(u8, value, "reach-segments")) return .segments;
        if (std.mem.eql(u8, value, "reach-segment")) return .segment;
        if (std.mem.eql(u8, value, "reach-segment-contacts")) return .segment_contacts;
        if (std.mem.eql(u8, value, "reach-profile-segment-contacts")) return .profile_segment_contacts;
        return null;
    }
};

pub const ReachMutationEndpoint = enum {
    delete_contact,
    create_profile_contacts,
    create_segment,

    pub fn parse(value: []const u8) ?ReachMutationEndpoint {
        if (std.mem.eql(u8, value, "delete-contact")) return .delete_contact;
        if (std.mem.eql(u8, value, "create-profile-contacts") or std.mem.eql(u8, value, "create-contacts")) return .create_profile_contacts;
        if (std.mem.eql(u8, value, "create-segment")) return .create_segment;
        return null;
    }

    pub fn commandName(self: ReachMutationEndpoint) []const u8 {
        return switch (self) {
            .delete_contact => "delete-contact",
            .create_profile_contacts => "create-profile-contacts",
            .create_segment => "create-segment",
        };
    }

    pub fn group(self: ReachMutationEndpoint) []const u8 {
        return switch (self) {
            .delete_contact, .create_profile_contacts => "Reach: Contacts",
            .create_segment => "Reach: Segments",
        };
    }

    pub fn method(self: ReachMutationEndpoint) []const u8 {
        return switch (self) {
            .delete_contact => "DELETE",
            .create_profile_contacts, .create_segment => "POST",
        };
    }

    pub fn operationId(self: ReachMutationEndpoint) []const u8 {
        return switch (self) {
            .delete_contact => "reach_deleteAContactV1",
            .create_profile_contacts => "reach_createNewContactsV1",
            .create_segment => "reach_createANewContactSegmentV1",
        };
    }

    pub fn summary(self: ReachMutationEndpoint) []const u8 {
        return switch (self) {
            .delete_contact => "Delete a contact",
            .create_profile_contacts => "Create new contacts",
            .create_segment => "Create a new contact segment",
        };
    }

    pub fn requestBodySchemaRef(self: ReachMutationEndpoint) ?[]const u8 {
        return switch (self) {
            .delete_contact => null,
            .create_profile_contacts => "#/components/schemas/Reach.V1.Contacts.StoreRequest",
            .create_segment => "#/components/schemas/Reach.V1.Contacts.Segments.StoreRequest",
        };
    }

    pub fn requiresContactUuid(self: ReachMutationEndpoint) bool {
        return self == .delete_contact;
    }

    pub fn requiresProfileUuid(self: ReachMutationEndpoint) bool {
        return self == .create_profile_contacts;
    }
};

pub const ReachMutationArgs = struct {
    contact_uuid: ?[]const u8 = null,
    profile_uuid: ?[]const u8 = null,
};

pub fn virtualMachinesUrl(gpa: Allocator, host: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, virtual_machines_path });
}

pub fn virtualMachineDetailsUrl(gpa: Allocator, host: []const u8, vm_id: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}{s}/{s}", .{ host, virtual_machines_path, vm_id });
}

pub fn endpointUrl(gpa: Allocator, host: []const u8, vm_id: []const u8, endpoint: VmEndpoint) ![]u8 {
    if (endpoint == .metrics) return try metricsUrl(gpa, host, vm_id);
    return try std.fmt.allocPrint(gpa, "{s}{s}/{s}/{s}", .{ host, virtual_machines_path, vm_id, endpoint.label() });
}

pub fn endpointPageUrl(gpa: Allocator, host: []const u8, vm_id: []const u8, endpoint: VmEndpoint, page: usize) ![]u8 {
    const base = try endpointUrl(gpa, host, vm_id, endpoint);
    defer gpa.free(base);
    return try pageUrl(gpa, base, page);
}

pub fn actionDetailsUrl(gpa: Allocator, host: []const u8, vm_id: []const u8, action_id: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}{s}/{s}/actions/{s}", .{ host, virtual_machines_path, vm_id, action_id });
}

pub fn vpsMutationPath(gpa: Allocator, endpoint: VpsMutationEndpoint, args: VpsMutationArgs) ![]u8 {
    if (!endpoint.requiresVmId()) return try gpa.dupe(u8, virtual_machines_path);
    const id = args.vm_id orelse return error.MissingVirtualMachineId;
    const suffix = endpoint.suffix() orelse return error.MissingVpsMutationSuffix;
    const escaped_id = try pathEscape(gpa, id);
    defer gpa.free(escaped_id);
    if (endpoint.requiresIpAddressId()) {
        const ip_address_id = args.ip_address_id orelse return error.MissingIpAddressId;
        const escaped_ip_address_id = try pathEscape(gpa, ip_address_id);
        defer gpa.free(escaped_ip_address_id);
        return try std.fmt.allocPrint(gpa, "{s}/{s}/{s}/{s}", .{ virtual_machines_path, escaped_id, suffix, escaped_ip_address_id });
    }
    if (endpoint.requiresBackupId()) {
        const backup_id = args.backup_id orelse return error.MissingBackupId;
        const escaped_backup_id = try pathEscape(gpa, backup_id);
        defer gpa.free(escaped_backup_id);
        return try std.fmt.allocPrint(gpa, "{s}/{s}/{s}/{s}/restore", .{ virtual_machines_path, escaped_id, suffix, escaped_backup_id });
    }
    return try std.fmt.allocPrint(gpa, "{s}/{s}/{s}", .{ virtual_machines_path, escaped_id, suffix });
}

pub fn vpsMutationPlanJson(gpa: Allocator, endpoint: VpsMutationEndpoint, args: VpsMutationArgs) ![]u8 {
    const path = try vpsMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = endpoint.group(),
        .operation = endpoint.commandName(),
        .operation_id = endpoint.operationId(),
        .summary = endpoint.summary(),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = endpoint.requestBodySchemaRef(),
    });
}

pub fn dockerEndpointUrl(gpa: Allocator, host: []const u8, vm_id: []const u8, endpoint: DockerEndpoint, project_name: ?[]const u8) ![]u8 {
    const path = try dockerEndpointPath(gpa, vm_id, endpoint, project_name);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn dockerEndpointPath(gpa: Allocator, vm_id: []const u8, endpoint: DockerEndpoint, project_name: ?[]const u8) ![]u8 {
    if (!endpoint.requiresProject()) return try std.fmt.allocPrint(gpa, "{s}/{s}/docker", .{ virtual_machines_path, vm_id });
    const project = project_name orelse return error.MissingDockerProjectName;
    const escaped_project = try pathEscape(gpa, project);
    defer gpa.free(escaped_project);
    if (endpoint.suffix()) |suffix| {
        return try std.fmt.allocPrint(gpa, "{s}/{s}/docker/{s}/{s}", .{ virtual_machines_path, vm_id, escaped_project, suffix });
    }
    return try std.fmt.allocPrint(gpa, "{s}/{s}/docker/{s}", .{ virtual_machines_path, vm_id, escaped_project });
}

pub fn dockerMutationPath(gpa: Allocator, endpoint: DockerMutationEndpoint, args: DockerMutationArgs) ![]u8 {
    const escaped_vm_id = try pathEscape(gpa, args.vm_id);
    defer gpa.free(escaped_vm_id);
    if (!endpoint.requiresProject()) {
        return try std.fmt.allocPrint(gpa, "{s}/{s}/docker", .{ virtual_machines_path, escaped_vm_id });
    }
    const project_name = args.project_name orelse return error.MissingDockerProjectName;
    const escaped_project_name = try pathEscape(gpa, project_name);
    defer gpa.free(escaped_project_name);
    const suffix = endpoint.suffix() orelse return error.MissingDockerMutationSuffix;
    return try std.fmt.allocPrint(gpa, "{s}/{s}/docker/{s}/{s}", .{ virtual_machines_path, escaped_vm_id, escaped_project_name, suffix });
}

pub fn dockerMutationPlanJson(gpa: Allocator, endpoint: DockerMutationEndpoint, args: DockerMutationArgs) ![]u8 {
    const path = try dockerMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = endpoint.group(),
        .operation = endpoint.commandName(),
        .operation_id = endpoint.operationId(),
        .summary = endpoint.summary(),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = endpoint.requestBodySchemaRef(),
    });
}

pub fn billingEndpointUrl(gpa: Allocator, host: []const u8, endpoint: BillingEndpoint) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, endpoint.path() });
}

pub fn billingMutationPath(gpa: Allocator, endpoint: BillingMutationEndpoint, args: BillingMutationArgs) ![]u8 {
    return switch (endpoint) {
        .set_default_payment_method, .delete_payment_method => blk: {
            const payment_method_id = args.payment_method_id orelse return error.MissingPaymentMethodId;
            const escaped = try pathEscape(gpa, payment_method_id);
            defer gpa.free(escaped);
            break :blk try std.fmt.allocPrint(gpa, "{s}/{s}", .{ billing_payment_methods_path, escaped });
        },
        .enable_auto_renewal, .disable_auto_renewal => blk: {
            const subscription_id = args.subscription_id orelse return error.MissingSubscriptionId;
            const escaped = try pathEscape(gpa, subscription_id);
            defer gpa.free(escaped);
            const action = switch (endpoint) {
                .enable_auto_renewal => "enable",
                .disable_auto_renewal => "disable",
                else => unreachable,
            };
            break :blk try std.fmt.allocPrint(gpa, "{s}/{s}/auto-renewal/{s}", .{ billing_subscriptions_path, escaped, action });
        },
    };
}

pub fn billingMutationPlanJson(gpa: Allocator, endpoint: BillingMutationEndpoint, args: BillingMutationArgs) ![]u8 {
    const path = try billingMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = endpoint.group(),
        .operation = endpoint.commandName(),
        .operation_id = endpoint.operationId(),
        .summary = endpoint.summary(),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = endpoint.requestBodySchemaRef(),
    });
}

pub fn dnsEndpointUrl(gpa: Allocator, host: []const u8, endpoint: DnsEndpoint, domain: []const u8, snapshot_id: ?[]const u8) ![]u8 {
    const path = try dnsEndpointPath(gpa, endpoint, domain, snapshot_id);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn dnsEndpointPath(gpa: Allocator, endpoint: DnsEndpoint, domain: []const u8, snapshot_id: ?[]const u8) ![]u8 {
    const escaped_domain = try pathEscape(gpa, domain);
    defer gpa.free(escaped_domain);
    return switch (endpoint) {
        .zone => try std.fmt.allocPrint(gpa, "{s}/{s}", .{ dns_zones_path, escaped_domain }),
        .snapshots => try std.fmt.allocPrint(gpa, "{s}/{s}", .{ dns_snapshots_path, escaped_domain }),
        .snapshot => blk: {
            const id = snapshot_id orelse return error.MissingDnsSnapshotId;
            const escaped_id = try pathEscape(gpa, id);
            defer gpa.free(escaped_id);
            break :blk try std.fmt.allocPrint(gpa, "{s}/{s}/{s}", .{ dns_snapshots_path, escaped_domain, escaped_id });
        },
    };
}

pub fn dnsMutationPath(gpa: Allocator, endpoint: DnsMutationEndpoint, args: DnsMutationArgs) ![]u8 {
    const escaped_domain = try pathEscape(gpa, args.domain);
    defer gpa.free(escaped_domain);
    return switch (endpoint) {
        .restore_snapshot => blk: {
            const snapshot_id = args.snapshot_id orelse return error.MissingDnsSnapshotId;
            const escaped_snapshot_id = try pathEscape(gpa, snapshot_id);
            defer gpa.free(escaped_snapshot_id);
            break :blk try std.fmt.allocPrint(gpa, "{s}/{s}/{s}/restore", .{ dns_snapshots_path, escaped_domain, escaped_snapshot_id });
        },
        .update_zone, .delete_zone => try std.fmt.allocPrint(gpa, "{s}/{s}", .{ dns_zones_path, escaped_domain }),
        .reset_zone, .validate_zone => {
            const suffix = endpoint.suffix() orelse unreachable;
            return try std.fmt.allocPrint(gpa, "{s}/{s}/{s}", .{ dns_zones_path, escaped_domain, suffix });
        },
    };
}

pub fn dnsMutationPlanJson(gpa: Allocator, endpoint: DnsMutationEndpoint, args: DnsMutationArgs) ![]u8 {
    const path = try dnsMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = endpoint.group(),
        .operation = endpoint.commandName(),
        .operation_id = endpoint.operationId(),
        .summary = endpoint.summary(),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = endpoint.requestBodySchemaRef(),
    });
}

pub fn domainEndpointUrl(gpa: Allocator, host: []const u8, endpoint: DomainEndpoint, path_arg: ?[]const u8, tld: ?[]const u8) ![]u8 {
    const path = try domainEndpointPath(gpa, endpoint, path_arg, tld);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn domainEndpointPath(gpa: Allocator, endpoint: DomainEndpoint, path_arg: ?[]const u8, tld: ?[]const u8) ![]u8 {
    return switch (endpoint) {
        .portfolio => try gpa.dupe(u8, domains_portfolio_path),
        .portfolio_detail => blk: {
            const domain = path_arg orelse return error.MissingDomainName;
            const escaped = try pathEscape(gpa, domain);
            defer gpa.free(escaped);
            break :blk try std.fmt.allocPrint(gpa, "{s}/{s}", .{ domains_portfolio_path, escaped });
        },
        .forwarding => blk: {
            const domain = path_arg orelse return error.MissingDomainName;
            const escaped = try pathEscape(gpa, domain);
            defer gpa.free(escaped);
            break :blk try std.fmt.allocPrint(gpa, "{s}/{s}", .{ domains_forwarding_path, escaped });
        },
        .whois_profiles => blk: {
            const filter = tld orelse return try gpa.dupe(u8, domains_whois_path);
            const escaped = try pathEscape(gpa, filter);
            defer gpa.free(escaped);
            break :blk try std.fmt.allocPrint(gpa, "{s}?tld={s}", .{ domains_whois_path, escaped });
        },
        .whois_profile => blk: {
            const whois_id = path_arg orelse return error.MissingWhoisId;
            const escaped = try pathEscape(gpa, whois_id);
            defer gpa.free(escaped);
            break :blk try std.fmt.allocPrint(gpa, "{s}/{s}", .{ domains_whois_path, escaped });
        },
        .whois_usage => blk: {
            const whois_id = path_arg orelse return error.MissingWhoisId;
            const escaped = try pathEscape(gpa, whois_id);
            defer gpa.free(escaped);
            break :blk try std.fmt.allocPrint(gpa, "{s}/{s}/usage", .{ domains_whois_path, escaped });
        },
    };
}

pub fn domainMutationPath(gpa: Allocator, endpoint: DomainMutationEndpoint, args: DomainMutationArgs) ![]u8 {
    return switch (endpoint) {
        .check_availability => try gpa.dupe(u8, domains_availability_path),
        .create_forwarding => try gpa.dupe(u8, domains_forwarding_path),
        .delete_forwarding => blk: {
            const domain = args.domain orelse return error.MissingDomainName;
            const escaped = try pathEscape(gpa, domain);
            defer gpa.free(escaped);
            break :blk try std.fmt.allocPrint(gpa, "{s}/{s}", .{ domains_forwarding_path, escaped });
        },
        .purchase_domain => try gpa.dupe(u8, domains_portfolio_path),
        .enable_domain_lock, .disable_domain_lock, .update_nameservers, .enable_privacy_protection, .disable_privacy_protection => blk: {
            const domain = args.domain orelse return error.MissingDomainName;
            const escaped = try pathEscape(gpa, domain);
            defer gpa.free(escaped);
            const suffix = switch (endpoint) {
                .enable_domain_lock, .disable_domain_lock => "domain-lock",
                .update_nameservers => "nameservers",
                .enable_privacy_protection, .disable_privacy_protection => "privacy-protection",
                else => unreachable,
            };
            break :blk try std.fmt.allocPrint(gpa, "{s}/{s}/{s}", .{ domains_portfolio_path, escaped, suffix });
        },
        .create_whois_profile => try gpa.dupe(u8, domains_whois_path),
        .delete_whois_profile => blk: {
            const whois_id = args.whois_id orelse return error.MissingWhoisId;
            const escaped = try pathEscape(gpa, whois_id);
            defer gpa.free(escaped);
            break :blk try std.fmt.allocPrint(gpa, "{s}/{s}", .{ domains_whois_path, escaped });
        },
    };
}

pub fn domainMutationPlanJson(gpa: Allocator, endpoint: DomainMutationEndpoint, args: DomainMutationArgs) ![]u8 {
    const path = try domainMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = endpoint.group(),
        .operation = endpoint.commandName(),
        .operation_id = endpoint.operationId(),
        .summary = endpoint.summary(),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = endpoint.requestBodySchemaRef(),
    });
}

pub fn hostingEndpointUrl(gpa: Allocator, host: []const u8, endpoint: HostingEndpoint, args: HostingArgs) ![]u8 {
    const path = try hostingEndpointPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn hostingEndpointPageUrl(gpa: Allocator, host: []const u8, endpoint: HostingEndpoint, args: HostingArgs, page: usize) ![]u8 {
    const base = try hostingEndpointUrl(gpa, host, endpoint, args);
    defer gpa.free(base);
    return try pageUrl(gpa, base, page);
}

pub fn hostingEndpointPath(gpa: Allocator, endpoint: HostingEndpoint, args: HostingArgs) ![]u8 {
    return switch (endpoint) {
        .orders => try gpa.dupe(u8, hosting_orders_path),
        .websites => try gpa.dupe(u8, hosting_websites_path),
        .wordpress => try gpa.dupe(u8, hosting_wordpress_installations_path),
        .datacenters => blk: {
            const order_id = args.order_id orelse return error.MissingHostingOrderId;
            break :blk try appendQueryParam(gpa, hosting_datacenters_path, "order_id", order_id);
        },
        .databases => blk: {
            const username = args.username orelse return error.MissingHostingUsername;
            const escaped_username = try pathEscape(gpa, username);
            defer gpa.free(escaped_username);
            break :blk try std.fmt.allocPrint(gpa, "{s}/{s}/databases", .{ hosting_accounts_path, escaped_username });
        },
        .phpmyadmin_link => blk: {
            const username = args.username orelse return error.MissingHostingUsername;
            const name = args.name orelse return error.MissingHostingDatabaseName;
            const escaped_username = try pathEscape(gpa, username);
            defer gpa.free(escaped_username);
            const escaped_name = try pathEscape(gpa, name);
            defer gpa.free(escaped_name);
            break :blk try std.fmt.allocPrint(gpa, "{s}/{s}/databases/{s}/phpmyadmin-link", .{ hosting_accounts_path, escaped_username, escaped_name });
        },
        .parked_domains, .subdomains, .nodejs_builds => blk: {
            const username = args.username orelse return error.MissingHostingUsername;
            const domain = args.domain orelse return error.MissingDomainName;
            const escaped_username = try pathEscape(gpa, username);
            defer gpa.free(escaped_username);
            const escaped_domain = try pathEscape(gpa, domain);
            defer gpa.free(escaped_domain);
            const suffix = switch (endpoint) {
                .parked_domains => "parked-domains",
                .subdomains => "subdomains",
                .nodejs_builds => "nodejs/builds",
                else => unreachable,
            };
            break :blk try std.fmt.allocPrint(gpa, "{s}/{s}/websites/{s}/{s}", .{ hosting_accounts_path, escaped_username, escaped_domain, suffix });
        },
        .nodejs_logs => blk: {
            const username = args.username orelse return error.MissingHostingUsername;
            const domain = args.domain orelse return error.MissingDomainName;
            const uuid = args.uuid orelse return error.MissingHostingBuildUuid;
            const escaped_username = try pathEscape(gpa, username);
            defer gpa.free(escaped_username);
            const escaped_domain = try pathEscape(gpa, domain);
            defer gpa.free(escaped_domain);
            const escaped_uuid = try pathEscape(gpa, uuid);
            defer gpa.free(escaped_uuid);
            const base_path = try std.fmt.allocPrint(gpa, "{s}/{s}/websites/{s}/nodejs/builds/{s}/logs", .{ hosting_accounts_path, escaped_username, escaped_domain, escaped_uuid });
            defer gpa.free(base_path);
            if (args.from_line) |line| break :blk try appendQueryParam(gpa, base_path, "from_line", line);
            break :blk try gpa.dupe(u8, base_path);
        },
    };
}

pub fn hostingMutationPath(gpa: Allocator, endpoint: HostingMutationEndpoint, args: HostingMutationArgs) ![]u8 {
    return switch (endpoint) {
        .create_website => try gpa.dupe(u8, hosting_websites_path),
        .install_wordpress => blk: {
            const username = args.username orelse return error.MissingHostingUsername;
            const escaped_username = try pathEscape(gpa, username);
            defer gpa.free(escaped_username);
            break :blk try std.fmt.allocPrint(gpa, "{s}/{s}/wordpress/installations", .{ hosting_accounts_path, escaped_username });
        },
        .create_database => blk: {
            const username = args.username orelse return error.MissingHostingUsername;
            const escaped_username = try pathEscape(gpa, username);
            defer gpa.free(escaped_username);
            break :blk try std.fmt.allocPrint(gpa, "{s}/{s}/databases", .{ hosting_accounts_path, escaped_username });
        },
        .delete_database, .change_database_password, .repair_database => blk: {
            const username = args.username orelse return error.MissingHostingUsername;
            const database_name = args.database_name orelse return error.MissingHostingDatabaseName;
            const escaped_username = try pathEscape(gpa, username);
            defer gpa.free(escaped_username);
            const escaped_name = try pathEscape(gpa, database_name);
            defer gpa.free(escaped_name);
            const suffix: ?[]const u8 = switch (endpoint) {
                .change_database_password => "change-password",
                .repair_database => "repair",
                .delete_database => null,
                else => unreachable,
            };
            if (suffix) |value| {
                break :blk try std.fmt.allocPrint(gpa, "{s}/{s}/databases/{s}/{s}", .{ hosting_accounts_path, escaped_username, escaped_name, value });
            }
            break :blk try std.fmt.allocPrint(gpa, "{s}/{s}/databases/{s}", .{ hosting_accounts_path, escaped_username, escaped_name });
        },
        .generate_free_subdomain => try std.fmt.allocPrint(gpa, "{s}/free-subdomains", .{hosting_domains_path}),
        .verify_domain_ownership => try std.fmt.allocPrint(gpa, "{s}/verify-ownership", .{hosting_domains_path}),
        .create_parked_domain, .delete_parked_domain, .create_subdomain, .delete_subdomain => blk: {
            const username = args.username orelse return error.MissingHostingUsername;
            const domain = args.domain orelse return error.MissingDomainName;
            const escaped_username = try pathEscape(gpa, username);
            defer gpa.free(escaped_username);
            const escaped_domain = try pathEscape(gpa, domain);
            defer gpa.free(escaped_domain);
            const collection = switch (endpoint) {
                .create_parked_domain, .delete_parked_domain => "parked-domains",
                .create_subdomain, .delete_subdomain => "subdomains",
                else => unreachable,
            };
            if (endpoint == .delete_parked_domain) {
                const parked_domain = args.parked_domain orelse return error.MissingHostingParkedDomain;
                const escaped_parked_domain = try pathEscape(gpa, parked_domain);
                defer gpa.free(escaped_parked_domain);
                break :blk try std.fmt.allocPrint(gpa, "{s}/{s}/websites/{s}/{s}/{s}", .{ hosting_accounts_path, escaped_username, escaped_domain, collection, escaped_parked_domain });
            }
            if (endpoint == .delete_subdomain) {
                const subdomain = args.subdomain orelse return error.MissingHostingSubdomain;
                const escaped_subdomain = try pathEscape(gpa, subdomain);
                defer gpa.free(escaped_subdomain);
                break :blk try std.fmt.allocPrint(gpa, "{s}/{s}/websites/{s}/{s}/{s}", .{ hosting_accounts_path, escaped_username, escaped_domain, collection, escaped_subdomain });
            }
            break :blk try std.fmt.allocPrint(gpa, "{s}/{s}/websites/{s}/{s}", .{ hosting_accounts_path, escaped_username, escaped_domain, collection });
        },
        .create_nodejs_build_from_archive => blk: {
            const username = args.username orelse return error.MissingHostingUsername;
            const domain = args.domain orelse return error.MissingDomainName;
            const escaped_username = try pathEscape(gpa, username);
            defer gpa.free(escaped_username);
            const escaped_domain = try pathEscape(gpa, domain);
            defer gpa.free(escaped_domain);
            break :blk try std.fmt.allocPrint(gpa, "{s}/{s}/websites/{s}/nodejs/builds/from-archive", .{ hosting_accounts_path, escaped_username, escaped_domain });
        },
    };
}

pub fn hostingMutationPlanJson(gpa: Allocator, endpoint: HostingMutationEndpoint, args: HostingMutationArgs) ![]u8 {
    const path = try hostingMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = endpoint.group(),
        .operation = endpoint.commandName(),
        .operation_id = endpoint.operationId(),
        .summary = endpoint.summary(),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = endpoint.requestBodySchemaRef(),
    });
}

pub fn ecommerceEndpointUrl(gpa: Allocator, host: []const u8, endpoint: EcommerceEndpoint) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, endpoint.path() });
}

pub fn ecommerceEndpointPageUrl(gpa: Allocator, host: []const u8, endpoint: EcommerceEndpoint, page: usize) ![]u8 {
    const base = try ecommerceEndpointUrl(gpa, host, endpoint);
    defer gpa.free(base);
    return try pageUrl(gpa, base, page);
}

pub fn ecommerceMutationPath(gpa: Allocator, endpoint: EcommerceMutationEndpoint) ![]u8 {
    return switch (endpoint) {
        .create_store => try gpa.dupe(u8, ecommerce_stores_path),
    };
}

pub fn ecommerceMutationPlanJson(gpa: Allocator, endpoint: EcommerceMutationEndpoint) ![]u8 {
    const path = try ecommerceMutationPath(gpa, endpoint);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = endpoint.group(),
        .operation = endpoint.commandName(),
        .operation_id = endpoint.operationId(),
        .summary = endpoint.summary(),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = endpoint.requestBodySchemaRef(),
    });
}

pub fn horizonsEndpointUrl(gpa: Allocator, host: []const u8, endpoint: HorizonsEndpoint, website_id: []const u8) ![]u8 {
    const path = try horizonsEndpointPath(gpa, endpoint, website_id);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn horizonsEndpointPath(gpa: Allocator, endpoint: HorizonsEndpoint, website_id: []const u8) ![]u8 {
    const escaped = try pathEscape(gpa, website_id);
    defer gpa.free(escaped);
    return switch (endpoint) {
        .website => try std.fmt.allocPrint(gpa, "{s}/{s}", .{ horizons_websites_path, escaped }),
    };
}

pub fn horizonsMutationPath(gpa: Allocator, endpoint: HorizonsMutationEndpoint) ![]u8 {
    return switch (endpoint) {
        .create_website => try gpa.dupe(u8, horizons_websites_path),
    };
}

pub fn horizonsMutationPlanJson(gpa: Allocator, endpoint: HorizonsMutationEndpoint) ![]u8 {
    const path = try horizonsMutationPath(gpa, endpoint);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = endpoint.group(),
        .operation = endpoint.commandName(),
        .operation_id = endpoint.operationId(),
        .summary = endpoint.summary(),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = endpoint.requestBodySchemaRef(),
    });
}

pub fn reachEndpointUrl(gpa: Allocator, host: []const u8, endpoint: ReachEndpoint, args: ReachArgs) ![]u8 {
    const path = try reachEndpointPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, path });
}

pub fn reachEndpointPageUrl(gpa: Allocator, host: []const u8, endpoint: ReachEndpoint, args: ReachArgs, page: usize) ![]u8 {
    const base = try reachEndpointUrl(gpa, host, endpoint, args);
    defer gpa.free(base);
    return try pageUrl(gpa, base, page);
}

pub fn reachEndpointPath(gpa: Allocator, endpoint: ReachEndpoint, args: ReachArgs) ![]u8 {
    return switch (endpoint) {
        .contacts => try gpa.dupe(u8, reach_contacts_path),
        .profiles => try gpa.dupe(u8, reach_profiles_path),
        .segments => try gpa.dupe(u8, reach_segments_path),
        .segment => blk: {
            const segment_uuid = args.segment_uuid orelse return error.MissingReachSegmentUuid;
            const escaped_segment = try pathEscape(gpa, segment_uuid);
            defer gpa.free(escaped_segment);
            break :blk try std.fmt.allocPrint(gpa, "{s}/{s}", .{ reach_segments_path, escaped_segment });
        },
        .segment_contacts => blk: {
            const segment_uuid = args.segment_uuid orelse return error.MissingReachSegmentUuid;
            const escaped_segment = try pathEscape(gpa, segment_uuid);
            defer gpa.free(escaped_segment);
            break :blk try std.fmt.allocPrint(gpa, "{s}/{s}/contacts", .{ reach_segments_path, escaped_segment });
        },
        .profile_segment_contacts => blk: {
            const profile_uuid = args.profile_uuid orelse return error.MissingReachProfileUuid;
            const segment_uuid = args.segment_uuid orelse return error.MissingReachSegmentUuid;
            const escaped_profile = try pathEscape(gpa, profile_uuid);
            defer gpa.free(escaped_profile);
            const escaped_segment = try pathEscape(gpa, segment_uuid);
            defer gpa.free(escaped_segment);
            break :blk try std.fmt.allocPrint(gpa, "{s}/{s}/segmentation/segments/{s}/contacts", .{ reach_profiles_path, escaped_profile, escaped_segment });
        },
    };
}

pub fn reachMutationPath(gpa: Allocator, endpoint: ReachMutationEndpoint, args: ReachMutationArgs) ![]u8 {
    return switch (endpoint) {
        .delete_contact => blk: {
            const contact_uuid = args.contact_uuid orelse return error.MissingReachContactUuid;
            const escaped_contact = try pathEscape(gpa, contact_uuid);
            defer gpa.free(escaped_contact);
            break :blk try std.fmt.allocPrint(gpa, "{s}/{s}", .{ reach_contacts_path, escaped_contact });
        },
        .create_profile_contacts => blk: {
            const profile_uuid = args.profile_uuid orelse return error.MissingReachProfileUuid;
            const escaped_profile = try pathEscape(gpa, profile_uuid);
            defer gpa.free(escaped_profile);
            break :blk try std.fmt.allocPrint(gpa, "{s}/{s}/contacts", .{ reach_profiles_path, escaped_profile });
        },
        .create_segment => try gpa.dupe(u8, reach_segments_path),
    };
}

pub fn reachMutationPlanJson(gpa: Allocator, endpoint: ReachMutationEndpoint, args: ReachMutationArgs) ![]u8 {
    const path = try reachMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = endpoint.group(),
        .operation = endpoint.commandName(),
        .operation_id = endpoint.operationId(),
        .summary = endpoint.summary(),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = endpoint.requestBodySchemaRef(),
    });
}

pub fn vpsInventoryUrl(gpa: Allocator, host: []const u8, endpoint: VpsInventoryEndpoint) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}{s}", .{ host, endpoint.path() });
}

pub fn vpsInventoryPageUrl(gpa: Allocator, host: []const u8, endpoint: VpsInventoryEndpoint, page: usize) ![]u8 {
    const base = try vpsInventoryUrl(gpa, host, endpoint);
    defer gpa.free(base);
    return try pageUrl(gpa, base, page);
}

pub fn vpsInventoryDetailUrl(gpa: Allocator, host: []const u8, endpoint: VpsInventoryDetailEndpoint, id: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}{s}/{s}", .{ host, endpoint.pathPrefix(), id });
}

pub fn vpsInventoryDetailPath(gpa: Allocator, endpoint: VpsInventoryDetailEndpoint, id: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ endpoint.pathPrefix(), id });
}

pub fn vpsResourceMutationPath(gpa: Allocator, endpoint: VpsResourceMutationEndpoint, args: VpsResourceMutationArgs) ![]u8 {
    return switch (endpoint) {
        .create_public_key => try gpa.dupe(u8, public_keys_path),
        .delete_public_key => blk: {
            const public_key_id = args.public_key_id orelse return error.MissingPublicKeyId;
            const escaped = try pathEscape(gpa, public_key_id);
            defer gpa.free(escaped);
            break :blk try std.fmt.allocPrint(gpa, "{s}/{s}", .{ public_keys_path, escaped });
        },
        .attach_public_key => blk: {
            const vm_id = args.vm_id orelse return error.MissingVirtualMachineId;
            const escaped = try pathEscape(gpa, vm_id);
            defer gpa.free(escaped);
            break :blk try std.fmt.allocPrint(gpa, "{s}/attach/{s}", .{ public_keys_path, escaped });
        },
        .create_post_install_script => try gpa.dupe(u8, post_install_scripts_path),
        .update_post_install_script, .delete_post_install_script => blk: {
            const post_install_script_id = args.post_install_script_id orelse return error.MissingPostInstallScriptId;
            const escaped = try pathEscape(gpa, post_install_script_id);
            defer gpa.free(escaped);
            break :blk try std.fmt.allocPrint(gpa, "{s}/{s}", .{ post_install_scripts_path, escaped });
        },
    };
}

pub fn vpsResourceMutationPlanJson(gpa: Allocator, endpoint: VpsResourceMutationEndpoint, args: VpsResourceMutationArgs) ![]u8 {
    const path = try vpsResourceMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = endpoint.group(),
        .operation = endpoint.commandName(),
        .operation_id = endpoint.operationId(),
        .summary = endpoint.summary(),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = endpoint.requestBodySchemaRef(),
    });
}

pub fn firewallMutationPath(gpa: Allocator, endpoint: FirewallMutationEndpoint, args: FirewallMutationArgs) ![]u8 {
    if (!endpoint.requiresFirewallId()) return try gpa.dupe(u8, firewall_path);
    const firewall_id = args.firewall_id orelse return error.MissingFirewallId;
    const escaped_firewall_id = try pathEscape(gpa, firewall_id);
    defer gpa.free(escaped_firewall_id);
    if (endpoint.requiresVmId()) {
        const vm_id = args.vm_id orelse return error.MissingVirtualMachineId;
        const escaped_vm_id = try pathEscape(gpa, vm_id);
        defer gpa.free(escaped_vm_id);
        const action = switch (endpoint) {
            .activate => "activate",
            .deactivate => "deactivate",
            .sync => "sync",
            else => unreachable,
        };
        return try std.fmt.allocPrint(gpa, "{s}/{s}/{s}/{s}", .{ firewall_path, escaped_firewall_id, action, escaped_vm_id });
    }
    if (endpoint.requiresRuleId()) {
        const rule_id = args.rule_id orelse return error.MissingFirewallRuleId;
        const escaped_rule_id = try pathEscape(gpa, rule_id);
        defer gpa.free(escaped_rule_id);
        return try std.fmt.allocPrint(gpa, "{s}/{s}/rules/{s}", .{ firewall_path, escaped_firewall_id, escaped_rule_id });
    }
    return switch (endpoint) {
        .create_rule => try std.fmt.allocPrint(gpa, "{s}/{s}/rules", .{ firewall_path, escaped_firewall_id }),
        .delete => try std.fmt.allocPrint(gpa, "{s}/{s}", .{ firewall_path, escaped_firewall_id }),
        else => unreachable,
    };
}

pub fn firewallMutationPlanJson(gpa: Allocator, endpoint: FirewallMutationEndpoint, args: FirewallMutationArgs) ![]u8 {
    const path = try firewallMutationPath(gpa, endpoint, args);
    defer gpa.free(path);
    return try dryRunPlanJson(gpa, .{
        .group = endpoint.group(),
        .operation = endpoint.commandName(),
        .operation_id = endpoint.operationId(),
        .summary = endpoint.summary(),
        .method = endpoint.method(),
        .path = path,
        .request_body_schema = endpoint.requestBodySchemaRef(),
    });
}

pub fn pageUrl(gpa: Allocator, base: []const u8, page: usize) ![]u8 {
    if (page <= 1) return try gpa.dupe(u8, base);
    const sep: []const u8 = if (std.mem.indexOfScalar(u8, base, '?') == null) "?" else "&";
    return try std.fmt.allocPrint(gpa, "{s}{s}page={d}", .{ base, sep, page });
}

fn dryRunPlanJson(gpa: Allocator, plan: DryRunPlan) ![]u8 {
    return try typed_routes.dryRunPlanJson(gpa, "hostinger", "No Hostinger API request is sent. This is a typed dry-run plan for a live mutation route.", plan);
}

pub fn metricsUrl(gpa: Allocator, host: []const u8, vm_id: []const u8) ![]u8 {
    const now = try core_time.currentEpochSeconds();
    return try metricsUrlAt(gpa, host, vm_id, now);
}

pub fn metricsUrlAt(gpa: Allocator, host: []const u8, vm_id: []const u8, now: u64) ![]u8 {
    const day: u64 = 24 * 60 * 60;
    const from = if (now > day) now - day else 0;
    var from_buf: [17]u8 = undefined;
    var to_buf: [17]u8 = undefined;
    const date_from = try core_time.formatUtcMinute(&from_buf, from);
    const date_to = try core_time.formatUtcMinute(&to_buf, now);
    return try std.fmt.allocPrint(gpa, "{s}{s}/{s}/metrics?date_from={s}&date_to={s}", .{ host, virtual_machines_path, vm_id, date_from, date_to });
}

test "vm endpoint labels match official path segments used by the POC" {
    try std.testing.expectEqualStrings("metrics", VmEndpoint.metrics.label());
    try std.testing.expectEqualStrings("actions", VmEndpoint.actions.label());
    try std.testing.expectEqualStrings("public-keys", VmEndpoint.public_keys.label());
    try std.testing.expectEqualStrings("backups", VmEndpoint.backups.label());
    try std.testing.expectEqualStrings("snapshot", VmEndpoint.snapshot.label());
    try std.testing.expectEqualStrings("monarx", VmEndpoint.monarx.label());
    try std.testing.expectEqualStrings("docker", VmEndpoint.docker.label());
    try std.testing.expectEqual(VmEndpoint.public_keys, VmEndpoint.parse("public-keys").?);
    try std.testing.expect(VmEndpoint.parse("recreate") == null);
}

test "vps mutation endpoints map to official operation metadata" {
    try std.testing.expectEqual(VpsMutationEndpoint.restart, VpsMutationEndpoint.parse("restart").?);
    try std.testing.expectEqual(VpsMutationEndpoint.start_recovery, VpsMutationEndpoint.parse("start-recovery").?);
    try std.testing.expectEqual(VpsMutationEndpoint.create_ptr, VpsMutationEndpoint.parse("create-ptr").?);
    try std.testing.expectEqual(VpsMutationEndpoint.restore_backup, VpsMutationEndpoint.parse("restore-backup").?);
    try std.testing.expectEqual(VpsMutationEndpoint.create_snapshot, VpsMutationEndpoint.parse("create-snapshot").?);
    try std.testing.expectEqual(VpsMutationEndpoint.restore_snapshot, VpsMutationEndpoint.parse("restore-snapshot").?);
    try std.testing.expectEqual(VpsMutationEndpoint.install_monarx, VpsMutationEndpoint.parse("install-malware-scanner").?);
    try std.testing.expectEqual(VpsMutationEndpoint.uninstall_monarx, VpsMutationEndpoint.parse("uninstall-monarx").?);
    try std.testing.expectEqualStrings("POST", VpsMutationEndpoint.restart.method());
    try std.testing.expectEqualStrings("DELETE", VpsMutationEndpoint.delete_snapshot.method());
    try std.testing.expectEqualStrings("VPS_restartVirtualMachineV1", VpsMutationEndpoint.restart.operationId());
    try std.testing.expect(VpsMutationEndpoint.restart.requestBodySchemaRef() == null);
    try std.testing.expectEqualStrings("VPS: Recovery", VpsMutationEndpoint.start_recovery.group());
    try std.testing.expectEqualStrings("VPS_startRecoveryModeV1", VpsMutationEndpoint.start_recovery.operationId());
    try std.testing.expectEqualStrings("#/components/schemas/VPS.V1.VirtualMachine.Recovery.StartRequest", VpsMutationEndpoint.start_recovery.requestBodySchemaRef().?);
    try std.testing.expectEqualStrings("VPS: PTR records", VpsMutationEndpoint.create_ptr.group());
    try std.testing.expectEqualStrings("VPS_createPTRRecordV1", VpsMutationEndpoint.create_ptr.operationId());
    try std.testing.expectEqualStrings("#/components/schemas/VPS.V1.VirtualMachine.PTR.StoreRequest", VpsMutationEndpoint.create_ptr.requestBodySchemaRef().?);
    try std.testing.expectEqualStrings("#/components/schemas/VPS.V1.VirtualMachine.HostnameUpdateRequest", VpsMutationEndpoint.set_hostname.requestBodySchemaRef().?);
    try std.testing.expectEqualStrings("VPS: Backups", VpsMutationEndpoint.restore_backup.group());
    try std.testing.expectEqualStrings("VPS_restoreBackupV1", VpsMutationEndpoint.restore_backup.operationId());
    try std.testing.expect(VpsMutationEndpoint.restore_backup.requestBodySchemaRef() == null);
    try std.testing.expectEqualStrings("VPS: Snapshots", VpsMutationEndpoint.restore_snapshot.group());
    try std.testing.expectEqualStrings("VPS_restoreSnapshotV1", VpsMutationEndpoint.restore_snapshot.operationId());
    try std.testing.expectEqualStrings("VPS: Malware scanner", VpsMutationEndpoint.install_monarx.group());
    try std.testing.expectEqualStrings("VPS_installMonarxV1", VpsMutationEndpoint.install_monarx.operationId());
    try std.testing.expect(VpsMutationEndpoint.purchase.requiresVmId() == false);
    try std.testing.expect(VpsMutationEndpoint.stop.requiresVmId());
    try std.testing.expect(VpsMutationEndpoint.create_ptr.requiresIpAddressId());
    try std.testing.expect(VpsMutationEndpoint.restore_backup.requiresBackupId());
}

test "builds Hostinger VPS mutation dry-run plan JSON" {
    const allocator = std.testing.allocator;
    const plan = try vpsMutationPlanJson(allocator, .restart, .{ .vm_id = "vm 1" });
    defer allocator.free(plan);

    try std.testing.expect(std.mem.indexOf(u8, plan, "\"method\":\"POST\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "/api/vps/v1/virtual-machines/vm%201/restart") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"operation_id\":\"VPS_restartVirtualMachineV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"will_execute\":false") != null);

    const ptr = try vpsMutationPlanJson(allocator, .create_ptr, .{ .vm_id = "vm 1", .ip_address_id = "ip/1" });
    defer allocator.free(ptr);
    try std.testing.expect(std.mem.indexOf(u8, ptr, "\"group\":\"VPS: PTR records\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, ptr, "/api/vps/v1/virtual-machines/vm%201/ptr/ip%2F1") != null);
    try std.testing.expect(std.mem.indexOf(u8, ptr, "\"operation_id\":\"VPS_createPTRRecordV1\"") != null);

    const backup = try vpsMutationPlanJson(allocator, .restore_backup, .{ .vm_id = "vm 1", .backup_id = "backup/1" });
    defer allocator.free(backup);
    try std.testing.expect(std.mem.indexOf(u8, backup, "\"group\":\"VPS: Backups\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, backup, "/api/vps/v1/virtual-machines/vm%201/backups/backup%2F1/restore") != null);
    try std.testing.expect(std.mem.indexOf(u8, backup, "\"request_body_schema\":null") != null);

    const snapshot = try vpsMutationPlanJson(allocator, .restore_snapshot, .{ .vm_id = "vm 1" });
    defer allocator.free(snapshot);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "\"group\":\"VPS: Snapshots\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "/api/vps/v1/virtual-machines/vm%201/snapshot/restore") != null);

    const monarx = try vpsMutationPlanJson(allocator, .install_monarx, .{ .vm_id = "vm 1" });
    defer allocator.free(monarx);
    try std.testing.expect(std.mem.indexOf(u8, monarx, "\"group\":\"VPS: Malware scanner\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, monarx, "\"operation_id\":\"VPS_installMonarxV1\"") != null);
}

test "vps inventory endpoint labels match official path segments used by the POC" {
    try std.testing.expectEqualStrings("data-centers", VpsInventoryEndpoint.data_centers.label());
    try std.testing.expectEqualStrings("firewalls", VpsInventoryEndpoint.firewalls.label());
    try std.testing.expectEqualStrings("public-keys-global", VpsInventoryEndpoint.public_keys.label());
    try std.testing.expectEqualStrings("templates", VpsInventoryEndpoint.templates.label());
    try std.testing.expectEqualStrings("post-install-scripts", VpsInventoryEndpoint.post_install_scripts.label());
    try std.testing.expectEqual(VpsInventoryEndpoint.firewalls, VpsInventoryEndpoint.parse("firewall").?);
    try std.testing.expectEqual(VpsInventoryEndpoint.public_keys, VpsInventoryEndpoint.parse("public-keys").?);
    try std.testing.expect(VpsInventoryEndpoint.parse("orders") == null);
}

test "vps inventory detail endpoint labels match official path segments used by the POC" {
    try std.testing.expectEqualStrings("firewall-detail", VpsInventoryDetailEndpoint.firewall.label());
    try std.testing.expectEqualStrings("template-detail", VpsInventoryDetailEndpoint.template.label());
    try std.testing.expectEqualStrings("post-install-script-detail", VpsInventoryDetailEndpoint.post_install_script.label());
    try std.testing.expectEqual(VpsInventoryDetailEndpoint.firewall, VpsInventoryDetailEndpoint.parse("firewall").?);
    try std.testing.expectEqual(VpsInventoryDetailEndpoint.template, VpsInventoryDetailEndpoint.parse("template").?);
    try std.testing.expectEqual(VpsInventoryDetailEndpoint.post_install_script, VpsInventoryDetailEndpoint.parse("post-install").?);
    try std.testing.expect(VpsInventoryDetailEndpoint.parse("public-key") == null);
}

test "vps resource mutation endpoints map to official operation metadata" {
    try std.testing.expectEqual(VpsResourceMutationEndpoint.create_public_key, VpsResourceMutationEndpoint.parse("create-public-key").?);
    try std.testing.expectEqual(VpsResourceMutationEndpoint.delete_public_key, VpsResourceMutationEndpoint.parseScoped("public-key", "delete").?);
    try std.testing.expectEqual(VpsResourceMutationEndpoint.attach_public_key, VpsResourceMutationEndpoint.parseScoped("public-keys", "attach").?);
    try std.testing.expectEqual(VpsResourceMutationEndpoint.create_post_install_script, VpsResourceMutationEndpoint.parseScoped("post-install-script", "create").?);
    try std.testing.expectEqual(VpsResourceMutationEndpoint.update_post_install_script, VpsResourceMutationEndpoint.parse("update-post-install").?);
    try std.testing.expectEqual(VpsResourceMutationEndpoint.delete_post_install_script, VpsResourceMutationEndpoint.parseScoped("post-install", "delete").?);
    try std.testing.expectEqualStrings("VPS: Public Keys", VpsResourceMutationEndpoint.create_public_key.group());
    try std.testing.expectEqualStrings("VPS: Post-install scripts", VpsResourceMutationEndpoint.update_post_install_script.group());
    try std.testing.expectEqualStrings("POST", VpsResourceMutationEndpoint.create_public_key.method());
    try std.testing.expectEqualStrings("PUT", VpsResourceMutationEndpoint.update_post_install_script.method());
    try std.testing.expectEqualStrings("DELETE", VpsResourceMutationEndpoint.delete_post_install_script.method());
    try std.testing.expectEqualStrings("VPS_createPublicKeyV1", VpsResourceMutationEndpoint.create_public_key.operationId());
    try std.testing.expectEqualStrings("VPS_attachPublicKeyV1", VpsResourceMutationEndpoint.attach_public_key.operationId());
    try std.testing.expectEqualStrings("VPS_updatePostInstallScriptV1", VpsResourceMutationEndpoint.update_post_install_script.operationId());
    try std.testing.expectEqualStrings("#/components/schemas/VPS.V1.PublicKey.StoreRequest", VpsResourceMutationEndpoint.create_public_key.requestBodySchemaRef().?);
    try std.testing.expectEqualStrings("#/components/schemas/VPS.V1.PublicKey.AttachRequest", VpsResourceMutationEndpoint.attach_public_key.requestBodySchemaRef().?);
    try std.testing.expectEqualStrings("#/components/schemas/VPS.V1.PostInstallScript.StoreRequest", VpsResourceMutationEndpoint.update_post_install_script.requestBodySchemaRef().?);
    try std.testing.expect(VpsResourceMutationEndpoint.delete_public_key.requestBodySchemaRef() == null);
    try std.testing.expect(VpsResourceMutationEndpoint.delete_public_key.requiresPublicKeyId());
    try std.testing.expect(VpsResourceMutationEndpoint.attach_public_key.requiresVmId());
    try std.testing.expect(VpsResourceMutationEndpoint.update_post_install_script.requiresPostInstallScriptId());
}

test "builds Hostinger VPS resource mutation dry-run plan JSON" {
    const allocator = std.testing.allocator;
    const create_key = try vpsResourceMutationPlanJson(allocator, .create_public_key, .{});
    defer allocator.free(create_key);
    try std.testing.expect(std.mem.indexOf(u8, create_key, "\"group\":\"VPS: Public Keys\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create_key, "\"operation_id\":\"VPS_createPublicKeyV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create_key, "\"path\":\"/api/vps/v1/public-keys\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create_key, "\"request_body_schema\":\"#/components/schemas/VPS.V1.PublicKey.StoreRequest\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create_key, "\"will_execute\":false") != null);

    const attach_key = try vpsResourceMutationPlanJson(allocator, .attach_public_key, .{ .vm_id = "vm 1" });
    defer allocator.free(attach_key);
    try std.testing.expect(std.mem.indexOf(u8, attach_key, "/api/vps/v1/public-keys/attach/vm%201") != null);
    try std.testing.expect(std.mem.indexOf(u8, attach_key, "\"request_body_schema\":\"#/components/schemas/VPS.V1.PublicKey.AttachRequest\"") != null);

    const delete_key = try vpsResourceMutationPlanJson(allocator, .delete_public_key, .{ .public_key_id = "key/1" });
    defer allocator.free(delete_key);
    try std.testing.expect(std.mem.indexOf(u8, delete_key, "\"method\":\"DELETE\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, delete_key, "/api/vps/v1/public-keys/key%2F1") != null);
    try std.testing.expect(std.mem.indexOf(u8, delete_key, "\"request_body_schema\":null") != null);

    const update_script = try vpsResourceMutationPlanJson(allocator, .update_post_install_script, .{ .post_install_script_id = "script/1" });
    defer allocator.free(update_script);
    try std.testing.expect(std.mem.indexOf(u8, update_script, "\"group\":\"VPS: Post-install scripts\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, update_script, "\"method\":\"PUT\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, update_script, "/api/vps/v1/post-install-scripts/script%2F1") != null);
    try std.testing.expect(std.mem.indexOf(u8, update_script, "\"operation_id\":\"VPS_updatePostInstallScriptV1\"") != null);
}

test "firewall mutation endpoints map to official operation metadata" {
    try std.testing.expectEqual(FirewallMutationEndpoint.create, FirewallMutationEndpoint.parse("create-firewall").?);
    try std.testing.expectEqual(FirewallMutationEndpoint.delete, FirewallMutationEndpoint.parse("delete").?);
    try std.testing.expectEqual(FirewallMutationEndpoint.activate, FirewallMutationEndpoint.parse("activate").?);
    try std.testing.expectEqual(FirewallMutationEndpoint.deactivate, FirewallMutationEndpoint.parse("deactivate").?);
    try std.testing.expectEqual(FirewallMutationEndpoint.sync, FirewallMutationEndpoint.parse("sync").?);
    try std.testing.expectEqual(FirewallMutationEndpoint.create_rule, FirewallMutationEndpoint.parse("create-rule").?);
    try std.testing.expectEqual(FirewallMutationEndpoint.update_rule, FirewallMutationEndpoint.parse("update-rule").?);
    try std.testing.expectEqual(FirewallMutationEndpoint.delete_rule, FirewallMutationEndpoint.parse("delete-rule").?);
    try std.testing.expectEqualStrings("VPS: Firewall", FirewallMutationEndpoint.create.group());
    try std.testing.expectEqualStrings("POST", FirewallMutationEndpoint.create.method());
    try std.testing.expectEqualStrings("PUT", FirewallMutationEndpoint.update_rule.method());
    try std.testing.expectEqualStrings("DELETE", FirewallMutationEndpoint.delete_rule.method());
    try std.testing.expectEqualStrings("VPS_createNewFirewallV1", FirewallMutationEndpoint.create.operationId());
    try std.testing.expectEqualStrings("VPS_activateFirewallV1", FirewallMutationEndpoint.activate.operationId());
    try std.testing.expectEqualStrings("VPS_updateFirewallRuleV1", FirewallMutationEndpoint.update_rule.operationId());
    try std.testing.expectEqualStrings("#/components/schemas/VPS.V1.Firewall.StoreRequest", FirewallMutationEndpoint.create.requestBodySchemaRef().?);
    try std.testing.expectEqualStrings("#/components/schemas/VPS.V1.Firewall.Rules.StoreRequest", FirewallMutationEndpoint.create_rule.requestBodySchemaRef().?);
    try std.testing.expect(FirewallMutationEndpoint.delete.requestBodySchemaRef() == null);
    try std.testing.expect(!FirewallMutationEndpoint.create.requiresFirewallId());
    try std.testing.expect(FirewallMutationEndpoint.delete.requiresFirewallId());
    try std.testing.expect(FirewallMutationEndpoint.activate.requiresVmId());
    try std.testing.expect(FirewallMutationEndpoint.update_rule.requiresRuleId());
}

test "builds Hostinger firewall mutation dry-run plan JSON" {
    const allocator = std.testing.allocator;
    const create = try firewallMutationPlanJson(allocator, .create, .{});
    defer allocator.free(create);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"group\":\"VPS: Firewall\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"operation_id\":\"VPS_createNewFirewallV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"path\":\"/api/vps/v1/firewall\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"request_body_schema\":\"#/components/schemas/VPS.V1.Firewall.StoreRequest\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"will_execute\":false") != null);

    const activate = try firewallMutationPlanJson(allocator, .activate, .{ .firewall_id = "fw/1", .vm_id = "vm 1" });
    defer allocator.free(activate);
    try std.testing.expect(std.mem.indexOf(u8, activate, "/api/vps/v1/firewall/fw%2F1/activate/vm%201") != null);
    try std.testing.expect(std.mem.indexOf(u8, activate, "\"request_body_schema\":null") != null);

    const update_rule = try firewallMutationPlanJson(allocator, .update_rule, .{ .firewall_id = "fw/1", .rule_id = "rule/1" });
    defer allocator.free(update_rule);
    try std.testing.expect(std.mem.indexOf(u8, update_rule, "\"method\":\"PUT\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, update_rule, "/api/vps/v1/firewall/fw%2F1/rules/rule%2F1") != null);
    try std.testing.expect(std.mem.indexOf(u8, update_rule, "\"request_body_schema\":\"#/components/schemas/VPS.V1.Firewall.Rules.StoreRequest\"") != null);
}

test "docker endpoint labels match official path segments used by the POC" {
    try std.testing.expectEqualStrings("docker", DockerEndpoint.projects.label());
    try std.testing.expectEqualStrings("docker-contents", DockerEndpoint.contents.label());
    try std.testing.expectEqualStrings("docker-containers", DockerEndpoint.containers.label());
    try std.testing.expectEqualStrings("docker-logs", DockerEndpoint.logs.label());
    try std.testing.expectEqual(DockerEndpoint.projects, DockerEndpoint.parse("docker").?);
    try std.testing.expectEqual(DockerEndpoint.contents, DockerEndpoint.parse("docker-project").?);
    try std.testing.expectEqual(DockerEndpoint.containers, DockerEndpoint.parse("docker-containers").?);
    try std.testing.expectEqual(DockerEndpoint.logs, DockerEndpoint.parse("docker-logs").?);
    try std.testing.expect(DockerEndpoint.parse("docker-restart") == null);
}

test "docker mutation endpoints map to official operation metadata" {
    try std.testing.expectEqual(DockerMutationEndpoint.create_project, DockerMutationEndpoint.parse("create-project").?);
    try std.testing.expectEqual(DockerMutationEndpoint.delete_project, DockerMutationEndpoint.parse("down").?);
    try std.testing.expectEqual(DockerMutationEndpoint.restart_project, DockerMutationEndpoint.parse("restart").?);
    try std.testing.expectEqual(DockerMutationEndpoint.start_project, DockerMutationEndpoint.parse("start").?);
    try std.testing.expectEqual(DockerMutationEndpoint.stop_project, DockerMutationEndpoint.parse("stop").?);
    try std.testing.expectEqual(DockerMutationEndpoint.update_project, DockerMutationEndpoint.parse("update-project").?);
    try std.testing.expectEqualStrings("VPS: Docker Manager", DockerMutationEndpoint.create_project.group());
    try std.testing.expectEqualStrings("POST", DockerMutationEndpoint.create_project.method());
    try std.testing.expectEqualStrings("DELETE", DockerMutationEndpoint.delete_project.method());
    try std.testing.expectEqualStrings("VPS_createNewProjectV1", DockerMutationEndpoint.create_project.operationId());
    try std.testing.expectEqualStrings("VPS_deleteProjectV1", DockerMutationEndpoint.delete_project.operationId());
    try std.testing.expectEqualStrings("VPS_updateProjectV1", DockerMutationEndpoint.update_project.operationId());
    try std.testing.expectEqualStrings("#/components/schemas/VPS.V1.VirtualMachine.DockerManager.UpRequest", DockerMutationEndpoint.create_project.requestBodySchemaRef().?);
    try std.testing.expect(DockerMutationEndpoint.update_project.requestBodySchemaRef() == null);
    try std.testing.expect(!DockerMutationEndpoint.create_project.requiresProject());
    try std.testing.expect(DockerMutationEndpoint.restart_project.requiresProject());
}

test "builds Hostinger Docker Manager mutation dry-run plan JSON" {
    const allocator = std.testing.allocator;
    const create = try dockerMutationPlanJson(allocator, .create_project, .{ .vm_id = "vm 1" });
    defer allocator.free(create);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"group\":\"VPS: Docker Manager\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"operation_id\":\"VPS_createNewProjectV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"path\":\"/api/vps/v1/virtual-machines/vm%201/docker\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"request_body_schema\":\"#/components/schemas/VPS.V1.VirtualMachine.DockerManager.UpRequest\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"will_execute\":false") != null);

    const restart = try dockerMutationPlanJson(allocator, .restart_project, .{ .vm_id = "vm 1", .project_name = "project/one" });
    defer allocator.free(restart);
    try std.testing.expect(std.mem.indexOf(u8, restart, "\"method\":\"POST\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, restart, "/api/vps/v1/virtual-machines/vm%201/docker/project%2Fone/restart") != null);
    try std.testing.expect(std.mem.indexOf(u8, restart, "\"request_body_schema\":null") != null);

    const delete_project = try dockerMutationPlanJson(allocator, .delete_project, .{ .vm_id = "vm 1", .project_name = "project/one" });
    defer allocator.free(delete_project);
    try std.testing.expect(std.mem.indexOf(u8, delete_project, "\"method\":\"DELETE\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, delete_project, "/api/vps/v1/virtual-machines/vm%201/docker/project%2Fone/down") != null);
}

test "billing endpoint labels match official path segments used by the POC" {
    try std.testing.expectEqualStrings("billing-catalog", BillingEndpoint.catalog.label());
    try std.testing.expectEqualStrings("billing-payment-methods", BillingEndpoint.payment_methods.label());
    try std.testing.expectEqualStrings("billing-subscriptions", BillingEndpoint.subscriptions.label());
    try std.testing.expectEqual(BillingEndpoint.catalog, BillingEndpoint.parse("billing-catalog").?);
    try std.testing.expectEqual(BillingEndpoint.payment_methods, BillingEndpoint.parse("billing-payments").?);
    try std.testing.expectEqual(BillingEndpoint.subscriptions, BillingEndpoint.parse("billing-subscriptions").?);
    try std.testing.expect(BillingEndpoint.parse("billing-delete") == null);
}

test "billing mutation endpoints map to official operation metadata" {
    try std.testing.expectEqual(BillingMutationEndpoint.set_default_payment_method, BillingMutationEndpoint.parse("set-default-payment").?);
    try std.testing.expectEqual(BillingMutationEndpoint.delete_payment_method, BillingMutationEndpoint.parse("delete-payment-method").?);
    try std.testing.expectEqual(BillingMutationEndpoint.enable_auto_renewal, BillingMutationEndpoint.parse("enable-auto-renewal").?);
    try std.testing.expectEqual(BillingMutationEndpoint.disable_auto_renewal, BillingMutationEndpoint.parse("disable-auto-renewal").?);
    try std.testing.expectEqualStrings("Billing: Payment methods", BillingMutationEndpoint.set_default_payment_method.group());
    try std.testing.expectEqualStrings("Billing: Subscriptions", BillingMutationEndpoint.enable_auto_renewal.group());
    try std.testing.expectEqualStrings("POST", BillingMutationEndpoint.set_default_payment_method.method());
    try std.testing.expectEqualStrings("DELETE", BillingMutationEndpoint.delete_payment_method.method());
    try std.testing.expectEqualStrings("PATCH", BillingMutationEndpoint.enable_auto_renewal.method());
    try std.testing.expectEqualStrings("billing_setDefaultPaymentMethodV1", BillingMutationEndpoint.set_default_payment_method.operationId());
    try std.testing.expectEqualStrings("billing_disableAutoRenewalV1", BillingMutationEndpoint.disable_auto_renewal.operationId());
    try std.testing.expect(BillingMutationEndpoint.set_default_payment_method.requestBodySchemaRef() == null);
    try std.testing.expect(BillingMutationEndpoint.set_default_payment_method.requiresPaymentMethodId());
    try std.testing.expect(BillingMutationEndpoint.enable_auto_renewal.requiresSubscriptionId());
}

test "builds Hostinger billing mutation dry-run plan JSON" {
    const allocator = std.testing.allocator;
    const payment = try billingMutationPlanJson(allocator, .set_default_payment_method, .{ .payment_method_id = "pm/1" });
    defer allocator.free(payment);
    try std.testing.expect(std.mem.indexOf(u8, payment, "\"group\":\"Billing: Payment methods\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payment, "\"operation_id\":\"billing_setDefaultPaymentMethodV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payment, "/api/billing/v1/payment-methods/pm%2F1") != null);
    try std.testing.expect(std.mem.indexOf(u8, payment, "\"will_execute\":false") != null);

    const subscription = try billingMutationPlanJson(allocator, .enable_auto_renewal, .{ .subscription_id = "sub 1" });
    defer allocator.free(subscription);
    try std.testing.expect(std.mem.indexOf(u8, subscription, "\"group\":\"Billing: Subscriptions\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, subscription, "\"method\":\"PATCH\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, subscription, "/api/billing/v1/subscriptions/sub%201/auto-renewal/enable") != null);
    try std.testing.expect(std.mem.indexOf(u8, subscription, "\"request_body_schema\":null") != null);
}

test "dns endpoint labels match official path segments used by the POC" {
    try std.testing.expectEqualStrings("dns-zone", DnsEndpoint.zone.label());
    try std.testing.expectEqualStrings("dns-snapshots", DnsEndpoint.snapshots.label());
    try std.testing.expectEqualStrings("dns-snapshot", DnsEndpoint.snapshot.label());
    try std.testing.expectEqual(DnsEndpoint.zone, DnsEndpoint.parse("dns").?);
    try std.testing.expectEqual(DnsEndpoint.snapshots, DnsEndpoint.parse("dns-snapshots").?);
    try std.testing.expectEqual(DnsEndpoint.snapshot, DnsEndpoint.parse("dns-snapshot").?);
    try std.testing.expect(DnsEndpoint.parse("dns-reset") == null);
}

test "dns mutation endpoints map to official operation metadata" {
    try std.testing.expectEqual(DnsMutationEndpoint.restore_snapshot, DnsMutationEndpoint.parse("restore-snapshot").?);
    try std.testing.expectEqual(DnsMutationEndpoint.update_zone, DnsMutationEndpoint.parse("update").?);
    try std.testing.expectEqual(DnsMutationEndpoint.delete_zone, DnsMutationEndpoint.parse("delete-zone").?);
    try std.testing.expectEqualStrings("DNS: Snapshot", DnsMutationEndpoint.restore_snapshot.group());
    try std.testing.expectEqualStrings("DNS: Zone", DnsMutationEndpoint.validate_zone.group());
    try std.testing.expectEqualStrings("POST", DnsMutationEndpoint.restore_snapshot.method());
    try std.testing.expectEqualStrings("PUT", DnsMutationEndpoint.update_zone.method());
    try std.testing.expectEqualStrings("DELETE", DnsMutationEndpoint.delete_zone.method());
    try std.testing.expectEqualStrings("DNS_restoreDNSSnapshotV1", DnsMutationEndpoint.restore_snapshot.operationId());
    try std.testing.expectEqualStrings("DNS_validateDNSRecordsV1", DnsMutationEndpoint.validate_zone.operationId());
    try std.testing.expect(DnsMutationEndpoint.restore_snapshot.requestBodySchemaRef() == null);
    try std.testing.expectEqualStrings("#/components/schemas/DNS.V1.Zone.UpdateRequest", DnsMutationEndpoint.validate_zone.requestBodySchemaRef().?);
    try std.testing.expect(DnsMutationEndpoint.restore_snapshot.requiresSnapshotId());
}

test "builds Hostinger DNS mutation dry-run plan JSON" {
    const allocator = std.testing.allocator;
    const validate = try dnsMutationPlanJson(allocator, .validate_zone, .{ .domain = "plosca.ru" });
    defer allocator.free(validate);
    try std.testing.expect(std.mem.indexOf(u8, validate, "\"group\":\"DNS: Zone\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, validate, "\"operation_id\":\"DNS_validateDNSRecordsV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, validate, "/api/dns/v1/zones/plosca.ru/validate") != null);
    try std.testing.expect(std.mem.indexOf(u8, validate, "\"will_execute\":false") != null);

    const restore = try dnsMutationPlanJson(allocator, .restore_snapshot, .{ .domain = "space domain.test", .snapshot_id = "snap/1" });
    defer allocator.free(restore);
    try std.testing.expect(std.mem.indexOf(u8, restore, "\"group\":\"DNS: Snapshot\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, restore, "/api/dns/v1/snapshots/space%20domain.test/snap%2F1/restore") != null);
    try std.testing.expect(std.mem.indexOf(u8, restore, "\"request_body_schema\":null") != null);
}

test "domain endpoint labels match official path segments used by the POC" {
    try std.testing.expectEqualStrings("domains", DomainEndpoint.portfolio.label());
    try std.testing.expectEqualStrings("domain", DomainEndpoint.portfolio_detail.label());
    try std.testing.expectEqualStrings("domain-forwarding", DomainEndpoint.forwarding.label());
    try std.testing.expectEqualStrings("whois", DomainEndpoint.whois_profiles.label());
    try std.testing.expectEqualStrings("whois-profile", DomainEndpoint.whois_profile.label());
    try std.testing.expectEqualStrings("whois-usage", DomainEndpoint.whois_usage.label());
    try std.testing.expectEqual(DomainEndpoint.portfolio, DomainEndpoint.parse("domains").?);
    try std.testing.expectEqual(DomainEndpoint.portfolio_detail, DomainEndpoint.parse("domain").?);
    try std.testing.expectEqual(DomainEndpoint.forwarding, DomainEndpoint.parse("domain-forwarding").?);
    try std.testing.expectEqual(DomainEndpoint.whois_profiles, DomainEndpoint.parse("whois-profiles").?);
    try std.testing.expectEqual(DomainEndpoint.whois_profile, DomainEndpoint.parse("whois-profile").?);
    try std.testing.expectEqual(DomainEndpoint.whois_usage, DomainEndpoint.parse("whois-usage").?);
    try std.testing.expect(DomainEndpoint.parse("domain-lock") == null);
}

test "domain mutation endpoints map to official operation metadata" {
    try std.testing.expectEqual(DomainMutationEndpoint.check_availability, DomainMutationEndpoint.parse("availability").?);
    try std.testing.expectEqual(DomainMutationEndpoint.check_availability, DomainMutationEndpoint.parse("check-availability").?);
    try std.testing.expectEqual(DomainMutationEndpoint.create_forwarding, DomainMutationEndpoint.parse("create-forwarding").?);
    try std.testing.expectEqual(DomainMutationEndpoint.create_forwarding, DomainMutationEndpoint.parse("forwarding-create").?);
    try std.testing.expectEqual(DomainMutationEndpoint.delete_forwarding, DomainMutationEndpoint.parse("delete-forwarding").?);
    try std.testing.expectEqual(DomainMutationEndpoint.delete_forwarding, DomainMutationEndpoint.parse("forwarding-delete").?);
    try std.testing.expectEqual(DomainMutationEndpoint.purchase_domain, DomainMutationEndpoint.parse("purchase").?);
    try std.testing.expectEqual(DomainMutationEndpoint.purchase_domain, DomainMutationEndpoint.parse("purchase-domain").?);
    try std.testing.expectEqual(DomainMutationEndpoint.enable_domain_lock, DomainMutationEndpoint.parse("enable-domain-lock").?);
    try std.testing.expectEqual(DomainMutationEndpoint.disable_domain_lock, DomainMutationEndpoint.parse("disable-domain-lock").?);
    try std.testing.expectEqual(DomainMutationEndpoint.update_nameservers, DomainMutationEndpoint.parse("update-nameservers").?);
    try std.testing.expectEqual(DomainMutationEndpoint.enable_privacy_protection, DomainMutationEndpoint.parse("enable-privacy-protection").?);
    try std.testing.expectEqual(DomainMutationEndpoint.disable_privacy_protection, DomainMutationEndpoint.parse("disable-privacy-protection").?);
    try std.testing.expectEqual(DomainMutationEndpoint.create_whois_profile, DomainMutationEndpoint.parse("create-whois").?);
    try std.testing.expectEqual(DomainMutationEndpoint.delete_whois_profile, DomainMutationEndpoint.parse("delete-whois-profile").?);
    try std.testing.expectEqualStrings("Domains: Availability", DomainMutationEndpoint.check_availability.group());
    try std.testing.expectEqualStrings("Domains: Forwarding", DomainMutationEndpoint.create_forwarding.group());
    try std.testing.expectEqualStrings("Domains: Portfolio", DomainMutationEndpoint.update_nameservers.group());
    try std.testing.expectEqualStrings("Domains: WHOIS", DomainMutationEndpoint.delete_whois_profile.group());
    try std.testing.expectEqualStrings("POST", DomainMutationEndpoint.check_availability.method());
    try std.testing.expectEqualStrings("POST", DomainMutationEndpoint.create_forwarding.method());
    try std.testing.expectEqualStrings("DELETE", DomainMutationEndpoint.delete_forwarding.method());
    try std.testing.expectEqualStrings("PUT", DomainMutationEndpoint.update_nameservers.method());
    try std.testing.expectEqualStrings("DELETE", DomainMutationEndpoint.delete_whois_profile.method());
    try std.testing.expectEqualStrings("domains_checkDomainAvailabilityV1", DomainMutationEndpoint.check_availability.operationId());
    try std.testing.expectEqualStrings("domains_createDomainForwardingV1", DomainMutationEndpoint.create_forwarding.operationId());
    try std.testing.expectEqualStrings("domains_deleteDomainForwardingV1", DomainMutationEndpoint.delete_forwarding.operationId());
    try std.testing.expectEqualStrings("domains_purchaseNewDomainV1", DomainMutationEndpoint.purchase_domain.operationId());
    try std.testing.expectEqualStrings("domains_updateDomainNameserversV1", DomainMutationEndpoint.update_nameservers.operationId());
    try std.testing.expectEqualStrings("domains_createWHOISProfileV1", DomainMutationEndpoint.create_whois_profile.operationId());
    try std.testing.expectEqualStrings("domains_deleteWHOISProfileV1", DomainMutationEndpoint.delete_whois_profile.operationId());
    try std.testing.expectEqualStrings("#/components/schemas/Domains.V1.Availability.AvailabilityRequest", DomainMutationEndpoint.check_availability.requestBodySchemaRef().?);
    try std.testing.expectEqualStrings("#/components/schemas/Domains.V1.Forwarding.StoreRequest", DomainMutationEndpoint.create_forwarding.requestBodySchemaRef().?);
    try std.testing.expectEqualStrings("#/components/schemas/Domains.V1.Portfolio.PurchaseRequest", DomainMutationEndpoint.purchase_domain.requestBodySchemaRef().?);
    try std.testing.expectEqualStrings("#/components/schemas/Domains.V1.Portfolio.UpdateNameserversRequest", DomainMutationEndpoint.update_nameservers.requestBodySchemaRef().?);
    try std.testing.expectEqualStrings("#/components/schemas/Domains.V1.WHOIS.StoreRequest", DomainMutationEndpoint.create_whois_profile.requestBodySchemaRef().?);
    try std.testing.expect(DomainMutationEndpoint.delete_forwarding.requestBodySchemaRef() == null);
    try std.testing.expect(!DomainMutationEndpoint.create_forwarding.requiresDomain());
    try std.testing.expect(DomainMutationEndpoint.delete_forwarding.requiresDomain());
    try std.testing.expect(DomainMutationEndpoint.enable_domain_lock.requiresDomain());
    try std.testing.expect(DomainMutationEndpoint.disable_privacy_protection.requiresDomain());
    try std.testing.expect(!DomainMutationEndpoint.create_whois_profile.requiresDomain());
    try std.testing.expect(DomainMutationEndpoint.delete_whois_profile.requiresWhoisId());
}

test "builds Hostinger domain mutation dry-run plan JSON" {
    const allocator = std.testing.allocator;
    const availability = try domainMutationPlanJson(allocator, .check_availability, .{});
    defer allocator.free(availability);
    try std.testing.expect(std.mem.indexOf(u8, availability, "\"group\":\"Domains: Availability\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, availability, "\"operation_id\":\"domains_checkDomainAvailabilityV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, availability, "\"path\":\"/api/domains/v1/availability\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, availability, "\"request_body_schema\":\"#/components/schemas/Domains.V1.Availability.AvailabilityRequest\"") != null);

    const create = try domainMutationPlanJson(allocator, .create_forwarding, .{});
    defer allocator.free(create);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"group\":\"Domains: Forwarding\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"operation_id\":\"domains_createDomainForwardingV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"request_body_schema\":\"#/components/schemas/Domains.V1.Forwarding.StoreRequest\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"path\":\"/api/domains/v1/forwarding\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, create, "\"will_execute\":false") != null);

    const delete = try domainMutationPlanJson(allocator, .delete_forwarding, .{ .domain = "space domain.test" });
    defer allocator.free(delete);
    try std.testing.expect(std.mem.indexOf(u8, delete, "\"method\":\"DELETE\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, delete, "/api/domains/v1/forwarding/space%20domain.test") != null);
    try std.testing.expect(std.mem.indexOf(u8, delete, "\"request_body_schema\":null") != null);

    const nameservers = try domainMutationPlanJson(allocator, .update_nameservers, .{ .domain = "plosca.ru" });
    defer allocator.free(nameservers);
    try std.testing.expect(std.mem.indexOf(u8, nameservers, "\"group\":\"Domains: Portfolio\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, nameservers, "\"method\":\"PUT\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, nameservers, "/api/domains/v1/portfolio/plosca.ru/nameservers") != null);
    try std.testing.expect(std.mem.indexOf(u8, nameservers, "\"request_body_schema\":\"#/components/schemas/Domains.V1.Portfolio.UpdateNameserversRequest\"") != null);

    const purchase = try domainMutationPlanJson(allocator, .purchase_domain, .{});
    defer allocator.free(purchase);
    try std.testing.expect(std.mem.indexOf(u8, purchase, "\"operation_id\":\"domains_purchaseNewDomainV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, purchase, "\"path\":\"/api/domains/v1/portfolio\"") != null);

    const whois = try domainMutationPlanJson(allocator, .delete_whois_profile, .{ .whois_id = "whois/1" });
    defer allocator.free(whois);
    try std.testing.expect(std.mem.indexOf(u8, whois, "\"group\":\"Domains: WHOIS\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, whois, "/api/domains/v1/whois/whois%2F1") != null);
    try std.testing.expect(std.mem.indexOf(u8, whois, "\"request_body_schema\":null") != null);
}

test "hosting endpoint labels match official path segments used by the POC" {
    try std.testing.expectEqualStrings("hosting-orders", HostingEndpoint.orders.label());
    try std.testing.expectEqualStrings("hosting-websites", HostingEndpoint.websites.label());
    try std.testing.expectEqualStrings("hosting-wordpress", HostingEndpoint.wordpress.label());
    try std.testing.expectEqualStrings("hosting-datacenters", HostingEndpoint.datacenters.label());
    try std.testing.expectEqualStrings("hosting-databases", HostingEndpoint.databases.label());
    try std.testing.expectEqualStrings("hosting-phpmyadmin", HostingEndpoint.phpmyadmin_link.label());
    try std.testing.expectEqualStrings("hosting-parked-domains", HostingEndpoint.parked_domains.label());
    try std.testing.expectEqualStrings("hosting-subdomains", HostingEndpoint.subdomains.label());
    try std.testing.expectEqualStrings("hosting-node-builds", HostingEndpoint.nodejs_builds.label());
    try std.testing.expectEqualStrings("hosting-node-logs", HostingEndpoint.nodejs_logs.label());
    try std.testing.expectEqual(HostingEndpoint.orders, HostingEndpoint.parse("hosting-orders").?);
    try std.testing.expectEqual(HostingEndpoint.wordpress, HostingEndpoint.parse("hosting-wordpress-installations").?);
    try std.testing.expectEqual(HostingEndpoint.phpmyadmin_link, HostingEndpoint.parse("hosting-phpmyadmin-link").?);
    try std.testing.expect(HostingEndpoint.parse("hosting-create") == null);
}

test "hosting mutation endpoints map to official operation metadata" {
    try std.testing.expectEqual(HostingMutationEndpoint.create_website, HostingMutationEndpoint.parse("create-website").?);
    try std.testing.expectEqual(HostingMutationEndpoint.install_wordpress, HostingMutationEndpoint.parse("install-wordpress").?);
    try std.testing.expectEqual(HostingMutationEndpoint.create_database, HostingMutationEndpoint.parse("create-database").?);
    try std.testing.expectEqual(HostingMutationEndpoint.delete_database, HostingMutationEndpoint.parse("delete-database").?);
    try std.testing.expectEqual(HostingMutationEndpoint.change_database_password, HostingMutationEndpoint.parse("change-database-password").?);
    try std.testing.expectEqual(HostingMutationEndpoint.repair_database, HostingMutationEndpoint.parse("repair-database").?);
    try std.testing.expectEqual(HostingMutationEndpoint.generate_free_subdomain, HostingMutationEndpoint.parse("free-subdomain").?);
    try std.testing.expectEqual(HostingMutationEndpoint.verify_domain_ownership, HostingMutationEndpoint.parse("verify-ownership").?);
    try std.testing.expectEqual(HostingMutationEndpoint.create_parked_domain, HostingMutationEndpoint.parse("parked-domain-create").?);
    try std.testing.expectEqual(HostingMutationEndpoint.delete_parked_domain, HostingMutationEndpoint.parse("delete-parked-domain").?);
    try std.testing.expectEqual(HostingMutationEndpoint.create_subdomain, HostingMutationEndpoint.parse("subdomain-create").?);
    try std.testing.expectEqual(HostingMutationEndpoint.delete_subdomain, HostingMutationEndpoint.parse("delete-subdomain").?);
    try std.testing.expectEqual(HostingMutationEndpoint.create_nodejs_build_from_archive, HostingMutationEndpoint.parse("create-nodejs-build").?);
    try std.testing.expectEqualStrings("Hosting: Websites", HostingMutationEndpoint.create_website.group());
    try std.testing.expectEqualStrings("Hosting: Wordpress", HostingMutationEndpoint.install_wordpress.group());
    try std.testing.expectEqualStrings("Hosting: Databases", HostingMutationEndpoint.change_database_password.group());
    try std.testing.expectEqualStrings("Hosting: Domains", HostingMutationEndpoint.delete_subdomain.group());
    try std.testing.expectEqualStrings("Hosting: NodeJS", HostingMutationEndpoint.create_nodejs_build_from_archive.group());
    try std.testing.expectEqualStrings("POST", HostingMutationEndpoint.create_website.method());
    try std.testing.expectEqualStrings("DELETE", HostingMutationEndpoint.delete_database.method());
    try std.testing.expectEqualStrings("PATCH", HostingMutationEndpoint.repair_database.method());
    try std.testing.expectEqualStrings("hosting_createWebsiteV1", HostingMutationEndpoint.create_website.operationId());
    try std.testing.expectEqualStrings("hosting_installWordPressV1", HostingMutationEndpoint.install_wordpress.operationId());
    try std.testing.expectEqualStrings("hosting_changeDatabasePasswordV1", HostingMutationEndpoint.change_database_password.operationId());
    try std.testing.expectEqualStrings("hosting_verifyDomainOwnershipV1", HostingMutationEndpoint.verify_domain_ownership.operationId());
    try std.testing.expectEqualStrings("hosting_createNodeJSBuildFromArchiveV1", HostingMutationEndpoint.create_nodejs_build_from_archive.operationId());
    try std.testing.expectEqualStrings("#/components/schemas/Hosting.V1.Websites.CreateWebsiteRequest", HostingMutationEndpoint.create_website.requestBodySchemaRef().?);
    try std.testing.expectEqualStrings("#/components/schemas/Hosting.V1.Wordpress.InstallWordpressRequest", HostingMutationEndpoint.install_wordpress.requestBodySchemaRef().?);
    try std.testing.expectEqualStrings("#/components/schemas/Hosting.V1.Databases.CreateDatabaseRequest", HostingMutationEndpoint.create_database.requestBodySchemaRef().?);
    try std.testing.expectEqualStrings("#/components/schemas/Hosting.V1.Domains.CreateSubdomainRequest", HostingMutationEndpoint.create_subdomain.requestBodySchemaRef().?);
    try std.testing.expect(HostingMutationEndpoint.generate_free_subdomain.requestBodySchemaRef() == null);
    try std.testing.expect(HostingMutationEndpoint.install_wordpress.requiresUsername());
    try std.testing.expect(HostingMutationEndpoint.change_database_password.requiresDatabaseName());
    try std.testing.expect(HostingMutationEndpoint.create_nodejs_build_from_archive.requiresDomain());
    try std.testing.expect(HostingMutationEndpoint.delete_parked_domain.requiresParkedDomain());
    try std.testing.expect(HostingMutationEndpoint.delete_subdomain.requiresSubdomain());
}

test "builds Hostinger hosting mutation dry-run plan JSON" {
    const allocator = std.testing.allocator;
    const website = try hostingMutationPlanJson(allocator, .create_website, .{});
    defer allocator.free(website);
    try std.testing.expect(std.mem.indexOf(u8, website, "\"group\":\"Hosting: Websites\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, website, "\"operation_id\":\"hosting_createWebsiteV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, website, "\"path\":\"/api/hosting/v1/websites\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, website, "\"request_body_schema\":\"#/components/schemas/Hosting.V1.Websites.CreateWebsiteRequest\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, website, "\"will_execute\":false") != null);

    const wordpress = try hostingMutationPlanJson(allocator, .install_wordpress, .{ .username = "user/1" });
    defer allocator.free(wordpress);
    try std.testing.expect(std.mem.indexOf(u8, wordpress, "\"group\":\"Hosting: Wordpress\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, wordpress, "/api/hosting/v1/accounts/user%2F1/wordpress/installations") != null);

    const database = try hostingMutationPlanJson(allocator, .change_database_password, .{ .username = "user 1", .database_name = "db/1" });
    defer allocator.free(database);
    try std.testing.expect(std.mem.indexOf(u8, database, "\"method\":\"PATCH\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, database, "/api/hosting/v1/accounts/user%201/databases/db%2F1/change-password") != null);
    try std.testing.expect(std.mem.indexOf(u8, database, "\"request_body_schema\":\"#/components/schemas/Hosting.V1.Databases.ChangeDatabasePasswordRequest\"") != null);

    const parked = try hostingMutationPlanJson(allocator, .delete_parked_domain, .{ .username = "u", .domain = "site.test", .parked_domain = "parked/site.test" });
    defer allocator.free(parked);
    try std.testing.expect(std.mem.indexOf(u8, parked, "\"group\":\"Hosting: Domains\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, parked, "/api/hosting/v1/accounts/u/websites/site.test/parked-domains/parked%2Fsite.test") != null);
    try std.testing.expect(std.mem.indexOf(u8, parked, "\"request_body_schema\":null") != null);

    const nodejs = try hostingMutationPlanJson(allocator, .create_nodejs_build_from_archive, .{ .username = "u", .domain = "space domain.test" });
    defer allocator.free(nodejs);
    try std.testing.expect(std.mem.indexOf(u8, nodejs, "\"group\":\"Hosting: NodeJS\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, nodejs, "/api/hosting/v1/accounts/u/websites/space%20domain.test/nodejs/builds/from-archive") != null);
}

test "reach ecommerce horizons endpoint labels match official path segments used by the POC" {
    try std.testing.expectEqualStrings("ecommerce-stores", EcommerceEndpoint.stores.label());
    try std.testing.expectEqual(EcommerceEndpoint.stores, EcommerceEndpoint.parse("ecommerce-stores").?);
    try std.testing.expect(EcommerceEndpoint.parse("ecommerce-create") == null);

    try std.testing.expectEqualStrings("horizons-website", HorizonsEndpoint.website.label());
    try std.testing.expectEqual(HorizonsEndpoint.website, HorizonsEndpoint.parse("horizons-website").?);
    try std.testing.expect(HorizonsEndpoint.parse("horizons-create") == null);

    try std.testing.expectEqualStrings("reach-contacts", ReachEndpoint.contacts.label());
    try std.testing.expectEqualStrings("reach-profiles", ReachEndpoint.profiles.label());
    try std.testing.expectEqualStrings("reach-segments", ReachEndpoint.segments.label());
    try std.testing.expectEqualStrings("reach-segment", ReachEndpoint.segment.label());
    try std.testing.expectEqualStrings("reach-segment-contacts", ReachEndpoint.segment_contacts.label());
    try std.testing.expectEqualStrings("reach-profile-segment-contacts", ReachEndpoint.profile_segment_contacts.label());
    try std.testing.expectEqual(ReachEndpoint.profile_segment_contacts, ReachEndpoint.parse("reach-profile-segment-contacts").?);
    try std.testing.expect(ReachEndpoint.parse("reach-create") == null);
}

test "reach ecommerce horizons mutation endpoints map to official operation metadata" {
    try std.testing.expectEqual(EcommerceMutationEndpoint.create_store, EcommerceMutationEndpoint.parse("create").?);
    try std.testing.expectEqualStrings("Ecommerce: Stores", EcommerceMutationEndpoint.create_store.group());
    try std.testing.expectEqualStrings("POST", EcommerceMutationEndpoint.create_store.method());
    try std.testing.expectEqualStrings("ecommerce_createStoreV1", EcommerceMutationEndpoint.create_store.operationId());
    try std.testing.expectEqualStrings("#/components/schemas/Ecommerce.V1.Store.StoreRequest", EcommerceMutationEndpoint.create_store.requestBodySchemaRef().?);

    try std.testing.expectEqual(HorizonsMutationEndpoint.create_website, HorizonsMutationEndpoint.parse("create-website").?);
    try std.testing.expectEqualStrings("Horizons: Websites", HorizonsMutationEndpoint.create_website.group());
    try std.testing.expectEqualStrings("POST", HorizonsMutationEndpoint.create_website.method());
    try std.testing.expectEqualStrings("horizons_createWebsiteV1", HorizonsMutationEndpoint.create_website.operationId());
    try std.testing.expectEqualStrings("#/components/schemas/Horizons.V1.Websites.CreateWebsiteRequest", HorizonsMutationEndpoint.create_website.requestBodySchemaRef().?);

    try std.testing.expectEqual(ReachMutationEndpoint.delete_contact, ReachMutationEndpoint.parse("delete-contact").?);
    try std.testing.expectEqual(ReachMutationEndpoint.create_profile_contacts, ReachMutationEndpoint.parse("create-contacts").?);
    try std.testing.expectEqual(ReachMutationEndpoint.create_segment, ReachMutationEndpoint.parse("create-segment").?);
    try std.testing.expectEqualStrings("Reach: Contacts", ReachMutationEndpoint.delete_contact.group());
    try std.testing.expectEqualStrings("Reach: Segments", ReachMutationEndpoint.create_segment.group());
    try std.testing.expectEqualStrings("DELETE", ReachMutationEndpoint.delete_contact.method());
    try std.testing.expectEqualStrings("POST", ReachMutationEndpoint.create_profile_contacts.method());
    try std.testing.expectEqualStrings("reach_deleteAContactV1", ReachMutationEndpoint.delete_contact.operationId());
    try std.testing.expectEqualStrings("reach_createNewContactsV1", ReachMutationEndpoint.create_profile_contacts.operationId());
    try std.testing.expectEqualStrings("reach_createANewContactSegmentV1", ReachMutationEndpoint.create_segment.operationId());
    try std.testing.expect(ReachMutationEndpoint.delete_contact.requestBodySchemaRef() == null);
    try std.testing.expectEqualStrings("#/components/schemas/Reach.V1.Contacts.StoreRequest", ReachMutationEndpoint.create_profile_contacts.requestBodySchemaRef().?);
    try std.testing.expectEqualStrings("#/components/schemas/Reach.V1.Contacts.Segments.StoreRequest", ReachMutationEndpoint.create_segment.requestBodySchemaRef().?);
    try std.testing.expect(ReachMutationEndpoint.delete_contact.requiresContactUuid());
    try std.testing.expect(ReachMutationEndpoint.create_profile_contacts.requiresProfileUuid());
}

test "builds Hostinger Reach Ecommerce Horizons mutation dry-run plan JSON" {
    const allocator = std.testing.allocator;
    const store = try ecommerceMutationPlanJson(allocator, .create_store);
    defer allocator.free(store);
    try std.testing.expect(std.mem.indexOf(u8, store, "\"group\":\"Ecommerce: Stores\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, store, "\"operation_id\":\"ecommerce_createStoreV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, store, "\"path\":\"/api/ecommerce/v1/stores\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, store, "\"request_body_schema\":\"#/components/schemas/Ecommerce.V1.Store.StoreRequest\"") != null);

    const website = try horizonsMutationPlanJson(allocator, .create_website);
    defer allocator.free(website);
    try std.testing.expect(std.mem.indexOf(u8, website, "\"group\":\"Horizons: Websites\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, website, "\"operation_id\":\"horizons_createWebsiteV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, website, "\"path\":\"/api/horizons/v1/websites\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, website, "\"will_execute\":false") != null);

    const delete_contact = try reachMutationPlanJson(allocator, .delete_contact, .{ .contact_uuid = "contact/1" });
    defer allocator.free(delete_contact);
    try std.testing.expect(std.mem.indexOf(u8, delete_contact, "\"group\":\"Reach: Contacts\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, delete_contact, "\"method\":\"DELETE\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, delete_contact, "/api/reach/v1/contacts/contact%2F1") != null);
    try std.testing.expect(std.mem.indexOf(u8, delete_contact, "\"request_body_schema\":null") != null);

    const profile_contacts = try reachMutationPlanJson(allocator, .create_profile_contacts, .{ .profile_uuid = "profile/1" });
    defer allocator.free(profile_contacts);
    try std.testing.expect(std.mem.indexOf(u8, profile_contacts, "\"operation_id\":\"reach_createNewContactsV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, profile_contacts, "/api/reach/v1/profiles/profile%2F1/contacts") != null);
    try std.testing.expect(std.mem.indexOf(u8, profile_contacts, "\"request_body_schema\":\"#/components/schemas/Reach.V1.Contacts.StoreRequest\"") != null);

    const segment = try reachMutationPlanJson(allocator, .create_segment, .{});
    defer allocator.free(segment);
    try std.testing.expect(std.mem.indexOf(u8, segment, "\"group\":\"Reach: Segments\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, segment, "\"path\":\"/api/reach/v1/segmentation/segments\"") != null);
}

test "builds official Hostinger VPS URLs" {
    const allocator = std.testing.allocator;
    const list = try virtualMachinesUrl(allocator, base_url);
    defer allocator.free(list);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/vps/v1/virtual-machines", list);

    const details = try virtualMachineDetailsUrl(allocator, base_url, "1307809");
    defer allocator.free(details);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/vps/v1/virtual-machines/1307809", details);

    const actions = try endpointUrl(allocator, base_url, "1307809", .actions);
    defer allocator.free(actions);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/vps/v1/virtual-machines/1307809/actions", actions);

    const action_details = try actionDetailsUrl(allocator, base_url, "1307809", "8123712");
    defer allocator.free(action_details);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/vps/v1/virtual-machines/1307809/actions/8123712", action_details);

    const firewalls = try vpsInventoryUrl(allocator, base_url, .firewalls);
    defer allocator.free(firewalls);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/vps/v1/firewall", firewalls);

    const action_page = try endpointPageUrl(allocator, base_url, "1307809", .actions, 2);
    defer allocator.free(action_page);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/vps/v1/virtual-machines/1307809/actions?page=2", action_page);

    const key_page = try vpsInventoryPageUrl(allocator, base_url, .public_keys, 2);
    defer allocator.free(key_page);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/vps/v1/public-keys?page=2", key_page);

    const template_detail = try vpsInventoryDetailUrl(allocator, base_url, .template, "1034");
    defer allocator.free(template_detail);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/vps/v1/templates/1034", template_detail);

    const firewall_detail = try vpsInventoryDetailUrl(allocator, base_url, .firewall, "65224");
    defer allocator.free(firewall_detail);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/vps/v1/firewall/65224", firewall_detail);

    const post_install_detail = try vpsInventoryDetailUrl(allocator, base_url, .post_install_script, "8123712");
    defer allocator.free(post_install_detail);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/vps/v1/post-install-scripts/8123712", post_install_detail);

    const docker_projects = try dockerEndpointUrl(allocator, base_url, "1307809", .projects, null);
    defer allocator.free(docker_projects);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/vps/v1/virtual-machines/1307809/docker", docker_projects);

    const docker_contents = try dockerEndpointUrl(allocator, base_url, "1307809", .contents, "my app");
    defer allocator.free(docker_contents);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/vps/v1/virtual-machines/1307809/docker/my%20app", docker_contents);

    const docker_containers = try dockerEndpointUrl(allocator, base_url, "1307809", .containers, "my app");
    defer allocator.free(docker_containers);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/vps/v1/virtual-machines/1307809/docker/my%20app/containers", docker_containers);

    const docker_logs = try dockerEndpointUrl(allocator, base_url, "1307809", .logs, "my app");
    defer allocator.free(docker_logs);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/vps/v1/virtual-machines/1307809/docker/my%20app/logs", docker_logs);

    const catalog = try billingEndpointUrl(allocator, base_url, .catalog);
    defer allocator.free(catalog);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/billing/v1/catalog", catalog);

    const payment_methods = try billingEndpointUrl(allocator, base_url, .payment_methods);
    defer allocator.free(payment_methods);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/billing/v1/payment-methods", payment_methods);

    const subscriptions = try billingEndpointUrl(allocator, base_url, .subscriptions);
    defer allocator.free(subscriptions);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/billing/v1/subscriptions", subscriptions);

    const dns_zone = try dnsEndpointUrl(allocator, base_url, .zone, "plosca.ru", null);
    defer allocator.free(dns_zone);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/dns/v1/zones/plosca.ru", dns_zone);

    const dns_snapshots = try dnsEndpointUrl(allocator, base_url, .snapshots, "plosca.ru", null);
    defer allocator.free(dns_snapshots);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/dns/v1/snapshots/plosca.ru", dns_snapshots);

    const dns_snapshot = try dnsEndpointUrl(allocator, base_url, .snapshot, "plosca.ru", "1234");
    defer allocator.free(dns_snapshot);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/dns/v1/snapshots/plosca.ru/1234", dns_snapshot);

    const domains = try domainEndpointUrl(allocator, base_url, .portfolio, null, null);
    defer allocator.free(domains);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/domains/v1/portfolio", domains);

    const domain_detail = try domainEndpointUrl(allocator, base_url, .portfolio_detail, "plosca.ru", null);
    defer allocator.free(domain_detail);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/domains/v1/portfolio/plosca.ru", domain_detail);

    const domain_forwarding = try domainEndpointUrl(allocator, base_url, .forwarding, "plosca.ru", null);
    defer allocator.free(domain_forwarding);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/domains/v1/forwarding/plosca.ru", domain_forwarding);

    const whois = try domainEndpointUrl(allocator, base_url, .whois_profiles, null, null);
    defer allocator.free(whois);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/domains/v1/whois", whois);

    const whois_filtered = try domainEndpointUrl(allocator, base_url, .whois_profiles, null, "co uk");
    defer allocator.free(whois_filtered);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/domains/v1/whois?tld=co%20uk", whois_filtered);

    const whois_profile = try domainEndpointUrl(allocator, base_url, .whois_profile, "564651", null);
    defer allocator.free(whois_profile);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/domains/v1/whois/564651", whois_profile);

    const whois_usage = try domainEndpointUrl(allocator, base_url, .whois_usage, "564651", null);
    defer allocator.free(whois_usage);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/domains/v1/whois/564651/usage", whois_usage);

    const hosting_orders = try hostingEndpointUrl(allocator, base_url, .orders, .{});
    defer allocator.free(hosting_orders);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/hosting/v1/orders", hosting_orders);

    const hosting_websites = try hostingEndpointUrl(allocator, base_url, .websites, .{});
    defer allocator.free(hosting_websites);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/hosting/v1/websites", hosting_websites);

    const hosting_wordpress = try hostingEndpointUrl(allocator, base_url, .wordpress, .{});
    defer allocator.free(hosting_wordpress);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/hosting/v1/wordpress/installations", hosting_wordpress);

    const hosting_datacenters = try hostingEndpointUrl(allocator, base_url, .datacenters, .{ .order_id = "12345" });
    defer allocator.free(hosting_datacenters);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/hosting/v1/datacenters?order_id=12345", hosting_datacenters);

    const hosting_databases = try hostingEndpointPageUrl(allocator, base_url, .databases, .{ .username = "user name" }, 2);
    defer allocator.free(hosting_databases);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/hosting/v1/accounts/user%20name/databases?page=2", hosting_databases);

    const phpmyadmin = try hostingEndpointUrl(allocator, base_url, .phpmyadmin_link, .{ .username = "user", .name = "db/main" });
    defer allocator.free(phpmyadmin);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/hosting/v1/accounts/user/databases/db%2Fmain/phpmyadmin-link", phpmyadmin);

    const parked = try hostingEndpointUrl(allocator, base_url, .parked_domains, .{ .username = "user", .domain = "plosca.ru" });
    defer allocator.free(parked);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/hosting/v1/accounts/user/websites/plosca.ru/parked-domains", parked);

    const subdomains = try hostingEndpointUrl(allocator, base_url, .subdomains, .{ .username = "user", .domain = "plosca.ru" });
    defer allocator.free(subdomains);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/hosting/v1/accounts/user/websites/plosca.ru/subdomains", subdomains);

    const node_builds = try hostingEndpointPageUrl(allocator, base_url, .nodejs_builds, .{ .username = "user", .domain = "plosca.ru" }, 2);
    defer allocator.free(node_builds);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/hosting/v1/accounts/user/websites/plosca.ru/nodejs/builds?page=2", node_builds);

    const node_logs = try hostingEndpointUrl(allocator, base_url, .nodejs_logs, .{ .username = "user", .domain = "plosca.ru", .uuid = "build uuid", .from_line = "10" });
    defer allocator.free(node_logs);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/hosting/v1/accounts/user/websites/plosca.ru/nodejs/builds/build%20uuid/logs?from_line=10", node_logs);

    const ecommerce_stores = try ecommerceEndpointPageUrl(allocator, base_url, .stores, 2);
    defer allocator.free(ecommerce_stores);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/ecommerce/v1/stores?page=2", ecommerce_stores);

    const horizons_website = try horizonsEndpointUrl(allocator, base_url, .website, "site id");
    defer allocator.free(horizons_website);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/horizons/v1/websites/site%20id", horizons_website);

    const reach_contacts = try reachEndpointPageUrl(allocator, base_url, .contacts, .{}, 2);
    defer allocator.free(reach_contacts);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/reach/v1/contacts?page=2", reach_contacts);

    const reach_profiles = try reachEndpointUrl(allocator, base_url, .profiles, .{});
    defer allocator.free(reach_profiles);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/reach/v1/profiles", reach_profiles);

    const reach_segments = try reachEndpointUrl(allocator, base_url, .segments, .{});
    defer allocator.free(reach_segments);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/reach/v1/segmentation/segments", reach_segments);

    const reach_segment = try reachEndpointUrl(allocator, base_url, .segment, .{ .segment_uuid = "seg uuid" });
    defer allocator.free(reach_segment);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/reach/v1/segmentation/segments/seg%20uuid", reach_segment);

    const reach_segment_contacts = try reachEndpointPageUrl(allocator, base_url, .segment_contacts, .{ .segment_uuid = "seg uuid" }, 2);
    defer allocator.free(reach_segment_contacts);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/reach/v1/segmentation/segments/seg%20uuid/contacts?page=2", reach_segment_contacts);

    const reach_profile_segment_contacts = try reachEndpointPageUrl(allocator, base_url, .profile_segment_contacts, .{ .profile_uuid = "profile uuid", .segment_uuid = "seg uuid" }, 2);
    defer allocator.free(reach_profile_segment_contacts);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/reach/v1/profiles/profile%20uuid/segmentation/segments/seg%20uuid/contacts?page=2", reach_profile_segment_contacts);
}

test "metrics url uses deterministic 24 hour UTC window" {
    const allocator = std.testing.allocator;
    const url = try metricsUrlAt(allocator, base_url, "1307809", 1767225600);
    defer allocator.free(url);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/vps/v1/virtual-machines/1307809/metrics?date_from=2025-12-31T00:00Z&date_to=2026-01-01T00:00Z", url);
}

test "page url preserves existing query strings" {
    const allocator = std.testing.allocator;
    const first = try pageUrl(allocator, "https://developers.hostinger.com/api/vps/v1/public-keys", 1);
    defer allocator.free(first);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/vps/v1/public-keys", first);

    const second = try pageUrl(allocator, "https://developers.hostinger.com/api/vps/v1/virtual-machines/1/metrics?date_from=x", 2);
    defer allocator.free(second);
    try std.testing.expectEqualStrings("https://developers.hostinger.com/api/vps/v1/virtual-machines/1/metrics?date_from=x&page=2", second);
}

test "path escape encodes docker project path segments" {
    const allocator = std.testing.allocator;
    const escaped = try pathEscape(allocator, "team api/blue");
    defer allocator.free(escaped);
    try std.testing.expectEqualStrings("team%20api%2Fblue", escaped);
}
