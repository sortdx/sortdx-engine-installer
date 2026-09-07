# Storage Engine installer

Installs the SortDX Storage Engine from a prebuilt release. Source is private:

https://github.com/sortdx/storage-engine.git

## Install

```bash
./install.sh
```

Or:

```bash
curl -fsSL http://get.sortdx.com/sortdx-storage-engine | bash
```

The script downloads:

`https://downloads.sortdx.com/sortdx-storage-engine/releases/v1.0.0/storage-engine-linux-amd64`

and installs it as `~/.local/bin/sortdx` (binary stored in `~/.sortdx/bin/sortdx`).

## Options

| Flag / env | Default | Purpose |
|---|---|---|
| `--prefix` / `SORTDX_PREFIX` | `~/.sortdx` | Install home |
| `--bin-dir` / `SORTDX_BIN_DIR` | `~/.local/bin` | Shim on PATH |
| `--version` / `SORTDX_VERSION` | latest | Release tag |
| `SORTDX_DOWNLOAD_URL` | constructed | Override full binary URL |
| `--systemd` | off | Linux user unit |
| `STORAGE_DATABASE_*` | `storage` @ `127.0.0.1:5432` | PostgreSQL connection |
| `SORTDX_SKIP_POSTGRES` | `0` | Skip role/database creation |

On install the script creates the local PostgreSQL role and database (when the host is localhost), writes connection settings to `~/.sortdx/.env`, and loads that file from the `sortdx` wrapper and systemd unit.

Other platforms use the same pattern: `storage-engine-<os>-<arch>` under the same version directory.
