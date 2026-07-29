#!/usr/bin/env bash
#
# Supports Ubuntu/Debian x86_64 and downloads only from Primate Labs.
#

set -euo pipefail

readonly VERSION="6.7.1"
readonly ARCHIVE="Geekbench-${VERSION}-Linux.tar.gz"
readonly SOURCE_DIR="Geekbench-${VERSION}-Linux"
readonly DOWNLOAD_URL="https://cdn.geekbench.com/${ARCHIVE}"
readonly EXPECTED_SHA256="0ddca977deb6d9db4bd866485f9408e72e2869d0dea0737b18d4bfe472858ace"
readonly INSTALL_ROOT="/opt/geekbench6"
readonly INSTALL_DIR="${INSTALL_ROOT}/${VERSION}"
readonly COMMAND_PATH="/usr/local/bin/geekbench6"

TEMP_DIR=""
STAGING_DIR=""

info() {
    printf '[INFO] %s\n' "$*"
}

warn() {
    printf '[WARN] %s\n' "$*" >&2
}

die() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

confirm() {
    local reply

    read -r -p "$1 [y/N]: " reply || return 1
    [[ "${reply,,}" == "y" || "${reply,,}" == "yes" ]]
}

cleanup() {
    if [[ -n "$TEMP_DIR" &&
          "$TEMP_DIR" == /tmp/geekbench6-install.* &&
          -d "$TEMP_DIR" ]]; then
        rm -rf -- "$TEMP_DIR"
    fi

    if [[ -n "$STAGING_DIR" &&
          "$STAGING_DIR" == "$INSTALL_ROOT/.${VERSION}.install."* &&
          -d "$STAGING_DIR" ]]; then
        rm -rf -- "$STAGING_DIR"
    fi
}

installation_is_valid() {
    local directory="$1"

    [[ -x "$directory/geekbench6" &&
       -x "$directory/geekbench_avx2" &&
       -x "$directory/geekbench_x86_64" &&
       -f "$directory/geekbench.plar" &&
       -f "$directory/geekbench-workload.plar" ]]
}

show_docker_warning() {
    local containers
    local count

    command -v docker >/dev/null 2>&1 || return 0
    containers="$(docker ps --format '  {{.Names}}  {{.Status}}' 2>/dev/null || true)"
    [[ -n "$containers" ]] || return 0

    count="$(printf '%s\n' "$containers" | wc -l)"
    count="${count//[[:space:]]/}"

    warn "$count Docker container(s) are currently running:"
    printf '%s\n' "$containers"
    warn "The installer will not stop them automatically."
}

download_and_extract() {
    info "Downloading approximately 220 MB from Primate Labs"
    curl \
        --fail \
        --location \
        --show-error \
        --proto '=https' \
        --proto-redir '=https' \
        --tlsv1.2 \
        --connect-timeout 20 \
        --retry 3 \
        --retry-delay 2 \
        --output "$TEMP_DIR/$ARCHIVE" \
        "$DOWNLOAD_URL"

    info "Verifying SHA-256 checksum"
    printf '%s  %s\n' "$EXPECTED_SHA256" "$TEMP_DIR/$ARCHIVE" |
        sha256sum --check --status ||
        die "Checksum verification failed. Nothing was installed."

    info "Validating archive structure"
    tar -tzf "$TEMP_DIR/$ARCHIVE" >"$TEMP_DIR/archive-list.txt"

    if grep -Eq '(^/|(^|/)\.\.(/|$))' "$TEMP_DIR/archive-list.txt"; then
        die "The downloaded archive contains an unsafe path."
    fi

    grep -Fxq "${SOURCE_DIR}/geekbench6" "$TEMP_DIR/archive-list.txt" ||
        die "The official Geekbench launcher was not found in the archive."

    tar \
        --extract \
        --gzip \
        --file "$TEMP_DIR/$ARCHIVE" \
        --directory "$TEMP_DIR" \
        --no-same-owner \
        --no-same-permissions

    installation_is_valid "$TEMP_DIR/$SOURCE_DIR" ||
        die "The extracted Geekbench files are incomplete."
}

install_geekbench() {
    install -d -m 0755 "$INSTALL_ROOT"
    STAGING_DIR="$(mktemp -d "$INSTALL_ROOT/.${VERSION}.install.XXXXXX")"

    cp -a -- "$TEMP_DIR/$SOURCE_DIR/." "$STAGING_DIR/"
    chown -R root:root "$STAGING_DIR"
    chmod -R u=rwX,go=rX "$STAGING_DIR"

    installation_is_valid "$STAGING_DIR" ||
        die "The staged Geekbench installation is incomplete."

    mv -T -- "$STAGING_DIR" "$INSTALL_DIR"
    STAGING_DIR=""
}

install_command_wrapper() {
    local wrapper="$TEMP_DIR/geekbench6-wrapper"

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        "cd \"$INSTALL_DIR\" || exit 1" \
        "exec \"$INSTALL_DIR/geekbench6\" \"\$@\"" \
        >"$wrapper"

    install -d -m 0755 /usr/local/bin
    install -m 0755 "$wrapper" "$COMMAND_PATH"
}

trap cleanup EXIT

[[ "$EUID" -eq 0 ]] ||
    die "Run this installer with: sudo bash install-geekbench6.sh"

[[ "$(uname -m)" == "x86_64" ]] ||
    die "This package requires AMD/Intel x86_64. Detected: $(uname -m)"

command -v apt-get >/dev/null 2>&1 ||
    die "This installer supports Ubuntu and Debian systems using apt."

printf '\nGeekbench 6 installer\n'
printf 'Version: %s\n' "$VERSION"
printf 'Source:  %s\n\n' "$DOWNLOAD_URL"
printf 'Geekbench uses all CPU cores and can cause player lag.\n'
printf 'Run it only while game servers are stopped or during maintenance.\n\n'

show_docker_warning

if ! confirm "Continue with installation?"; then
    printf 'Cancelled; nothing was changed.\n'
    exit 0
fi

info "Installing required packages"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates \
    coreutils \
    curl \
    grep \
    libgcc-s1 \
    tar \
    zlib1g

TEMP_DIR="$(mktemp -d /tmp/geekbench6-install.XXXXXX)"

if installation_is_valid "$INSTALL_DIR"; then
    info "Geekbench $VERSION is already installed; skipping the download."
elif [[ -e "$INSTALL_DIR" ]]; then
    die "An incomplete installation exists at $INSTALL_DIR. Move or remove it, then rerun this installer."
else
    download_and_extract
    info "Installing Geekbench into $INSTALL_DIR"
    install_geekbench
fi

install_command_wrapper

printf '\n[OK] Geekbench %s is installed.\n' "$VERSION"
printf 'Command: %s\n\n' "$COMMAND_PATH"

if confirm "Run the full CPU benchmark now?"; then
    printf '\nStarting Geekbench. Do not start game servers until it finishes.\n\n'
    trap - EXIT
    cleanup
    exec "$COMMAND_PATH" --cpu
fi

printf '\nRun it later with:\n  geekbench6 --cpu\n'
