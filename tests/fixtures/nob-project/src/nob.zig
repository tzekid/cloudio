const std = @import("std");
const nob = @import("nob");

pub fn main(init: std.process.Init) !void {
    try nob.dispatch(init, .{
        .project_id = "dev.cloudio.acceptance",
        .build_id = "cloudio-acceptance-v1",
        .observe = observe,
        .actions = &.{
            nob.action("check", planCheck, runCheck),
            nob.action("fail", planFail, runFail),
            nob.action("slow", planSlow, runSlow),
            nob.action("secret-check", planSecretCheck, runSecretCheck),
        },
    });
}

fn observe(context: *nob.ObserveContext) !void {
    const facts: std.json.ObjectMap = .empty;
    try context.builder.resource("workspace", .healthy, "fixture workspace is available", .{ .object = facts });
    try context.builder.result(.healthy, "acceptance fixture is ready");
}

fn planCheck(context: *nob.PlanContext) !void {
    try context.builder.downtime(1);
    try context.builder.stage("check", "Validate fixture inputs", true);
    try context.builder.stage("artifact", "Write retained result", true);
}

fn runCheck(context: *nob.RunContext) !void {
    try context.checkCancelled();
    try context.events.stageStarted("check", "Validate fixture inputs");
    try context.events.log(.info, "check", "fixture inputs accepted");
    try context.events.progress("check", 1, 1, "check");
    try context.events.stageFinished("check", .succeeded);
    try context.events.stageStarted("artifact", "Write retained result");
    try writeArtifact(context, "check-result", "check-result.txt", "fixture check completed\n");
    try context.events.stageFinished("artifact", .succeeded);
}

fn planFail(context: *nob.PlanContext) !void {
    try context.builder.stage("failure", "Exercise runner failure handling", false);
}

fn runFail(context: *nob.RunContext) !void {
    try context.events.stageStarted("failure", "Exercise runner failure handling");
    try context.events.log(.warning, "failure", "intentional fixture failure follows");
    return error.IntentionalFixtureFailure;
}

fn planSlow(context: *nob.PlanContext) !void {
    try context.builder.stage("wait", "Wait for cancellation", true);
}

fn runSlow(context: *nob.RunContext) !void {
    try context.events.stageStarted("wait", "Wait for cancellation");
    try writeArtifact(context, "cancel-marker", "cancel-marker.txt", "created before cancellation\n");
    var index: usize = 0;
    while (index < 400) : (index += 1) {
        try context.checkCancelled();
        if (index % 10 == 0) try context.events.progress("wait", index + 1, 400, "ticks");
        std.Io.Timeout.sleep(.{ .duration = .{ .raw = .fromMilliseconds(50), .clock = .awake } }, context.io) catch {};
    }
    try context.events.stageFinished("wait", .succeeded);
}

fn planSecretCheck(context: *nob.PlanContext) !void {
    try context.builder.stage("secret", "Verify logical secret delivery", true);
}

fn runSecretCheck(context: *nob.RunContext) !void {
    try context.events.stageStarted("secret", "Verify logical secret delivery");
    const path = try context.secretPath("fixture-token");
    defer context.allocator.free(path);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(context.io, path, context.allocator, .limited(4096));
    defer context.allocator.free(bytes);
    if (bytes.len == 0) return error.EmptyFixtureSecret;
    try context.events.log(.info, "secret", "logical secret was delivered without exposing it");
    try context.events.stageFinished("secret", .succeeded);
}

fn writeArtifact(context: *nob.RunContext, artifact_id: []const u8, filename: []const u8, contents: []const u8) !void {
    const path = try std.fs.path.join(context.allocator, &.{ context.artifact_dir, filename });
    defer context.allocator.free(path);
    try std.Io.Dir.cwd().writeFile(context.io, .{ .sub_path = path, .data = contents });
    try context.events.artifactFile(context.io, context.artifact_dir, artifact_id, "fixture-result", path);
}
