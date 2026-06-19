const std = @import("std");
const sqlite = @import("sqlite");
const core_output = @import("core_output");
const db_store = @import("db_store");
const net_http = @import("net_http");
const collector_capture = @import("collector_capture");
const collector_capture_normalize = @import("collector_capture_normalize");
const provider_hostinger = @import("provider_hostinger");
const provider_hostinger_models = @import("provider_hostinger_models");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Db = db_store.Db;
const columnText = db_store.columnText;

pub const VmEndpoint = provider_hostinger.VmEndpoint;
pub const VpsInventoryEndpoint = provider_hostinger.VpsInventoryEndpoint;
pub const VpsInventoryDetailEndpoint = provider_hostinger.VpsInventoryDetailEndpoint;
pub const DockerEndpoint = provider_hostinger.DockerEndpoint;
pub const BillingEndpoint = provider_hostinger.BillingEndpoint;
pub const DnsEndpoint = provider_hostinger.DnsEndpoint;
pub const DomainEndpoint = provider_hostinger.DomainEndpoint;
pub const HostingEndpoint = provider_hostinger.HostingEndpoint;
pub const HostingArgs = provider_hostinger.HostingArgs;
pub const EcommerceEndpoint = provider_hostinger.EcommerceEndpoint;
pub const HorizonsEndpoint = provider_hostinger.HorizonsEndpoint;
pub const ReachEndpoint = provider_hostinger.ReachEndpoint;
pub const ReachArgs = provider_hostinger.ReachArgs;

const billing_endpoints = [_]BillingEndpoint{
    .catalog,
    .payment_methods,
    .subscriptions,
};
const vps_inventory_endpoints = [_]VpsInventoryEndpoint{
    .data_centers,
    .firewalls,
    .public_keys,
    .templates,
    .post_install_scripts,
};
const hosting_refresh_endpoints = [_]HostingEndpoint{
    .orders,
    .websites,
    .wordpress,
};
const reach_refresh_endpoints = [_]ReachEndpoint{
    .contacts,
    .profiles,
    .segments,
};
const docker_project_detail_endpoints = [_]DockerEndpoint{
    .contents,
    .containers,
    .logs,
};
const max_hostinger_pages = 25;

pub const Output = core_output.Output;

pub fn collectAll(io: Io, gpa: Allocator, token: ?[]const u8, domains: []const []const u8, db: *Db) !void {
    for (billing_endpoints) |endpoint| {
        var billing = try collectBillingEndpoint(io, gpa, token, db, endpoint, false);
        billing.deinit(gpa);
    }

    var domain_portfolio = try collectDomainEndpoint(io, gpa, token, db, .portfolio, null, null, false);
    domain_portfolio.deinit(gpa);
    var whois_profiles = try collectDomainEndpoint(io, gpa, token, db, .whois_profiles, null, null, false);
    whois_profiles.deinit(gpa);

    for (domains) |domain| {
        var domain_detail = try collectDomainEndpoint(io, gpa, token, db, .portfolio_detail, domain, null, false);
        domain_detail.deinit(gpa);
        var forwarding = try collectDomainEndpoint(io, gpa, token, db, .forwarding, domain, null, false);
        forwarding.deinit(gpa);
        var dns_zone = try collectDnsEndpoint(io, gpa, token, db, .zone, domain, null, false);
        dns_zone.deinit(gpa);
        var dns_snapshots = try collectDnsEndpoint(io, gpa, token, db, .snapshots, domain, null, false);
        dns_snapshots.deinit(gpa);
    }

    for (hosting_refresh_endpoints) |endpoint| {
        var hosting = try collectHostingEndpoint(io, gpa, token, db, endpoint, .{}, false);
        hosting.deinit(gpa);
    }

    var ecommerce = try collectEcommerceEndpoint(io, gpa, token, db, .stores, false);
    ecommerce.deinit(gpa);

    for (reach_refresh_endpoints) |endpoint| {
        var reach = try collectReachEndpoint(io, gpa, token, db, endpoint, .{}, false);
        reach.deinit(gpa);
    }

    var vps_output = try collectVps(io, gpa, token, db, false);
    vps_output.deinit(gpa);

    for (vps_inventory_endpoints) |endpoint| {
        var inventory = try collectVpsInventoryEndpoint(io, gpa, token, db, endpoint, false);
        inventory.deinit(gpa);
    }

    var ids = std.ArrayList([]u8).empty;
    defer {
        for (ids.items) |id| gpa.free(id);
        ids.deinit(gpa);
    }
    try dbHostingerIds(gpa, db, &ids);
    for (ids.items) |id| {
        var details = try collectVpsDetails(io, gpa, token, db, id, false);
        details.deinit(gpa);
        var metrics = try collectVmEndpoint(io, gpa, token, db, id, .metrics, false);
        metrics.deinit(gpa);
        var actions = try collectVmEndpoint(io, gpa, token, db, id, .actions, false);
        actions.deinit(gpa);
        var public_keys = try collectVmEndpoint(io, gpa, token, db, id, .public_keys, false);
        public_keys.deinit(gpa);
        var backups = try collectVmEndpoint(io, gpa, token, db, id, .backups, false);
        backups.deinit(gpa);
        var snapshot = try collectVmEndpoint(io, gpa, token, db, id, .snapshot, false);
        snapshot.deinit(gpa);
        var monarx = try collectVmEndpoint(io, gpa, token, db, id, .monarx, false);
        monarx.deinit(gpa);
        try collectDockerProjectGroup(io, gpa, token, db, id);
    }
}

pub fn collectDashboard(io: Io, gpa: Allocator, token: ?[]const u8, db: *Db) !void {
    var vps_output = try collectVps(io, gpa, token, db, false);
    vps_output.deinit(gpa);

    const dashboard_inventory_endpoints = [_]VpsInventoryEndpoint{
        .firewalls,
        .public_keys,
    };
    for (dashboard_inventory_endpoints) |endpoint| {
        var inventory = try collectVpsInventoryEndpoint(io, gpa, token, db, endpoint, false);
        inventory.deinit(gpa);
    }

    var ids = std.ArrayList([]u8).empty;
    defer {
        for (ids.items) |id| gpa.free(id);
        ids.deinit(gpa);
    }
    try dbHostingerIds(gpa, db, &ids);
    for (ids.items) |id| {
        var details = try collectVpsDetails(io, gpa, token, db, id, false);
        details.deinit(gpa);
        const vm_endpoints = [_]VmEndpoint{
            .metrics,
            .actions,
            .public_keys,
            .backups,
            .snapshot,
            .monarx,
        };
        for (vm_endpoints) |endpoint| {
            var output = try collectVmEndpoint(io, gpa, token, db, id, endpoint, false);
            output.deinit(gpa);
        }
        try collectDockerProjectGroup(io, gpa, token, db, id);
    }
}

pub fn collectVps(io: Io, gpa: Allocator, token: ?[]const u8, db: *Db, capture_output: bool) !Output {
    const client = clientFromToken(token) catch {
        return try collector_capture.skipped(gpa, db, "hostinger", "vps", null, "missing Hostinger API token", "Hostinger token missing", capture_output);
    };
    const body = try client.getVirtualMachines(io, gpa);
    defer body.deinit(gpa);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "hostinger",
        .kind = "vps",
        .summary_label = "virtual machines",
        .endpoint = provider_hostinger.virtual_machines_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    if (net_http.isOk(body.status)) {
        try db.clear("hostinger_vps");
        try persistVpsRows(gpa, db, redacted);
        try persistResourceRows(gpa, db, "vps", null, redacted);
    }
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectVpsDetails(io: Io, gpa: Allocator, token: ?[]const u8, db: *Db, vm_id: []const u8, capture_output: bool) !Output {
    const client = clientFromToken(token) catch {
        return try collector_capture.skipped(gpa, db, "hostinger", "vps-detail", vm_id, "missing Hostinger API token", "Hostinger token missing", capture_output);
    };
    const body = try client.getVirtualMachineDetails(io, gpa, vm_id);
    defer body.deinit(gpa);
    const endpoint_path = try vpsDetailPath(gpa, vm_id);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "hostinger",
        .kind = "vps-detail",
        .target = vm_id,
        .summary_label = "virtual machine detail",
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    if (net_http.isOk(body.status)) {
        try persistVpsRows(gpa, db, redacted);
        try persistResourceRows(gpa, db, "vps-detail", vm_id, redacted);
    }
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectVmEndpoint(io: Io, gpa: Allocator, token: ?[]const u8, db: *Db, vm_id: []const u8, endpoint: VmEndpoint, capture_output: bool) !Output {
    if (isPaginatedVmEndpoint(endpoint)) return try collectPagedVmEndpoint(io, gpa, token, db, vm_id, endpoint, capture_output);

    const endpoint_label = endpoint.label();
    const client = clientFromToken(token) catch {
        return try collector_capture.skipped(gpa, db, "hostinger", endpoint_label, vm_id, "missing Hostinger API token", "Hostinger token missing", capture_output);
    };
    const body = try client.getVirtualMachineEndpoint(io, gpa, vm_id, endpoint);
    defer body.deinit(gpa);
    const endpoint_path = try vmEndpointPath(gpa, vm_id, endpoint);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "hostinger",
        .kind = endpoint_label,
        .target = vm_id,
        .summary_label = endpoint_label,
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    if (net_http.isOk(body.status)) try persistResourceRows(gpa, db, endpoint_label, vm_id, redacted);
    if (endpoint == .metrics) try db.insertHostingerMetric(vm_id, endpoint_label, null, redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectActionDetails(io: Io, gpa: Allocator, token: ?[]const u8, db: *Db, vm_id: []const u8, action_id: []const u8, capture_output: bool) !Output {
    const target = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ vm_id, action_id });
    defer gpa.free(target);
    const client = clientFromToken(token) catch {
        return try collector_capture.skipped(gpa, db, "hostinger", "action-detail", target, "missing Hostinger API token", "Hostinger token missing", capture_output);
    };
    const body = try client.getActionDetails(io, gpa, vm_id, action_id);
    defer body.deinit(gpa);
    const endpoint_path = try actionDetailPath(gpa, vm_id, action_id);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "hostinger",
        .kind = "action-detail",
        .target = target,
        .summary_label = "action detail",
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    if (net_http.isOk(body.status)) try persistResourceRows(gpa, db, "action-detail", target, redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectDockerEndpoint(io: Io, gpa: Allocator, token: ?[]const u8, db: *Db, vm_id: []const u8, endpoint: DockerEndpoint, project_name: ?[]const u8, capture_output: bool) !Output {
    const endpoint_label = endpoint.label();
    const target = try dockerTarget(gpa, vm_id, project_name);
    defer gpa.free(target);
    const client = clientFromToken(token) catch {
        return try collector_capture.skipped(gpa, db, "hostinger", endpoint_label, target, "missing Hostinger API token", "Hostinger token missing", capture_output);
    };
    const body = try client.getDockerEndpoint(io, gpa, vm_id, endpoint, project_name);
    defer body.deinit(gpa);
    const endpoint_path = try provider_hostinger.dockerEndpointPath(gpa, vm_id, endpoint, project_name);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "hostinger",
        .kind = endpoint_label,
        .target = target,
        .summary_label = endpoint_label,
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    if (net_http.isOk(body.status)) try persistResourceRows(gpa, db, endpoint_label, target, redacted);
    return .{ .text = if (capture_output) redacted else null };
}

fn collectDockerProjectGroup(io: Io, gpa: Allocator, token: ?[]const u8, db: *Db, vm_id: []const u8) !void {
    var projects = try collectDockerEndpoint(io, gpa, token, db, vm_id, .projects, null, true);
    defer projects.deinit(gpa);
    const body = projects.text orelse return;

    var project_names = try provider_hostinger_models.parseDockerProjectNames(gpa, body);
    defer project_names.deinit(gpa);

    for (project_names.items) |project_name| {
        for (docker_project_detail_endpoints) |endpoint| {
            var detail = try collectDockerEndpoint(io, gpa, token, db, vm_id, endpoint, project_name, false);
            detail.deinit(gpa);
        }
    }
}

pub fn collectBillingEndpoint(io: Io, gpa: Allocator, token: ?[]const u8, db: *Db, endpoint: BillingEndpoint, capture_output: bool) !Output {
    const endpoint_label = endpoint.label();
    const client = clientFromToken(token) catch {
        return try collector_capture.skipped(gpa, db, "hostinger", endpoint_label, null, "missing Hostinger API token", "Hostinger token missing", capture_output);
    };
    const body = try client.getBillingEndpoint(io, gpa, endpoint);
    defer body.deinit(gpa);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "hostinger",
        .kind = endpoint_label,
        .summary_label = endpoint_label,
        .endpoint = endpoint.path(),
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    if (net_http.isOk(body.status)) try persistResourceRows(gpa, db, endpoint_label, null, redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectDnsEndpoint(io: Io, gpa: Allocator, token: ?[]const u8, db: *Db, endpoint: DnsEndpoint, domain: []const u8, snapshot_id: ?[]const u8, capture_output: bool) !Output {
    const endpoint_label = endpoint.label();
    const target = try dnsTarget(gpa, domain, snapshot_id);
    defer gpa.free(target);
    const client = clientFromToken(token) catch {
        return try collector_capture.skipped(gpa, db, "hostinger", endpoint_label, target, "missing Hostinger API token", "Hostinger token missing", capture_output);
    };
    const body = try client.getDnsEndpoint(io, gpa, endpoint, domain, snapshot_id);
    defer body.deinit(gpa);
    const endpoint_path = try provider_hostinger.dnsEndpointPath(gpa, endpoint, domain, snapshot_id);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "hostinger",
        .kind = endpoint_label,
        .target = target,
        .summary_label = endpoint_label,
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    if (net_http.isOk(body.status)) try persistResourceRows(gpa, db, endpoint_label, target, redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectDomainEndpoint(io: Io, gpa: Allocator, token: ?[]const u8, db: *Db, endpoint: DomainEndpoint, path_arg: ?[]const u8, tld: ?[]const u8, capture_output: bool) !Output {
    const endpoint_label = endpoint.label();
    const target = try domainTarget(gpa, path_arg, tld);
    defer if (target) |value| gpa.free(value);
    const client = clientFromToken(token) catch {
        return try collector_capture.skipped(gpa, db, "hostinger", endpoint_label, target, "missing Hostinger API token", "Hostinger token missing", capture_output);
    };
    const body = try client.getDomainEndpoint(io, gpa, endpoint, path_arg, tld);
    defer body.deinit(gpa);
    const endpoint_path = try provider_hostinger.domainEndpointPath(gpa, endpoint, path_arg, tld);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "hostinger",
        .kind = endpoint_label,
        .target = target,
        .summary_label = endpoint_label,
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    if (net_http.isOk(body.status)) try persistResourceRows(gpa, db, endpoint_label, target, redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectHostingEndpoint(io: Io, gpa: Allocator, token: ?[]const u8, db: *Db, endpoint: HostingEndpoint, args: HostingArgs, capture_output: bool) !Output {
    if (isPaginatedHostingEndpoint(endpoint)) return try collectPagedHostingEndpoint(io, gpa, token, db, endpoint, args, capture_output);

    const endpoint_label = endpoint.label();
    const target = try hostingTarget(gpa, args);
    defer if (target) |value| gpa.free(value);
    const client = clientFromToken(token) catch {
        return try collector_capture.skipped(gpa, db, "hostinger", endpoint_label, target, "missing Hostinger API token", "Hostinger token missing", capture_output);
    };
    const body = try client.getHostingEndpoint(io, gpa, endpoint, args);
    defer body.deinit(gpa);
    const endpoint_path = try provider_hostinger.hostingEndpointPath(gpa, endpoint, args);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "hostinger",
        .kind = endpoint_label,
        .target = target,
        .summary_label = endpoint_label,
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    if (net_http.isOk(body.status)) try persistResourceRows(gpa, db, endpoint_label, target, redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectEcommerceEndpoint(io: Io, gpa: Allocator, token: ?[]const u8, db: *Db, endpoint: EcommerceEndpoint, capture_output: bool) !Output {
    return try collectPagedEcommerceEndpoint(io, gpa, token, db, endpoint, capture_output);
}

pub fn collectHorizonsEndpoint(io: Io, gpa: Allocator, token: ?[]const u8, db: *Db, endpoint: HorizonsEndpoint, website_id: []const u8, capture_output: bool) !Output {
    const endpoint_label = endpoint.label();
    const client = clientFromToken(token) catch {
        return try collector_capture.skipped(gpa, db, "hostinger", endpoint_label, website_id, "missing Hostinger API token", "Hostinger token missing", capture_output);
    };
    const body = try client.getHorizonsEndpoint(io, gpa, endpoint, website_id);
    defer body.deinit(gpa);
    const endpoint_path = try provider_hostinger.horizonsEndpointPath(gpa, endpoint, website_id);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "hostinger",
        .kind = endpoint_label,
        .target = website_id,
        .summary_label = endpoint_label,
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    if (net_http.isOk(body.status)) try persistResourceRows(gpa, db, endpoint_label, website_id, redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectReachEndpoint(io: Io, gpa: Allocator, token: ?[]const u8, db: *Db, endpoint: ReachEndpoint, args: ReachArgs, capture_output: bool) !Output {
    if (isPaginatedReachEndpoint(endpoint)) return try collectPagedReachEndpoint(io, gpa, token, db, endpoint, args, capture_output);

    const endpoint_label = endpoint.label();
    const target = try reachTarget(gpa, args);
    defer if (target) |value| gpa.free(value);
    const client = clientFromToken(token) catch {
        return try collector_capture.skipped(gpa, db, "hostinger", endpoint_label, target, "missing Hostinger API token", "Hostinger token missing", capture_output);
    };
    const body = try client.getReachEndpoint(io, gpa, endpoint, args);
    defer body.deinit(gpa);
    const endpoint_path = try provider_hostinger.reachEndpointPath(gpa, endpoint, args);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "hostinger",
        .kind = endpoint_label,
        .target = target,
        .summary_label = endpoint_label,
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    if (net_http.isOk(body.status)) try persistResourceRows(gpa, db, endpoint_label, target, redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectVpsInventoryEndpoint(io: Io, gpa: Allocator, token: ?[]const u8, db: *Db, endpoint: VpsInventoryEndpoint, capture_output: bool) !Output {
    if (isPaginatedVpsInventoryEndpoint(endpoint)) return try collectPagedVpsInventoryEndpoint(io, gpa, token, db, endpoint, capture_output);

    const endpoint_label = endpoint.label();
    const client = clientFromToken(token) catch {
        return try collector_capture.skipped(gpa, db, "hostinger", endpoint_label, null, "missing Hostinger API token", "Hostinger token missing", capture_output);
    };
    const body = try client.getVpsInventoryEndpoint(io, gpa, endpoint);
    defer body.deinit(gpa);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "hostinger",
        .kind = endpoint_label,
        .summary_label = endpoint_label,
        .endpoint = endpoint.path(),
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    if (net_http.isOk(body.status)) try persistResourceRows(gpa, db, endpoint_label, null, redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn collectVpsInventoryDetail(io: Io, gpa: Allocator, token: ?[]const u8, db: *Db, endpoint: VpsInventoryDetailEndpoint, id: []const u8, capture_output: bool) !Output {
    const endpoint_label = endpoint.label();
    const client = clientFromToken(token) catch {
        return try collector_capture.skipped(gpa, db, "hostinger", endpoint_label, id, "missing Hostinger API token", "Hostinger token missing", capture_output);
    };
    const body = try client.getVpsInventoryDetail(io, gpa, endpoint, id);
    defer body.deinit(gpa);
    const endpoint_path = try provider_hostinger.vpsInventoryDetailPath(gpa, endpoint, id);
    defer gpa.free(endpoint_path);
    const redacted = try collector_capture.storeResponse(gpa, db, .{
        .provider = "hostinger",
        .kind = endpoint_label,
        .target = id,
        .summary_label = endpoint_label,
        .endpoint = endpoint_path,
        .status = body.status,
        .body = body.body,
    });
    defer if (!capture_output) gpa.free(redacted);
    if (net_http.isOk(body.status)) try persistResourceRows(gpa, db, endpoint_label, id, redacted);
    return .{ .text = if (capture_output) redacted else null };
}

pub fn persistVpsRows(gpa: Allocator, db: *Db, body: []const u8) !void {
    var rows = try provider_hostinger_models.parseVpsRows(gpa, body);
    defer rows.deinit(gpa);
    for (rows.items) |row| {
        try db.upsertHostingerVps(row.id, row.name, row.status, row.ipv4, row.plan, row.raw_json);
    }
}

pub fn persistResourceRows(gpa: Allocator, db: *Db, kind: []const u8, target: ?[]const u8, body: []const u8) !void {
    _ = try collector_capture_normalize.persistHostingerResourceRows(gpa, db, kind, target, body);
}

pub fn persistInventoryRows(gpa: Allocator, db: *Db, kind: []const u8, target: ?[]const u8, body: []const u8) !void {
    _ = try collector_capture_normalize.persistHostingerInventoryRows(gpa, db, kind, target, body);
}

fn collectPagedVmEndpoint(io: Io, gpa: Allocator, token: ?[]const u8, db: *Db, vm_id: []const u8, endpoint: VmEndpoint, capture_output: bool) !Output {
    const endpoint_label = endpoint.label();
    const client = clientFromToken(token) catch {
        return try collector_capture.skipped(gpa, db, "hostinger", endpoint_label, vm_id, "missing Hostinger API token", "Hostinger token missing", capture_output);
    };

    var pages = std.ArrayList([]u8).empty;
    defer {
        for (pages.items) |page_body| gpa.free(page_body);
        pages.deinit(gpa);
    }

    var page: usize = 1;
    while (page <= max_hostinger_pages) : (page += 1) {
        const body = try client.getVirtualMachineEndpointPage(io, gpa, vm_id, endpoint, page);
        defer body.deinit(gpa);
        const target = try pageTarget(gpa, vm_id, page);
        defer gpa.free(target);
        const summary_label = try pageSummaryLabel(gpa, endpoint_label, page);
        defer gpa.free(summary_label);
        const endpoint_path = try vmEndpointPathPage(gpa, vm_id, endpoint, page);
        defer gpa.free(endpoint_path);
        const redacted = try collector_capture.storeResponse(gpa, db, .{
            .provider = "hostinger",
            .kind = endpoint_label,
            .target = target,
            .summary_label = summary_label,
            .endpoint = endpoint_path,
            .status = body.status,
            .body = body.body,
        });
        errdefer gpa.free(redacted);
        try pages.append(gpa, redacted);
        if (!net_http.isOk(body.status)) break;
        try persistResourceRows(gpa, db, endpoint_label, vm_id, redacted);
        const pagination = provider_hostinger_models.paginationInfo(redacted) orelse break;
        if (!pagination.hasNext()) break;
    }

    return try outputPages(gpa, capture_output, pages.items);
}

fn collectPagedVpsInventoryEndpoint(io: Io, gpa: Allocator, token: ?[]const u8, db: *Db, endpoint: VpsInventoryEndpoint, capture_output: bool) !Output {
    const endpoint_label = endpoint.label();
    const client = clientFromToken(token) catch {
        return try collector_capture.skipped(gpa, db, "hostinger", endpoint_label, null, "missing Hostinger API token", "Hostinger token missing", capture_output);
    };

    var pages = std.ArrayList([]u8).empty;
    defer {
        for (pages.items) |page_body| gpa.free(page_body);
        pages.deinit(gpa);
    }

    var page: usize = 1;
    while (page <= max_hostinger_pages) : (page += 1) {
        const body = try client.getVpsInventoryEndpointPage(io, gpa, endpoint, page);
        defer body.deinit(gpa);
        const summary_label = try pageSummaryLabel(gpa, endpoint_label, page);
        defer gpa.free(summary_label);
        const target = try optionalPageTarget(gpa, page);
        defer if (target) |value| gpa.free(value);
        const endpoint_path = try vpsInventoryPathPage(gpa, endpoint, page);
        defer gpa.free(endpoint_path);
        const redacted = try collector_capture.storeResponse(gpa, db, .{
            .provider = "hostinger",
            .kind = endpoint_label,
            .target = target,
            .summary_label = summary_label,
            .endpoint = endpoint_path,
            .status = body.status,
            .body = body.body,
        });
        errdefer gpa.free(redacted);
        try pages.append(gpa, redacted);
        if (!net_http.isOk(body.status)) break;
        try persistResourceRows(gpa, db, endpoint_label, null, redacted);
        const pagination = provider_hostinger_models.paginationInfo(redacted) orelse break;
        if (!pagination.hasNext()) break;
    }

    return try outputPages(gpa, capture_output, pages.items);
}

fn collectPagedHostingEndpoint(io: Io, gpa: Allocator, token: ?[]const u8, db: *Db, endpoint: HostingEndpoint, args: HostingArgs, capture_output: bool) !Output {
    const endpoint_label = endpoint.label();
    const client = clientFromToken(token) catch {
        const target = try hostingTarget(gpa, args);
        defer if (target) |value| gpa.free(value);
        return try collector_capture.skipped(gpa, db, "hostinger", endpoint_label, target, "missing Hostinger API token", "Hostinger token missing", capture_output);
    };

    var pages = std.ArrayList([]u8).empty;
    defer {
        for (pages.items) |page_body| gpa.free(page_body);
        pages.deinit(gpa);
    }

    var page: usize = 1;
    while (page <= max_hostinger_pages) : (page += 1) {
        const body = try client.getHostingEndpointPage(io, gpa, endpoint, args, page);
        defer body.deinit(gpa);
        const base_target = try hostingTarget(gpa, args);
        defer if (base_target) |value| gpa.free(value);
        const target = try optionalPagedTarget(gpa, base_target, page);
        defer if (target) |value| gpa.free(value);
        const summary_label = try pageSummaryLabel(gpa, endpoint_label, page);
        defer gpa.free(summary_label);
        const endpoint_path = try provider_hostinger.hostingEndpointPath(gpa, endpoint, args);
        defer gpa.free(endpoint_path);
        const page_path = try provider_hostinger.pageUrl(gpa, endpoint_path, page);
        defer gpa.free(page_path);
        const redacted = try collector_capture.storeResponse(gpa, db, .{
            .provider = "hostinger",
            .kind = endpoint_label,
            .target = target,
            .summary_label = summary_label,
            .endpoint = page_path,
            .status = body.status,
            .body = body.body,
        });
        errdefer gpa.free(redacted);
        try pages.append(gpa, redacted);
        if (!net_http.isOk(body.status)) break;
        try persistResourceRows(gpa, db, endpoint_label, base_target, redacted);
        const pagination = provider_hostinger_models.paginationInfo(redacted) orelse break;
        if (!pagination.hasNext()) break;
    }

    return try outputPages(gpa, capture_output, pages.items);
}

fn collectPagedEcommerceEndpoint(io: Io, gpa: Allocator, token: ?[]const u8, db: *Db, endpoint: EcommerceEndpoint, capture_output: bool) !Output {
    const endpoint_label = endpoint.label();
    const client = clientFromToken(token) catch {
        return try collector_capture.skipped(gpa, db, "hostinger", endpoint_label, null, "missing Hostinger API token", "Hostinger token missing", capture_output);
    };

    var pages = std.ArrayList([]u8).empty;
    defer {
        for (pages.items) |page_body| gpa.free(page_body);
        pages.deinit(gpa);
    }

    var page: usize = 1;
    while (page <= max_hostinger_pages) : (page += 1) {
        const body = try client.getEcommerceEndpointPage(io, gpa, endpoint, page);
        defer body.deinit(gpa);
        const target = try optionalPageTarget(gpa, page);
        defer if (target) |value| gpa.free(value);
        const summary_label = try pageSummaryLabel(gpa, endpoint_label, page);
        defer gpa.free(summary_label);
        const page_path = try provider_hostinger.pageUrl(gpa, endpoint.path(), page);
        defer gpa.free(page_path);
        const redacted = try collector_capture.storeResponse(gpa, db, .{
            .provider = "hostinger",
            .kind = endpoint_label,
            .target = target,
            .summary_label = summary_label,
            .endpoint = page_path,
            .status = body.status,
            .body = body.body,
        });
        errdefer gpa.free(redacted);
        try pages.append(gpa, redacted);
        if (!net_http.isOk(body.status)) break;
        try persistResourceRows(gpa, db, endpoint_label, null, redacted);
        const pagination = provider_hostinger_models.paginationInfo(redacted) orelse break;
        if (!pagination.hasNext()) break;
    }

    return try outputPages(gpa, capture_output, pages.items);
}

fn collectPagedReachEndpoint(io: Io, gpa: Allocator, token: ?[]const u8, db: *Db, endpoint: ReachEndpoint, args: ReachArgs, capture_output: bool) !Output {
    const endpoint_label = endpoint.label();
    const client = clientFromToken(token) catch {
        const target = try reachTarget(gpa, args);
        defer if (target) |value| gpa.free(value);
        return try collector_capture.skipped(gpa, db, "hostinger", endpoint_label, target, "missing Hostinger API token", "Hostinger token missing", capture_output);
    };

    var pages = std.ArrayList([]u8).empty;
    defer {
        for (pages.items) |page_body| gpa.free(page_body);
        pages.deinit(gpa);
    }

    var page: usize = 1;
    while (page <= max_hostinger_pages) : (page += 1) {
        const body = try client.getReachEndpointPage(io, gpa, endpoint, args, page);
        defer body.deinit(gpa);
        const base_target = try reachTarget(gpa, args);
        defer if (base_target) |value| gpa.free(value);
        const target = try optionalPagedTarget(gpa, base_target, page);
        defer if (target) |value| gpa.free(value);
        const summary_label = try pageSummaryLabel(gpa, endpoint_label, page);
        defer gpa.free(summary_label);
        const endpoint_path = try provider_hostinger.reachEndpointPath(gpa, endpoint, args);
        defer gpa.free(endpoint_path);
        const page_path = try provider_hostinger.pageUrl(gpa, endpoint_path, page);
        defer gpa.free(page_path);
        const redacted = try collector_capture.storeResponse(gpa, db, .{
            .provider = "hostinger",
            .kind = endpoint_label,
            .target = target,
            .summary_label = summary_label,
            .endpoint = page_path,
            .status = body.status,
            .body = body.body,
        });
        errdefer gpa.free(redacted);
        try pages.append(gpa, redacted);
        if (!net_http.isOk(body.status)) break;
        try persistResourceRows(gpa, db, endpoint_label, base_target, redacted);
        const pagination = provider_hostinger_models.paginationInfo(redacted) orelse break;
        if (!pagination.hasNext()) break;
    }

    return try outputPages(gpa, capture_output, pages.items);
}

fn clientFromToken(token: ?[]const u8) !provider_hostinger.Client {
    const value = token orelse return error.MissingHostingerToken;
    if (value.len == 0) return error.MissingHostingerToken;
    return provider_hostinger.Client.init(value);
}

fn outputPages(gpa: Allocator, capture_output: bool, pages: []const []const u8) !Output {
    if (!capture_output) return .{};
    if (pages.len == 0) return try collector_capture.outputText(gpa, true, "");
    if (pages.len == 1) return try collector_capture.outputText(gpa, true, pages[0]);
    return .{ .text = try provider_hostinger_models.mergePaginatedBodies(gpa, pages) };
}

fn dockerTarget(gpa: Allocator, vm_id: []const u8, project_name: ?[]const u8) ![]u8 {
    if (project_name) |project| return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ vm_id, project });
    return try gpa.dupe(u8, vm_id);
}

fn dnsTarget(gpa: Allocator, domain: []const u8, snapshot_id: ?[]const u8) ![]u8 {
    if (snapshot_id) |id| return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ domain, id });
    return try gpa.dupe(u8, domain);
}

fn domainTarget(gpa: Allocator, path_arg: ?[]const u8, tld: ?[]const u8) !?[]u8 {
    if (path_arg) |value| return try gpa.dupe(u8, value);
    if (tld) |value| return try std.fmt.allocPrint(gpa, "tld={s}", .{value});
    return null;
}

fn hostingTarget(gpa: Allocator, args: HostingArgs) !?[]u8 {
    if (args.username) |username| {
        if (args.domain) |domain| {
            if (args.uuid) |uuid| return try std.fmt.allocPrint(gpa, "{s}/{s}/{s}", .{ username, domain, uuid });
            return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ username, domain });
        }
        if (args.name) |name| return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ username, name });
        return try gpa.dupe(u8, username);
    }
    if (args.order_id) |order_id| return try std.fmt.allocPrint(gpa, "order_id={s}", .{order_id});
    return null;
}

fn reachTarget(gpa: Allocator, args: ReachArgs) !?[]u8 {
    if (args.profile_uuid) |profile_uuid| {
        if (args.segment_uuid) |segment_uuid| return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ profile_uuid, segment_uuid });
        return try gpa.dupe(u8, profile_uuid);
    }
    if (args.segment_uuid) |segment_uuid| return try gpa.dupe(u8, segment_uuid);
    return null;
}

fn optionalPagedTarget(gpa: Allocator, base: ?[]const u8, page: usize) !?[]u8 {
    if (base) |value| {
        if (page <= 1) return try gpa.dupe(u8, value);
        return try std.fmt.allocPrint(gpa, "{s}?page={d}", .{ value, page });
    }
    return try optionalPageTarget(gpa, page);
}

fn dbHostingerIds(gpa: Allocator, db: *Db, out: *std.ArrayList([]u8)) !void {
    const stmt = try db.prepare("SELECT id FROM hostinger_vps ORDER BY id");
    defer _ = sqlite.sqlite3_finalize(stmt);
    while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
        if (columnText(stmt, 0)) |id| try out.append(gpa, try gpa.dupe(u8, id));
    }
}

fn vpsDetailPath(gpa: Allocator, vm_id: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ provider_hostinger.virtual_machines_path, vm_id });
}

fn vmEndpointPath(gpa: Allocator, vm_id: []const u8, endpoint: VmEndpoint) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/{s}/{s}", .{ provider_hostinger.virtual_machines_path, vm_id, endpoint.label() });
}

fn vmEndpointPathPage(gpa: Allocator, vm_id: []const u8, endpoint: VmEndpoint, page: usize) ![]u8 {
    const path = try vmEndpointPath(gpa, vm_id, endpoint);
    defer gpa.free(path);
    return try provider_hostinger.pageUrl(gpa, path, page);
}

fn actionDetailPath(gpa: Allocator, vm_id: []const u8, action_id: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/{s}/actions/{s}", .{ provider_hostinger.virtual_machines_path, vm_id, action_id });
}

fn vpsInventoryPathPage(gpa: Allocator, endpoint: VpsInventoryEndpoint, page: usize) ![]u8 {
    return try provider_hostinger.pageUrl(gpa, endpoint.path(), page);
}

fn pageTarget(gpa: Allocator, target: []const u8, page: usize) ![]u8 {
    if (page <= 1) return try gpa.dupe(u8, target);
    return try std.fmt.allocPrint(gpa, "{s}?page={d}", .{ target, page });
}

fn optionalPageTarget(gpa: Allocator, page: usize) !?[]u8 {
    if (page <= 1) return null;
    return try std.fmt.allocPrint(gpa, "page={d}", .{page});
}

fn pageSummaryLabel(gpa: Allocator, label: []const u8, page: usize) ![]u8 {
    if (page <= 1) return try gpa.dupe(u8, label);
    return try std.fmt.allocPrint(gpa, "{s} page {d}", .{ label, page });
}

fn isPaginatedVmEndpoint(endpoint: VmEndpoint) bool {
    return switch (endpoint) {
        .actions, .public_keys, .backups => true,
        .metrics, .snapshot, .monarx, .docker => false,
    };
}

fn isPaginatedVpsInventoryEndpoint(endpoint: VpsInventoryEndpoint) bool {
    return switch (endpoint) {
        .firewalls, .public_keys, .post_install_scripts => true,
        .data_centers, .templates => false,
    };
}

fn isPaginatedHostingEndpoint(endpoint: HostingEndpoint) bool {
    return switch (endpoint) {
        .orders, .websites, .databases, .nodejs_builds => true,
        .wordpress, .datacenters, .phpmyadmin_link, .parked_domains, .subdomains, .nodejs_logs => false,
    };
}

fn isPaginatedReachEndpoint(endpoint: ReachEndpoint) bool {
    return switch (endpoint) {
        .contacts, .segment_contacts, .profile_segment_contacts => true,
        .profiles, .segments, .segment => false,
    };
}

test "persists Hostinger VPS rows without nested template rows" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/hostinger.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    try persistVpsRows(allocator, &db,
        \\[{
        \\  "id": 1307809,
        \\  "plan": "KVM 4",
        \\  "hostname": "srv1307809.hstgr.cloud",
        \\  "state": "running",
        \\  "ipv4": [{"id": 1389040, "address": "76.13.130.170"}],
        \\  "template": {"id": 1034, "name": "Arch Linux"}
        \\}]
    );

    try std.testing.expectEqual(@as(i64, 1), try db.countTable("hostinger_vps"));
    const stmt = try db.prepare("SELECT id, name, status, ipv4, plan FROM hostinger_vps");
    defer _ = sqlite.sqlite3_finalize(stmt);
    try std.testing.expectEqual(@as(c_int, sqlite.SQLITE_ROW), sqlite.sqlite3_step(stmt));
    try std.testing.expectEqualStrings("1307809", columnText(stmt, 0) orelse "");
    try std.testing.expectEqualStrings("srv1307809.hstgr.cloud", columnText(stmt, 1) orelse "");
    try std.testing.expectEqualStrings("running", columnText(stmt, 2) orelse "");
    try std.testing.expectEqualStrings("76.13.130.170", columnText(stmt, 3) orelse "");
    try std.testing.expectEqualStrings("KVM 4", columnText(stmt, 4) orelse "");
}

test "persists normalized Hostinger resource rows" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/hostinger-resources.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    try persistResourceRows(allocator, &db, "hostinger-websites", null,
        \\{"data":[{"domain":"plosca.ru","username":"u123","is_enabled":true},{"domain":"sparkdate.love","username":"u123","is_enabled":false}]}
    );
    try persistResourceRows(allocator, &db, "hostinger-dns-zone", "plosca.ru",
        \\[{"name":"@","type":"A","ttl":14400,"records":[{"content":"1.2.3.4"}]}]
    );

    try std.testing.expectEqual(@as(i64, 3), try db.countTable("hostinger_resources"));
    try std.testing.expectEqual(@as(i64, 3), try db.countTable("hostinger_inventory_items"));
    const stmt = try db.prepare("SELECT resource_id, name, status, domain FROM hostinger_resources WHERE kind = 'hostinger-websites' ORDER BY resource_id LIMIT 1");
    defer _ = sqlite.sqlite3_finalize(stmt);
    try std.testing.expectEqual(@as(c_int, sqlite.SQLITE_ROW), sqlite.sqlite3_step(stmt));
    try std.testing.expectEqualStrings("plosca.ru", columnText(stmt, 0) orelse "");
    try std.testing.expectEqualStrings("plosca.ru", columnText(stmt, 1) orelse "");
    try std.testing.expectEqualStrings("enabled", columnText(stmt, 2) orelse "");
    try std.testing.expectEqualStrings("plosca.ru", columnText(stmt, 3) orelse "");

    const inventory_stmt = try db.prepare("SELECT resource_id, category, domain, flag, related_id FROM hostinger_inventory_items WHERE kind = 'hostinger-dns-zone' LIMIT 1");
    defer _ = sqlite.sqlite3_finalize(inventory_stmt);
    try std.testing.expectEqual(@as(c_int, sqlite.SQLITE_ROW), sqlite.sqlite3_step(inventory_stmt));
    try std.testing.expectEqualStrings("@|A", columnText(inventory_stmt, 0) orelse "");
    try std.testing.expectEqualStrings("A", columnText(inventory_stmt, 1) orelse "");
    try std.testing.expectEqualStrings("plosca.ru", columnText(inventory_stmt, 2) orelse "");
    try std.testing.expectEqualStrings("", columnText(inventory_stmt, 3) orelse "");
    try std.testing.expectEqualStrings("1.2.3.4", columnText(inventory_stmt, 4) orelse "");
}

test "persists typed Hostinger Docker project inventory rows" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/hostinger-docker-inventory.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    try persistResourceRows(allocator, &db, "docker", "1307809",
        \\{"data":[
        \\  {"projectName":"cloudio-stack","status":"running"},
        \\  {"project_name":"worker-stack","state":"stopped","containers":[{"id":"ctr-1","name":"worker","status":"running"}]},
        \\  {"logs":"pulled image\\nstarted worker\\n","lines":2},
        \\  {"line":"worker log line"}
        \\]}
    );

    try std.testing.expectEqual(@as(i64, 3), try db.countTable("hostinger_resources"));
    try std.testing.expectEqual(@as(i64, 5), try db.countTable("hostinger_inventory_items"));
    const project_stmt = try db.prepare("SELECT resource_id, status FROM hostinger_inventory_items WHERE kind = 'docker' AND resource_id = 'cloudio-stack'");
    defer _ = sqlite.sqlite3_finalize(project_stmt);
    try std.testing.expectEqual(@as(c_int, sqlite.SQLITE_ROW), sqlite.sqlite3_step(project_stmt));
    try std.testing.expectEqualStrings("cloudio-stack", columnText(project_stmt, 0) orelse "");
    try std.testing.expectEqualStrings("running", columnText(project_stmt, 1) orelse "");

    const container_stmt = try db.prepare("SELECT resource_id, display_name, status FROM hostinger_inventory_items WHERE kind = 'docker' AND resource_id = 'ctr-1'");
    defer _ = sqlite.sqlite3_finalize(container_stmt);
    try std.testing.expectEqual(@as(c_int, sqlite.SQLITE_ROW), sqlite.sqlite3_step(container_stmt));
    try std.testing.expectEqualStrings("ctr-1", columnText(container_stmt, 0) orelse "");
    try std.testing.expectEqualStrings("worker", columnText(container_stmt, 1) orelse "");
    try std.testing.expectEqualStrings("running", columnText(container_stmt, 2) orelse "");

    const log_stmt = try db.prepare("SELECT resource_id FROM hostinger_inventory_items WHERE kind = 'docker' AND resource_id = 'worker log line'");
    defer _ = sqlite.sqlite3_finalize(log_stmt);
    try std.testing.expectEqual(@as(c_int, sqlite.SQLITE_ROW), sqlite.sqlite3_step(log_stmt));
    try std.testing.expectEqualStrings("worker log line", columnText(log_stmt, 0) orelse "");
}

test "missing Hostinger token records inventory snapshot without live API call" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/hostinger-inventory.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    var output = try collectVpsInventoryEndpoint(std.testing.io, allocator, null, &db, .templates, true);
    defer output.deinit(allocator);
    try std.testing.expectEqualStrings("Hostinger token missing", output.text orelse "");
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("snapshots"));
}

test "missing Hostinger token records inventory detail snapshot without live API call" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/hostinger-inventory-detail.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    var output = try collectVpsInventoryDetail(std.testing.io, allocator, null, &db, .template, "1034", true);
    defer output.deinit(allocator);
    try std.testing.expectEqualStrings("Hostinger token missing", output.text orelse "");
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("snapshots"));
}

test "missing Hostinger token records docker snapshot without live API call" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/hostinger-docker.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    var output = try collectDockerEndpoint(std.testing.io, allocator, null, &db, "1307809", .containers, "my app", true);
    defer output.deinit(allocator);
    try std.testing.expectEqualStrings("Hostinger token missing", output.text orelse "");
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("snapshots"));
}

test "missing Hostinger token records billing snapshot without live API call" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/hostinger-billing.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    var output = try collectBillingEndpoint(std.testing.io, allocator, null, &db, .subscriptions, true);
    defer output.deinit(allocator);
    try std.testing.expectEqualStrings("Hostinger token missing", output.text orelse "");
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("snapshots"));
}

test "missing Hostinger token records dns snapshot without live API call" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/hostinger-dns.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    var output = try collectDnsEndpoint(std.testing.io, allocator, null, &db, .snapshot, "plosca.ru", "1234", true);
    defer output.deinit(allocator);
    try std.testing.expectEqualStrings("Hostinger token missing", output.text orelse "");
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("snapshots"));
}

test "missing Hostinger token records domain snapshot without live API call" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/hostinger-domains.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    var output = try collectDomainEndpoint(std.testing.io, allocator, null, &db, .whois_usage, "564651", null, true);
    defer output.deinit(allocator);
    try std.testing.expectEqualStrings("Hostinger token missing", output.text orelse "");
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("snapshots"));
}

test "missing Hostinger token records hosting snapshot without live API call" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/hostinger-hosting.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    var output = try collectHostingEndpoint(std.testing.io, allocator, null, &db, .nodejs_logs, .{ .username = "user", .domain = "plosca.ru", .uuid = "build" }, true);
    defer output.deinit(allocator);
    try std.testing.expectEqualStrings("Hostinger token missing", output.text orelse "");
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("snapshots"));
}

test "missing Hostinger token records ecommerce snapshot without live API call" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/hostinger-ecommerce.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    var output = try collectEcommerceEndpoint(std.testing.io, allocator, null, &db, .stores, true);
    defer output.deinit(allocator);
    try std.testing.expectEqualStrings("Hostinger token missing", output.text orelse "");
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("snapshots"));
}

test "missing Hostinger token records horizons snapshot without live API call" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/hostinger-horizons.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    var output = try collectHorizonsEndpoint(std.testing.io, allocator, null, &db, .website, "site-id", true);
    defer output.deinit(allocator);
    try std.testing.expectEqualStrings("Hostinger token missing", output.text orelse "");
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("snapshots"));
}

test "missing Hostinger token records reach snapshot without live API call" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/hostinger-reach.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    var output = try collectReachEndpoint(std.testing.io, allocator, null, &db, .profile_segment_contacts, .{ .profile_uuid = "profile", .segment_uuid = "segment" }, true);
    defer output.deinit(allocator);
    try std.testing.expectEqualStrings("Hostinger token missing", output.text orelse "");
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("snapshots"));
}
