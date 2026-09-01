# Storage Engine installer

Installs the SortDX Storage Engine from a prebuilt release. Source is private:

https://github.com/sortdx/storage-engine.git

## Install

```bash
./install.sh
```

Or:

```bash
curl -fsSL https://downloads.sortdx.com/releases/v1.0.0/install.sh | bash
```

The script downloads:

`https://downloads.sortdx.com/releases/v1.0.0/storage-engine-linux-amd64`

and installs it as `~/.local/bin/sortdx` (binary stored in `~/.sortdx/bin/sortdx`).

## Options

| Flag / env | Default | Purpose |
|---|---|---|
| `--prefix` / `SORTDX_PREFIX` | `~/.sortdx` | Install home |
| `--bin-dir` / `SORTDX_BIN_DIR` | `~/.local/bin` | Shim on PATH |
| `--version` / `SORTDX_VERSION` | `v1.0.0` | Release tag |
| `SORTDX_DOWNLOAD_URL` | constructed | Override full binary URL |
| `--systemd` | off | Linux user unit |

Other platforms use the same pattern: `storage-engine-<os>-<arch>` under the same version directory.
