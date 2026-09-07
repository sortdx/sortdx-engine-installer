#!/usr/bin/env bash
# SortDX Storage Engine installer
#
# Installs the latest prebuilt SortDX Storage Engine binary.
#
# One-line install:
#   curl -fsSL https://get.sortdx.com/sortdx-storage-engine | bash
#
# Local install:
#   ./install.sh
#
# Specific version:
#   ./install.sh --version v1.0.0
#   SORTDX_VERSION=v1.0.0 ./install.sh
#
# Custom installation:
#   ./install.sh --prefix /opt/sortdx
#
# Systemd:
#   ./install.sh --systemd
#
# Environment:
#   SORTDX_VERSION
#   SORTDX_DOWNLOAD_BASE
#   SORTDX_LATEST_URL
#   SORTDX_DOWNLOAD_URL
#   SORTDX_PREFIX
#   SORTDX_BIN_DIR
#   CLOUD_BASE_URL
#   ENGINE_PUBLIC_URL
#   STORAGE_ROOT
#   STORAGE_DATABASE_HOST
#   STORAGE_DATABASE_PORT
#   STORAGE_DATABASE_USER
#   STORAGE_DATABASE_PASSWORD
#   STORAGE_DATABASE_NAME
#   STORAGE_DATABASE_SSLMODE
#   SORTDX_SKIP_POSTGRES

set -euo pipefail

# --------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------

PREFIX="${SORTDX_PREFIX:-${HOME}/.sortdx}"
BIN_DIR="${SORTDX_BIN_DIR:-${HOME}/.local/bin}"

# Empty means "automatically determine latest version".
VERSION="${SORTDX_VERSION:-}"

DOWNLOAD_BASE="${SORTDX_DOWNLOAD_BASE:-https://downloads.sortdx.com/sortdx-storage-engine/releases}"

LATEST_URL="${SORTDX_LATEST_URL:-https://downloads.sortdx.com/sortdx-storage-engine/releases/latest.json}"

# If specified, this completely overrides version/OS/architecture detection.
DOWNLOAD_URL="${SORTDX_DOWNLOAD_URL:-}"

REPO="${SORTDX_REPO:-https://github.com/sortdx/storage-engine.git}"

SYSTEMD=0
UNINSTALL=0
UNINSTALL_YES=0
PURGE_DATABASE=0

# PostgreSQL defaults (overridable via environment).
DB_HOST="${STORAGE_DATABASE_HOST:-127.0.0.1}"
DB_PORT="${STORAGE_DATABASE_PORT:-5432}"
DB_USER="${STORAGE_DATABASE_USER:-storage}"
DB_PASSWORD="${STORAGE_DATABASE_PASSWORD:-storage}"
DB_NAME="${STORAGE_DATABASE_NAME:-storage}"
DB_SSLMODE="${STORAGE_DATABASE_SSLMODE:-disable}"
SKIP_POSTGRES="${SORTDX_SKIP_POSTGRES:-0}"

# --------------------------------------------------------------------
# Colors
# --------------------------------------------------------------------

bold=""
dim=""
red=""
green=""
yellow=""
reset=""

if [ -t 1 ]; then
	bold="$(printf '\033[1m')"
	dim="$(printf '\033[2m')"
	red="$(printf '\033[31m')"
	green="$(printf '\033[32m')"
	yellow="$(printf '\033[33m')"
	reset="$(printf '\033[0m')"
fi

# --------------------------------------------------------------------
# Output helpers
# --------------------------------------------------------------------

info() {
	printf '%s==>%s %s\n' "$bold" "$reset" "$*"
}

ok() {
	printf '%sOK%s  %s\n' "$green" "$reset" "$*"
}

warn() {
	printf '%s!!%s  %s\n' "$red" "$reset" "$*"
}

die() {
	warn "$*"
	exit 1
}

# --------------------------------------------------------------------
# Usage
# --------------------------------------------------------------------

usage() {
	cat <<EOF
Install the SortDX Storage Engine from a prebuilt release binary.

Usage:

  curl -fsSL https://get.sortdx.com/sortdx-storage-engine | bash

  ./install.sh [options]

Options:

  --prefix DIR
      Installation home.
      Default: ~/.sortdx

  --bin-dir DIR
      Directory for the sortdx command.
      Default: ~/.local/bin

  --version TAG
      Install a specific release.
      Default: latest release

  --systemd
      Install and enable a user systemd service.
      Linux only.

  --uninstall
      Remove a previous installer-created install (requires --yes).

  --yes
      Confirm --uninstall.

  --purge-database
      With --uninstall, drop the local PostgreSQL database and role.

  -h, --help
      Show this help.

Environment:

  SORTDX_VERSION
      Specific release version.

  SORTDX_DOWNLOAD_BASE
      Release root.

      Default:
      https://downloads.sortdx.com/sortdx-storage-engine/releases

  SORTDX_LATEST_URL
      URL containing latest release information.

      Default:
      https://downloads.sortdx.com/sortdx-storage-engine/latest.json

  SORTDX_DOWNLOAD_URL
      Full binary URL.
      Overrides version/OS/architecture detection.

  SORTDX_PREFIX
      Same as --prefix.

  SORTDX_BIN_DIR
      Same as --bin-dir.

  CLOUD_BASE_URL
      SortDX Cloud Platform URL.

      Default:
      https://ngine.sortdx.com

  ENGINE_PUBLIC_URL
      URL teammates use to reach this engine.

      Example:
      http://192.168.1.100:8080

  STORAGE_ROOT
      Storage data directory.

  STORAGE_DATABASE_HOST
  STORAGE_DATABASE_PORT
  STORAGE_DATABASE_USER
  STORAGE_DATABASE_PASSWORD
  STORAGE_DATABASE_NAME
  STORAGE_DATABASE_SSLMODE
      PostgreSQL connection settings.
      Defaults: 127.0.0.1:5432 / user+db+password: storage / sslmode: disable

  SORTDX_SKIP_POSTGRES
      Set to 1 to skip creating the PostgreSQL role and database.

Latest release:

  ${LATEST_URL}

Release downloads:

  ${DOWNLOAD_BASE}

Private source repository:

  ${REPO}

EOF
}

# --------------------------------------------------------------------
# Parse arguments
# --------------------------------------------------------------------

while [ $# -gt 0 ]; do
	case "$1" in
	--prefix)
		PREFIX="${2:?missing value for --prefix}"
		shift 2
		;;

	--bin-dir)
		BIN_DIR="${2:?missing value for --bin-dir}"
		shift 2
		;;

	--version)
		VERSION="${2:?missing value for --version}"
		shift 2
		;;

	--systemd)
		SYSTEMD=1
		shift
		;;

	--uninstall)
		UNINSTALL=1
		shift
		;;

	--yes)
		UNINSTALL_YES=1
		shift
		;;

	--purge-database)
		PURGE_DATABASE=1
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

# --------------------------------------------------------------------
# Required commands
# --------------------------------------------------------------------

need_cmd() {
	command -v "$1" >/dev/null 2>&1 ||
		die "missing required command: $1"
}

# --------------------------------------------------------------------
# Operating system
# --------------------------------------------------------------------

os_name() {
	uname -s | tr '[:upper:]' '[:lower:]'
}

# --------------------------------------------------------------------
# CPU architecture
# --------------------------------------------------------------------

go_arch() {
	case "$(uname -m)" in
	x86_64 | amd64)
		printf 'amd64\n'
		;;

	aarch64 | arm64)
		printf 'arm64\n'
		;;

	*)
		die "unsupported architecture: $(uname -m)"
		;;
	esac
}

# --------------------------------------------------------------------
# Resolve latest version
# --------------------------------------------------------------------

resolve_latest_version() {
	# If user explicitly specified a version, don't query latest.json.
	if [ -n "$VERSION" ]; then
		ok "using requested version: ${VERSION}"
		return
	fi

	need_cmd curl

	info "Checking latest SortDX Storage Engine version..."

	local response
	response="$(curl \
		-fsSL \
		--retry 3 \
		--retry-delay 1 \
		"$LATEST_URL"
	)" || die "failed to retrieve latest version information: ${LATEST_URL}"

	# Expected JSON:
	#
	# {
	#   "product": "sortdx-storage-engine",
	#   "version": "v1.3.2"
	# }
	#
	VERSION="$(
		printf '%s' "$response" |
			grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' |
			head -1 |
			cut -d'"' -f4
	)"

	if [ -z "$VERSION" ]; then
		die "could not determine latest SortDX Storage Engine version from ${LATEST_URL}"
	fi

	ok "latest version: ${VERSION}"
}

# --------------------------------------------------------------------
# Release URL
# --------------------------------------------------------------------

release_url() {
	if [ -n "$DOWNLOAD_URL" ]; then
		printf '%s\n' "$DOWNLOAD_URL"
		return
	fi

	printf '%s/%s/storage-engine-%s-%s\n' \
		"$DOWNLOAD_BASE" \
		"$VERSION" \
		"$(os_name)" \
		"$(go_arch)"
}

# --------------------------------------------------------------------
# Download binary
# --------------------------------------------------------------------

download_binary() {
	need_cmd curl
	need_cmd install

	local url
	local dest
	local tmp

	url="$(release_url)"
	dest="${PREFIX}/bin/sortdx"

	tmp="$(mktemp)"

	info "Downloading SortDX Storage Engine"
	info "${url}"

	if ! curl \
		-fL \
		--retry 3 \
		--retry-delay 1 \
		-o "$tmp" \
		"$url"; then

		rm -f "$tmp"

		die "download failed: ${url}"
	fi

	if [ ! -s "$tmp" ]; then
		rm -f "$tmp"

		die "downloaded file is empty: ${url}"
	fi

	# Detect common HTML error pages.
	if head -c 256 "$tmp" |
		grep -qiE '<html|<!doctype|<head|<body'; then

		rm -f "$tmp"

		die "download returned HTML instead of a binary: ${url}"
	fi

	mkdir -p "${PREFIX}/bin"

	install -m 0755 "$tmp" "$dest"

	rm -f "$tmp"

	ok "installed ${dest}"
}

# --------------------------------------------------------------------
# Detect public URL
# --------------------------------------------------------------------

detect_public_url() {
	if [ -n "${ENGINE_PUBLIC_URL:-}" ]; then
		printf '%s' "$ENGINE_PUBLIC_URL"
		return
	fi

	local host

	host="$(
		hostname -f 2>/dev/null ||
			hostname -s 2>/dev/null ||
			echo 127.0.0.1
	)"

	printf 'http://%s:8080' "$host"
}

# --------------------------------------------------------------------
# SQL / URL helpers
# --------------------------------------------------------------------

sql_quote() {
	# Escape a literal for single-quoted SQL strings.
	printf "%s" "$1" | sed "s/'/''/g"
}

pg_ident() {
	# Quote a PostgreSQL identifier.
	printf '"%s"' "$(printf "%s" "$1" | sed 's/"/""/g')"
}

url_encode() {
	# Minimal RFC 3986 encode for passwords in DATABASE_URL.
	local raw="$1"
	local out=""
	local i c hex

	for ((i = 0; i < ${#raw}; i++)); do
		c="${raw:i:1}"
		case "$c" in
		[a-zA-Z0-9.~_-])
			out+="$c"
			;;
		*)
			printf -v hex '%%%02X' "'$c"
			out+="$hex"
			;;
		esac
	done

	printf '%s' "$out"
}

is_local_db_host() {
	case "$DB_HOST" in
	127.0.0.1 | localhost | ::1)
		return 0
		;;
	*)
		return 1
		;;
	esac
}

# --------------------------------------------------------------------
# Run psql as a local PostgreSQL superuser when possible
# --------------------------------------------------------------------

run_psql_admin() {
	if command -v sudo >/dev/null 2>&1 &&
		id postgres >/dev/null 2>&1 &&
		sudo -n -u postgres true >/dev/null 2>&1; then

		sudo -u postgres psql -v ON_ERROR_STOP=1 -d postgres "$@"
		return
	fi

	if [ "$(id -u)" -eq 0 ] && id postgres >/dev/null 2>&1; then
		# Pass args through a quoted remote command for su.
		local cmd="psql -v ON_ERROR_STOP=1 -d postgres"
		local a
		for a in "$@"; do
			cmd+=" $(printf '%q' "$a")"
		done
		su -s /bin/sh postgres -c "$cmd"
		return
	fi

	# Peer auth as current user (common on developer machines).
	psql -v ON_ERROR_STOP=1 -d postgres "$@"
}

# --------------------------------------------------------------------
# PostgreSQL role + database
# --------------------------------------------------------------------

setup_postgres() {
	if [ "$SKIP_POSTGRES" = "1" ]; then
		warn "skipping PostgreSQL setup (SORTDX_SKIP_POSTGRES=1)"
		return
	fi

	info "Setting up PostgreSQL"

	if ! command -v psql >/dev/null 2>&1; then
		warn "psql not found; install PostgreSQL client tools and create:"
		warn "  role:     ${DB_USER}"
		warn "  database: ${DB_NAME}"
		return
	fi

	if command -v pg_isready >/dev/null 2>&1; then
		if ! pg_isready -q -h "$DB_HOST" -p "$DB_PORT"; then
			warn "PostgreSQL is not reachable at ${DB_HOST}:${DB_PORT}"
			warn "Start PostgreSQL, then re-run the installer or create the role/database manually."
			return
		fi
		ok "PostgreSQL is reachable at ${DB_HOST}:${DB_PORT}"
	fi

	if ! is_local_db_host; then
		warn "database host is ${DB_HOST}; skipping automatic role/database creation"
		warn "ensure role '${DB_USER}' and database '${DB_NAME}' already exist"
		verify_postgres_login || true
		return
	fi

	local q_user q_pass q_db ident_user ident_db role_exists db_exists
	q_user="$(sql_quote "$DB_USER")"
	q_pass="$(sql_quote "$DB_PASSWORD")"
	q_db="$(sql_quote "$DB_NAME")"
	ident_user="$(pg_ident "$DB_USER")"
	ident_db="$(pg_ident "$DB_NAME")"

	if ! role_exists="$(
		run_psql_admin -tAc "SELECT 1 FROM pg_roles WHERE rolname = '${q_user}'" |
			tr -d '[:space:]'
	)"; then
		warn "could not query PostgreSQL roles (need local superuser access)"
		warn "create role '${DB_USER}' and database '${DB_NAME}' manually, or set SORTDX_SKIP_POSTGRES=1"
		return
	fi

	if [ "$role_exists" = "1" ]; then
		if ! run_psql_admin -c "ALTER ROLE ${ident_user} WITH LOGIN PASSWORD '${q_pass}';" >/dev/null; then
			warn "could not update password for PostgreSQL role '${DB_USER}'"
			return
		fi
		ok "PostgreSQL role ready: ${DB_USER}"
	else
		if ! run_psql_admin -c "CREATE ROLE ${ident_user} LOGIN PASSWORD '${q_pass}';" >/dev/null; then
			warn "could not create PostgreSQL role '${DB_USER}'"
			return
		fi
		ok "created PostgreSQL role: ${DB_USER}"
	fi

	if ! db_exists="$(
		run_psql_admin -tAc "SELECT 1 FROM pg_database WHERE datname = '${q_db}'" |
			tr -d '[:space:]'
	)"; then
		warn "could not query PostgreSQL databases"
		return
	fi

	if [ "$db_exists" = "1" ]; then
		ok "PostgreSQL database already exists: ${DB_NAME}"
	else
		if ! run_psql_admin -c "CREATE DATABASE ${ident_db} OWNER ${ident_user};" >/dev/null; then
			warn "could not create PostgreSQL database '${DB_NAME}'"
			return
		fi
		ok "created PostgreSQL database: ${DB_NAME}"
	fi

	run_psql_admin -c "GRANT ALL PRIVILEGES ON DATABASE ${ident_db} TO ${ident_user};" >/dev/null 2>&1 || true

	verify_postgres_login
}

verify_postgres_login() {
	if ! command -v psql >/dev/null 2>&1; then
		return 1
	fi

	if PGPASSWORD="$DB_PASSWORD" \
		psql \
		-h "$DB_HOST" \
		-p "$DB_PORT" \
		-U "$DB_USER" \
		-d "$DB_NAME" \
		-v ON_ERROR_STOP=1 \
		-c 'SELECT 1;' >/dev/null 2>&1; then

		ok "PostgreSQL login verified (${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME})"
		return 0
	fi

	warn "could not log in as ${DB_USER} to ${DB_NAME} on ${DB_HOST}:${DB_PORT}"
	return 1
}

# --------------------------------------------------------------------
# Write .env with PostgreSQL connection settings
# --------------------------------------------------------------------

write_env() {
	mkdir -p "$PREFIX"

	local env_file="${PREFIX}/.env"
	local encoded_pass
	encoded_pass="$(url_encode "$DB_PASSWORD")"

	cat >"$env_file" <<EOF
# SortDX Storage Engine environment
# Generated by install.sh — do not commit this file.

SORTDX_HOME=${PREFIX}

STORAGE_DATABASE_HOST=${DB_HOST}
STORAGE_DATABASE_PORT=${DB_PORT}
STORAGE_DATABASE_USER=${DB_USER}
STORAGE_DATABASE_PASSWORD="${DB_PASSWORD}"
STORAGE_DATABASE_NAME=${DB_NAME}
STORAGE_DATABASE_SSLMODE=${DB_SSLMODE}

PGHOST=${DB_HOST}
PGPORT=${DB_PORT}
PGUSER=${DB_USER}
PGPASSWORD="${DB_PASSWORD}"
PGDATABASE=${DB_NAME}
PGSSLMODE=${DB_SSLMODE}

DATABASE_URL="postgres://${DB_USER}:${encoded_pass}@${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=${DB_SSLMODE}"
EOF

	chmod 600 "$env_file"
	ok "wrote ${env_file}"
}

# --------------------------------------------------------------------
# Write configuration
# --------------------------------------------------------------------

write_config() {
	mkdir -p \
		"${PREFIX}/config" \
		"${PREFIX}/data" \
		"${PREFIX}/storage"

	local cfg="${PREFIX}/config/config.yaml"

	# Never overwrite an existing configuration.
	if [ -f "$cfg" ]; then
		ok "keeping existing ${cfg}"
		return
	fi

	local secret
	local cloud
	local root
	local engine

	secret="$(
		head -c 32 /dev/urandom |
			od -An -tx1 |
			tr -d ' \n'
	)"

	cloud="${CLOUD_BASE_URL:-https://ngine.sortdx.com}"

	root="${STORAGE_ROOT:-${PREFIX}/storage}"

	engine="$(detect_public_url)"

	cat >"$cfg" <<EOF
server:
  host: 0.0.0.0
  port: 8080

storage:
  driver: local
  root: ${root}

database:
  driver: postgres
  host: ${DB_HOST}
  port: ${DB_PORT}
  user: ${DB_USER}
  password: ${DB_PASSWORD}
  name: ${DB_NAME}
  sslmode: ${DB_SSLMODE}

jwt:
  secret: ${secret}

cloud:
  base_url: ${cloud}
  install_state_path: ${PREFIX}/data/installation.json

invitation:
  expiry_hours: 168

app:
  base_url: ${engine}
EOF

	chmod 600 "$cfg"

	ok "wrote ${cfg}"
}

# --------------------------------------------------------------------
# Write command wrapper
# --------------------------------------------------------------------

write_wrapper() {
	mkdir -p "$BIN_DIR"

	local wrap="${BIN_DIR}/sortdx"

	cat >"$wrap" <<EOF
#!/usr/bin/env bash
set -euo pipefail

export SORTDX_HOME="${PREFIX}"

if [ -f "\${SORTDX_HOME}/.env" ]; then
	set -a
	# shellcheck disable=SC1091
	. "\${SORTDX_HOME}/.env"
	set +a
fi

cd "\$SORTDX_HOME"

exec "${PREFIX}/bin/sortdx" "\$@"
EOF

	chmod +x "$wrap"

	ok "installed ${wrap}"
}

# --------------------------------------------------------------------
# Add binary directory to PATH
# --------------------------------------------------------------------

ensure_path() {
	case ":${PATH}:" in
	*":${BIN_DIR}:"*)
		return
		;;
	esac

	local rc=""

	if [ -n "${ZSH_VERSION:-}" ] ||
		[ "$(basename "${SHELL:-}")" = "zsh" ]; then

		rc="${HOME}/.zshrc"
	else
		rc="${HOME}/.bashrc"
	fi

	local line="export PATH=\"${BIN_DIR}:\$PATH\""

	if [ -f "$rc" ] &&
		grep -Fqs "$BIN_DIR" "$rc"; then
		return
	fi

	printf '\n# SortDX Storage Engine\n%s\n' "$line" >>"$rc"

	ok "added ${BIN_DIR} to PATH in ${rc}"
}

# --------------------------------------------------------------------
# systemd user service
# --------------------------------------------------------------------

write_systemd() {
	[ "$(os_name)" = "linux" ] ||
		die "--systemd is only supported on Linux"

	local unit_dir="${HOME}/.config/systemd/user"

	mkdir -p "$unit_dir"

	cat >"${unit_dir}/sortdx-storage-engine.service" <<EOF
[Unit]
Description=SortDX Storage Engine
After=network-online.target postgresql.service postgresql@*.service
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${PREFIX}
ExecStart=${PREFIX}/bin/sortdx run
Restart=on-failure
RestartSec=3
Environment=SORTDX_HOME=${PREFIX}
EnvironmentFile=-${PREFIX}/.env

[Install]
WantedBy=default.target
EOF

	if command -v systemctl >/dev/null 2>&1; then

		systemctl --user daemon-reload || true

		if systemctl --user enable --now sortdx-storage-engine.service; then
			ok "SortDX Storage Engine service started"
		else
			warn "could not start systemd service automatically"
			warn "run: systemctl --user enable --now sortdx-storage-engine"
		fi
	fi

	ok "systemd user unit installed"
}

# --------------------------------------------------------------------
# Uninstall (undo install.sh)
# --------------------------------------------------------------------

remove_sortdx_path_block() {
	local rc="$1"
	local bin_dir="$2"
	[ -f "$rc" ] || return 0

	local tmp
	tmp="$(mktemp)"
	awk -v bin="$bin_dir" '
		$0 == "# SortDX Storage Engine" { skip = 1; next }
		skip == 1 {
			skip = 0
			want = "export PATH=\"" bin ":$PATH\""
			if ($0 == want || $0 == "") next
		}
		{ print }
	' "$rc" >"$tmp"
	if ! cmp -s "$rc" "$tmp"; then
		cat "$tmp" >"$rc"
		ok "removed PATH entry from ${rc}"
	fi
	rm -f "$tmp"
}

drop_local_postgres() {
	if [ "$SKIP_POSTGRES" = "1" ]; then
		warn "SORTDX_SKIP_POSTGRES=1; not dropping PostgreSQL objects"
		return
	fi
	if ! is_local_db_host; then
		warn "database host is ${DB_HOST}; drop role '${DB_USER}' and database '${DB_NAME}' manually"
		return
	fi
	if ! command -v psql >/dev/null 2>&1; then
		warn "psql not found; PostgreSQL objects were not dropped"
		return
	fi

	local ident_user ident_db q_db
	ident_user="$(pg_ident "$DB_USER")"
	ident_db="$(pg_ident "$DB_NAME")"
	q_db="$(sql_quote "$DB_NAME")"

	run_psql_admin -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${q_db}' AND pid <> pg_backend_pid();" >/dev/null 2>&1 || true
	if run_psql_admin -c "DROP DATABASE IF EXISTS ${ident_db};" >/dev/null; then
		ok "dropped PostgreSQL database: ${DB_NAME}"
	else
		warn "could not drop PostgreSQL database '${DB_NAME}'"
	fi
	if run_psql_admin -c "DROP ROLE IF EXISTS ${ident_user};" >/dev/null; then
		ok "dropped PostgreSQL role: ${DB_USER}"
	else
		warn "could not drop PostgreSQL role '${DB_USER}'"
	fi
}

run_uninstall() {
	if [ "$UNINSTALL_YES" -ne 1 ]; then
		die "refusing to uninstall without --yes"
	fi

	printf '\n'
	info "Uninstalling SortDX Storage Engine from ${PREFIX}"

	if command -v systemctl >/dev/null 2>&1; then
		systemctl --user stop sortdx-storage-engine.service >/dev/null 2>&1 || true
		systemctl --user disable sortdx-storage-engine.service >/dev/null 2>&1 || true
	fi
	local unit="${HOME}/.config/systemd/user/sortdx-storage-engine.service"
	if [ -f "$unit" ]; then
		rm -f "$unit"
		ok "removed ${unit}"
		systemctl --user daemon-reload >/dev/null 2>&1 || true
	fi

	if [ "$PURGE_DATABASE" -eq 1 ]; then
		drop_local_postgres
	else
		info "keeping PostgreSQL ${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME} (pass --purge-database to drop)"
	fi

	remove_sortdx_path_block "${HOME}/.bashrc" "$BIN_DIR"
	remove_sortdx_path_block "${HOME}/.zshrc" "$BIN_DIR"

	local wrap="${BIN_DIR}/sortdx"
	if [ -f "$wrap" ] && grep -Fqs "SORTDX_HOME" "$wrap" && grep -Fqs "${PREFIX}/bin/sortdx" "$wrap"; then
		rm -f "$wrap"
		ok "removed ${wrap}"
	fi

	if [ -d "$PREFIX" ]; then
		rm -rf "$PREFIX"
		ok "removed ${PREFIX}"
	else
		warn "install home not found: ${PREFIX}"
	fi

	printf '\n'
	ok "SortDX Storage Engine uninstall complete."
	printf '%sCloud Platform may still list this installation; remove it from the tenant dashboard if needed.%s\n\n' "$dim" "$reset"
}

# --------------------------------------------------------------------
# Verify installation
# --------------------------------------------------------------------

verify_installation() {
	local binary="${PREFIX}/bin/sortdx"

	if [ ! -x "$binary" ]; then
		die "installation verification failed: ${binary} is missing"
	fi

	ok "binary verification passed"

	# Try to display version if supported.
	if "$binary" --version >/dev/null 2>&1; then
		printf '\n'
		"$binary" --version || true
	fi
}

# --------------------------------------------------------------------
# Main
# --------------------------------------------------------------------

main() {

	case "$(os_name)" in
	linux | darwin)
		;;
	*)
		die "unsupported operating system: $(os_name)"
		;;
	esac

	local OS
	local ARCH

	OS="$(os_name)"
	ARCH="$(go_arch)"

	if [ "$UNINSTALL" -eq 1 ]; then
		run_uninstall
		return
	fi

	printf '\n'
	printf '%s========================================%s\n' "$bold" "$reset"
	printf '%s SortDX Storage Engine Installer%s\n' "$bold" "$reset"
	printf '%s========================================%s\n' "$bold" "$reset"
	printf '\n'

	info "Operating system: ${OS}"
	info "Architecture:     ${ARCH}"

	resolve_latest_version

	info "Installing version: ${VERSION}"

	mkdir -p "$PREFIX" "$BIN_DIR"

	download_binary

	setup_postgres

	write_env

	write_config

	write_wrapper

	ensure_path

	verify_installation

	if [ "$SYSTEMD" -eq 1 ]; then
		write_systemd
	fi

	printf '\n'
	printf '%s========================================%s\n' "$bold" "$reset"
	printf '%s SortDX Storage Engine installed%s\n' "$bold" "$reset"
	printf '%s========================================%s\n' "$bold" "$reset"
	printf '\n'

	printf '  Version  %s\n' "$VERSION"
	printf '  Home     %s\n' "$PREFIX"
	printf '  Binary   %s/sortdx\n' "$BIN_DIR"
	printf '  Config   %s/config/config.yaml\n' "$PREFIX"
	printf '  Env      %s/.env\n' "$PREFIX"
	printf '  Database %s@%s:%s/%s\n' "$DB_USER" "$DB_HOST" "$DB_PORT" "$DB_NAME"
	printf '  Release  %s\n' "$(release_url)"

	printf '\n'

	printf '%sNext steps:%s\n' "$bold" "$reset"

	printf '\n'

	printf '  1. Reload your shell:\n'
	printf '     source ~/.bashrc\n'
	printf '\n'

	printf '  2. Register this engine:\n'
	printf '     sortdx install register \\\n'
	printf '       --api-key <key> \\\n'
	printf '       --secret <secret> \\\n'
	printf '       --name %s \\\n' \
		"$(hostname -s 2>/dev/null || echo engine-1)"
	printf '       --public-url %s\n' \
		"$(detect_public_url)"

	printf '\n'

	printf '  3. Start the engine:\n'
	printf '     sortdx run\n'

	printf '\n'

	printf '%sCloud:%s %s\n' \
		"$bold" \
		"$reset" \
		"${CLOUD_BASE_URL:-https://ngine.sortdx.com}"

	printf '\n'

	printf '%sWorkspace users log in to SortDX Cloud and receive this engine URL automatically.%s\n' \
		"$dim" \
		"$reset"

	printf '\n'

	printf '%sTo uninstall later:%s\n' "$bold" "$reset"
	printf '  sortdx uninstall --yes\n'
	printf '  # or: ./install.sh --uninstall --yes [--purge-database]\n'

	printf '\n'
}

main "$@"