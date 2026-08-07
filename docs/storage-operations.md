# Storage operations

Cloudio keeps destructive storage work in the host CLI. The Dashboard only
shows a read-only warning when the configured budget is near exhaustion or a
safe maintenance run would not fit.

## Policy and accounting

```toml
[storage]
auto_prune = false
backup_root = ".cloudio/backups"
disk_budget_bytes = 0
snapshot_retention_days = 14
provider_raw_retention_days = 14
metrics_retention_days = 30
maintenance_interval_hours = 24
maintenance_batch_rows = 5000
```

`disk_budget_bytes = 0` disables budget warnings. When a budget is configured,
Cloudio warns at 80 percent utilization and whenever the current database
cannot be backed up and compacted within that budget.

Run:

```sh
cloudio maintenance status
cloudio maintenance status --json
```

The report separates:

- the database file, WAL, and shared-memory file;
- the current log;
- every regular file below `storage.backup_root`;
- retained nob operation state and artifacts;
- the nob runner cache;
- logical database pages, reclaimable pages, and row eligibility.

Symlinks are not followed during directory accounting. An unsafe or
unreasonably large inventory is reported as an error rather than silently
under-counted.

Backup retention is deliberately independent from database-row retention.
Cloudio never deletes files under `storage.backup_root`, including during
scheduled pruning. Copy important backups off-host and remove old ones only as
an explicit operator decision after confirming a newer recovery point.

## Required free space

Before applying maintenance, reserve at least the
`maintenance_headroom_bytes` reported by `maintenance status`. The estimate is
two database copies plus the current WAL: one copy for the verified online
backup and one for SQLite compaction. The destination filesystem for the
backup and the database filesystem must both have enough space when they are
different.

## Safe maintenance procedure

1. Inspect current usage and eligible rows:

   ```sh
   cloudio maintenance status
   cloudio maintenance run
   ```

2. Choose a new backup path. The path must not already exist:

   ```sh
   cloudio maintenance run --apply \
     --backup .cloudio/backups/before-maintenance-YYYYMMDD-HHMMSS.db
   ```

3. Confirm the command reports a verified backup, the expected deleted row
   counts, and `pruned=true compacted=true`.

4. Re-run checks:

   ```sh
   cloudio maintenance status
   cloudio doctor
   ```

Use `maintenance prune --apply --backup <new-path>` when compaction is not
needed, or `maintenance compact --apply --backup <new-path>` when no row
retention should run. Both still require and verify a new backup first.

Scheduled retention runs only when `auto_prune = true`. It prunes eligible rows
and matching expired nob operation directories in bounded batches. It does not
compact the database and cannot run through the scheduler without the explicit
policy switch.

## Failure or interruption

If maintenance returns an error or the process is interrupted:

1. Do not retry with the same backup path and do not delete either database.
2. Stop the Cloudio service before replacing any database file.
3. Preserve the current database, WAL, and shared-memory files together as an
   incident copy.
4. Run `cloudio doctor` against the current database. If it opens and passes,
   retain the verified backup and investigate before retrying.
5. If restoration is required, copy the verified backup to a new candidate
   path, set mode `0600`, point a temporary Cloudio configuration at that copy,
   and run `cloudio doctor`. Only after that check succeeds should the normal
   database path be changed or atomically replaced while the service is
   stopped.
6. Start Cloudio and verify authentication, Dashboard source freshness, Audit,
   and the affected Projects runs before resuming mutations.

The backup command uses SQLite's online backup API, runs `integrity_check`,
rejects an existing destination, and applies mode `0600`. A failed backup is
removed; a verified backup is never overwritten by Cloudio.
