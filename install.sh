#!/bin/sh
set -eu

RELEASE_REPO="${NOPEID_RELEASE_REPO:-nopeid/public}"
BASE_URL="${BASE_URL:-}"
MIN_MACOS_MAJOR=26

ARTIFACT_PATH=""
CHECKSUM_PATH=""
VERSION="${NOPEID_VERSION:-}"
CHANNEL="${NOPEID_CHANNEL:-stable}"
TARGET_USER=""
YES="${NOPEID_YES:-0}"
NON_INTERACTIVE="${NOPEID_NON_INTERACTIVE:-0}"
DRY_RUN=0
NO_START=0
DO_UNINSTALL=0
KEEP_DATA=0
PURGE_SYSTEM=0
DEV=0
DEV_BINARY=""
DEV_HELPER=""
TMP_DIR=""
STAGED_OCI_IMAGE=""

C_RESET=""
C_INFO=""
C_WARN=""
C_OK=""
C_STEP=""

init_ui() {
	if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
		C_RESET="$(printf '\033[0m')"
		C_INFO="$(printf '\033[36m')"
		C_WARN="$(printf '\033[33m')"
		C_OK="$(printf '\033[32m')"
		C_STEP="$(printf '\033[1;34m')"
	fi
}

info() { printf '%s[INFO]%s %s\n' "$C_INFO" "$C_RESET" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$C_WARN" "$C_RESET" "$*" >&2; }
ok() { printf '%s[OK]%s   %s\n' "$C_OK" "$C_RESET" "$*"; }
step() { printf '\n%s==>%s %s\n' "$C_STEP" "$C_RESET" "$*"; }

usage() {
	cat <<'EOF'
NopeID installer

Usage:
  install.sh [--yes] [--non-interactive] [--dry-run] [--no-start]
             [--version vX.Y.Z] [--channel stable|beta] [--target-user user]
             [--artifact /abs/path/nopeid-agent-macos-<arch>.tar.gz]
             [--checksum /abs/path/nopeid-agent-macos-<arch>.tar.gz.sha256]
  install.sh --dev [--binary /abs/path/nopeid --helper /abs/path/nopeid-helper]
  install.sh --uninstall [--purge-system] [--keep-data] [--dev]

Dev defaults:
  When --dev is used without --binary and --helper, install.sh uses
  agent/bin/nopeid and agent/bin/nopeid-helper.

Environment overrides:
  NOPEID_VERSION                 Release version to install.
  NOPEID_CHANNEL                 Release channel. Defaults to stable.
  NOPEID_RELEASE_REPO            Public release repo, e.g. nopeid/public.
  NOPEID_YES                     Set to 1 to skip confirmation prompts.
  NOPEID_NON_INTERACTIVE         Set to 1 to fail instead of prompting unless NOPEID_YES=1.
EOF
}

normalize_bool() {
	case "$1" in
	1|true|TRUE|yes|YES|y|Y) printf '1\n' ;;
	*) printf '0\n' ;;
	esac
}

cleanup() {
	if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
		rm -rf "$TMP_DIR"
	fi
}
trap cleanup EXIT INT TERM

need_cmd() {
	if ! command -v "$1" >/dev/null 2>&1; then
		echo "Missing required command: $1" >&2
		exit 1
	fi
}

parse_args() {
	YES="$(normalize_bool "$YES")"
	NON_INTERACTIVE="$(normalize_bool "$NON_INTERACTIVE")"
	while [ $# -gt 0 ]; do
		case "$1" in
		--yes|-y)
			YES=1
			;;
		--non-interactive)
			NON_INTERACTIVE=1
			;;
		--dry-run)
			DRY_RUN=1
			;;
		--no-start)
			NO_START=1
			;;
		--version)
			VERSION="${2:-}"
			shift
			;;
		--channel)
			CHANNEL="${2:-}"
			shift
			;;
		--target-user)
			TARGET_USER="${2:-}"
			shift
			;;
		--artifact)
			ARTIFACT_PATH="${2:-}"
			shift
			;;
		--checksum)
			CHECKSUM_PATH="${2:-}"
			shift
			;;
		--dev)
			DEV=1
			;;
		--binary)
			DEV_BINARY="${2:-}"
			shift
			;;
		--helper)
			DEV_HELPER="${2:-}"
			shift
			;;
		--uninstall)
			DO_UNINSTALL=1
			;;
		--purge-system)
			PURGE_SYSTEM=1
			;;
		--keep-data)
			KEEP_DATA=1
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "Unknown argument: $1" >&2
			usage
			exit 1
			;;
		esac
		shift
	done
}

default_dev_bin_dir() {
	cwd_default="$(pwd -P)/agent/bin"
	if [ -d "$cwd_default" ]; then
		printf '%s\n' "$cwd_default"
		return
	fi

	script_parent="$(CDPATH= cd "$(dirname "$0")/.." 2>/dev/null && pwd -P || true)"
	if [ -n "$script_parent" ] && [ -d "$script_parent/agent/bin" ]; then
		printf '%s\n' "$script_parent/agent/bin"
		return
	fi

	printf '%s\n' "$cwd_default"
}

resolve_dev_paths() {
	if [ "$DEV" -ne 1 ]; then
		return
	fi
	if [ -z "$DEV_BINARY" ] && [ -z "$DEV_HELPER" ]; then
		dev_bin_dir="$(default_dev_bin_dir)"
		DEV_BINARY="$dev_bin_dir/nopeid"
		DEV_HELPER="$dev_bin_dir/nopeid-helper"
		return
	fi
	if [ "$DO_UNINSTALL" -ne 1 ] && { [ -z "$DEV_BINARY" ] || [ -z "$DEV_HELPER" ]; }; then
		echo "--dev requires both --binary and --helper, or neither to use agent/bin defaults." >&2
		exit 1
	fi
}

detect_arch() {
	OS="$(uname -s)"
	if [ "$OS" != "Darwin" ]; then
		echo "Unsupported OS: $OS" >&2
		exit 1
	fi
	ARCH="$(uname -m)"
	case "$ARCH" in
	arm64|aarch64) ART_ARCH="arm64" ;;
	x86_64|amd64) ART_ARCH="amd64" ;;
	*) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
	esac
}

check_macos_version() {
	if [ "$DEV" -eq 1 ]; then
		return
	fi
	product_version="$(sw_vers -productVersion 2>/dev/null || true)"
	major="${product_version%%.*}"
	case "$major" in
	""|*[!0-9]*)
		echo "Unable to determine macOS version." >&2
		exit 1
		;;
	esac
	if [ "$major" -lt "$MIN_MACOS_MAJOR" ]; then
		echo "Unsupported macOS version: $product_version. NopeID requires macOS $MIN_MACOS_MAJOR or newer." >&2
		exit 1
	fi
}

release_base_url() {
	if [ -n "$BASE_URL" ]; then
		printf '%s\n' "$BASE_URL"
		return
	fi
	if [ -n "$VERSION" ]; then
		printf 'https://github.com/%s/releases/download/%s\n' "$RELEASE_REPO" "$VERSION"
		return
	fi
	printf 'https://github.com/%s/releases/latest/download\n' "$RELEASE_REPO"
}

json_value() {
	/usr/bin/plutil -extract "$1" raw -o - "$2" 2>/dev/null || true
}

download_with_retries() {
	url="$1"
	out="$2"
	curl -fL --retry 2 --retry-delay 2 --connect-timeout 20 --max-time 120 "$url" -o "$out"
}

confirm_continue() {
	answer=""
	if [ ! -t 0 ] && { [ -t 1 ] || [ -t 2 ]; }; then
		if { exec 3<>/dev/tty; } 2>/dev/null; then
			printf 'Continue? [Y/n]: ' >&3
			IFS= read -r answer <&3 || answer=""
			exec 3<&-
		else
			printf 'Continue? [Y/n]: '
			IFS= read -r answer || answer=""
		fi
	else
		printf 'Continue? [Y/n]: '
		IFS= read -r answer || answer=""
	fi
	answer="$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')"
	[ -z "$answer" ] || [ "$answer" = "y" ] || [ "$answer" = "yes" ]
}

verify_sha256() {
	path="$1"
	expected="$2"
	actual="$(shasum -a 256 "$path" | awk '{print $1}')"
	if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
		echo "Checksum verification failed for $path" >&2
		exit 1
	fi
	ok "Artifact checksum verified"
}

stage_artifact() {
	TMP_DIR="$(mktemp -d /tmp/nopeid-install.XXXXXX)"
	if [ "$DEV" -eq 1 ]; then
		if [ ! -x "$DEV_BINARY" ]; then
			echo "Dev binary is missing or not executable: $DEV_BINARY" >&2
			exit 1
		fi
		if [ ! -x "$DEV_HELPER" ]; then
			echo "Dev helper is missing or not executable: $DEV_HELPER" >&2
			exit 1
		fi
		STAGED_ARTIFACT=""
		EXPECTED_VERSION="dev"
		return
	fi

	if [ -n "$ARTIFACT_PATH" ]; then
		if [ ! -f "$ARTIFACT_PATH" ]; then
			echo "Artifact not found: $ARTIFACT_PATH" >&2
			exit 1
		fi
		STAGED_ARTIFACT="$ARTIFACT_PATH"
		if [ -n "$CHECKSUM_PATH" ]; then
			expected="$(awk '{print $1}' "$CHECKSUM_PATH" | tr -d ' \n')"
			verify_sha256 "$STAGED_ARTIFACT" "$expected"
		elif [ -f "$ARTIFACT_PATH.sha256" ]; then
			expected="$(awk '{print $1}' "$ARTIFACT_PATH.sha256" | tr -d ' \n')"
			verify_sha256 "$STAGED_ARTIFACT" "$expected"
		else
			warn "Local artifact checksum was not provided."
		fi
		EXPECTED_VERSION="$VERSION"
		if [ -z "$EXPECTED_VERSION" ]; then
			EXPECTED_VERSION="$(tar -xOzf "$STAGED_ARTIFACT" version.txt 2>/dev/null | head -n 1 || true)"
		fi
		if [ -z "$EXPECTED_VERSION" ]; then
			echo "Local artifacts must include version.txt or be installed with --version." >&2
			exit 1
		fi
		return
	fi

	base="$(release_base_url)"
	manifest="$TMP_DIR/nopeid-release.json"
	download_with_retries "$base/nopeid-release.json" "$manifest"

	EXPECTED_VERSION="$(json_value version "$manifest")"
	if [ -z "$EXPECTED_VERSION" ]; then
		echo "Release manifest is missing version." >&2
		exit 1
	fi
	manifest_channel="$(json_value channel "$manifest")"
	min_macos="$(json_value minimum_macos "$manifest")"
	if [ -n "$manifest_channel" ] && [ "$CHANNEL" != "$manifest_channel" ]; then
		echo "Release channel mismatch: requested $CHANNEL, manifest has $manifest_channel" >&2
		exit 1
	fi
	if [ -n "$min_macos" ]; then
		info "Release minimum macOS: $min_macos"
	fi
	artifact_key="artifacts.macos-$ART_ARCH"
	artifact_url="$(json_value "$artifact_key.url" "$manifest")"
	artifact_sha="$(json_value "$artifact_key.sha256" "$manifest")"
	if [ -z "$artifact_url" ] || [ -z "$artifact_sha" ]; then
		echo "Release manifest is missing macos-$ART_ARCH artifact metadata." >&2
		exit 1
	fi
	STAGED_ARTIFACT="$TMP_DIR/nopeid-agent-macos-$ART_ARCH.tar.gz"
	download_with_retries "$artifact_url" "$STAGED_ARTIFACT"
	verify_sha256 "$STAGED_ARTIFACT" "$artifact_sha"

	oci_key="artifacts.oci-linux-$ART_ARCH"
	oci_url="$(json_value "$oci_key.url" "$manifest")"
	oci_sha="$(json_value "$oci_key.sha256" "$manifest")"
	if [ -n "$oci_url" ] && [ -n "$oci_sha" ]; then
		STAGED_OCI_IMAGE="$TMP_DIR/nopeid-agent-oci-linux-$ART_ARCH.tar.gz"
		download_with_retries "$oci_url" "$STAGED_OCI_IMAGE"
		verify_sha256 "$STAGED_OCI_IMAGE" "$oci_sha"
	else
		warn "Release manifest is missing oci-linux-$ART_ARCH artifact metadata; OCI sandbox image will use the embedded artifact if present."
	fi
}

confirm_plan() {
	if [ "$DO_UNINSTALL" -eq 1 ]; then
		step "Uninstall configuration"
		if [ "$DEV" -eq 1 ]; then
			info "Mode: dev uninstall"
			info "Dev binary for cleanup: ${DEV_BINARY:-auto-detect}"
			info "Remove install root: no"
		else
			info "Mode: production uninstall"
			info "Remove install root: /opt/nopeid"
		fi
		info "Clear Agentguard hooks/shims: yes"
		if [ "$KEEP_DATA" -eq 1 ]; then
			info "Data/log cleanup: keep"
		elif [ "$PURGE_SYSTEM" -eq 1 ]; then
			info "Data/log cleanup: remove /var/lib/nopeid and /var/log/nopeid"
		else
			info "Data/log cleanup: keep"
		fi
		if [ "$DRY_RUN" -eq 1 ]; then
			ok "Dry run complete"
			exit 0
		fi
		if [ "$YES" -eq 1 ]; then
			return
		fi
		if [ "$NON_INTERACTIVE" -eq 1 ]; then
			echo "--non-interactive requires --yes." >&2
			exit 1
		fi
		if ! confirm_continue; then
			echo "Uninstall cancelled." >&2
			exit 1
		fi
		return
	fi

	step "Install configuration"
	if [ "$DEV" -eq 1 ]; then
		info "Mode: dev"
		info "Dev binary: ${DEV_BINARY:-artifact install}"
		info "Dev helper: ${DEV_HELPER:-artifact install}"
	else
		info "Mode: production"
		info "Install root: /opt/nopeid"
		info "Data root: /var/lib/nopeid"
		info "Log root: /var/log/nopeid"
	fi
	info "Version: ${VERSION:-latest}"
	info "Channel: $CHANNEL"
	info "Start after install: $([ "$NO_START" -eq 1 ] && printf 'no' || printf 'yes')"
	if [ "$DRY_RUN" -eq 1 ]; then
		ok "Dry run complete"
		exit 0
	fi
	if [ "$YES" -eq 1 ]; then
		return
	fi
	if [ "$NON_INTERACTIVE" -eq 1 ]; then
		echo "--non-interactive requires --yes." >&2
		exit 1
	fi
	if ! confirm_continue; then
		echo "Install cancelled." >&2
		exit 1
	fi
}

run_privileged_phase() {
	sudo env \
		NOPEID_PRIV_ARTIFACT="$STAGED_ARTIFACT" \
		NOPEID_PRIV_OCI_IMAGE="$STAGED_OCI_IMAGE" \
		NOPEID_PRIV_VERSION="$EXPECTED_VERSION" \
		NOPEID_PRIV_ART_ARCH="$ART_ARCH" \
		NOPEID_PRIV_NO_START="$NO_START" \
		NOPEID_PRIV_DEV="$DEV" \
		NOPEID_PRIV_DEV_BINARY="$DEV_BINARY" \
		NOPEID_PRIV_DEV_HELPER="$DEV_HELPER" \
		NOPEID_PRIV_TARGET_USER="$TARGET_USER" \
		NOPEID_PRIV_UNINSTALL="$DO_UNINSTALL" \
		NOPEID_PRIV_KEEP_DATA="$KEEP_DATA" \
		NOPEID_PRIV_PURGE_SYSTEM="$PURGE_SYSTEM" \
		/bin/sh -s <<'ROOT_SCRIPT'
set -eu

INSTALL_ROOT="/opt/nopeid"
VERSIONS_DIR="$INSTALL_ROOT/versions"
CURRENT_LINK="$INSTALL_ROOT/current"
BIN_DIR="$INSTALL_ROOT/bin"
USER_BIN_DIR="/usr/local/bin"
USER_BIN_LINK="$USER_BIN_DIR/nopeid"
DATA_ROOT="/var/lib/nopeid"
LOG_ROOT="/var/log/nopeid"
RECEIPT_DIR="$DATA_ROOT/install"
PROD_SERVICE_ID="com.nopeid.agent"
DEV_SERVICE_ID="com.nopeid.agent.dev"
PROD_PLIST="/Library/LaunchDaemons/$PROD_SERVICE_ID.plist"
DEV_PLIST="/Library/LaunchDaemons/$DEV_SERVICE_ID.plist"
LOCK_DIR="/var/run/nopeid-install.lock"

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
ok() { printf '[OK]   %s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }

lock_install() {
	if mkdir "$LOCK_DIR" 2>/dev/null; then
		printf '%s\n' "$$" > "$LOCK_DIR/pid"
		return
	fi
	if [ -f "$LOCK_DIR/pid" ]; then
		pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
		if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
			echo "Another NopeID install is running (pid $pid)." >&2
			exit 1
		fi
	fi
	warn "Removing stale install lock."
	rm -rf "$LOCK_DIR"
	mkdir "$LOCK_DIR"
	printf '%s\n' "$$" > "$LOCK_DIR/pid"
}

unlock_install() {
	rm -rf "$LOCK_DIR"
}
trap unlock_install EXIT INT TERM

stop_launchdaemons() {
	launchctl bootout "system/$PROD_SERVICE_ID" >/dev/null 2>&1 || true
	launchctl bootout system "$PROD_PLIST" >/dev/null 2>&1 || true
	launchctl bootout "system/$DEV_SERVICE_ID" >/dev/null 2>&1 || true
	launchctl bootout system "$DEV_PLIST" >/dev/null 2>&1 || true
}

stop_nopeid_processes() {
	for name in nopeid-agent nopeid-helper nopeid; do
		for pid in $(pgrep -x "$name" 2>/dev/null || true); do
			kill "$pid" 2>/dev/null || true
		done
	done
	sleep 2
	for name in nopeid-agent nopeid-helper nopeid; do
		for pid in $(pgrep -x "$name" 2>/dev/null || true); do
			if [ "${NOPEID_PRIV_DEV:-0}" -eq 1 ]; then
				warn "Terminating stale $name process $pid; custom-path processes will not be restarted after the dev install."
			fi
			kill -9 "$pid" 2>/dev/null || true
		done
	done
}

stop_all_nopeid() {
	step "Stopping existing NopeID services/processes"
	stop_launchdaemons
	stop_nopeid_processes
	ok "Existing services/processes stopped"
}

enable_audit_service() {
	/usr/sbin/audit -s >/dev/null 2>&1 || true
	/bin/launchctl enable system/com.apple.auditd >/dev/null 2>&1 || true
	/bin/launchctl kickstart -k system/com.apple.auditd >/dev/null 2>&1 || true
	if ! /usr/bin/pgrep -x auditd >/dev/null 2>&1; then
		warn "auditd is not running; auditd must be running for proper auditing."
	fi
}

write_plist() {
	service_id="$1"
	program="$2"
	log_root="$3"
	plist="$4"
	mkdir -p "$(dirname "$plist")" "$log_root"
	cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$service_id</string>
  <key>ProgramArguments</key>
  <array>
    <string>$program</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>
  <key>StandardOutPath</key>
  <string>$log_root/agent.stdout.log</string>
  <key>StandardErrorPath</key>
  <string>$log_root/agent.stderr.log</string>
</dict>
</plist>
EOF
	chown root:wheel "$plist"
	chmod 0644 "$plist"
}

resolve_settings_user() {
	if [ -n "${NOPEID_PRIV_TARGET_USER:-}" ]; then
		printf '%s\n' "$NOPEID_PRIV_TARGET_USER"
		return 0
	fi
	user="$(stat -f%Su /dev/console 2>/dev/null || true)"
	case "$user" in ""|root|loginwindow) user="${SUDO_USER:-}" ;; esac
	case "$user" in ""|root|loginwindow) return 1 ;; esac
	printf '%s\n' "$user"
}

ensure_settings_file() {
	if ! user="$(resolve_settings_user)"; then
		warn "Unable to resolve target user for settings.json; skipping settings initialization."
		return
	fi
	home_dir="$(dscl . -read "/Users/$user" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
	if [ -z "$home_dir" ]; then
		warn "Unable to resolve home directory for $user; skipping settings initialization."
		return
	fi
	settings_dir="$home_dir/.nopeid/etc"
	settings_path="$settings_dir/settings.json"
	settings_group="$(id -gn "$user")"
	mkdir -p "$settings_dir"
	chown "$user:$settings_group" "$settings_dir"
	chmod 0700 "$settings_dir"
	if [ ! -f "$settings_path" ]; then
		printf '{}\n' > "$settings_path"
	fi
	chown "$user:$settings_group" "$settings_path"
	chmod 0600 "$settings_path"
}

install_oci_image_cache() {
	embedded_image="$1"
	arch="${NOPEID_PRIV_ART_ARCH:-}"
	if [ -z "$arch" ]; then
		warn "Unable to determine architecture for OCI sandbox image cache; skipping image install."
		return
	fi
	if ! user="$(resolve_settings_user)"; then
		warn "Unable to resolve target user for OCI sandbox image cache; skipping image install."
		return
	fi
	home_dir="$(dscl . -read "/Users/$user" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
	if [ -z "$home_dir" ]; then
		warn "Unable to resolve home directory for $user; skipping OCI sandbox image install."
		return
	fi
	settings_group="$(id -gn "$user")"
	cache_root="$home_dir/.nopeid/oci-image-cache"
	cache_dir="$cache_root/linux/$arch"
	image_path="$cache_dir/nopeid-agent-oci.tar"
	tmp_image="$cache_dir/.nopeid-agent-oci.tar.$$"

	mkdir -p "$cache_dir"
	chown "$user:$settings_group" "$home_dir/.nopeid" "$cache_root" "$cache_root/linux" "$cache_dir"
	chmod 0700 "$home_dir/.nopeid" "$cache_root" "$cache_root/linux" "$cache_dir"

	if [ -f "${NOPEID_PRIV_OCI_IMAGE:-}" ]; then
		gzip -dc "$NOPEID_PRIV_OCI_IMAGE" > "$tmp_image"
	elif [ -f "$embedded_image" ]; then
		cp "$embedded_image" "$tmp_image"
	else
		warn "OCI sandbox image archive is missing; container sandbox will load only if the image already exists locally."
		return
	fi

	chown "$user:$settings_group" "$tmp_image"
	chmod 0600 "$tmp_image"
	mv "$tmp_image" "$image_path"
	chown "$user:$settings_group" "$image_path"
	chmod 0600 "$image_path"
	ok "OCI sandbox image installed"
}

start_service() {
	service_id="$1"
	plist="$2"
	launchctl enable "system/$service_id" >/dev/null 2>&1 || true
	launchctl bootstrap system "$plist"
	launchctl kickstart -k "system/$service_id"
}

install_path_symlink() {
	mkdir -p "$USER_BIN_DIR"
	if ! validate_user_bin_dir; then
		return 0
	fi
	validate_path_symlink
	ln -sfn "$BIN_DIR/nopeid" "$USER_BIN_LINK"
}

validate_user_bin_dir() {
	owner_uid="$(stat -f '%u' "$USER_BIN_DIR" 2>/dev/null || true)"
	case "$owner_uid" in
	*[!0-9]*|"") owner_uid="$(stat -c '%u' "$USER_BIN_DIR" 2>/dev/null || true)" ;;
	esac
	mode="$(stat -f '%Lp' "$USER_BIN_DIR" 2>/dev/null || true)"
	case "$mode" in
	*[!0-9]*|"") mode="$(stat -c '%a' "$USER_BIN_DIR" 2>/dev/null || true)" ;;
	esac
	case "$owner_uid:$mode" in
	0:*) ;;
	*)
		warn "$USER_BIN_DIR is not owned by root; skipping $USER_BIN_LINK creation."
		remove_path_symlink
		return 1
		;;
	esac
	group_perms="$(printf '%s' "$mode" | awk '{print substr($0, length($0)-1, 1)}')"
	other_perms="$(printf '%s' "$mode" | awk '{print substr($0, length($0), 1)}')"
	case "$group_perms$other_perms" in
	*[2367]*)
		warn "$USER_BIN_DIR is writable by non-root users; skipping $USER_BIN_LINK creation."
		remove_path_symlink
		return 1
		;;
	esac
}

validate_path_symlink() {
	if [ -e "$USER_BIN_LINK" ] || [ -L "$USER_BIN_LINK" ]; then
		current="$(readlink "$USER_BIN_LINK" 2>/dev/null || true)"
		if [ "$current" != "$BIN_DIR/nopeid" ]; then
			echo "$USER_BIN_LINK already exists and does not point to $BIN_DIR/nopeid" >&2
			exit 1
		fi
	fi
}

remove_path_symlink() {
	if [ -L "$USER_BIN_LINK" ] && [ "$(readlink "$USER_BIN_LINK" 2>/dev/null || true)" = "$BIN_DIR/nopeid" ]; then
		rm -f "$USER_BIN_LINK"
	fi
}

program_version() {
	program="$1"
	"$program" --version 2>/dev/null | awk -F': ' '/AgentVersion:/ {print $2; exit}'
}

launchd_pid() {
	service_id="$1"
	launchctl print "system/$service_id" 2>/dev/null | awk -F'= ' '/^[[:space:]]*pid = / {print $2; exit}'
}

launchd_program() {
	service_id="$1"
	launchctl print "system/$service_id" 2>/dev/null | awk -F'= ' '/^[[:space:]]*program = / {print $2; exit}'
}

health_check() {
	expected="$1"
	version_program="$2"
	service_id="$3"
	service_program="$4"
	for _ in 1 2 3 4 5 6 7 8 9 10; do
		pid="$(launchd_pid "$service_id")"
		loaded_program="$(launchd_program "$service_id")"
		case "$pid" in
		""|*[!0-9]*)
			sleep 1
			continue
			;;
		esac
		[ "$loaded_program" = "$service_program" ] && \
			kill -0 "$pid" 2>/dev/null && \
			[ "$(program_version "$version_program")" = "$expected" ] && return 0
		sleep 1
	done
	return 1
}

plist_program() {
	plist="$1"
	/usr/bin/plutil -extract ProgramArguments.0 raw -o - "$plist" 2>/dev/null || true
}

cleanup_launchd_env_for_user() {
	user="$1"
	uid="$(id -u "$user" 2>/dev/null || true)"
	if [ -z "$uid" ]; then
		return
	fi
	for key in CODEX_CLI_PATH NOPEID_CODEX_REAL_BINARY; do
		/bin/launchctl asuser "$uid" /bin/launchctl unsetenv "$key" >/dev/null 2>&1 || true
	done
}

cleanup_agentguard_for_user() {
	if ! user="$(resolve_settings_user)"; then
		warn "Unable to resolve target user for Agentguard cleanup; managed provider hooks may remain."
		return
	fi

	agentguard_bin=""
	for candidate in \
		"${NOPEID_PRIV_DEV_BINARY:-}" \
		"$(plist_program "$DEV_PLIST")" \
		"$BIN_DIR/nopeid" \
		"$CURRENT_LINK/bin/nopeid"
	do
		if [ -n "$candidate" ] && [ -x "$candidate" ]; then
			agentguard_bin="$candidate"
			break
		fi
	done

	if [ -n "$agentguard_bin" ]; then
		if "$agentguard_bin" tool agentguard uninstall --target-user "$user"; then
			ok "Agentguard provider hooks cleared for $user"
		else
			warn "Failed to clear Agentguard provider hooks for $user"
		fi
	else
		warn "No NopeID binary found for Agentguard cleanup; managed provider hooks may remain."
	fi
	cleanup_launchd_env_for_user "$user"
}

safe_version_component() {
	printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}

install_prod() {
	version="$(safe_version_component "${NOPEID_PRIV_VERSION:-}")"
	if [ -z "$version" ]; then
		version="unknown"
	fi
	artifact="${NOPEID_PRIV_ARTIFACT:-}"
	if [ ! -f "$artifact" ]; then
		echo "Staged artifact is missing: $artifact" >&2
		exit 1
	fi

	stage_root="$VERSIONS_DIR/.stage-$version-$$"
	extract_root="$stage_root/extract"
	version_dir="$VERSIONS_DIR/$version"
	backup_dir=""
	previous_current="$(readlink "$CURRENT_LINK" 2>/dev/null || true)"
	plist_backup="/tmp/nopeid-prev-plist.$$"
	[ -f "$PROD_PLIST" ] && cp "$PROD_PLIST" "$plist_backup" || true

	rm -rf "$stage_root"
	mkdir -p "$extract_root" "$stage_root/bin"
	tar -xzf "$artifact" -C "$extract_root"
	if [ -f "$extract_root/nopeid" ]; then
		install -m 0755 -o root -g wheel "$extract_root/nopeid" "$stage_root/bin/nopeid"
	elif [ -f "$extract_root/nopeid-agent" ]; then
		install -m 0755 -o root -g wheel "$extract_root/nopeid-agent" "$stage_root/bin/nopeid"
	else
		echo "Artifact is missing nopeid binary" >&2
		exit 1
	fi
	if [ ! -f "$extract_root/nopeid-helper" ]; then
		echo "Artifact is missing nopeid-helper binary" >&2
		exit 1
	fi
	install -m 0755 -o root -g wheel "$extract_root/nopeid-helper" "$stage_root/bin/nopeid-helper"
	install_oci_image_cache "$extract_root/nopeid-agent-oci.tar"
	ln -sfn nopeid "$stage_root/bin/nopeid-agent"
	rm -rf "$extract_root"
	validate_path_symlink

	stop_all_nopeid
	enable_audit_service
	mkdir -p "$VERSIONS_DIR" "$BIN_DIR" "$DATA_ROOT" "$LOG_ROOT" "$RECEIPT_DIR"
	chown -R root:wheel "$INSTALL_ROOT"
	chown root:wheel "$DATA_ROOT" "$LOG_ROOT" "$RECEIPT_DIR"
	chmod 0755 "$INSTALL_ROOT" "$VERSIONS_DIR" "$BIN_DIR"
	chmod 0700 "$DATA_ROOT"
	chmod 0750 "$LOG_ROOT"

	if [ -e "$version_dir" ]; then
		backup_dir="$VERSIONS_DIR/.rollback-$version-$$"
		mv "$version_dir" "$backup_dir"
	fi
	mv "$stage_root" "$version_dir"
	ln -sfn "$version_dir" "$CURRENT_LINK"
	ln -sfn "$CURRENT_LINK/bin/nopeid" "$BIN_DIR/nopeid"
	ln -sfn "$CURRENT_LINK/bin/nopeid-agent" "$BIN_DIR/nopeid-agent"
	ln -sfn "$CURRENT_LINK/bin/nopeid-helper" "$BIN_DIR/nopeid-helper"
	write_plist "$PROD_SERVICE_ID" "$BIN_DIR/nopeid-agent" "$LOG_ROOT" "$PROD_PLIST"
	rm -f "$DEV_PLIST"
	ensure_settings_file

	if [ "${NOPEID_PRIV_NO_START:-0}" -ne 1 ]; then
		if ! start_service "$PROD_SERVICE_ID" "$PROD_PLIST" || ! health_check "$version" "$BIN_DIR/nopeid" "$PROD_SERVICE_ID" "$BIN_DIR/nopeid-agent"; then
			warn "New version failed health checks; rolling back."
			stop_launchdaemons
			if [ -n "$previous_current" ]; then
				ln -sfn "$previous_current" "$CURRENT_LINK"
			fi
			if [ -n "$backup_dir" ] && [ -d "$backup_dir" ]; then
				rm -rf "$version_dir"
				mv "$backup_dir" "$version_dir"
			fi
			if [ -f "$plist_backup" ]; then
				cp "$plist_backup" "$PROD_PLIST"
			fi
			if [ -n "$previous_current" ]; then
				start_service "$PROD_SERVICE_ID" "$PROD_PLIST" || true
			fi
			exit 1
		fi
	fi
	install_path_symlink
	if [ -n "$backup_dir" ]; then
		rm -rf "$backup_dir"
	fi
	rm -f "$plist_backup"
	previous_version=""
	if [ -n "$previous_current" ]; then
		previous_version="$(basename "$previous_current")"
	fi
	cat > "$RECEIPT_DIR/receipt.json" <<EOF
{
  "installed_version": "$version",
  "installed_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "previous_version": "$previous_version"
}
EOF
	ok "NopeID production install complete"
}

install_dev() {
	binary="${NOPEID_PRIV_DEV_BINARY:-}"
	helper="${NOPEID_PRIV_DEV_HELPER:-}"
	if [ ! -x "$binary" ]; then
		echo "Dev binary is missing or not executable: $binary" >&2
		exit 1
	fi
	if [ ! -x "$helper" ]; then
		echo "Dev helper is missing or not executable: $helper" >&2
		exit 1
	fi
	expected_helper="$(dirname "$binary")/nopeid-helper"
	if [ "$helper" != "$expected_helper" ]; then
		warn "Helper is not adjacent to the dev agent binary; runtime helper supervisor expects $expected_helper."
	fi
	stop_all_nopeid
	enable_audit_service
	write_plist "$DEV_SERVICE_ID" "$binary" "/tmp" "$DEV_PLIST"
	rm -f "$PROD_PLIST"
	if [ "${NOPEID_PRIV_NO_START:-0}" -ne 1 ]; then
		start_service "$DEV_SERVICE_ID" "$DEV_PLIST"
	fi
	ok "NopeID dev install complete"
}

uninstall_nopeid() {
	stop_all_nopeid
	cleanup_agentguard_for_user
	rm -f "$PROD_PLIST" "$DEV_PLIST"
	if [ "${NOPEID_PRIV_DEV:-0}" -ne 1 ]; then
		remove_path_symlink
		rm -rf "$INSTALL_ROOT"
	fi
	if [ "${NOPEID_PRIV_KEEP_DATA:-0}" -eq 1 ]; then
		info "Keeping data/log directories"
	elif [ "${NOPEID_PRIV_PURGE_SYSTEM:-0}" -eq 1 ]; then
		rm -rf "$DATA_ROOT" "$LOG_ROOT"
	fi
	ok "Uninstall complete"
}

lock_install
if [ "${NOPEID_PRIV_UNINSTALL:-0}" -eq 1 ]; then
	uninstall_nopeid
elif [ "${NOPEID_PRIV_DEV:-0}" -eq 1 ]; then
	install_dev
else
	install_prod
fi
ROOT_SCRIPT
}

main() {
	init_ui
	parse_args "$@"
	need_cmd uname
	need_cmd curl
	need_cmd gzip
	need_cmd tar
	need_cmd shasum
	need_cmd sudo
	detect_arch
	if [ "$DO_UNINSTALL" -ne 1 ]; then
		check_macos_version
		resolve_dev_paths
		confirm_plan
		stage_artifact
	else
		resolve_dev_paths
		confirm_plan
		STAGED_ARTIFACT=""
		EXPECTED_VERSION=""
	fi
	run_privileged_phase
}

main "$@"
