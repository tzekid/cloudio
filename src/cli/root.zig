const std = @import("std");
const app_doctor = @import("app_doctor");
const app_export = @import("app_export");
const app_init = @import("app_init");
const app_log = @import("app_log");
const app_overview = @import("app_overview");
const app_refresh = @import("app_refresh");
const core_config = @import("core_config");
const cloudio = @import("cloudio");
const cli_caddy = @import("cli_caddy");
const cli_cloudflare = @import("cli_cloudflare");
const cli_coverage = @import("cli_coverage");
const cli_hostinger = @import("cli_hostinger");
const cli_projects = @import("cli_projects");
const cli_system = @import("cli_system");
const db_store = @import("db_store");

const Io = std.Io;
const Allocator = std.mem.Allocator;
const Config = core_config.Config;
const Db = db_store.Db;

const version = cloudio.version;

pub fn run(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 2) {
        usage();
        return;
    }

    const cfg = try Config.load(init.io, arena, init.environ_map);
    var db = try Db.open(init.io, cfg.db_path);
    defer db.close();
    try db.initSchema();

    const cmd = args[1];
    if (std.mem.eql(u8, cmd, "help") or std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "-h")) {
        usage();
    } else if (std.mem.eql(u8, cmd, "init")) {
        try commandInit(init.io, init.gpa, cfg, &db);
    } else if (std.mem.eql(u8, cmd, "doctor")) {
        try commandDoctor(init.io, init.gpa, cfg, &db);
    } else if (std.mem.eql(u8, cmd, "refresh")) {
        try commandRefresh(init.io, init.gpa, cfg, &db, args[2..]);
    } else if (std.mem.eql(u8, cmd, "overview")) {
        try commandOverview(init.gpa, &db);
    } else if (std.mem.eql(u8, cmd, "export")) {
        try commandExport(init.gpa, &db);
    } else if (std.mem.eql(u8, cmd, "coverage")) {
        try cli_coverage.run(.{
            .io = init.io,
            .gpa = init.gpa,
        }, args[2..]);
    } else if (std.mem.eql(u8, cmd, "log")) {
        try commandLog(init.io, init.gpa, cfg);
    } else if (std.mem.eql(u8, cmd, "cloudflare")) {
        try cli_cloudflare.run(.{
            .io = init.io,
            .gpa = init.gpa,
            .auth = cloudflareAuth(cfg),
            .domains = cfg.domains,
            .db = &db,
        }, args[2..]);
    } else if (std.mem.eql(u8, cmd, "hostinger")) {
        try cli_hostinger.run(.{
            .io = init.io,
            .gpa = init.gpa,
            .token = cfg.hostinger_api_token,
            .domains = cfg.domains,
            .db = &db,
        }, args[2..]);
    } else if (std.mem.eql(u8, cmd, "caddy")) {
        try cli_caddy.run(.{
            .io = init.io,
            .gpa = init.gpa,
            .paths = caddyPaths(cfg),
            .db = &db,
        }, args[2..]);
    } else if (std.mem.eql(u8, cmd, "system")) {
        try cli_system.run(.{
            .io = init.io,
            .gpa = init.gpa,
            .db = &db,
        }, args[2..]);
    } else if (std.mem.eql(u8, cmd, "projects")) {
        try cli_projects.run(.{
            .io = init.io,
            .gpa = init.gpa,
            .projects_root = cfg.projects_root,
            .db = &db,
        }, args[2..]);
    } else {
        std.debug.print("unknown command: {s}\n\n", .{cmd});
        usage();
        return error.InvalidCliCommand;
    }
}

fn usage() void {
    std.debug.print(
        \\cloudio {s}
        \\
        \\Usage:
        \\  cloudio init
        \\  cloudio doctor
        \\  cloudio refresh [--all|--cloudflare|--hostinger|--caddy|--system|--projects]
        \\  cloudio overview
        \\  cloudio export
        \\  cloudio coverage summary|tags|routes [all|cloudflare|hostinger] [tag-query] [--support <status>] [--mode <mode>]
        \\  cloudio log
        \\  cloudio cloudflare account [list]|account show <account-id>|account profile <account-id>|account organizations <account-id>
        \\  cloudio cloudflare account dns-record-usage <account-id>
        \\  cloudio cloudflare account members|roles <account-id>|account member|role <account-id> <resource-id>
        \\  cloudio cloudflare account tokens|token-permission-groups|token-verify <account-id>
        \\  cloudio cloudflare account token <account-id> <token-id>
        \\  cloudio cloudflare account permission-groups|resource-groups|user-groups <account-id>
        \\  cloudio cloudflare account permission-group|resource-group|user-group <account-id> <resource-id>
        \\  cloudio cloudflare account user-group-members <account-id> <user-group-id>
        \\  cloudio cloudflare account user-group-member <account-id> <user-group-id> <member-id>
        \\  cloudio cloudflare ips [jdcloud]|user|tenants|memberships|membership <membership-id>|token [list]|token show <token-id>|token verify|token permission-groups|zone [domain]|zone show <zone-id>|setting <setting-id> [domain]|diagnose [domain]
        \\  cloudio cloudflare zone available-plans|available-rate-plans|cache-reserve|cache-reserve-clear|regional-tiered-cache|variants|environments|hold|subscription <zone-id>
        \\  cloudio cloudflare zone available-plan <zone-id> <plan-id>
        \\  cloudio cloudflare secondary-dns acls|peers|tsigs <account-id>
        \\  cloudio cloudflare secondary-dns acl|peer|tsig <account-id> <resource-id>
        \\  cloudio cloudflare secondary-dns primary|primary-status|secondary <zone-id>
        \\  cloudio cloudflare dns-analytics report|bytime <zone-id>
        \\  cloudio cloudflare dns-firewall list <account-id>|show|reverse-dns <account-id> <dns-firewall-id>
        \\  cloudio cloudflare dns-firewall analytics report|bytime <account-id> <dns-firewall-id>
        \\  cloudio cloudflare load-balancing account monitor-groups|monitors|pools|regions|search <account-id> [query]
        \\  cloudio cloudflare load-balancing account monitor-group|monitor-group-references|monitor|monitor-references|preview-result|pool|pool-health|pool-references|region <account-id> <resource-id>
        \\  cloudio cloudflare load-balancing user monitors|pools|healthcheck-events
        \\  cloudio cloudflare load-balancing user monitor|monitor-references|preview-result|pool|pool-health|pool-references <resource-id>
        \\  cloudio cloudflare load-balancing zone load-balancers <zone-id>|zone load-balancer <zone-id> <load-balancer-id>
        \\  cloudio cloudflare health-checks endpoint list <account-id>|endpoint show <account-id> <healthcheck-id>
        \\  cloudio cloudflare health-checks zone list <zone-id>|zone show|preview <zone-id> <healthcheck-id>
        \\  cloudio cloudflare health-checks smart-shield list <zone-id>|smart-shield show <zone-id> <healthcheck-id>
        \\  cloudio cloudflare resource-tags account tags|keys|resources|values <account-id> [resource-type] [resource-id]
        \\  cloudio cloudflare resource-tags zone tags <zone-id> [resource-type] [resource-id]
        \\  cloudio cloudflare rulesets account|zone list <scope-id>|show <scope-id> <ruleset-id>|versions <scope-id> <ruleset-id>
        \\  cloudio cloudflare rulesets account|zone entrypoint|entrypoint-versions <scope-id> <phase>|entrypoint-version <scope-id> <phase> <version>
        \\  cloudio cloudflare rulesets account|zone version <scope-id> <ruleset-id> <version>|rules-by-tag <scope-id> <ruleset-id> <version> <tag>
        \\  cloudio cloudflare cloudforce-one-rules list|managed|stats|tree <account-id> [key=value...]
        \\  cloudio cloudflare cloudforce-one-rules search <account-id> <query> [key=value...]|show <account-id> <rule-id>
        \\  cloudio cloudflare ip-access user list [key=value...]|user show <rule-id>
        \\  cloudio cloudflare ip-access account list <account-id> [key=value...]|account show <account-id> <rule-id>
        \\  cloudio cloudflare ip-access zone list <zone-id> [key=value...]
        \\  cloudio cloudflare page-rules|ua-rules|zone-lockdown list <zone-id>
        \\  cloudio cloudflare page-rules|ua-rules|zone-lockdown show <zone-id> <rule-id>
        \\  cloudio cloudflare dns [domain]|dns list|export|usage|scan-review [domain]|dns show <record-id> [domain]
        \\  cloudio cloudflare dnssec [domain]|dnssec zsk [domain]
        \\  cloudio cloudflare dry-run dns create|batch|import|apply-scan-results|trigger-scan <zone-id>
        \\  cloudio cloudflare dry-run dns delete|patch|update <zone-id> <record-id>
        \\  cloudio cloudflare dry-run dnssec delete|edit-status <zone-id>
        \\  cloudio cloudflare dry-run zone create
        \\  cloudio cloudflare dry-run zone delete|edit|purge-cache|activation-check <zone-id>
        \\  cloudio cloudflare dry-run zone purge-environment-cache <zone-id> <environment-id>
        \\  cloudio cloudflare dry-run zone-lifecycle cache-reserve-change|cache-reserve-clear-start|regional-tiered-cache-change|variants-delete|variants-change <zone-id>
        \\  cloudio cloudflare dry-run zone-lifecycle environments-create|environments-edit|environments-update|hold-create|hold-update|hold-delete|subscription-create|subscription-update <zone-id>
        \\  cloudio cloudflare dry-run zone-lifecycle environment-delete|environment-rollback <zone-id> <environment-id>
        \\  cloudio cloudflare dry-run secondary-dns-account acl|peer|tsig create <account-id>
        \\  cloudio cloudflare dry-run secondary-dns-account acl|peer|tsig update|delete <account-id> <resource-id>
        \\  cloudio cloudflare dry-run secondary-dns-zone primary-create|primary-update|primary-delete|primary-enable|primary-disable|primary-force-notify <zone-id>
        \\  cloudio cloudflare dry-run secondary-dns-zone secondary-create|secondary-update|secondary-delete|secondary-force-axfr <zone-id>
        \\  cloudio cloudflare dry-run dns-firewall create <account-id>
        \\  cloudio cloudflare dry-run dns-firewall update|delete|update-reverse-dns <account-id> <dns-firewall-id>
        \\  cloudio cloudflare dry-run dns-settings account <account-id>|zone <zone-id>
        \\  cloudio cloudflare dry-run load-balancing account-monitor-group create <account-id>|update|patch|delete <account-id> <monitor-group-id>
        \\  cloudio cloudflare dry-run load-balancing account-monitor create <account-id>|update|patch|delete|preview <account-id> <monitor-id>
        \\  cloudio cloudflare dry-run load-balancing account-pool create|patch-all <account-id>|update|patch|delete|preview <account-id> <pool-id>
        \\  cloudio cloudflare dry-run load-balancing user-monitor create|update|patch|delete|preview [monitor-id]
        \\  cloudio cloudflare dry-run load-balancing user-pool create|patch-all|update|patch|delete|preview [pool-id]
        \\  cloudio cloudflare dry-run load-balancing zone-load-balancer create <zone-id>|update|patch|delete <zone-id> <load-balancer-id>
        \\  cloudio cloudflare dry-run health-checks endpoint create <account-id>|update|delete <account-id> <healthcheck-id>
        \\  cloudio cloudflare dry-run health-checks zone create <zone-id>|update|patch|delete <zone-id> <healthcheck-id>
        \\  cloudio cloudflare dry-run health-checks preview create <zone-id>|delete <zone-id> <preview-id>
        \\  cloudio cloudflare dry-run health-checks smart-shield create <zone-id>|update|patch|delete <zone-id> <healthcheck-id>
        \\  cloudio cloudflare dry-run resource-tags account set|delete <account-id>
        \\  cloudio cloudflare dry-run resource-tags zone set|delete <zone-id>
        \\  cloudio cloudflare dry-run rulesets account|zone create <scope-id>|update|delete <scope-id> <ruleset-id>|update-entrypoint <scope-id> <phase>
        \\  cloudio cloudflare dry-run rulesets account|zone create-rule <scope-id> <ruleset-id>|update-rule|delete-rule <scope-id> <ruleset-id> <rule-id>|delete-version <scope-id> <ruleset-id> <version>
        \\  cloudio cloudflare dry-run cloudforce-one-rules create|delete-all|validate <account-id>
        \\  cloudio cloudflare dry-run cloudforce-one-rules update|delete <account-id> <rule-id>
        \\  cloudio cloudflare dry-run ip-access user create|user update|delete <rule-id>
        \\  cloudio cloudflare dry-run ip-access account|zone create <scope-id>
        \\  cloudio cloudflare dry-run ip-access account|zone update|delete <scope-id> <rule-id>
        \\  cloudio cloudflare dry-run page-rules create <zone-id>|update|edit|delete <zone-id> <rule-id>
        \\  cloudio cloudflare dry-run ua-rules|zone-lockdown create <zone-id>|update|delete <zone-id> <rule-id>
        \\  cloudio cloudflare dry-run token create
        \\  cloudio cloudflare dry-run token delete|update|roll <token-id>
        \\  cloudio cloudflare dry-run account create|batch-move
        \\  cloudio cloudflare dry-run account update|delete|move|profile <account-id>
        \\  cloudio cloudflare dry-run membership update|delete <membership-id>
        \\  cloudio cloudflare dry-run account-token create <account-id>
        \\  cloudio cloudflare dry-run account-token delete|update|roll <account-id> <token-id>
        \\  cloudio cloudflare dry-run account-member create <account-id>
        \\  cloudio cloudflare dry-run account-member update|delete <account-id> <member-id>
        \\  cloudio cloudflare dry-run resource-group|user-group create <account-id>
        \\  cloudio cloudflare dry-run resource-group|user-group update|delete <account-id> <resource-id>
        \\  cloudio cloudflare dry-run account-user-group-member create|update <account-id> <user-group-id>
        \\  cloudio cloudflare dry-run account-user-group-member delete <account-id> <user-group-id> <member-id>
        \\  cloudio hostinger vps [list|show <vm-id>|<vm-id>]|metrics <vm-id>|actions <vm-id>|action <vm-id> <action-id>|security <vm-id>
        \\  cloudio hostinger dry-run vps purchase|start|stop|restart|setup|recreate|start-recovery|stop-recovery|set-hostname|reset-hostname|set-nameservers|set-root-password|set-panel-password [vm-id]
        \\  cloudio hostinger dry-run vps create-ptr|delete-ptr <vm-id> <ip-address-id>
        \\  cloudio hostinger dry-run vps restore-backup <vm-id> <backup-id>
        \\  cloudio hostinger dry-run vps create-snapshot|delete-snapshot|restore-snapshot|install-monarx|uninstall-monarx <vm-id>
        \\  cloudio hostinger dry-run firewall create
        \\  cloudio hostinger dry-run firewall delete|create-rule <firewall-id>
        \\  cloudio hostinger dry-run firewall activate|deactivate|sync <firewall-id> <vm-id>
        \\  cloudio hostinger dry-run firewall update-rule|delete-rule <firewall-id> <rule-id>
        \\  cloudio hostinger dry-run docker create <vm-id>
        \\  cloudio hostinger dry-run docker delete|start|stop|restart|update <vm-id> <project-name>
        \\  cloudio hostinger dry-run public-key create
        \\  cloudio hostinger dry-run public-key attach <vm-id>|delete <public-key-id>
        \\  cloudio hostinger dry-run post-install-script create
        \\  cloudio hostinger dry-run post-install-script update|delete <script-id>
        \\  cloudio hostinger dry-run billing set-default-payment-method|delete-payment-method <payment-method-id>
        \\  cloudio hostinger dry-run billing enable-auto-renewal|disable-auto-renewal <subscription-id>
        \\  cloudio hostinger dry-run dns update|delete|reset|validate <domain>|restore-snapshot <domain> <snapshot-id>
        \\  cloudio hostinger dry-run domain availability|purchase-domain|create-forwarding|create-whois-profile
        \\  cloudio hostinger dry-run domain delete-forwarding|enable-domain-lock|disable-domain-lock|update-nameservers|enable-privacy-protection|disable-privacy-protection <domain>
        \\  cloudio hostinger dry-run domain delete-whois-profile <whois-id>
        \\  cloudio hostinger dry-run hosting create-website|generate-free-subdomain|verify-domain-ownership
        \\  cloudio hostinger dry-run hosting install-wordpress|create-database <username>
        \\  cloudio hostinger dry-run hosting delete-database|change-database-password|repair-database <username> <database>
        \\  cloudio hostinger dry-run hosting create-parked-domain|create-subdomain|create-nodejs-build-from-archive <username> <domain>
        \\  cloudio hostinger dry-run hosting delete-parked-domain|delete-subdomain <username> <domain> <name>
        \\  cloudio hostinger dry-run ecommerce create-store
        \\  cloudio hostinger dry-run horizons create-website
        \\  cloudio hostinger dry-run reach create-segment
        \\  cloudio hostinger dry-run reach delete-contact <contact-uuid>|create-profile-contacts <profile-uuid>
        \\  cloudio hostinger billing-catalog|billing-payment-methods|billing-subscriptions
        \\  cloudio hostinger dns [domain]|dns-snapshots [domain]|dns-snapshot <domain> <snapshot-id>
        \\  cloudio hostinger domains|domain [domain]|domain-forwarding [domain]|whois [tld]|whois-profile <whois-id>|whois-usage <whois-id>
        \\  cloudio hostinger hosting-orders|hosting-websites|hosting-wordpress|hosting-datacenters <order-id>
        \\  cloudio hostinger hosting-databases <username>|hosting-phpmyadmin <username> <database>
        \\  cloudio hostinger hosting-parked-domains <username> <domain>|hosting-subdomains <username> <domain>
        \\  cloudio hostinger hosting-node-builds <username> <domain>|hosting-node-logs <username> <domain> <build-uuid> [from-line]
        \\  cloudio hostinger ecommerce-stores|horizons-website <website-id>
        \\  cloudio hostinger reach-contacts|reach-profiles|reach-segments|reach-segment <segment-uuid>
        \\  cloudio hostinger reach-segment-contacts <segment-uuid>|reach-profile-segment-contacts <profile-uuid> <segment-uuid>
        \\  cloudio hostinger docker <vm-id>|docker-project <vm-id> <name>|docker-containers <vm-id> <name>|docker-logs <vm-id> <name>
        \\  cloudio hostinger data-centers|firewalls|public-keys|templates|post-install-scripts
        \\  cloudio hostinger firewall <id>|template <id>|post-install-script <id>
        \\  cloudio caddy sites|upstreams|render|diff|validate
        \\  cloudio system summary|services|ports|containers|metrics|logs [unit]
        \\  cloudio projects list|show <name>
        \\
    , .{version});
}

fn commandInit(io: Io, gpa: Allocator, cfg: Config, db: *Db) !void {
    _ = db;
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    try app_init.writeText(.{
        .io = io,
        .gpa = gpa,
        .config = cfg,
    }, &out.writer);
    const text = try out.toOwnedSlice();
    defer gpa.free(text);
    std.debug.print("{s}", .{text});
}

fn commandDoctor(io: Io, gpa: Allocator, cfg: Config, db: *Db) !void {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    try app_doctor.writeText(.{
        .io = io,
        .gpa = gpa,
        .version = version,
        .config = cfg,
        .db = db,
    }, &out.writer);
    const text = try out.toOwnedSlice();
    defer gpa.free(text);
    std.debug.print("{s}", .{text});
}

fn commandRefresh(io: Io, gpa: Allocator, cfg: Config, db: *Db, args: []const []const u8) !void {
    try app_refresh.run(.{
        .io = io,
        .gpa = gpa,
        .db = db,
        .domains = cfg.domains,
        .cloudflare_auth = cloudflareAuth(cfg),
        .hostinger_token = cfg.hostinger_api_token,
        .caddy_paths = caddyPaths(cfg),
        .projects_root = cfg.projects_root,
        .log = .{
            .version = version,
            .db_path = cfg.db_path,
            .config_path = cfg.config_path,
            .log_path = cfg.log_path,
            .loaded_dotenv = cfg.loaded_dotenv,
            .loaded_fish_env = cfg.loaded_fish_env,
            .cloudflare_auth = cfg.hasCloudflareAuth(),
            .hostinger_auth = cfg.hasHostingerAuth(),
        },
    }, refreshSelectionFromArgs(args));
    std.debug.print("refresh complete\n", .{});
}

fn commandLog(io: Io, gpa: Allocator, cfg: Config) !void {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    try app_log.writeText(.{
        .io = io,
        .gpa = gpa,
        .path = cfg.log_path,
    }, &out.writer);
    const text = try out.toOwnedSlice();
    defer gpa.free(text);
    std.debug.print("{s}", .{text});
}

fn commandExport(gpa: Allocator, db: *Db) !void {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    try app_export.writeRecentSnapshotsJson(gpa, db, &out.writer);
    const text = try out.toOwnedSlice();
    defer gpa.free(text);
    std.debug.print("{s}", .{text});
}

fn refreshSelectionFromArgs(args: []const []const u8) app_refresh.Selection {
    if (args.len == 0) return .all();
    var out = app_refresh.Selection.none();
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--all")) return .all();
        if (std.mem.eql(u8, arg, "--cloudflare")) out.cloudflare = true;
        if (std.mem.eql(u8, arg, "--hostinger")) out.hostinger = true;
        if (std.mem.eql(u8, arg, "--caddy")) out.caddy = true;
        if (std.mem.eql(u8, arg, "--system")) out.system = true;
        if (std.mem.eql(u8, arg, "--projects")) out.projects = true;
    }
    return out;
}

fn commandOverview(gpa: Allocator, db: *Db) !void {
    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    try app_overview.writeText(gpa, db, &out.writer);
    const text = try out.toOwnedSlice();
    defer gpa.free(text);
    std.debug.print("{s}", .{text});
}

fn cloudflareAuth(cfg: Config) cloudio.app.cloudflare.Auth {
    return .{
        .token = cfg.cloudflare_api_token,
        .email = cfg.cloudflare_email,
        .key = cfg.cloudflare_api_key,
    };
}

fn caddyPaths(cfg: Config) cloudio.app.caddy.Paths {
    return .{
        .caddyfile_path = cfg.caddyfile_path,
        .caddy_sites_path = cfg.caddy_sites_path,
        .caddy_admin_socket = cfg.caddy_admin_socket,
    };
}

test "sqlite schema initializes" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/cloudio.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();
    try std.testing.expectEqual(@as(i64, 0), try db.countTable("snapshots"));
}
