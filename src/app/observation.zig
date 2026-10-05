//! Freshness of a stored observation, shared by every page that shows one.

const std = @import("std");
const core_config = @import("../core/config.zig");
const db_store = @import("../db/store.zig");

pub const Freshness = enum {
    current,
    stale,
    unavailable,

    pub fn label(self: Freshness) []const u8 {
        return switch (self) {
            .current => "Current",
            .stale => "Stale",
            .unavailable => "Unavailable",
        };
    }
};

/// An observation stays current for two refresh intervals, never less than
/// ten minutes, so a slow scheduled refresh does not flap writes off.
pub fn freshAfterSeconds(config: core_config.Config) i64 {
    return @max(@as(i64, config.refresh_seconds) * 2, 600);
}

/// Unavailable until one collection has succeeded; stale when the latest
/// attempt failed or the last success is older than the freshness window.
pub fn freshness(observation: ?db_store.Observation, config: core_config.Config) Freshness {
    const value = observation orelse return .unavailable;
    if (!value.hasSuccessfulObservation()) return .unavailable;
    if (!std.mem.eql(u8, value.attempt_status, "ok")) return .stale;
    return if (value.age_seconds >= 0 and value.age_seconds <= freshAfterSeconds(config)) .current else .stale;
}

/// The last successful observation time, or empty when none succeeded.
pub fn observedAt(observation: ?db_store.Observation) []const u8 {
    const value = observation orelse return "";
    return if (value.hasSuccessfulObservation()) value.observed_at else "";
}
