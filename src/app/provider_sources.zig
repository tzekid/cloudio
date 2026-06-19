const std = @import("std");
const app_provider_coverage_render = @import("app_provider_coverage_render");
const core_json = @import("core_json");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const writeJsonBoolField = app_provider_coverage_render.writeJsonBoolField;
const writeJsonCountField = app_provider_coverage_render.writeJsonCountField;
const writeJsonField = app_provider_coverage_render.writeJsonField;
const writeMaybeJsonComma = app_provider_coverage_render.writeMaybeJsonComma;

const max_metadata_bytes = 128 * 1024;
const max_manifest_bytes = 12 * 1024 * 1024;
const metadata_path = "coverage/generated/metadata.json";

pub const Paths = provider_routes.Paths;
pub const ProviderFilter = provider_routes.ProviderFilter;

pub const SourceOptions = struct {
    provider: ProviderFilter = .all,
};

pub const ManifestSummary = struct {
    rows: usize = 0,
    bytes: usize = 0,
    non_deprecated: usize = 0,
    deprecated: usize = 0,
    routable: usize = 0,
    read_routes: usize = 0,
    dry_run_routes: usize = 0,
    write_routes: usize = 0,
    none_routes: usize = 0,
    missing_operation_id: usize = 0,

    pub fn addRoute(self: *ManifestSummary, route: provider_routes.Route) void {
        self.rows += 1;
        if (route.deprecated) self.deprecated += 1 else self.non_deprecated += 1;
        if (route.isRoutable()) self.routable += 1;
        switch (route.mode) {
            .read => self.read_routes += 1,
            .dry_run => self.dry_run_routes += 1,
            .write => self.write_routes += 1,
            .none => self.none_routes += 1,
        }
        if (route.operation_id == null) self.missing_operation_id += 1;
    }
};

pub const ProviderSource = struct {
    provider: provider_routes.Provider,
    source_url: []u8,
    manifest_path: []u8,
    override_path: []u8,
    official_operations: usize,
    manifest: ManifestSummary,

    pub fn deinit(self: ProviderSource, gpa: Allocator) void {
        gpa.free(self.source_url);
        gpa.free(self.manifest_path);
        gpa.free(self.override_path);
    }

    pub fn matchesMetadata(self: ProviderSource) bool {
        return self.official_operations == self.manifest.rows;
    }
};

pub const SourceReport = struct {
    schema_version: i64,
    metadata_path_value: []u8,
    classification_get: []u8,
    classification_non_get: []u8,
    classification_deprecated: []u8,
    providers: []ProviderSource,

    pub fn deinit(self: *SourceReport, gpa: Allocator) void {
        gpa.free(self.metadata_path_value);
        gpa.free(self.classification_get);
        gpa.free(self.classification_non_get);
        gpa.free(self.classification_deprecated);
        for (self.providers) |row| row.deinit(gpa);
        gpa.free(self.providers);
    }

    pub fn writeText(self: SourceReport, writer: anytype, options: SourceOptions) !void {
        try writer.writeAll("Cloudio provider source provenance\n");
        try writer.writeAll("scope: official OpenAPI sources -> generated manifests -> Cloudio route metadata\n");
        try writer.print("filter={s} metadata={s} schema_version={d}\n", .{ options.provider.name(), self.metadata_path_value, self.schema_version });
        try writer.print("classification_defaults GET={s} non_GET={s} deprecated={s}\n", .{
            self.classification_get,
            self.classification_non_get,
            self.classification_deprecated,
        });
        try writer.writeAll("commands refresh='zig build coverage-manifest' check='zig build coverage-check' summary='zig build api-summary'\n");

        var visible: usize = 0;
        for (self.providers) |row| {
            if (!options.provider.includesProvider(row.provider)) continue;
            visible += 1;
            try writeProviderText(row, writer);
        }
        if (visible == 0) try writer.writeAll("no provider sources for filter\n");
    }

    pub fn writeJson(self: SourceReport, writer: anytype, options: SourceOptions) !void {
        try writer.writeByte('{');
        try writeJsonField(writer, "kind", "provider_sources", true);
        try writeJsonField(writer, "filter", options.provider.name(), true);
        try writeJsonField(writer, "scope", "official OpenAPI sources -> generated manifests -> Cloudio route metadata", true);
        try writeJsonField(writer, "metadata_path", self.metadata_path_value, true);
        try writer.writeAll("\"schema_version\":");
        try writer.print("{d}", .{self.schema_version});
        try writer.writeByte(',');
        try writer.writeAll("\"classification_defaults\":{");
        try writeJsonField(writer, "GET", self.classification_get, true);
        try writeJsonField(writer, "non-GET", self.classification_non_get, true);
        try writeJsonField(writer, "deprecated", self.classification_deprecated, false);
        try writer.writeAll("},");
        try writer.writeAll("\"commands\":{");
        try writeJsonField(writer, "refresh", "zig build coverage-manifest", true);
        try writeJsonField(writer, "check", "zig build coverage-check", true);
        try writeJsonField(writer, "summary", "zig build api-summary", false);
        try writer.writeAll("},");
        try writer.writeAll("\"providers\":[");
        var first = true;
        var visible: usize = 0;
        for (self.providers) |row| {
            if (!options.provider.includesProvider(row.provider)) continue;
            visible += 1;
            try writeMaybeJsonComma(writer, &first);
            try writeProviderJson(row, writer);
        }
        try writer.writeAll("],");
        try writeJsonCountField(writer, "visible", visible, false);
        try writer.writeByte('}');
        try writer.writeByte('\n');
    }
};

pub fn load(io: Io, gpa: Allocator, paths: Paths) !SourceReport {
    const metadata = try Io.Dir.cwd().readFileAlloc(io, metadata_path, gpa, .limited(max_metadata_bytes));
    defer gpa.free(metadata);
    const cloudflare = try Io.Dir.cwd().readFileAlloc(io, paths.cloudflare_manifest, gpa, .limited(max_manifest_bytes));
    defer gpa.free(cloudflare);
    const hostinger = try Io.Dir.cwd().readFileAlloc(io, paths.hostinger_manifest, gpa, .limited(max_manifest_bytes));
    defer gpa.free(hostinger);
    return try loadFromText(gpa, paths, metadata, cloudflare, hostinger);
}

pub fn loadFromText(gpa: Allocator, paths: Paths, metadata_text: []const u8, cloudflare_text: []const u8, hostinger_text: []const u8) !SourceReport {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, metadata_text, .{});
    defer parsed.deinit();

    const sources = core_json.field(parsed.value, "sources") orelse return error.InvalidProviderSourceMetadata;
    const operation_counts = core_json.field(parsed.value, "operation_counts") orelse return error.InvalidProviderSourceMetadata;
    const overrides = core_json.field(parsed.value, "overrides") orelse return error.InvalidProviderSourceMetadata;
    const defaults = core_json.field(parsed.value, "classification_defaults") orelse return error.InvalidProviderSourceMetadata;

    var rows = std.ArrayList(ProviderSource).empty;
    errdefer deinitProviderSources(&rows, gpa);

    try rows.append(gpa, try providerSourceFromText(
        gpa,
        .cloudflare,
        paths.cloudflare_manifest,
        core_json.fieldString(sources, "cloudflare") orelse return error.InvalidProviderSourceMetadata,
        core_json.fieldString(overrides, "cloudflare") orelse return error.InvalidProviderSourceMetadata,
        countFromMetadata(operation_counts, "cloudflare"),
        cloudflare_text,
    ));
    try rows.append(gpa, try providerSourceFromText(
        gpa,
        .hostinger,
        paths.hostinger_manifest,
        core_json.fieldString(sources, "hostinger") orelse return error.InvalidProviderSourceMetadata,
        core_json.fieldString(overrides, "hostinger") orelse return error.InvalidProviderSourceMetadata,
        countFromMetadata(operation_counts, "hostinger"),
        hostinger_text,
    ));

    const metadata_path_value = try gpa.dupe(u8, metadata_path);
    errdefer gpa.free(metadata_path_value);
    const classification_get = try gpa.dupe(u8, core_json.fieldString(defaults, "GET") orelse return error.InvalidProviderSourceMetadata);
    errdefer gpa.free(classification_get);
    const classification_non_get = try gpa.dupe(u8, core_json.fieldString(defaults, "non-GET") orelse return error.InvalidProviderSourceMetadata);
    errdefer gpa.free(classification_non_get);
    const classification_deprecated = try gpa.dupe(u8, core_json.fieldString(defaults, "deprecated") orelse return error.InvalidProviderSourceMetadata);
    errdefer gpa.free(classification_deprecated);
    const providers = try rows.toOwnedSlice(gpa);
    errdefer {
        for (providers) |row| row.deinit(gpa);
        gpa.free(providers);
    }

    return .{
        .schema_version = core_json.fieldInt(parsed.value, "schema_version") orelse return error.InvalidProviderSourceMetadata,
        .metadata_path_value = metadata_path_value,
        .classification_get = classification_get,
        .classification_non_get = classification_non_get,
        .classification_deprecated = classification_deprecated,
        .providers = providers,
    };
}

pub fn writeTextFromFiles(io: Io, gpa: Allocator, paths: Paths, options: SourceOptions, writer: anytype) !void {
    var report = try load(io, gpa, paths);
    defer report.deinit(gpa);
    try report.writeText(writer, options);
}

pub fn writeJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, options: SourceOptions, writer: anytype) !void {
    var report = try load(io, gpa, paths);
    defer report.deinit(gpa);
    try report.writeJson(writer, options);
}

pub fn writeTextFromText(gpa: Allocator, paths: Paths, metadata_text: []const u8, cloudflare_text: []const u8, hostinger_text: []const u8, options: SourceOptions, writer: anytype) !void {
    var report = try loadFromText(gpa, paths, metadata_text, cloudflare_text, hostinger_text);
    defer report.deinit(gpa);
    try report.writeText(writer, options);
}

pub fn writeJsonFromText(gpa: Allocator, paths: Paths, metadata_text: []const u8, cloudflare_text: []const u8, hostinger_text: []const u8, options: SourceOptions, writer: anytype) !void {
    var report = try loadFromText(gpa, paths, metadata_text, cloudflare_text, hostinger_text);
    defer report.deinit(gpa);
    try report.writeJson(writer, options);
}

fn providerSourceFromText(
    gpa: Allocator,
    provider: provider_routes.Provider,
    manifest_path: []const u8,
    source_url: []const u8,
    override_path: []const u8,
    official_operations: usize,
    manifest_text: []const u8,
) !ProviderSource {
    const source_url_owned = try gpa.dupe(u8, source_url);
    errdefer gpa.free(source_url_owned);
    const manifest_path_owned = try gpa.dupe(u8, manifest_path);
    errdefer gpa.free(manifest_path_owned);
    const override_path_owned = try gpa.dupe(u8, override_path);
    errdefer gpa.free(override_path_owned);

    return .{
        .provider = provider,
        .source_url = source_url_owned,
        .manifest_path = manifest_path_owned,
        .override_path = override_path_owned,
        .official_operations = official_operations,
        .manifest = try manifestSummary(gpa, provider, manifest_text),
    };
}

fn manifestSummary(gpa: Allocator, provider: provider_routes.Provider, text: []const u8) !ManifestSummary {
    var routes = try provider_routes.loadProviderFromText(gpa, provider, text);
    defer routes.deinit(gpa);
    var summary = ManifestSummary{ .bytes = text.len };
    for (routes.items) |route| summary.addRoute(route);
    return summary;
}

fn countFromMetadata(operation_counts: std.json.Value, provider: []const u8) usize {
    const count = core_json.fieldInt(operation_counts, provider) orelse return 0;
    if (count < 0) return 0;
    return @as(usize, @intCast(count));
}

fn writeProviderText(row: ProviderSource, writer: anytype) !void {
    try writer.print("{s}: source={s}\n", .{ row.provider.name(), row.source_url });
    try writer.print("  manifest={s} override={s} bytes={d}\n", .{ row.manifest_path, row.override_path, row.manifest.bytes });
    try writer.print("  official_operations={d} manifest_rows={d} matches_metadata={s}\n", .{
        row.official_operations,
        row.manifest.rows,
        if (row.matchesMetadata()) "true" else "false",
    });
    try writer.print("  L1 rows: non_deprecated={d} deprecated={d} routable={d} read={d} dry_run={d} write={d} none={d} missing_operation_id={d}\n", .{
        row.manifest.non_deprecated,
        row.manifest.deprecated,
        row.manifest.routable,
        row.manifest.read_routes,
        row.manifest.dry_run_routes,
        row.manifest.write_routes,
        row.manifest.none_routes,
        row.manifest.missing_operation_id,
    });
}

fn writeProviderJson(row: ProviderSource, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonField(writer, "provider", row.provider.name(), true);
    try writeJsonField(writer, "source_url", row.source_url, true);
    try writeJsonField(writer, "manifest_path", row.manifest_path, true);
    try writeJsonField(writer, "override_path", row.override_path, true);
    try writeJsonCountField(writer, "official_operations", row.official_operations, true);
    try writeJsonBoolField(writer, "matches_metadata_operation_count", row.matchesMetadata(), true);
    try writer.writeAll("\"manifest\":");
    try writeManifestSummaryJson(row.manifest, writer);
    try writer.writeByte('}');
}

fn writeManifestSummaryJson(summary: ManifestSummary, writer: anytype) !void {
    try writer.writeByte('{');
    try writeJsonCountField(writer, "rows", summary.rows, true);
    try writeJsonCountField(writer, "bytes", summary.bytes, true);
    try writeJsonCountField(writer, "non_deprecated", summary.non_deprecated, true);
    try writeJsonCountField(writer, "deprecated", summary.deprecated, true);
    try writeJsonCountField(writer, "routable", summary.routable, true);
    try writeJsonCountField(writer, "read_routes", summary.read_routes, true);
    try writeJsonCountField(writer, "dry_run_routes", summary.dry_run_routes, true);
    try writeJsonCountField(writer, "write_routes", summary.write_routes, true);
    try writeJsonCountField(writer, "none_routes", summary.none_routes, true);
    try writeJsonCountField(writer, "missing_operation_id", summary.missing_operation_id, false);
    try writer.writeByte('}');
}

fn deinitProviderSources(rows: *std.ArrayList(ProviderSource), gpa: Allocator) void {
    for (rows.items) |row| row.deinit(gpa);
    rows.deinit(gpa);
}

test "renders provider source provenance from metadata and manifests" {
    const allocator = std.testing.allocator;
    const metadata =
        \\{"schema_version":6,"sources":{"cloudflare":"https://example.test/cloudflare.json","hostinger":"https://example.test/hostinger.json"},"operation_counts":{"cloudflare":2,"hostinger":1},"overrides":{"cloudflare":"coverage/overrides/cloudflare.jsonl","hostinger":"coverage/overrides/hostinger.jsonl"},"classification_defaults":{"GET":"planned/read","non-GET":"unsafe_mutation/dry_run","deprecated":"deprecated/none"}}
    ;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"DNS Records","method":"GET","path":"/zones/{zone_id}/dns_records","operation_id":"dns-list","path_params":[{"name":"zone_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"pending"}
        \\{"provider":"cloudflare","tag":"DNS Records","method":"POST","path":"/zones/{zone_id}/dns_records","operation_id":"dns-create","path_params":[{"name":"zone_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"dry-run only"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"Billing: Catalog","method":"GET","path":"/api/billing/v1/catalog","operation_id":"billing_getCatalogItemListV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"catalog"}
        \\
    ;
    var report = try loadFromText(allocator, .{}, metadata, cloudflare, hostinger);
    defer report.deinit(allocator);
    try std.testing.expectEqual(@as(i64, 6), report.schema_version);
    try std.testing.expectEqual(@as(usize, 2), report.providers.len);
    try std.testing.expect(report.providers[0].matchesMetadata());
    try std.testing.expectEqual(@as(usize, 2), report.providers[0].manifest.rows);
    try std.testing.expectEqual(@as(usize, 1), report.providers[0].manifest.read_routes);
    try std.testing.expectEqual(@as(usize, 1), report.providers[0].manifest.dry_run_routes);

    var text_out = std.Io.Writer.Allocating.init(allocator);
    defer text_out.deinit();
    try report.writeText(&text_out.writer, .{ .provider = .cloudflare });
    const text = try text_out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio provider source provenance\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "filter=cloudflare metadata=coverage/generated/metadata.json schema_version=6") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare: source=https://example.test/cloudflare.json") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "hostinger:") == null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try report.writeJson(&json_out.writer, .{ .provider = .all });
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    var parsed_json = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed_json.deinit();
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"provider_sources\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"matches_metadata_operation_count\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"refresh\":\"zig build coverage-manifest\"") != null);
}
