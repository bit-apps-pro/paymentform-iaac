# Database Replication — Operations

Day-2 ops for the replication topology. Use this once replication is already set up; first-time setup lives in [`database-replica-setup.md`](database-replica-setup.md).

## Topology

```
              ┌─────────────────────────────────┐
              │  AWS us-east-1                  │
              │  ┌─────────────┐                │
              │  │  primary    │ ── WAL ──► AZ-b replica
              │  │  pgbouncer  │                │
              │  └──────┬──────┘                │
              └─────────┼───────────────────────┘
                        │ 5432 via cloudflared tunnel
                        ▼
                ┌───────────────┐
                │ cloudflared   │ db-tunnel.paymentform.io
                └───────┬───────┘
            ┌───────────┴─────────────┐
            ▼                         ▼
    ┌─────────────┐           ┌─────────────┐
    │ hel1 replica │           │ sin1 replica │
    └─────────────┘           └─────────────┘
```

- **AZ-b replica**: streaming, sync candidate
- **Hetzner hel1, sin1**: streaming via Cloudflare tunnel, async, read-only

## Monitor

Run on each replica. Lag in seconds is the only number that matters for ops.

```bash
# On any replica:
psql -U postgres -c "SELECT
  now() - pg_last_xact_replay_timestamp() AS lag_seconds,
  pg_last_wal_receive_lsn() AS received,
  pg_last_wal_replay_lsn() AS replayed,
  pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn()) AS receive_to_replay_bytes;
"
```

On the **primary** see who is connected:

```bash
psql -U postgres -c "SELECT
  client_addr, state, sync_state,
  pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_lag_bytes,
  reply_time
FROM pg_stat_replication;
"
```

Healthy: `lag_seconds < 5`, `state = streaming`, `sync_state = async` (or `sync` for AZ-b replica if you configured synchronous_commit), `replay_lag_bytes` small and not growing.

## Alerts to set up

| Metric | Threshold | Action |
|---|---|---|
| `lag_seconds` > 60 | warn | Page on-call |
| `lag_seconds` > 300 | critical | Investigate immediately (see issues below) |
| `pg_stat_replication` row missing for a known replica | critical | Tunnel down OR replica process dead |
| WAL archive lag (last archived WAL > 5 min old) | critical | pgbackrest not keeping up |

A barebones Prometheus exporter or a periodic cron writing to `status.paymentform.io/api/logs/batch` is sufficient — keep ops noise low.

## Restart a replica

When a replica falls behind, hangs, or you have to maintenance-cycle it.

```bash
ssh ec2-user@postgres-replica   # or root@hel1, root@sin1
sudo systemctl status postgresql
sudo systemctl restart postgresql
psql -U postgres -c 'SELECT pg_is_in_recovery();'  # must return true
psql -U postgres -c "SELECT now() - pg_last_xact_replay_timestamp();"
```

Lag should resume catching up. If it grows: replication slot is gone, WAL is missing, or network is broken — see issues.

## Initial sync of a **new** replica

Or after a Hetzner replica is reset / re-provisioned. Authoritative procedure lives in `database-replica-setup.md` — this is the abbreviated version.

```bash
# On the new replica:
sudo systemctl stop postgresql
sudo -u postgres rm -rf /var/lib/postgresql/17/main/*

sudo -u postgres pg_basebackup \
  -h db-tunnel.paymentform.io \
  -U replicator \
  -D /var/lib/postgresql/17/main \
  -P -X stream -R -S replica_<name>

sudo systemctl start postgresql
psql -U postgres -c 'SELECT pg_is_in_recovery();'  # true
```

Things that bite people:

- **Replication slot already exists** on primary → `pg_basebackup` errors. Drop it: `SELECT pg_drop_replication_slot('replica_<name>');` on primary first.
- **Tunnel auth not configured** → connection times out via `db-tunnel.paymentform.io`. Check `cloudflared` service status on the primary side; see `database-tunnel-vpn.md`.

## Re-attach replica after primary promotion

After a failover (see `disaster-recovery.md` Scenario 2b), the *old* primary may come back. It can't rejoin as a replica without surgery — its timeline diverged.

Two paths:

### Path A — `pg_rewind` (fast, requires checksums on primary)

```bash
sudo systemctl stop postgresql
sudo -u postgres pg_rewind \
  --target-pgdata=/var/lib/postgresql/17/main \
  --source-server="host=<new-primary> port=5432 user=postgres dbname=postgres"

# Add standby.signal + primary_conninfo
sudo -u postgres tee -a /var/lib/postgresql/17/main/postgresql.auto.conf <<EOF
primary_conninfo = 'host=<new-primary> user=replicator application_name=replica_old-primary'
primary_slot_name = 'replica_old_primary'
EOF
sudo -u postgres touch /var/lib/postgresql/17/main/standby.signal

# Make sure the slot exists on new primary
psql -h <new-primary> -U postgres -c "SELECT pg_create_physical_replication_slot('replica_old_primary');"

sudo systemctl start postgresql
```

### Path B — `pg_basebackup` (safe, slow, full re-sync)

Same procedure as "Initial sync" above, pointing at the new primary instead.

Choose B when the old primary's data is suspicious (FS corruption, partial writes); A when you just diverged due to a clean failover.

## Switch a replica's upstream

When you promote the AZ-b replica and want Hetzner nodes to follow it:

```bash
# On each Hetzner replica:
sudo -u postgres psql -c "ALTER SYSTEM SET primary_conninfo = 'host=<new-primary-ip> user=replicator application_name=replica_<name>';"
sudo -u postgres psql -c "SELECT pg_reload_conf();"

# Force a reconnect:
sudo systemctl restart postgresql
psql -U postgres -c "SELECT now() - pg_last_xact_replay_timestamp();"
```

If you went through `tunnel-db`, you don't need to change the host (it stays `db-tunnel.paymentform.io`) — instead update the cloudflared route on the primary side. See `database-tunnel-vpn.md`.

## Drop a replica permanently

Don't forget the slot on the primary, or WAL accumulates and the primary's disk fills.

```bash
# On primary:
psql -U postgres -c "SELECT pg_drop_replication_slot('replica_<name>');"

# On the replica:
sudo systemctl stop postgresql && sudo systemctl disable postgresql
```

## Common issues

| Symptom | Cause | Resolution |
|---|---|---|
| Replica `state = catchup` for hours | Big batch on primary or replica fell far behind | Check `pg_stat_activity` on primary for long txns. If lag is bytes, just wait. If WAL was already recycled, re-pg_basebackup. |
| `requested WAL segment X has already been removed` on replica | `wal_keep_size` too small + slot wasn't preserving | Increase `wal_keep_size` on primary AND ensure replica uses a slot (`primary_slot_name`). Re-pg_basebackup the replica. |
| Replica caught up but `sync_state` stuck at `async` for one we want sync | `synchronous_standby_names` not set or not matching `application_name` | Set on primary: `ALTER SYSTEM SET synchronous_standby_names = 'FIRST 1 (replica_b)';` then reload. Confirm replica's `application_name=replica_b` in its `primary_conninfo`. |
| Slot disk usage growing without bound | Replica disconnected, slot keeps WAL | `SELECT slot_name, active, wal_status, pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) FROM pg_replication_slots;`. If replica truly gone, `pg_drop_replication_slot`. |
| Hetzner replica drops connection every few hours | Cloudflared tunnel idle timeout | Add TCP keepalives: `ALTER SYSTEM SET tcp_keepalives_idle = 60; tcp_keepalives_interval = 10; tcp_keepalives_count = 5;` on primary. Reload. |
| Hetzner replica throws `FATAL: requested timeline N is not a child of this server's history` | Replica restored from one primary, now talking to a different one (post-failover, no pg_rewind) | Re-pg_basebackup from the new primary, OR pg_rewind if timelines branch cleanly. |
| `pg_basebackup` is slow over tunnel | All replication WAL traffic also goes through tunnel; saturates one cloudflared connection | Run initial base backup from a snapshot/restore via R2 (pgbackrest) instead. Then stream WAL via tunnel. |
| Replica shows correct LSN but data is stale | Long-running read transaction blocking apply (hot standby feedback) | `SELECT * FROM pg_stat_activity WHERE state = 'active';` on replica; kill the blocker or let it finish. |
| pgbouncer on primary can't reach Postgres after restart | `unix_socket_directories` mismatch or path symlink broken | `cat /etc/pgbouncer/pgbouncer.ini`; verify `host=/var/run/postgresql`. Restart pgbouncer after PG. |

## Weekly health check

A 5-minute manual check that's worth keeping on the on-call calendar:

```bash
# On primary:
psql -U postgres -c "SELECT client_addr, state, sync_state, replay_lag FROM pg_stat_replication;"
psql -U postgres -c "SELECT slot_name, active, wal_status FROM pg_replication_slots;"

# On each replica:
psql -U postgres -c "SELECT now() - pg_last_xact_replay_timestamp() AS lag;"

# Disk usage on primary's pg_wal — guard against runaway WAL retention
ssh ec2-user@primary 'df -h /var/lib/postgresql/17/main/pg_wal'
```

If anything off, jump to the issues table.
