#!/usr/bin/env bash
# SortDX Storage Engine installer
#
# Downloads the prebuilt binary (private source lives at
# https://github.com/sortdx/storage-engine.git).
#
#   curl -fsSL https://downloads.sortdx.com/releases/v1.0.0/install.sh | bash
#   ./install.sh
#
# Optional:
#   ./install.sh --prefix /opt/sortdx
#   SORTDX_VERSION=v1.0.0 ./install.sh
set -euo pipefail

PREFIX="${SORTDX_PREFIX:-${HOME}/.sortdx}"
BIN_DIR="${SORTDX_BIN_DIR:-${HOME}/.local/bin}"
VERSION="${SORTDX_VERSION:-v1.0.0}"
DOWNLOAD_BASE="${SORTDX_DOWNLOAD_BASE:-https://downloads.sortdx.com/releases}"
DOWNLOAD_URL="${SORTDX_DOWNLOAD_URL:-}"
REPO="${SORTDX_REPO:-https://github.com/sortdx/storage-engine.git}"
SYSTEMD=0

bold=""
dim=""
red=""
green=""
reset=""
if [ -t 1 ]; then
	bold="$(printf '\033[1m')"
	dim="$(printf '\033[2m')"
	red="$(printf '\033[31m')"
	green="$(printf '\033[32m')"
	reset="$(printf '\033[0m')"
fi

info() { printf '%s==>%s %s\n' "$bold" "$reset" "$*"; }
ok() { printf '%sOK%s  %s\n' "$green" "$reset" "$*"; }
warn() { printf '%s!!%s  %s\n' "$red" "$reset" "$*"; }
die() { warn "$*"; exit 1; }

usage() {
	cat <<EOF
Install the SortDX Storage Engine (sortdx) from a prebuilt release binary.

Usage:
  curl -fsSL <install-url> | bash
  ./install.sh [options]

Options:
  --prefix DIR     Install home (default: ~/.sortdx)
  --bin-dir DIR    Directory for the sortdx shim (default: ~/.local/bin)
  --version TAG    Release tag (default: v1.0.0)
  --systemd        Install a user systemd unit (Linux)
  -h, --help       Show this help

Environment:
  SORTDX_VERSION         Same as --version
  SORTDX_DOWNLOAD_BASE   Release root (default: https://downloads.sortdx.com/releases)
  SORTDX_DOWNLOAD_URL    Full binary URL (overrides version/os/arch)
  SORTDX_PREFIX          Same as --prefix
  SORTDX_BIN_DIR         Same as --bin-dir
  CLOUD_BASE_URL         Written into config.yaml if set
  STORAGE_ROOT           Written into config.yaml if set

Default binary:
  ${DOWNLOAD_BASE}/${VERSION}/storage-engine-linux-amd64

Source (private):
  ${REPO}
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
	--prefix)
		PREFIX="${2:?}"
		shift 2
		;;
	--bin-dir)
		BIN_DIR="${2:?}"
		shift 2
		;;
	--version)
		VERSION="${2:?}"
		shift 2
		;;
	--systemd)
		SYSTEMD=1
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		die "unknown option: $1"
		;;
	esac
done

need_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

os_name() {
	uname -s | tr '[:upper:]' '[:lower:]'
}

go_arch() {
	case "$(uname -m)" in
	x86_64 | amd64) printf 'amd64\n' ;;
	aarch64 | arm64) printf 'arm64\n' ;;
	*) die "unsupported architecture: $(uname -m)" ;;
	esac
}

release_url() {
	if [ -n "$DOWNLOAD_URL" ]; then
		printf '%s\n' "$DOWNLOAD_URL"
		return
	fi
	printf '%s/%s/storage-engine-%s-%s\n' "$DOWNLOAD_BASE" "$VERSION" "$(os_name)" "$(go_arch)"
}

download_binary() {
	need_cmd curl
	local url dest tmp
	url="$(release_url)"
	dest="${PREFIX}/bin/sortdx"
	tmp="$(mktemp)"
	info "Downloading ${url}"
	if ! curl -fL --retry 3 --retry-delay 1 -o "$tmp" "$url"; then
		rm -f "$tmp"
		die "download failed: ${url}"
	fi
	if [ ! -s "$tmp" ]; then
		rm -f "$tmp"
		die "downloaded file is empty: ${url}"
	fi
	# CDN error pages are usually HTML; a real binary is not.
	if head -c 64 "$tmp" | grep -qi '<html\|<!doctype'; then
		rm -f "$tmp"
		die "download returned HTML, not a binary: ${url}"
	fi
	mkdir -p "${PREFIX}/bin"
	install -m 0755 "$tmp" "$dest"
	rm -f "$tmp"
	ok "installed ${dest}"
}

write_config() {
	mkdir -p "${PREFIX}/config" "${PREFIX}/data" "${PREFIX}/storage"
	local cfg="${PREFIX}/config/config.yaml"
	if [ -f "$cfg" ]; then
		ok "keeping existing ${cfg}"
		return
	fi

	local secret cloud root
	secret="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
	cloud="${CLOUD_BASE_URL:-http://127.0.0.1:8090}"
	root="${STORAGE_ROOT:-${PREFIX}/storage}"

	cat >"$cfg" <<EOF
server:
  host: 0.0.0.0
  port: 8080

storage:
  driver: local
  root: ${root}

database:
  driver: postgres
  host: ${STORAGE_DATABASE_HOST:-127.0.0.1}
  port: ${STORAGE_DATABASE_PORT:-5432}
  user: ${STORAGE_DATABASE_USER:-storage}
  password: ${STORAGE_DATABASE_PASSWORD:-storage}
  name: ${STORAGE_DATABASE_NAME:-storage}
  sslmode: ${STORAGE_DATABASE_SSLMODE:-disable}

jwt:
  secret: ${secret}

cloud:
  base_url: ${cloud}
  install_state_path: ${PREFIX}/data/installation.json

invitation:
  expiry_hours: 168

app:
  base_url: http://127.0.0.1:8080
EOF
	ok "wrote ${cfg}"
}

write_wrapper() {
	mkdir -p "$BIN_DIR"
	local wrap="${BIN_DIR}/sortdx"
	cat >"$wrap" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export SORTDX_HOME="${PREFIX}"
cd "\$SORTDX_HOME"
exec "${PREFIX}/bin/sortdx" "\$@"
EOF
	chmod +x "$wrap"
	ok "installed ${wrap}"
}

ensure_path() {
	case ":${PATH}:" in
	*":${BIN_DIR}:"*) return ;;
	esac
	local rc=""
	if [ -n "${ZSH_VERSION:-}" ] || [ "$(basename "${SHELL:-}")" = "zsh" ]; then
		rc="${HOME}/.zshrc"
	else
		rc="${HOME}/.bashrc"
	fi
	local line="export PATH=\"${BIN_DIR}:\$PATH\""
	if [ -f "$rc" ] && grep -Fqs "$BIN_DIR" "$rc"; then
		return
	fi
	printf '\n# SortDX Storage Engine\n%s\n' "$line" >>"$rc"
	ok "added ${BIN_DIR} to PATH in ${rc}"
}

write_systemd() {
	[ "$(os_name)" = "linux" ] || die "--systemd is only supported on Linux"
	local unit_dir="${HOME}/.config/systemd/user"
	mkdir -p "$unit_dir"
	cat >"${unit_dir}/sortdx-storage-engine.service" <<EOF
[Unit]
Description=SortDX Storage Engine
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${PREFIX}
ExecStart=${PREFIX}/bin/sortdx run
Restart=on-failure
RestartSec=3
Environment=SORTDX_HOME=${PREFIX}

[Install]
WantedBy=default.target
EOF
	if command -v systemctl >/dev/null 2>&1; then
		systemctl --user daemon-reload || true
		systemctl --user enable --now sortdx-storage-engine.service || warn "enable the unit with: systemctl --user enable --now sortdx-storage-engine"
	fi
	ok "systemd user unit sortdx-storage-engine.service"
}

check_postgres() {
	if command -v pg_isready >/dev/null 2>&1; then
		if pg_isready -q -h "${STORAGE_DATABASE_HOST:-127.0.0.1}" -p "${STORAGE_DATABASE_PORT:-5432}"; then
			ok "PostgreSQL is reachable"
			return
		fi
	fi
	warn "PostgreSQL is required at runtime (default 127.0.0.1:5432, db/user/password: storage)."
}

main() {
	case "$(os_name)" in
	linux | darwin) ;;
	*) die "unsupported OS: $(os_name)" ;;
	esac

	info "Installing SortDX Storage Engine ${VERSION}"
	mkdir -p "$PREFIX" "$BIN_DIR"
	download_binary
	write_config
	write_wrapper
	ensure_path
	if [ "$SYSTEMD" -eq 1 ]; then
		write_systemd
	fi
	check_postgres

	printf '\n%sSortDX Storage Engine installed.%s\n\n' "$bold" "$reset"
	printf '  Home     %s\n' "$PREFIX"
	printf '  Binary   %s/sortdx\n' "$BIN_DIR"
	printf '  Release  %s\n' "$(release_url)"
	printf '  Config   %s/config/config.yaml\n\n' "$PREFIX"
	printf '%sNext:%s\n' "$bold" "$reset"
	printf '  export PATH="%s:$PATH"\n' "$BIN_DIR"
	printf '  sortdx install register --cloud %s --token <bearer> --name %s\n' \
		"${CLOUD_BASE_URL:-http://127.0.0.1:8090}" "$(hostname -s 2>/dev/null || echo engine-1)"
	printf '  sortdx run\n\n'
	printf '%sListens on 0.0.0.0:8080%s\n' "$dim" "$reset"
}

main
