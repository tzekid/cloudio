const std = @import("std");
const app_provider_l1 = @import("app_provider_l1");
const app_provider_coverage_candidates = @import("app_provider_coverage_candidates");
const app_provider_coverage_actual_captures = @import("app_provider_coverage_actual_captures");
const app_provider_coverage_actual_ready = @import("app_provider_coverage_actual_ready");
const app_provider_coverage_families = @import("app_provider_coverage_families");
const app_provider_coverage_levels = @import("app_provider_coverage_levels");
const app_provider_coverage_rollups = @import("app_provider_coverage_rollups");
const app_provider_coverage_routes = @import("app_provider_coverage_routes");
const app_provider_coverage_typed_models = @import("app_provider_coverage_typed_models");
const app_provider_coverage_workplan = @import("app_provider_coverage_workplan");
const app_provider_route_capture = @import("app_provider_route_capture");
const app_provider_route_plan = @import("app_provider_route_plan");
const app_provider_sources = @import("app_provider_sources");
const db_store = @import("db_store");
const provider_auth = @import("provider_auth");
const provider_route_result = @import("provider_route_result");
const provider_routes = @import("provider_routes");

const Allocator = std.mem.Allocator;
const Db = db_store.Db;
const Io = std.Io;

const max_manifest_bytes = 8 * 1024 * 1024;

pub const support_names = app_provider_coverage_rollups.support_names;

pub const mode_names = app_provider_coverage_rollups.mode_names;

pub const PathParam = provider_routes.PathParam;
pub const QueryParam = provider_routes.QueryParam;
pub const HeaderParam = provider_routes.HeaderParam;
pub const Request = provider_routes.Request;
pub const BodyInput = provider_routes.BodyInput;
pub const Auth = provider_auth.Auth;
pub const CaptureOptions = app_provider_route_capture.CaptureOptions;
pub const DbHandle = Db;

pub const Paths = provider_routes.Paths;

pub const ProviderFilter = provider_routes.ProviderFilter;
pub const L1AuditFailures = app_provider_l1.L1AuditFailures;
pub const L1ProviderAudit = app_provider_l1.L1ProviderAudit;
pub const L1Audit = app_provider_l1.L1Audit;

pub const SupportFilter = app_provider_coverage_routes.SupportFilter;
pub const ModeFilter = app_provider_coverage_routes.ModeFilter;

pub const ProviderSummary = app_provider_coverage_rollups.ProviderSummary;

pub const TagSummary = app_provider_coverage_rollups.TagSummary;

pub const TagSummaries = app_provider_coverage_rollups.TagSummaries;

pub const GapOptions = app_provider_coverage_rollups.GapOptions;

pub const GapSummary = app_provider_coverage_rollups.GapSummary;

pub const GapReport = app_provider_coverage_rollups.GapReport;

pub const LevelProviderEvidence = app_provider_coverage_levels.LevelProviderEvidence;

pub const LevelTagOptions = app_provider_coverage_levels.LevelTagOptions;

pub const WorkplanFocus = app_provider_coverage_workplan.WorkplanFocus;

pub const WorkplanFamily = app_provider_coverage_workplan.WorkplanFamily;

pub const FamilyOptions = app_provider_coverage_families.FamilyOptions;

pub const WorkplanOptions = app_provider_coverage_workplan.WorkplanOptions;

pub const TypedModelOptions = app_provider_coverage_typed_models.TypedModelOptions;

pub const SourceOptions = app_provider_sources.SourceOptions;

pub const SourceReport = app_provider_sources.SourceReport;

pub const LevelTagEvidence = app_provider_coverage_levels.LevelTagEvidence;

pub const FamilyEvidence = app_provider_coverage_families.FamilyEvidence;

pub const FamilyReport = app_provider_coverage_families.FamilyReport;

pub const LevelTagReport = app_provider_coverage_levels.LevelTagReport;

pub const LevelReport = app_provider_coverage_levels.LevelReport;

pub const RouteFilter = app_provider_coverage_routes.RouteFilter;

pub const CaptureCandidateOptions = app_provider_coverage_candidates.CaptureCandidateOptions;

pub const ActualCaptureOptions = app_provider_coverage_actual_captures.ActualCaptureOptions;

pub const ActualCaptureFocus = app_provider_coverage_actual_captures.ActualCaptureFocus;

pub const ActualReadyCaptureOptions = app_provider_coverage_actual_ready.ActualReadyCaptureOptions;

pub const DryRunCandidateOptions = app_provider_coverage_candidates.DryRunCandidateOptions;

pub const RoutePlanInput = app_provider_coverage_routes.RoutePlanInput;
pub const CoverageRoute = app_provider_coverage_routes.CoverageRoute;
pub const CoverageRoutes = app_provider_coverage_routes.CoverageRoutes;
pub const parseRouteMethod = app_provider_coverage_routes.parseRouteMethod;
pub const parsePathParamAssignment = app_provider_coverage_routes.parsePathParamAssignment;
pub const parseQueryParamAssignment = app_provider_coverage_routes.parseQueryParamAssignment;
pub const parseHeaderParamAssignment = app_provider_coverage_routes.parseHeaderParamAssignment;

pub const Summary = app_provider_coverage_rollups.Summary;

pub fn load(io: Io, gpa: Allocator, paths: Paths) !Summary {
    return try app_provider_coverage_rollups.load(io, gpa, paths);
}

pub fn loadFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8) !Summary {
    return try app_provider_coverage_rollups.loadFromText(gpa, cloudflare_text, hostinger_text);
}

pub fn writeTextFromFiles(io: Io, gpa: Allocator, paths: Paths, writer: anytype) !void {
    try app_provider_coverage_rollups.writeTextFromFiles(io, gpa, paths, writer);
}

pub fn writeJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, writer: anytype) !void {
    try app_provider_coverage_rollups.writeJsonFromFiles(io, gpa, paths, writer);
}

pub fn loadTags(io: Io, gpa: Allocator, paths: Paths, filter: ProviderFilter) !TagSummaries {
    return try app_provider_coverage_rollups.loadTags(io, gpa, paths, filter);
}

pub fn loadTagsFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, filter: ProviderFilter) !TagSummaries {
    return try app_provider_coverage_rollups.loadTagsFromText(gpa, cloudflare_text, hostinger_text, filter);
}

pub fn writeTagsTextFromFiles(io: Io, gpa: Allocator, paths: Paths, filter: ProviderFilter, writer: anytype) !void {
    try app_provider_coverage_rollups.writeTagsTextFromFiles(io, gpa, paths, filter, writer);
}

pub fn writeTagsJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, filter: ProviderFilter, writer: anytype) !void {
    try app_provider_coverage_rollups.writeTagsJsonFromFiles(io, gpa, paths, filter, writer);
}

pub fn loadGaps(io: Io, gpa: Allocator, paths: Paths, filter: ProviderFilter) !GapReport {
    return try app_provider_coverage_rollups.loadGaps(io, gpa, paths, filter);
}

pub fn loadGapsFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, filter: ProviderFilter) !GapReport {
    return try app_provider_coverage_rollups.loadGapsFromText(gpa, cloudflare_text, hostinger_text, filter);
}

pub fn writeGapsTextFromFiles(io: Io, gpa: Allocator, paths: Paths, options: GapOptions, writer: anytype) !void {
    try app_provider_coverage_rollups.writeGapsTextFromFiles(io, gpa, paths, options, writer);
}

pub fn writeGapsJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, options: GapOptions, writer: anytype) !void {
    try app_provider_coverage_rollups.writeGapsJsonFromFiles(io, gpa, paths, options, writer);
}

pub fn loadLevels(io: Io, gpa: Allocator, paths: Paths, filter: ProviderFilter) !LevelReport {
    return try app_provider_coverage_levels.loadLevels(io, gpa, paths, filter);
}

pub fn loadLevelsFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, filter: ProviderFilter) !LevelReport {
    return try app_provider_coverage_levels.loadLevelsFromText(gpa, cloudflare_text, hostinger_text, filter);
}

pub fn writeLevelsTextFromFiles(io: Io, gpa: Allocator, paths: Paths, filter: ProviderFilter, writer: anytype) !void {
    try app_provider_coverage_levels.writeLevelsTextFromFiles(io, gpa, paths, filter, writer);
}

pub fn writeLevelsJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, filter: ProviderFilter, writer: anytype) !void {
    try app_provider_coverage_levels.writeLevelsJsonFromFiles(io, gpa, paths, filter, writer);
}

pub fn loadLevelTags(io: Io, gpa: Allocator, paths: Paths, filter: ProviderFilter) !LevelTagReport {
    return try app_provider_coverage_levels.loadLevelTags(io, gpa, paths, filter);
}

pub fn loadLevelTagsFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, filter: ProviderFilter) !LevelTagReport {
    return try app_provider_coverage_levels.loadLevelTagsFromText(gpa, cloudflare_text, hostinger_text, filter);
}

pub fn writeLevelTagsTextFromFiles(io: Io, gpa: Allocator, paths: Paths, options: LevelTagOptions, writer: anytype) !void {
    try app_provider_coverage_levels.writeLevelTagsTextFromFiles(io, gpa, paths, options, writer);
}

pub fn writeLevelTagsJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, options: LevelTagOptions, writer: anytype) !void {
    try app_provider_coverage_levels.writeLevelTagsJsonFromFiles(io, gpa, paths, options, writer);
}

pub fn loadFamilies(io: Io, gpa: Allocator, paths: Paths, options: FamilyOptions) !FamilyReport {
    var tags = try loadLevelTags(io, gpa, paths, options.provider);
    defer tags.deinit(gpa);
    return try app_provider_coverage_families.buildReport(gpa, tags.items, options);
}

pub fn loadFamiliesFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: FamilyOptions) !FamilyReport {
    var tags = try loadLevelTagsFromText(gpa, cloudflare_text, hostinger_text, options.provider);
    defer tags.deinit(gpa);
    return try app_provider_coverage_families.buildReport(gpa, tags.items, options);
}

pub fn writeFamiliesTextFromFiles(io: Io, gpa: Allocator, paths: Paths, options: FamilyOptions, writer: anytype) !void {
    var report = try loadFamilies(io, gpa, paths, options);
    defer report.deinit(gpa);
    var bundle_routes = try app_provider_coverage_families.loadBundleRoutesFromFiles(io, gpa, paths, options);
    defer if (bundle_routes) |*routes| routes.deinit(gpa);
    try report.writeText(gpa, writer, if (bundle_routes) |routes| routes.items else null, options);
}

pub fn writeFamiliesJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, options: FamilyOptions, writer: anytype) !void {
    var report = try loadFamilies(io, gpa, paths, options);
    defer report.deinit(gpa);
    var bundle_routes = try app_provider_coverage_families.loadBundleRoutesFromFiles(io, gpa, paths, options);
    defer if (bundle_routes) |*routes| routes.deinit(gpa);
    try report.writeJson(gpa, writer, if (bundle_routes) |routes| routes.items else null, options);
}

pub fn writeFamiliesTextFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: FamilyOptions, writer: anytype) !void {
    var report = try loadFamiliesFromText(gpa, cloudflare_text, hostinger_text, options);
    defer report.deinit(gpa);
    var bundle_routes = try app_provider_coverage_families.loadBundleRoutesFromText(gpa, cloudflare_text, hostinger_text, options);
    defer if (bundle_routes) |*routes| routes.deinit(gpa);
    try report.writeText(gpa, writer, if (bundle_routes) |routes| routes.items else null, options);
}

pub fn writeFamiliesJsonFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: FamilyOptions, writer: anytype) !void {
    var report = try loadFamiliesFromText(gpa, cloudflare_text, hostinger_text, options);
    defer report.deinit(gpa);
    var bundle_routes = try app_provider_coverage_families.loadBundleRoutesFromText(gpa, cloudflare_text, hostinger_text, options);
    defer if (bundle_routes) |*routes| routes.deinit(gpa);
    try report.writeJson(gpa, writer, if (bundle_routes) |routes| routes.items else null, options);
}

pub fn writeTypedModelsTextFromFiles(io: Io, gpa: Allocator, paths: Paths, options: TypedModelOptions, writer: anytype) !void {
    var report = try loadLevelTags(io, gpa, paths, options.provider);
    defer report.deinit(gpa);
    try app_provider_coverage_typed_models.writeText(gpa, report.items, options, writer);
}

pub fn writeTypedModelsJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, options: TypedModelOptions, writer: anytype) !void {
    var report = try loadLevelTags(io, gpa, paths, options.provider);
    defer report.deinit(gpa);
    try app_provider_coverage_typed_models.writeJson(gpa, report.items, options, writer);
}

pub fn writeTypedModelsTextFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: TypedModelOptions, writer: anytype) !void {
    var report = try loadLevelTagsFromText(gpa, cloudflare_text, hostinger_text, options.provider);
    defer report.deinit(gpa);
    try app_provider_coverage_typed_models.writeText(gpa, report.items, options, writer);
}

pub fn writeTypedModelsJsonFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: TypedModelOptions, writer: anytype) !void {
    var report = try loadLevelTagsFromText(gpa, cloudflare_text, hostinger_text, options.provider);
    defer report.deinit(gpa);
    try app_provider_coverage_typed_models.writeJson(gpa, report.items, options, writer);
}

pub fn loadSources(io: Io, gpa: Allocator, paths: Paths) !SourceReport {
    return try app_provider_sources.load(io, gpa, paths);
}

pub fn loadSourcesFromText(gpa: Allocator, paths: Paths, metadata_text: []const u8, cloudflare_text: []const u8, hostinger_text: []const u8) !SourceReport {
    return try app_provider_sources.loadFromText(gpa, paths, metadata_text, cloudflare_text, hostinger_text);
}

pub fn writeSourcesTextFromFiles(io: Io, gpa: Allocator, paths: Paths, options: SourceOptions, writer: anytype) !void {
    try app_provider_sources.writeTextFromFiles(io, gpa, paths, options, writer);
}

pub fn writeSourcesJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, options: SourceOptions, writer: anytype) !void {
    try app_provider_sources.writeJsonFromFiles(io, gpa, paths, options, writer);
}

pub fn writeSourcesTextFromText(gpa: Allocator, paths: Paths, metadata_text: []const u8, cloudflare_text: []const u8, hostinger_text: []const u8, options: SourceOptions, writer: anytype) !void {
    try app_provider_sources.writeTextFromText(gpa, paths, metadata_text, cloudflare_text, hostinger_text, options, writer);
}

pub fn writeSourcesJsonFromText(gpa: Allocator, paths: Paths, metadata_text: []const u8, cloudflare_text: []const u8, hostinger_text: []const u8, options: SourceOptions, writer: anytype) !void {
    try app_provider_sources.writeJsonFromText(gpa, paths, metadata_text, cloudflare_text, hostinger_text, options, writer);
}

pub fn writeWorkplanTextFromFiles(io: Io, gpa: Allocator, paths: Paths, options: WorkplanOptions, writer: anytype) !void {
    var report = try loadLevelTags(io, gpa, paths, options.provider);
    defer report.deinit(gpa);
    var bundle_routes = try app_provider_coverage_workplan.loadBundleRoutesFromFiles(io, gpa, paths, options);
    defer if (bundle_routes) |*routes| routes.deinit(gpa);
    try app_provider_coverage_workplan.writeText(gpa, report.items, if (bundle_routes) |routes| routes.items else null, options, writer);
}

pub fn writeWorkplanJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, options: WorkplanOptions, writer: anytype) !void {
    var report = try loadLevelTags(io, gpa, paths, options.provider);
    defer report.deinit(gpa);
    var bundle_routes = try app_provider_coverage_workplan.loadBundleRoutesFromFiles(io, gpa, paths, options);
    defer if (bundle_routes) |*routes| routes.deinit(gpa);
    try app_provider_coverage_workplan.writeJson(gpa, report.items, if (bundle_routes) |routes| routes.items else null, options, writer);
}

pub fn writeWorkplanTextFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: WorkplanOptions, writer: anytype) !void {
    var report = try loadLevelTagsFromText(gpa, cloudflare_text, hostinger_text, options.provider);
    defer report.deinit(gpa);
    var bundle_routes = try app_provider_coverage_workplan.loadBundleRoutesFromText(gpa, cloudflare_text, hostinger_text, options);
    defer if (bundle_routes) |*routes| routes.deinit(gpa);
    try app_provider_coverage_workplan.writeText(gpa, report.items, if (bundle_routes) |routes| routes.items else null, options, writer);
}

pub fn writeWorkplanJsonFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: WorkplanOptions, writer: anytype) !void {
    var report = try loadLevelTagsFromText(gpa, cloudflare_text, hostinger_text, options.provider);
    defer report.deinit(gpa);
    var bundle_routes = try app_provider_coverage_workplan.loadBundleRoutesFromText(gpa, cloudflare_text, hostinger_text, options);
    defer if (bundle_routes) |*routes| routes.deinit(gpa);
    try app_provider_coverage_workplan.writeJson(gpa, report.items, if (bundle_routes) |routes| routes.items else null, options, writer);
}

pub fn auditL1(io: Io, gpa: Allocator, paths: Paths, filter: ProviderFilter) !L1Audit {
    return try app_provider_l1.auditFromFiles(io, gpa, paths, filter);
}

pub fn auditL1FromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, filter: ProviderFilter) !L1Audit {
    return try app_provider_l1.auditFromText(gpa, cloudflare_text, hostinger_text, filter);
}

pub fn writeL1AuditTextFromFiles(io: Io, gpa: Allocator, paths: Paths, filter: ProviderFilter, writer: anytype) !void {
    try app_provider_l1.writeTextFromFiles(io, gpa, paths, filter, writer);
}

pub fn writeL1AuditJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, filter: ProviderFilter, writer: anytype) !void {
    try app_provider_l1.writeJsonFromFiles(io, gpa, paths, filter, writer);
}

pub fn loadRoutes(io: Io, gpa: Allocator, paths: Paths, filter: RouteFilter) !CoverageRoutes {
    return try app_provider_coverage_routes.loadRoutes(io, gpa, paths, filter);
}

pub fn loadRoutesFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, filter: RouteFilter) !CoverageRoutes {
    return try app_provider_coverage_routes.loadRoutesFromText(gpa, cloudflare_text, hostinger_text, filter);
}

pub fn writeRoutesTextFromFiles(io: Io, gpa: Allocator, paths: Paths, filter: RouteFilter, writer: anytype) !void {
    try app_provider_coverage_routes.writeRoutesTextFromFiles(io, gpa, paths, filter, writer);
}

pub fn writeRoutesJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, filter: RouteFilter, writer: anytype) !void {
    try app_provider_coverage_routes.writeRoutesJsonFromFiles(io, gpa, paths, filter, writer);
}

pub fn writeCaptureCandidatesTextFromFiles(io: Io, gpa: Allocator, paths: Paths, options: CaptureCandidateOptions, writer: anytype) !void {
    try app_provider_coverage_candidates.writeCaptureCandidatesTextFromFiles(io, gpa, paths, options, writer);
}

pub fn writeCaptureCandidatesJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, options: CaptureCandidateOptions, writer: anytype) !void {
    try app_provider_coverage_candidates.writeCaptureCandidatesJsonFromFiles(io, gpa, paths, options, writer);
}

pub fn writeCaptureCandidatesTextFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: CaptureCandidateOptions, writer: anytype) !void {
    try app_provider_coverage_candidates.writeCaptureCandidatesTextFromText(gpa, cloudflare_text, hostinger_text, options, writer);
}

pub fn writeCaptureCandidatesJsonFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: CaptureCandidateOptions, writer: anytype) !void {
    try app_provider_coverage_candidates.writeCaptureCandidatesJsonFromText(gpa, cloudflare_text, hostinger_text, options, writer);
}

pub fn writeActualCapturesTextFromFiles(io: Io, gpa: Allocator, paths: Paths, db: *Db, options: ActualCaptureOptions, writer: anytype) !void {
    try app_provider_coverage_actual_captures.writeActualCapturesTextFromFiles(io, gpa, paths, db, options, writer);
}

pub fn writeActualCapturesJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, db: *Db, options: ActualCaptureOptions, writer: anytype) !void {
    try app_provider_coverage_actual_captures.writeActualCapturesJsonFromFiles(io, gpa, paths, db, options, writer);
}

pub fn writeActualCapturesTextFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, db: *Db, options: ActualCaptureOptions, writer: anytype) !void {
    try app_provider_coverage_actual_captures.writeActualCapturesTextFromText(gpa, cloudflare_text, hostinger_text, db, options, writer);
}

pub fn writeActualCapturesJsonFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, db: *Db, options: ActualCaptureOptions, writer: anytype) !void {
    try app_provider_coverage_actual_captures.writeActualCapturesJsonFromText(gpa, cloudflare_text, hostinger_text, db, options, writer);
}

pub fn actualReadyCaptureJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, db: *Db, auth: Auth, options: ActualReadyCaptureOptions) ![]u8 {
    return try app_provider_coverage_actual_ready.actualReadyCaptureJsonFromFiles(io, gpa, paths, db, auth, options);
}

pub fn actualReadyCaptureJsonFromText(io: Io, gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, db: *Db, auth: Auth, options: ActualReadyCaptureOptions) ![]u8 {
    return try app_provider_coverage_actual_ready.actualReadyCaptureJsonFromText(io, gpa, cloudflare_text, hostinger_text, db, auth, options);
}

pub fn writeDryRunCandidatesTextFromFiles(io: Io, gpa: Allocator, paths: Paths, options: DryRunCandidateOptions, writer: anytype) !void {
    try app_provider_coverage_candidates.writeDryRunCandidatesTextFromFiles(io, gpa, paths, options, writer);
}

pub fn writeDryRunCandidatesJsonFromFiles(io: Io, gpa: Allocator, paths: Paths, options: DryRunCandidateOptions, writer: anytype) !void {
    try app_provider_coverage_candidates.writeDryRunCandidatesJsonFromFiles(io, gpa, paths, options, writer);
}

pub fn writeDryRunCandidatesTextFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: DryRunCandidateOptions, writer: anytype) !void {
    try app_provider_coverage_candidates.writeDryRunCandidatesTextFromText(gpa, cloudflare_text, hostinger_text, options, writer);
}

pub fn writeDryRunCandidatesJsonFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, options: DryRunCandidateOptions, writer: anytype) !void {
    try app_provider_coverage_candidates.writeDryRunCandidatesJsonFromText(gpa, cloudflare_text, hostinger_text, options, writer);
}

pub fn routePlanJson(io: Io, gpa: Allocator, paths: Paths, input: RoutePlanInput) ![]u8 {
    return try app_provider_route_plan.planJson(io, gpa, paths, routePlanInput(input));
}

pub fn routeReadMetadataJson(io: Io, gpa: Allocator, paths: Paths, input: RoutePlanInput, auth: Auth) ![]u8 {
    return try app_provider_route_plan.readMetadataJson(io, gpa, paths, routePlanInput(input), auth);
}

pub fn routeCaptureReadMetadataJson(io: Io, gpa: Allocator, paths: Paths, input: RoutePlanInput, auth: Auth, db: *Db, options: CaptureOptions) ![]u8 {
    return try app_provider_route_capture.readMetadataJson(io, gpa, paths, routePlanInput(input), auth, db, options);
}

pub fn routeDryRunJson(io: Io, gpa: Allocator, paths: Paths, input: RoutePlanInput, auth: Auth) ![]u8 {
    return try app_provider_route_plan.dryRunJson(io, gpa, paths, routePlanInput(input), auth);
}

pub fn routeDryRunJsonFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, input: RoutePlanInput, auth: Auth) ![]u8 {
    return try app_provider_route_plan.dryRunJsonFromText(gpa, cloudflare_text, hostinger_text, routePlanInput(input), auth);
}

pub fn routePlanJsonFromText(gpa: Allocator, cloudflare_text: []const u8, hostinger_text: []const u8, input: RoutePlanInput) ![]u8 {
    return try app_provider_route_plan.planJsonFromText(gpa, cloudflare_text, hostinger_text, routePlanInput(input));
}

fn routePlanInput(input: RoutePlanInput) app_provider_route_plan.RoutePlanInput {
    return .{
        .filter = routePlanFilter(input.filter),
        .request = input.request,
    };
}

fn routePlanFilter(filter: RouteFilter) app_provider_route_plan.RouteFilter {
    return .{
        .provider = filter.provider,
        .tag_query = filter.tag_query,
        .operation_id = filter.operation_id,
        .method = filter.method,
        .path_template = filter.path_template,
        .support = if (filter.support) |support| routePlanSupportFilter(support) else null,
        .mode = if (filter.mode) |mode| routePlanModeFilter(mode) else null,
    };
}

fn routePlanSupportFilter(support: SupportFilter) app_provider_route_plan.SupportFilter {
    return switch (support) {
        .implemented => .implemented,
        .partial => .partial,
        .planned => .planned,
        .blocked_permission => .blocked_permission,
        .unsafe_mutation => .unsafe_mutation,
        .deprecated => .deprecated,
        .not_applicable => .not_applicable,
    };
}

fn routePlanModeFilter(mode: ModeFilter) app_provider_route_plan.ModeFilter {
    return switch (mode) {
        .read => .read,
        .dry_run => .dry_run,
        .write => .write,
        .none => .none,
    };
}

pub fn captureRouteReadResultJson(gpa: Allocator, db: *Db, route: provider_routes.Route, request: Request, result: provider_route_result.ReadRouteResult, options: CaptureOptions) ![]u8 {
    return try app_provider_route_capture.readResultJson(gpa, db, route, request, result, options);
}

pub fn writeRoutePlanTextFromFiles(io: Io, gpa: Allocator, paths: Paths, input: RoutePlanInput, writer: anytype) !void {
    try app_provider_route_plan.writeTextFromFiles(io, gpa, paths, routePlanInput(input), writer);
}

fn selectSingleRoute(routes: []const CoverageRoute) !CoverageRoute {
    if (routes.len == 0) return error.ProviderRoutePlanNotFound;
    if (routes.len != 1) return error.ProviderRoutePlanAmbiguous;
    return routes[0];
}

fn captureCandidateRouteFilter(filter: RouteFilter) RouteFilter {
    return app_provider_coverage_candidates.captureCandidateRouteFilter(filter);
}

fn dryRunCandidateRouteFilter(filter: RouteFilter) RouteFilter {
    return app_provider_coverage_candidates.dryRunCandidateRouteFilter(filter);
}

fn routeIsCaptureCandidate(row: CoverageRoute, options: CaptureCandidateOptions) bool {
    return app_provider_coverage_candidates.isCaptureCandidate(row, options);
}

fn routeIsDryRunCandidate(row: CoverageRoute, options: DryRunCandidateOptions) bool {
    return app_provider_coverage_candidates.isDryRunCandidate(row, options);
}

fn workplanTagFamily(provider: []const u8, tag: []const u8) ?WorkplanFamily {
    return app_provider_coverage_workplan.tagFamily(provider, tag);
}

fn writeDryRunCandidateJson(gpa: Allocator, row: CoverageRoute, options: DryRunCandidateOptions, writer: anytype) !void {
    try app_provider_coverage_candidates.writeDryRunCandidateJson(gpa, row, options, writer);
}

fn routeDryRunPlanJson(gpa: Allocator, route: provider_routes.Route) ![]u8 {
    return try app_provider_coverage_candidates.dryRunPlanJson(gpa, route);
}

fn writeCaptureCandidateJson(gpa: Allocator, row: CoverageRoute, options: CaptureCandidateOptions, writer: anytype) !void {
    try app_provider_coverage_candidates.writeCaptureCandidateJson(gpa, row, options, writer);
}

fn writeStringList(writer: anytype, values: anytype) !void {
    if (values.len == 0) {
        try writer.writeAll("none");
        return;
    }
    for (values, 0..) |value, index| {
        if (index != 0) try writer.writeByte(',');
        try writer.writeAll(value);
    }
}

test "lists route capture candidates for missing L2 read evidence" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"Logs","method":"GET","path":"/accounts/{account_id}/logs","operation_id":"logs-list","path_params":[{"name":"account_id","required":true}],"query_params":[{"name":"page","required":false}],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"pending"}
        \\{"provider":"cloudflare","tag":"Logs","method":"GET","path":"/accounts/{account_id}/logs/blocked","operation_id":"logs-blocked","path_params":[{"name":"account_id","required":true}],"query_params":[{"name":"since","required":true}],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"blocked_permission","mode":"read","tests":"missing","deprecated":false,"notes":"needs diagnostic"}
        \\{"provider":"cloudflare","tag":"Logs","method":"GET","path":"/accounts/{account_id}/logs/ready","operation_id":"logs-ready","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,live_smoke","deprecated":false,"notes":"already captured"}
        \\{"provider":"cloudflare","tag":"Logs","method":"POST","path":"/accounts/{account_id}/logs","operation_id":"logs-create","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"mutation"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS","method":"GET","path":"/api/vps/v1/virtual-machines","operation_id":"VPS_getVirtualMachinesV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"other provider"}
        \\
    ;

    var text_out = std.Io.Writer.Allocating.init(allocator);
    defer text_out.deinit();
    try writeCaptureCandidatesTextFromText(allocator, cloudflare, hostinger, .{
        .filter = .{ .provider = .cloudflare, .tag_query = "Logs" },
        .limit = 1,
    }, &text_out.writer);
    const text = try text_out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio route capture candidates\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "GET /accounts/{account_id}/logs | support=planned op=logs-list") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "required_path=account_id required_query=- required_header=- pagination=page") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudio route capture cloudflare --operation logs-list --path-param account_id=<account_id> --paginate") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "logs-ready") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "omitted=1") != null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeCaptureCandidatesJsonFromText(allocator, cloudflare, hostinger, .{
        .filter = .{ .provider = .cloudflare, .tag_query = "Logs" },
        .limit = 0,
    }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"coverage_capture_candidates\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"total_candidates\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"operation_id\":\"logs-list\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"operation_id\":\"logs-blocked\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"required_query_params\":[\"since\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"capture_command\":\"cloudio route capture cloudflare --operation logs-blocked --path-param account_id=<account_id> --query-param since=<since>\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "logs-ready") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "VPS_getVirtualMachinesV1") == null);

    var family_json_out = std.Io.Writer.Allocating.init(allocator);
    defer family_json_out.deinit();
    try writeCaptureCandidatesJsonFromText(allocator, cloudflare, hostinger, .{
        .filter = .{ .provider = .all, .family = .logs },
        .limit = 0,
    }, &family_json_out.writer);
    const family_json = try family_json_out.toOwnedSlice();
    defer allocator.free(family_json);
    try std.testing.expect(std.mem.indexOf(u8, family_json, "\"family\":\"logs\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, family_json, "\"total_candidates\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, family_json, "\"operation_id\":\"logs-list\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, family_json, "VPS_getVirtualMachinesV1") == null);

    var plan_json_out = std.Io.Writer.Allocating.init(allocator);
    defer plan_json_out.deinit();
    try writeCaptureCandidatesJsonFromText(allocator, cloudflare, hostinger, .{
        .filter = .{ .provider = .cloudflare, .family = .logs },
        .limit = 1,
        .include_plans = true,
    }, &plan_json_out.writer);
    const plan_json = try plan_json_out.toOwnedSlice();
    defer allocator.free(plan_json);
    try std.testing.expect(std.mem.indexOf(u8, plan_json, "\"include_plans\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_json, "\"read_plan\":{\"provider\":\"cloudflare\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_json, "\"operation_id\":\"logs-list\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_json, "\"path\":\"/accounts/example/logs\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_json, "\"request_body_input\":{\"present\":false,\"content_type\":null,\"required_missing\":false}") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_json, "\"mode\":\"read\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_json, "\"will_execute\":false") != null);
}

test "closed Cloudflare security read slice has no capture candidates" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"Radar Bots","method":"GET","path":"/radar/bots","operation_id":"radar-get-bots","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,generic_route_plan","deprecated":false,"notes":"generic Radar bot telemetry capture"}
        \\{"provider":"cloudflare","tag":"Email Security","method":"GET","path":"/accounts/{account_id}/email-security/investigate","operation_id":"email_security_investigate","path_params":[{"name":"account_id","required":true}],"query_params":[{"name":"cursor","required":false},{"name":"page","required":false}],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,generic_route_plan","deprecated":false,"notes":"generic Email Security capture"}
        \\{"provider":"cloudflare","tag":"Security Center Scans","method":"GET","path":"/zones/{zone_id}/security-center/insights/scans","operation_id":"get-security-center-zone-scans","path_params":[{"name":"zone_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,generic_route_plan","deprecated":false,"notes":"generic Security Center scan capture"}
        \\{"provider":"cloudflare","tag":"security.txt","method":"GET","path":"/zones/{zone_id}/security-center/securitytxt","operation_id":"get-security-txt","path_params":[{"name":"zone_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,generic_route_plan","deprecated":false,"notes":"generic security.txt capture"}
        \\{"provider":"cloudflare","tag":"Workers","method":"GET","path":"/accounts/{account_id}/workers","operation_id":"workers-list","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"not a control-plane security family"}
        \\
    ;

    var candidates_json_out = std.Io.Writer.Allocating.init(allocator);
    defer candidates_json_out.deinit();
    try writeCaptureCandidatesJsonFromText(allocator, cloudflare, "", .{
        .filter = .{ .provider = .cloudflare, .family = .security },
        .limit = 0,
    }, &candidates_json_out.writer);
    const candidates_json = try candidates_json_out.toOwnedSlice();
    defer allocator.free(candidates_json);
    try std.testing.expect(std.mem.indexOf(u8, candidates_json, "\"family\":\"security\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, candidates_json, "\"total_candidates\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, candidates_json, "radar-get-bots") == null);
    try std.testing.expect(std.mem.indexOf(u8, candidates_json, "email_security_investigate") == null);
    try std.testing.expect(std.mem.indexOf(u8, candidates_json, "get-security-center-zone-scans") == null);
    try std.testing.expect(std.mem.indexOf(u8, candidates_json, "get-security-txt") == null);
    try std.testing.expect(std.mem.indexOf(u8, candidates_json, "workers-list") == null);

    var families_json_out = std.Io.Writer.Allocating.init(allocator);
    defer families_json_out.deinit();
    try writeFamiliesJsonFromText(allocator, cloudflare, "", .{
        .provider = .cloudflare,
        .limit = 0,
    }, &families_json_out.writer);
    const families_json = try families_json_out.toOwnedSlice();
    defer allocator.free(families_json);
    try std.testing.expect(std.mem.indexOf(u8, families_json, "\"family\":\"security\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, families_json, "\"priority\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, families_json, "\"l2_read_evidence\":4") != null);
    try std.testing.expect(std.mem.indexOf(u8, families_json, "\"pending_reads\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, families_json, "\"l3_typed_table_evidence\":4") != null);
    try std.testing.expect(std.mem.indexOf(u8, families_json, "Workers") == null);
}

test "closed Cloudflare accounts read slice has no capture candidates" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"Organizations","method":"GET","path":"/organizations","operation_id":"Organization_listOrganizations","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,generic_route_plan","deprecated":false,"notes":"generic organization capture"}
        \\{"provider":"cloudflare","tag":"OrganizationMembers","method":"GET","path":"/organizations/{organization_id}/members","operation_id":"Members_list","path_params":[{"name":"organization_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,generic_route_plan","deprecated":false,"notes":"generic organization members capture"}
        \\{"provider":"cloudflare","tag":"SCIM Users","method":"GET","path":"/accounts/{account_id}/scim/v2/Users","operation_id":"scim-users-list","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,generic_route_plan","deprecated":false,"notes":"generic SCIM Resources capture"}
        \\{"provider":"cloudflare","tag":"Worker Account Settings","method":"GET","path":"/accounts/{account_id}/workers/account-settings","operation_id":"worker-account-settings-fetch-worker-account-settings","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,generic_route_plan","deprecated":false,"notes":"generic worker account settings capture"}
        \\{"provider":"cloudflare","tag":"Logs","method":"GET","path":"/accounts/{account_id}/logs","operation_id":"logs-list","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"not an account-family row"}
        \\
    ;

    var candidates_json_out = std.Io.Writer.Allocating.init(allocator);
    defer candidates_json_out.deinit();
    try writeCaptureCandidatesJsonFromText(allocator, cloudflare, "", .{
        .filter = .{ .provider = .cloudflare, .family = .accounts },
        .limit = 0,
    }, &candidates_json_out.writer);
    const candidates_json = try candidates_json_out.toOwnedSlice();
    defer allocator.free(candidates_json);
    try std.testing.expect(std.mem.indexOf(u8, candidates_json, "\"family\":\"accounts\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, candidates_json, "\"total_candidates\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, candidates_json, "Organization_listOrganizations") == null);
    try std.testing.expect(std.mem.indexOf(u8, candidates_json, "Members_list") == null);
    try std.testing.expect(std.mem.indexOf(u8, candidates_json, "scim-users-list") == null);
    try std.testing.expect(std.mem.indexOf(u8, candidates_json, "worker-account-settings-fetch-worker-account-settings") == null);
    try std.testing.expect(std.mem.indexOf(u8, candidates_json, "logs-list") == null);

    var families_json_out = std.Io.Writer.Allocating.init(allocator);
    defer families_json_out.deinit();
    try writeFamiliesJsonFromText(allocator, cloudflare, "", .{
        .provider = .cloudflare,
        .limit = 0,
    }, &families_json_out.writer);
    const families_json = try families_json_out.toOwnedSlice();
    defer allocator.free(families_json);
    try std.testing.expect(std.mem.indexOf(u8, families_json, "\"family\":\"accounts\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, families_json, "\"priority\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, families_json, "\"l2_read_evidence\":4") != null);
    try std.testing.expect(std.mem.indexOf(u8, families_json, "\"pending_reads\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, families_json, "\"l3_typed_table_evidence\":4") != null);
    try std.testing.expect(std.mem.indexOf(u8, families_json, "Logs") == null);
}

test "lists route dry-run candidates for missing mutation review evidence" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"Workers","method":"POST","path":"/accounts/{account_id}/workers","operation_id":"workers-create","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":["#/components/schemas/WorkerCreateRequest"]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"pending dry-run"}
        \\{"provider":"cloudflare","tag":"Workers","method":"DELETE","path":"/accounts/{account_id}/workers/{worker_id}","operation_id":"workers-delete","path_params":[{"name":"account_id","required":true},{"name":"worker_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"pending dry-run"}
        \\{"provider":"cloudflare","tag":"Workers","method":"GET","path":"/accounts/{account_id}/workers","operation_id":"workers-list","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"read"}
        \\{"provider":"cloudflare","tag":"Workers","method":"PATCH","path":"/accounts/{account_id}/workers/{worker_id}","operation_id":"workers-patch","path_params":[{"name":"account_id","required":true},{"name":"worker_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"dry_run","tests":"fixture","deprecated":false,"notes":"already reviewed"}
        \\{"provider":"cloudflare","tag":"Workers","method":"POST","path":"/accounts/{account_id}/workers/old","operation_id":"workers-old","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"deprecated","mode":"none","tests":"generated","deprecated":true,"notes":"old"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS","method":"POST","path":"/api/vps/v1/virtual-machines","operation_id":"VPS_purchaseNewVirtualMachineV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":["#/components/schemas/VpsPurchaseRequest"]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"pending dry-run"}
        \\{"provider":"hostinger","tag":"VPS","method":"DELETE","path":"/api/vps/v1/virtual-machines/{virtualMachineId}","operation_id":"VPS_deleteVirtualMachineV1","path_params":[{"name":"virtualMachineId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"pending dry-run"}
        \\
    ;

    var text_out = std.Io.Writer.Allocating.init(allocator);
    defer text_out.deinit();
    try writeDryRunCandidatesTextFromText(allocator, cloudflare, hostinger, .{
        .filter = .{ .provider = .hostinger, .tag_query = "VPS" },
        .limit = 1,
    }, &text_out.writer);
    const text = try text_out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio route dry-run candidates\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "POST /api/vps/v1/virtual-machines | support=unsafe_mutation op=VPS_purchaseNewVirtualMachineV1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "required_path=- required_query=- required_header=- body_required=true body_content_type=application/json schema_refs=#/components/schemas/VpsPurchaseRequest") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudio route dry-run hostinger --operation VPS_purchaseNewVirtualMachineV1 --body-content-type application/json") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "workers-create") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "omitted=1") != null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeDryRunCandidatesJsonFromText(allocator, cloudflare, hostinger, .{
        .filter = .{ .provider = .hostinger, .tag_query = "VPS" },
        .limit = 0,
    }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"coverage_dry_run_candidates\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"total_candidates\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"operation_id\":\"VPS_purchaseNewVirtualMachineV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"operation_id\":\"VPS_deleteVirtualMachineV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"body_required\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"body_content_type\":\"application/json\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"request_body_schema_refs\":[\"#/components/schemas/VpsPurchaseRequest\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"dry_run_command\":\"cloudio route dry-run hostinger --operation VPS_purchaseNewVirtualMachineV1 --body-content-type application/json\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "workers-create") == null);

    var family_text_out = std.Io.Writer.Allocating.init(allocator);
    defer family_text_out.deinit();
    try writeDryRunCandidatesTextFromText(allocator, cloudflare, hostinger, .{
        .filter = .{ .provider = .hostinger, .tag_query = "VPS" },
        .limit = 0,
    }, &family_text_out.writer);
    const family_text = try family_text_out.toOwnedSlice();
    defer allocator.free(family_text);
    try std.testing.expect(std.mem.indexOf(u8, family_text, "filter provider=hostinger tag_query=VPS limit=all") != null);
    try std.testing.expect(std.mem.indexOf(u8, family_text, "VPS_purchaseNewVirtualMachineV1") != null);
    try std.testing.expect(std.mem.indexOf(u8, family_text, "workers-create") == null);

    var plan_json_out = std.Io.Writer.Allocating.init(allocator);
    defer plan_json_out.deinit();
    try writeDryRunCandidatesJsonFromText(allocator, cloudflare, hostinger, .{
        .filter = .{ .provider = .hostinger, .tag_query = "VPS" },
        .limit = 1,
        .include_plans = true,
    }, &plan_json_out.writer);
    const plan_json = try plan_json_out.toOwnedSlice();
    defer allocator.free(plan_json);
    try std.testing.expect(std.mem.indexOf(u8, plan_json, "\"include_plans\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_json, "\"dry_run_plan\":{\"provider\":\"hostinger\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_json, "\"operation_id\":\"VPS_purchaseNewVirtualMachineV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_json, "\"path\":\"/api/vps/v1/virtual-machines\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_json, "\"request_body_input\":{\"present\":true,\"content_type\":\"application/json\",\"required_missing\":false}") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_json, "\"will_execute\":false") != null);
}

test "counts generated Cloudflare mutation dry-runs as review evidence" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"DNS Records","method":"POST","path":"/zones/{zone_id}/dns_records","operation_id":"dns-records-create","path_params":[{"name":"zone_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"generated policy reviewed"}
        \\{"provider":"cloudflare","tag":"Workers","method":"POST","path":"/accounts/{account_id}/workers","operation_id":"workers-create","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"generated policy reviewed"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS","method":"POST","path":"/api/vps/v1/virtual-machines","operation_id":"VPS_purchaseNewVirtualMachineV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"hostinger remains pending"}
        \\
    ;

    const levels = try loadLevelsFromText(allocator, cloudflare, hostinger, .all);
    try std.testing.expectEqual(@as(usize, 2), levels.cloudflare.dry_run_routes);
    try std.testing.expectEqual(@as(usize, 2), levels.cloudflare.dry_run_evidence);
    try std.testing.expectEqual(@as(usize, 2), levels.cloudflare.generated_dry_run_policy_evidence);
    try std.testing.expectEqual(@as(usize, 0), levels.cloudflare.pending_mutation_dry_runs);
    try std.testing.expectEqual(@as(usize, 0), levels.hostinger.generated_dry_run_policy_evidence);
    try std.testing.expectEqual(@as(usize, 1), levels.hostinger.pending_mutation_dry_runs);

    var dns_candidates_out = std.Io.Writer.Allocating.init(allocator);
    defer dns_candidates_out.deinit();
    try writeDryRunCandidatesJsonFromText(allocator, cloudflare, hostinger, .{
        .filter = .{ .provider = .cloudflare, .family = .dns },
        .limit = 0,
        .include_plans = true,
    }, &dns_candidates_out.writer);
    const dns_candidates = try dns_candidates_out.toOwnedSlice();
    defer allocator.free(dns_candidates);
    try std.testing.expect(std.mem.indexOf(u8, dns_candidates, "\"total_candidates\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, dns_candidates, "dns-records-create") == null);

    var cloudflare_candidates_out = std.Io.Writer.Allocating.init(allocator);
    defer cloudflare_candidates_out.deinit();
    try writeDryRunCandidatesJsonFromText(allocator, cloudflare, hostinger, .{
        .filter = .{ .provider = .cloudflare, .tag_query = "Workers" },
        .limit = 0,
    }, &cloudflare_candidates_out.writer);
    const cloudflare_candidates = try cloudflare_candidates_out.toOwnedSlice();
    defer allocator.free(cloudflare_candidates);
    try std.testing.expect(std.mem.indexOf(u8, cloudflare_candidates, "\"total_candidates\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, cloudflare_candidates, "workers-create") == null);

    var pending_candidates_out = std.Io.Writer.Allocating.init(allocator);
    defer pending_candidates_out.deinit();
    try writeDryRunCandidatesJsonFromText(allocator, cloudflare, hostinger, .{
        .filter = .{ .provider = .all },
        .limit = 0,
    }, &pending_candidates_out.writer);
    const pending_candidates = try pending_candidates_out.toOwnedSlice();
    defer allocator.free(pending_candidates);
    try std.testing.expect(std.mem.indexOf(u8, pending_candidates, "\"total_candidates\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, pending_candidates, "\"operation_id\":\"workers-create\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, pending_candidates, "\"operation_id\":\"VPS_purchaseNewVirtualMachineV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, pending_candidates, "dns-records-create") == null);
}

test "summarizes manifest-backed provider coverage levels" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"Accounts","method":"GET","path":"/accounts","operation_id":"accounts-list","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,live_smoke","deprecated":false,"notes":"POC reads accounts and stores typed account rows."}
        \\{"provider":"cloudflare","tag":"Workers","method":"GET","path":"/accounts/{account_id}/workers","operation_id":"workers-list","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"pending"}
        \\{"provider":"cloudflare","tag":"Workers","method":"POST","path":"/accounts/{account_id}/workers","operation_id":"workers-create","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"pending dry-run"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS: Docker Manager","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/docker","operation_id":"VPS_getProjectListV1","path_params":[{"name":"virtualMachineId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"blocked_permission","mode":"read","tests":"fixture,live_smoke_blocked","deprecated":false,"notes":"unsupported OS diagnostic"}
        \\{"provider":"hostinger","tag":"VPS: Docker Manager","method":"POST","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/docker","operation_id":"VPS_createNewProjectV1","path_params":[{"name":"virtualMachineId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"dry_run","tests":"fixture","deprecated":false,"notes":"dry-run reviewed"}
        \\
    ;

    const levels = try loadLevelsFromText(allocator, cloudflare, hostinger, .all);
    try std.testing.expectEqual(@as(usize, 3), levels.cloudflare.total);
    try std.testing.expectEqual(@as(usize, 2), levels.cloudflare.read_routes);
    try std.testing.expectEqual(@as(usize, 1), levels.cloudflare.l2_read_evidence);
    try std.testing.expectEqual(@as(usize, 1), levels.cloudflare.pending_reads);
    try std.testing.expectEqual(@as(usize, 1), levels.cloudflare.dry_run_evidence);
    try std.testing.expectEqual(@as(usize, 1), levels.cloudflare.generated_dry_run_policy_evidence);
    try std.testing.expectEqual(@as(usize, 0), levels.cloudflare.pending_mutation_dry_runs);
    try std.testing.expectEqual(@as(usize, 1), levels.cloudflare.l3_typed_table_evidence);
    try std.testing.expectEqual(@as(usize, 1), levels.hostinger.l2_diagnostic_reads);
    try std.testing.expectEqual(@as(usize, 1), levels.hostinger.dry_run_evidence);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try levels.writeText(.all, &out.writer);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio provider coverage levels\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "L2 read_evidence=1 partial_reads=1 diagnostic_blocked_reads=0 pending_reads=1 read_missing_tests=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "L3 evidence generic_inventory_candidates=1 typed_table_evidence=1") != null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try levels.writeJson(.all, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"coverage_levels\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"providers\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"name\":\"cloudflare\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"pending_reads\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"name\":\"hostinger\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"l2_diagnostic_reads\":1") != null);
}

test "ranks manifest-backed provider coverage levels by tag" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"Accounts","method":"GET","path":"/accounts","operation_id":"accounts-list","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,live_smoke","deprecated":false,"notes":"POC reads accounts and stores typed account rows."}
        \\{"provider":"cloudflare","tag":"Workers","method":"GET","path":"/accounts/{account_id}/workers","operation_id":"workers-list","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"pending"}
        \\{"provider":"cloudflare","tag":"Workers","method":"POST","path":"/accounts/{account_id}/workers","operation_id":"workers-create","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"pending dry-run"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS: Docker Manager","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/docker","operation_id":"VPS_getProjectListV1","path_params":[{"name":"virtualMachineId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"blocked_permission","mode":"read","tests":"fixture,live_smoke_blocked","deprecated":false,"notes":"unsupported OS diagnostic"}
        \\{"provider":"hostinger","tag":"VPS: Docker Manager","method":"POST","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/docker","operation_id":"VPS_createNewProjectV1","path_params":[{"name":"virtualMachineId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"dry_run","tests":"fixture","deprecated":false,"notes":"dry-run reviewed"}
        \\
    ;

    var report = try loadLevelTagsFromText(allocator, cloudflare, hostinger, .all);
    defer report.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 3), report.items.len);
    try std.testing.expectEqualStrings("cloudflare", report.items[0].provider);
    try std.testing.expectEqualStrings("Workers", report.items[0].tag);
    try std.testing.expectEqual(@as(usize, 1), report.items[0].priority());
    try std.testing.expectEqual(@as(usize, 1), report.items[0].evidence.pending_reads);
    try std.testing.expectEqual(@as(usize, 1), report.items[0].evidence.generated_dry_run_policy_evidence);
    try std.testing.expectEqual(@as(usize, 0), report.items[0].evidence.pending_mutation_dry_runs);
    try std.testing.expectEqualStrings("hostinger", report.items[1].provider);
    try std.testing.expectEqualStrings("VPS: Docker Manager", report.items[1].tag);
    try std.testing.expectEqual(@as(usize, 0), report.items[1].priority());
    try std.testing.expectEqual(@as(usize, 1), report.items[1].evidence.l2_diagnostic_reads);
    try std.testing.expectEqual(@as(usize, 1), report.items[1].evidence.dry_run_evidence);
    try std.testing.expectEqualStrings("Accounts", report.items[2].tag);
    try std.testing.expectEqual(@as(usize, 0), report.items[2].priority());
    try std.testing.expectEqual(@as(usize, 1), report.items[2].evidence.l3_typed_table_evidence);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try report.writeText(&out.writer, .{ .provider = .all, .limit = 1 });
    const text = try out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio provider coverage levels by tag\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "rank: pending_reads + pending_mutation_dry_runs; diagnostic_blocked_reads are evidence\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare | Workers: priority=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "pending_reads=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "omitted=") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "closed_or_evidence_only_rows_hidden=2") != null);

    var full_out = std.Io.Writer.Allocating.init(allocator);
    defer full_out.deinit();
    try report.writeText(&full_out.writer, .{ .provider = .all, .limit = 0 });
    const full_text = try full_out.toOwnedSlice();
    defer allocator.free(full_text);
    try std.testing.expect(std.mem.indexOf(u8, full_text, "cloudflare | Accounts: priority=0") != null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try report.writeJson(&json_out.writer, .{ .provider = .all, .limit = 1 });
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"coverage_level_tags\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"items\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"tag\":\"Workers\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"priority\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"pending_reads\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"omitted\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"closed_or_evidence_only_rows_hidden\":2") != null);

    var full_json_out = std.Io.Writer.Allocating.init(allocator);
    defer full_json_out.deinit();
    try report.writeJson(&full_json_out.writer, .{ .provider = .all, .limit = 0 });
    const full_json = try full_json_out.toOwnedSlice();
    defer allocator.free(full_json);
    try std.testing.expect(std.mem.indexOf(u8, full_json, "\"tag\":\"Accounts\"") != null);
}

test "ranks typed model candidates from L3 generic inventory evidence" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"Security Center Insights","method":"GET","path":"/accounts/{account_id}/security-center/insights","operation_id":"security-insights-list","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture,live_smoke","deprecated":false,"notes":"generic inventory only"}
        \\{"provider":"cloudflare","tag":"Workers","method":"GET","path":"/accounts/{account_id}/workers","operation_id":"workers-list","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"generic inventory only"}
        \\{"provider":"cloudflare","tag":"Accounts","method":"GET","path":"/accounts","operation_id":"accounts-list","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"typed account rows"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"Horizons: Websites","method":"GET","path":"/api/horizons/v1/websites","operation_id":"Horizons_getWebsitesV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"generic inventory only"}
        \\
    ;

    var text_out = std.Io.Writer.Allocating.init(allocator);
    defer text_out.deinit();
    try writeTypedModelsTextFromText(allocator, cloudflare, hostinger, .{
        .provider = .cloudflare,
        .family = .security,
        .limit = 10,
        .include_complete = true,
    }, &text_out.writer);
    const text = try text_out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio typed model candidates\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare | Security Center Insights: typed_gap=0 L3_generic=1 typed=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "routes: cloudio coverage routes cloudflare 'Security Center Insights' --support partial --mode read --detail") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "review-bundle: cloudio coverage workplan cloudflare --family security --limit 5 --candidate-limit 10 --bundle --plans --json") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Accounts") == null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeTypedModelsJsonFromText(allocator, cloudflare, hostinger, .{
        .provider = .all,
        .limit = 10,
    }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"coverage_typed_model_candidates\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"summary\":{\"generic_inventory_rows\":4,\"control_plane_generic_inventory_rows\":3,\"outside_control_plane_generic_inventory_rows\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"control_plane_typed_gap\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"outside_control_plane_typed_gap\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"tag\":\"Workers\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"focus_family\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"scope\":\"outside-control-plane\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"required_for_goal\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"next_action\":\"optional_generic_inventory_modeling\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"typed_gap\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"routes_detail\",\"command\":\"cloudio coverage routes cloudflare 'Workers' --support partial --mode read --detail\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"tag\":\"Horizons: Websites\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"tag\":\"Security Center Insights\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"tag\":\"Accounts\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"typed_or_complete_rows_hidden\":3") != null);

    var complete_json_out = std.Io.Writer.Allocating.init(allocator);
    defer complete_json_out.deinit();
    try writeTypedModelsJsonFromText(allocator, cloudflare, hostinger, .{
        .provider = .cloudflare,
        .limit = 0,
        .include_complete = true,
    }, &complete_json_out.writer);
    const complete_json = try complete_json_out.toOwnedSlice();
    defer allocator.free(complete_json);
    try std.testing.expect(std.mem.indexOf(u8, complete_json, "\"tag\":\"Accounts\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, complete_json, "\"tag\":\"Security Center Insights\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, complete_json, "\"status\":\"typed\"") != null);

    var focused_json_out = std.Io.Writer.Allocating.init(allocator);
    defer focused_json_out.deinit();
    try writeTypedModelsJsonFromText(allocator, cloudflare, hostinger, .{
        .provider = .cloudflare,
        .focus = .control_plane,
        .limit = 0,
    }, &focused_json_out.writer);
    const focused_json = try focused_json_out.toOwnedSlice();
    defer allocator.free(focused_json);
    try std.testing.expect(std.mem.indexOf(u8, focused_json, "\"focus\":\"control-plane\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, focused_json, "\"control_plane_typed_gap\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, focused_json, "\"tag\":\"Workers\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, focused_json, "\"focus_filtered_rows_hidden\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, focused_json, "\"typed_or_complete_rows_hidden\":2") != null);
}

test "renders broad provider coverage workplan commands by tag" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"Workers","method":"GET","path":"/accounts/{account_id}/workers","operation_id":"workers-list","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"pending read"}
        \\{"provider":"cloudflare","tag":"Workers","method":"POST","path":"/accounts/{account_id}/workers","operation_id":"workers-create","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"pending dry-run"}
        \\{"provider":"cloudflare","tag":"DNS Records","method":"GET","path":"/zones/{zone_id}/dns_records","operation_id":"dns-records-list","path_params":[{"name":"zone_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"pending read"}
        \\{"provider":"cloudflare","tag":"Tokens","method":"DELETE","path":"/accounts/{account_id}/tokens/{token_id}","operation_id":"tokens-delete","path_params":[{"name":"account_id","required":true},{"name":"token_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"dry-run only"}
        \\{"provider":"cloudflare","tag":"Accounts","method":"GET","path":"/accounts","operation_id":"accounts-list","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"closed"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"Reach: Segments","method":"GET","path":"/api/reach/v1/segments","operation_id":"Reach_getSegmentsV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"403","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"blocked_permission","mode":"read","tests":"fixture,live_smoke_blocked","deprecated":false,"notes":"blocked diagnostic"}
        \\
    ;

    var text_out = std.Io.Writer.Allocating.init(allocator);
    defer text_out.deinit();
    try writeWorkplanTextFromText(allocator, cloudflare, hostinger, .{
        .provider = .all,
        .limit = 2,
    }, &text_out.writer);
    const text = try text_out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio provider coverage workplan\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare | Workers: priority=1 pending_reads=1 diagnostic_blocked_reads=0 pending_mutation_dry_runs=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "routes: cloudio coverage routes cloudflare 'Workers' --detail") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "capture-candidates: cloudio coverage capture-candidates cloudflare 'Workers' --limit 25") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "dry-run-candidates: cloudio coverage dry-run-candidates cloudflare 'Workers' --limit 25") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare | DNS Records: priority=1 pending_reads=1 diagnostic_blocked_reads=0 pending_mutation_dry_runs=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudio coverage capture-candidates cloudflare 'DNS Records' --limit 25") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare | Tokens: priority=1") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "omitted=") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "closed_or_evidence_only_rows_hidden=3") != null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeWorkplanJsonFromText(allocator, cloudflare, hostinger, .{
        .provider = .all,
        .limit = 0,
    }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"coverage_workplan\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"tag\":\"Workers\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"priority\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"tag\":\"DNS Records\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"routes_detail\",\"command\":\"cloudio coverage routes cloudflare 'Workers' --detail\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"capture_candidates\",\"command\":\"cloudio coverage capture-candidates cloudflare 'Workers' --limit 25\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"dry_run_candidates\",\"command\":\"cloudio coverage dry-run-candidates cloudflare 'Workers' --limit 25\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"tag\":\"Reach: Segments\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"closed_or_evidence_only_rows_hidden\":3") != null);

    var plans_json_out = std.Io.Writer.Allocating.init(allocator);
    defer plans_json_out.deinit();
    try writeWorkplanJsonFromText(allocator, cloudflare, hostinger, .{
        .provider = .all,
        .limit = 1,
        .include_plans = true,
    }, &plans_json_out.writer);
    const plans_json = try plans_json_out.toOwnedSlice();
    defer allocator.free(plans_json);
    try std.testing.expect(std.mem.indexOf(u8, plans_json, "\"include_plans\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, plans_json, "\"command\":\"cloudio coverage routes cloudflare 'Workers' --detail\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plans_json, "\"command\":\"cloudio coverage capture-candidates cloudflare 'Workers' --limit 25 --plans\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plans_json, "\"command\":\"cloudio coverage dry-run-candidates cloudflare 'Workers' --limit 25 --plans\"") == null);

    var bundle_json_out = std.Io.Writer.Allocating.init(allocator);
    defer bundle_json_out.deinit();
    try writeWorkplanJsonFromText(allocator, cloudflare, hostinger, .{
        .provider = .all,
        .limit = 1,
        .include_plans = true,
        .bundle_candidates = true,
        .candidate_limit = 1,
    }, &bundle_json_out.writer);
    const bundle_json = try bundle_json_out.toOwnedSlice();
    defer allocator.free(bundle_json);
    try std.testing.expect(std.mem.indexOf(u8, bundle_json, "\"bundle_candidates\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, bundle_json, "\"candidate_limit\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, bundle_json, "\"candidate_bundle\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, bundle_json, "\"capture\":{\"total\":1,\"visible\":1,\"omitted\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, bundle_json, "\"dry_run\":{\"total\":0,\"visible\":0,\"omitted\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, bundle_json, "\"capture_command\":\"cloudio route capture cloudflare --operation workers-list --path-param account_id=<account_id>\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bundle_json, "\"read_plan\":{\"provider\":\"cloudflare\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bundle_json, "\"dry_run_command\":\"cloudio route dry-run cloudflare --operation workers-create --path-param account_id=<account_id> --body-content-type application/json\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, bundle_json, "\"dry_run_plan\":{\"provider\":\"cloudflare\"") == null);

    var focused_out = std.Io.Writer.Allocating.init(allocator);
    defer focused_out.deinit();
    try writeWorkplanTextFromText(allocator, cloudflare, hostinger, .{
        .provider = .all,
        .limit = 0,
        .focus = .control_plane,
    }, &focused_out.writer);
    const focused_text = try focused_out.toOwnedSlice();
    defer allocator.free(focused_text);
    try std.testing.expect(std.mem.indexOf(u8, focused_text, "filter=all focus=control-plane family=all limit=all") != null);
    try std.testing.expect(std.mem.indexOf(u8, focused_text, "cloudflare | DNS Records: priority=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, focused_text, "family=dns") != null);
    try std.testing.expect(std.mem.indexOf(u8, focused_text, "cloudflare | Workers") == null);
    try std.testing.expect(std.mem.indexOf(u8, focused_text, "cloudflare | Tokens") == null);
    try std.testing.expect(std.mem.indexOf(u8, focused_text, "Reach: Segments") == null);
    try std.testing.expect(std.mem.indexOf(u8, focused_text, "focus_filtered_rows_hidden=1") != null);

    var focused_json_out = std.Io.Writer.Allocating.init(allocator);
    defer focused_json_out.deinit();
    try writeWorkplanJsonFromText(allocator, cloudflare, hostinger, .{
        .provider = .all,
        .limit = 0,
        .focus = .control_plane,
    }, &focused_json_out.writer);
    const focused_json = try focused_json_out.toOwnedSlice();
    defer allocator.free(focused_json);
    try std.testing.expect(std.mem.indexOf(u8, focused_json, "\"focus\":\"control-plane\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, focused_json, "\"family\":\"all\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, focused_json, "\"tag\":\"DNS Records\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, focused_json, "\"focus_family\":\"dns\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, focused_json, "\"tag\":\"Workers\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, focused_json, "\"tag\":\"Tokens\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, focused_json, "\"focus_filtered_rows_hidden\":1") != null);

    const family_cloudflare =
        \\{"provider":"cloudflare","tag":"DNS Records","method":"GET","path":"/zones/{zone_id}/dns_records","operation_id":"dns-records-list","path_params":[{"name":"zone_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"pending read"}
        \\{"provider":"cloudflare","tag":"Tokens","method":"DELETE","path":"/accounts/{account_id}/tokens/{token_id}","operation_id":"tokens-delete","path_params":[{"name":"account_id","required":true},{"name":"token_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"dry-run only"}
        \\{"provider":"cloudflare","tag":"Workers","method":"GET","path":"/accounts/{account_id}/workers","operation_id":"workers-list","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"pending read"}
        \\
    ;

    var family_text_out = std.Io.Writer.Allocating.init(allocator);
    defer family_text_out.deinit();
    try writeWorkplanTextFromText(allocator, family_cloudflare, "", .{
        .provider = .all,
        .limit = 0,
        .family = .dns,
    }, &family_text_out.writer);
    const family_text = try family_text_out.toOwnedSlice();
    defer allocator.free(family_text);
    try std.testing.expect(std.mem.indexOf(u8, family_text, "filter=all focus=control-plane family=dns limit=all") != null);
    try std.testing.expect(std.mem.indexOf(u8, family_text, "cloudflare | DNS Records: priority=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, family_text, "cloudflare | Tokens") == null);
    try std.testing.expect(std.mem.indexOf(u8, family_text, "cloudflare | Workers") == null);
    try std.testing.expect(std.mem.indexOf(u8, family_text, "focus_filtered_rows_hidden=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, family_text, "closed_or_evidence_only_rows_hidden=1") != null);

    var family_json_out = std.Io.Writer.Allocating.init(allocator);
    defer family_json_out.deinit();
    try writeWorkplanJsonFromText(allocator, family_cloudflare, "", .{
        .provider = .all,
        .limit = 0,
        .family = .dns,
    }, &family_json_out.writer);
    const family_json = try family_json_out.toOwnedSlice();
    defer allocator.free(family_json);
    try std.testing.expect(std.mem.indexOf(u8, family_json, "\"focus\":\"control-plane\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, family_json, "\"family\":\"dns\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, family_json, "\"tag\":\"DNS Records\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, family_json, "\"tag\":\"Tokens\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, family_json, "\"closed_or_evidence_only_rows_hidden\":1") != null);
}

test "aggregates provider coverage evidence by control-plane family" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"DNS Records","method":"GET","path":"/zones/{zone_id}/dns_records","operation_id":"dns-records-list","path_params":[{"name":"zone_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"pending read"}
        \\{"provider":"cloudflare","tag":"DNS Records","method":"POST","path":"/zones/{zone_id}/dns_records","operation_id":"dns-records-create","path_params":[{"name":"zone_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"pending dry-run"}
        \\{"provider":"cloudflare","tag":"Tokens","method":"DELETE","path":"/accounts/{account_id}/tokens/{token_id}","operation_id":"tokens-delete","path_params":[{"name":"account_id","required":true},{"name":"token_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"dry-run only"}
        \\{"provider":"cloudflare","tag":"Workers","method":"GET","path":"/accounts/{account_id}/workers","operation_id":"workers-list","path_params":[{"name":"account_id","required":true}],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"planned","mode":"read","tests":"missing","deprecated":false,"notes":"not a control-plane family"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS: Virtual machine","method":"GET","path":"/api/vps/v1/virtual-machines","operation_id":"VPS_getVirtualMachinesV1","path_params":[],"query_params":[],"header_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"blocked_permission","mode":"read","tests":"fixture,live_smoke_blocked","deprecated":false,"notes":"diagnostic read"}
        \\{"provider":"hostinger","tag":"VPS: Docker Manager","method":"POST","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/docker","operation_id":"VPS_createNewProjectV1","path_params":[{"name":"virtualMachineId","required":true}],"query_params":[],"header_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"dry_run","tests":"fixture","deprecated":false,"notes":"dry-run reviewed"}
        \\
    ;

    var text_out = std.Io.Writer.Allocating.init(allocator);
    defer text_out.deinit();
    try writeFamiliesTextFromText(allocator, cloudflare, hostinger, .{
        .provider = .all,
        .limit = 0,
    }, &text_out.writer);
    const text = try text_out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio provider coverage families\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "filter=all focus=control-plane limit=all") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare | dns: priority=1 tags=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "dry_run_evidence=1 generated_dry_run_policy_evidence=1 pending_mutation_dry_runs=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "workplan: cloudio coverage workplan cloudflare --family dns --limit 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cloudflare | tokens: priority=0 tags=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "hostinger | hostinger-vps: priority=0 tags=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "hostinger | docker: priority=0 tags=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Workers") == null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try writeFamiliesJsonFromText(allocator, cloudflare, hostinger, .{
        .provider = .all,
        .limit = 2,
    }, &json_out.writer);
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"coverage_families\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"family\":\"dns\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"tag_count\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"generated_dry_run_policy_evidence\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"pending_mutation_dry_runs\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"command\":\"cloudio coverage workplan cloudflare --family dns --limit 25\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"family\":\"hostinger-vps\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"family\":\"tokens\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"family\":\"docker\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"visible\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"omitted\":2") != null);
}

test "classifies Cloudflare logs without catalog or logo substring noise" {
    try std.testing.expectEqual(@as(?WorkplanFamily, .logs), workplanTagFamily("cloudflare", "AI Gateway Logs"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .logs), workplanTagFamily("cloudflare", "Logpush jobs for a zone"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .logs), workplanTagFamily("cloudflare", "Logcontrol CMB config for an account"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .logs), workplanTagFamily("cloudflare", "Worker Tail Logs"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .logs), workplanTagFamily("cloudflare", "Magic Network Monitoring VPC Flow logs"));
    try std.testing.expectEqual(@as(?WorkplanFamily, null), workplanTagFamily("cloudflare", "Catalog Sync"));
    try std.testing.expectEqual(@as(?WorkplanFamily, null), workplanTagFamily("cloudflare", "R2 Catalog Management"));
    try std.testing.expectEqual(@as(?WorkplanFamily, null), workplanTagFamily("cloudflare", "logo_match"));
    try std.testing.expectEqual(@as(?WorkplanFamily, null), workplanTagFamily("cloudflare", "Changelog"));
}

test "classifies broad Cloudflare control-plane read groups" {
    try std.testing.expectEqual(@as(?WorkplanFamily, .ssl_tls), workplanTagFamily("cloudflare", "Radar Certificate Transparency"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .ssl_tls), workplanTagFamily("cloudflare", "mTLS Certificate Management"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .zones), workplanTagFamily("cloudflare", "Custom Hostname for a Zone"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .zones), workplanTagFamily("cloudflare", "Zone Snippets"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .tunnels), workplanTagFamily("cloudflare", "Magic GRE tunnels"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .tunnels), workplanTagFamily("cloudflare", "Magic IPsec tunnels"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .tokens), workplanTagFamily("cloudflare", "AI Search Tokens"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .tokens), workplanTagFamily("cloudflare", "Token Validation Token Rules"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .dns), workplanTagFamily("cloudflare", "DNS Internal Views for an Account"));
    try std.testing.expectEqual(@as(?WorkplanFamily, .access), workplanTagFamily("cloudflare", "Infrastructure Access Targets"));
}

test "lists provider coverage routes by provider and tag query" {
    const allocator = std.testing.allocator;
    const cloudflare =
        \\{"provider":"cloudflare","tag":"Accounts","method":"GET","path":"/accounts","operation_id":"accounts-list","path_params":[],"query_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ok"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS: Virtual machine","method":"GET","path":"/api/vps/v1/virtual-machines/{virtualMachineId}/metrics","operation_id":"VPS_getMetricsV1","path_params":[{"name":"virtualMachineId","required":true}],"query_params":[{"name":"date_from","required":true},{"name":"date_to","required":true}],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":["#/components/schemas/VPS.V1.VirtualMachine.MetricsResource"]},{"status":"401","content_types":["application/json"],"schema_refs":[]}],"support":"partial","mode":"read","tests":"fixture,live_smoke","deprecated":false,"notes":"POC reads VPS metrics."}
        \\{"provider":"hostinger","tag":"Billing: Catalog","method":"GET","path":"/api/billing/v1/catalog","operation_id":"billing_getCatalogItemListV1","path_params":[],"query_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":["#/components/schemas/Billing.V1.Catalog.CatalogItemCollection"]}],"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"POC reads billing catalog."}
        \\{"provider":"hostinger","tag":"VPS: Virtual machine","method":"POST","path":"/api/vps/v1/virtual-machines","operation_id":"VPS_purchaseNewVirtualMachineV1","path_params":[],"query_params":[],"request_body":{"required":true,"content_types":["application/json"],"schema_refs":["#/components/schemas/VPS.V1.VirtualMachine.PurchaseRequest"]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":["#/components/schemas/Billing.V1.Order.VirtualMachineOrderResource"]}],"support":"unsafe_mutation","mode":"dry_run","tests":"missing","deprecated":false,"notes":"No writes in POC."}
        \\
    ;

    var routes = try loadRoutesFromText(allocator, cloudflare, hostinger, .{ .provider = .hostinger, .tag_query = "vps", .support = .partial, .mode = .read });
    defer routes.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), routes.items.len);
    try std.testing.expectEqualStrings("hostinger", routes.items[0].route.provider.name());
    try std.testing.expectEqualStrings("VPS: Virtual machine", routes.items[0].route.tag);
    try std.testing.expectEqual(provider_routes.Method.GET, routes.items[0].route.method);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try routes.writeText(&out.writer, false);
    const text = try out.toOwnedSlice();
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Cloudio provider coverage routes\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "GET /api/vps/v1/virtual-machines/{virtualMachineId}/metrics | support=partial mode=read") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Billing: Catalog") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "POST /api/vps/v1/virtual-machines") == null);

    var detail_out = std.Io.Writer.Allocating.init(allocator);
    defer detail_out.deinit();
    try routes.writeText(&detail_out.writer, true);
    const detail_text = try detail_out.toOwnedSlice();
    defer allocator.free(detail_text);
    try std.testing.expect(std.mem.indexOf(u8, detail_text, "path_params: virtualMachineId(required)") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail_text, "query_params: date_from(required), date_to(required)") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail_text, "request_body: required=false content_types=none schema_refs=none") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail_text, "200 content_types=application/json schema_refs=#/components/schemas/VPS.V1.VirtualMachine.MetricsResource") != null);

    var json_out = std.Io.Writer.Allocating.init(allocator);
    defer json_out.deinit();
    try routes.writeJson(&json_out.writer, .{ .provider = .hostinger, .tag_query = "vps", .support = .partial, .mode = .read });
    const json = try json_out.toOwnedSlice();
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"coverage_routes\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"filter\":{\"provider\":\"hostinger\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"family\":\"all\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"count\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"operation_id\":\"VPS_getMetricsV1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"path_params\":[{\"name\":\"virtualMachineId\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"query_params\":[{\"name\":\"date_from\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"request_body\":{\"required\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"responses\":[{\"status\":\"200\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"security\":{\"required\":false") != null);

    var mutations = try loadRoutesFromText(allocator, cloudflare, hostinger, .{ .provider = .hostinger, .support = .unsafe_mutation, .mode = .dry_run });
    defer mutations.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), mutations.items.len);
    try std.testing.expectEqual(provider_routes.Method.POST, mutations.items[0].route.method);

    var family_routes = try loadRoutesFromText(allocator, cloudflare, hostinger, .{ .provider = .hostinger, .family = .hostinger_vps });
    defer family_routes.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), family_routes.items.len);
    for (family_routes.items) |row| {
        try std.testing.expectEqualStrings("VPS: Virtual machine", row.route.tag);
    }

    var exact_operation = try loadRoutesFromText(allocator, cloudflare, hostinger, .{ .provider = .hostinger, .operation_id = "VPS_getMetricsV1" });
    defer exact_operation.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), exact_operation.items.len);
    try std.testing.expectEqualStrings("/api/vps/v1/virtual-machines/{virtualMachineId}/metrics", exact_operation.items[0].route.path_template);

    var exact_method_path = try loadRoutesFromText(allocator, cloudflare, hostinger, .{ .provider = .hostinger, .method = .GET, .path_template = "/api/billing/v1/catalog" });
    defer exact_method_path.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), exact_method_path.items.len);
    try std.testing.expectEqualStrings("billing_getCatalogItemListV1", exact_method_path.items[0].route.operation_id.?);

    var mismatched_method = try loadRoutesFromText(allocator, cloudflare, hostinger, .{ .provider = .hostinger, .method = .POST, .path_template = "/api/billing/v1/catalog" });
    defer mismatched_method.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), mismatched_method.items.len);
}

test "captures generic route read results into snapshots and provider raw" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/route-capture.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    const cloudflare =
        \\{"provider":"cloudflare","tag":"Accounts","method":"GET","path":"/accounts","operation_id":"accounts-list","path_params":[],"query_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ok"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS: Virtual machine","method":"GET","path":"/api/vps/v1/virtual-machines","operation_id":"VPS_getVirtualMachinesV1","path_params":[],"query_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":["#/components/schemas/VPS.V1.VirtualMachine.VirtualMachineCollection"]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"POC lists VPS."}
        \\
    ;

    var routes = try loadRoutesFromText(allocator, cloudflare, hostinger, .{ .provider = .hostinger, .operation_id = "VPS_getVirtualMachinesV1" });
    defer routes.deinit(allocator);
    const route = try selectSingleRoute(routes.items);
    const body = try allocator.dupe(u8, "{\"password\":\"super-secret-password\",\"data\":[{\"id\":1307809,\"hostname\":\"srv1307809.hstgr.cloud\",\"state\":\"running\"}]}");
    const result = provider_route_result.matchReadRouteResponse(route.route, .{ .status = .ok, .body = body });
    defer result.deinit(allocator);

    const json = try captureRouteReadResultJson(
        allocator,
        &db,
        route.route,
        .{},
        result,
        .{ .kind = "route-vps-inventory", .target = "test-vps-list" },
    );
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"captured\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"provider_raw\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"normalized_resources\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"typed_rows\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"snapshot_id\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"route-vps-inventory\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"target\":\"test-vps-list\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"body_included\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "super-secret-password") == null);
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("snapshots"));
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("provider_raw"));
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("audit_events"));
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("hostinger_resources"));
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("hostinger_inventory_items"));
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("hostinger_vps"));
    var resource_rows = try db.hostingerResourceList(allocator);
    defer resource_rows.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), resource_rows.items.len);
    try std.testing.expectEqualStrings("route-vps-inventory/1307809", resource_rows.items[0].name);
    try std.testing.expect(std.mem.indexOf(u8, resource_rows.items[0].value, "running srv1307809.hstgr.cloud") != null);
}

test "captures Cloudflare DNS route into typed records table" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/route-cloudflare-dns-records.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    const cloudflare =
        \\{"provider":"cloudflare","tag":"DNS Records for a Zone","method":"GET","path":"/zones/{zone_id}/dns_records","operation_id":"dns-records-for-a-zone-list-dns-records","path_params":[{"name":"zone_id","required":true,"style":null,"explode":null,"schema":{"schema_refs":[],"types":["string"],"formats":[],"enum_values":[]}}],"query_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ok"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS: Virtual machine","method":"GET","path":"/api/vps/v1/virtual-machines","operation_id":"VPS_getVirtualMachinesV1","path_params":[],"query_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ok"}
        \\
    ;

    var routes = try loadRoutesFromText(allocator, cloudflare, hostinger, .{ .provider = .cloudflare, .operation_id = "dns-records-for-a-zone-list-dns-records" });
    defer routes.deinit(allocator);
    const route = try selectSingleRoute(routes.items);
    const body = try allocator.dupe(u8,
        \\{"result":[{"id":"dns-1","name":"plosca.ru","type":"A","content":"76.13.130.170","ttl":1,"proxied":false}],"success":true,"errors":[],"messages":[]}
    );
    const result = provider_route_result.matchReadRouteResponse(route.route, .{ .status = .ok, .body = body });
    defer result.deinit(allocator);

    const json = try captureRouteReadResultJson(
        allocator,
        &db,
        route.route,
        .{ .path_params = &.{.{ .name = "zone_id", .value = "zone-1" }} },
        result,
        .{ .kind = "route-cloudflare-dns-records", .target = "zone-1" },
    );
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"normalized_resources\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"typed_rows\":2") != null);
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("cloudflare_resources"));
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("cloudflare_inventory_items"));
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("cloudflare_dns_records"));
}

test "captures Cloudflare security route into typed security table" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const db_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/route-cloudflare-security.db", .{tmp.sub_path});
    defer allocator.free(db_path);
    var db = try Db.open(std.testing.io, db_path);
    defer db.close();
    try db.initSchema();

    const cloudflare =
        \\{"provider":"cloudflare","tag":"Email Security Settings","method":"GET","path":"/accounts/{account_id}/email-security/settings/allow_policies","operation_id":"email-security-list-allow-policies","path_params":[{"name":"account_id","required":true}],"query_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["api_token"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ok"}
        \\
    ;
    const hostinger =
        \\{"provider":"hostinger","tag":"VPS: Virtual machine","method":"GET","path":"/api/vps/v1/virtual-machines","operation_id":"VPS_getVirtualMachinesV1","path_params":[],"query_params":[],"request_body":{"required":false,"content_types":[],"schema_refs":[]},"responses":[{"status":"200","content_types":["application/json"],"schema_refs":[]}],"security":{"required":true,"alternatives":[["apiToken"]]},"support":"partial","mode":"read","tests":"fixture","deprecated":false,"notes":"ok"}
        \\
    ;

    var routes = try loadRoutesFromText(allocator, cloudflare, hostinger, .{ .provider = .cloudflare, .operation_id = "email-security-list-allow-policies" });
    defer routes.deinit(allocator);
    const route = try selectSingleRoute(routes.items);
    const body = try allocator.dupe(u8,
        \\{"result":[{"policy_id":"policy-1","name":"Trusted sender","is_enabled":true,"action":"allow","pattern":"*@example.com","domain":"example.com","created_at":"2026-06-17T00:00:00Z"}],"success":true,"errors":[],"messages":[]}
    );
    const result = provider_route_result.matchReadRouteResponse(route.route, .{ .status = .ok, .body = body });
    defer result.deinit(allocator);

    const json = try captureRouteReadResultJson(
        allocator,
        &db,
        route.route,
        .{ .path_params = &.{.{ .name = "account_id", .value = "acct-1" }} },
        result,
        .{ .kind = "route-cloudflare-email-security", .target = "acct-1" },
    );
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"normalized_resources\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"typed_rows\":2") != null);
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("cloudflare_resources"));
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("cloudflare_inventory_items"));
    try std.testing.expectEqual(@as(i64, 1), try db.countTable("cloudflare_security_items"));
}
