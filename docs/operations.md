# Operations Guide

## Logging

Each run produces:

- text log: `server-bootstrap.log`
- JSON events: `events.jsonl`

Default locations:

- root: `/var/log/server-bootstrap`
- non-root fallback: `/tmp/server-bootstrap`

Override with:

- `BOOTSTRAP_LOG_DIR`

## State file

Run status is written to `state.json`:

- `run_id`, timestamps, version
- action/profile/dry-run metadata
- per-module status and details

Default locations:

- root: `/var/lib/server-bootstrap/state.json`
- non-root fallback: `/tmp/server-bootstrap-state/state.json`

Override with:

- `BOOTSTRAP_STATE_DIR`

## Locking

To prevent concurrent runs:

- Uses `flock` when available.
- Falls back to directory lock (`<lock>.dir`) if `flock` is not present.

Default lock file:

- root: `/var/lock/server-bootstrap.lock`
- non-root fallback: `/tmp/server-bootstrap.lock`

Override with:

- `BOOTSTRAP_LOCK_FILE`

## Failure handling

Default behavior:
- stop on first module failure.

Optional behavior:
- continue across modules using `BOOTSTRAP_CONTINUE_ON_ERROR=1`.

## Troubleshooting examples

Show planned actions without privilege:

```bash
./main.sh --plan --modules ssh-keys,webmin
```

Dry-run apply flow without writing:

```bash
BOOTSTRAP_DRY_RUN=1 ./main.sh --apply --modules docker
```

Verbose execution:

```bash
sudo BOOTSTRAP_VERBOSE=1 ./main.sh --apply --profile prod --modules docker
```
