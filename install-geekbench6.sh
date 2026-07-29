#!/usr/bin/env bash
#
# Supports Ubuntu/Debian x86_64 and downloads only from Primate Labs.
#

# Unofficial Geekbench 6 installer for Ubuntu/Debian x86_64.

set -euo pipefail

readonly VERSION="6.7.1"
readonly ARCHIVE="Geekbench-${VERSION}-Linux.tar.gz"
readonly SOURCE_DIR="Geekbench-${VERSION}-Linux"
readonly DOWNLOAD_URL="https://cdn.geekbench.com/${ARCHIVE}"
readonly EXPECTED_SHA256="0ddca977deb6d9db4bd866485f9408e72e2869d0dea0737b18d4bfe472858ace"
readonly INSTALL_ROOT="/opt/geekbench6"
readonly INSTALL_DIR="${INSTALL_ROOT}/${VERSION}"
readonly COMMAND_PATH="/usr/local/bin/geekbench6"
VERSION="6.7.1"
ARCHIVE="Geekbench-${VERSION}-Linux.tar.gz"
ARCHIVE_DIR="Geekbench-${VERSION}-Linux"
URL="https://cdn.geekbench.com/${ARCHIVE}"
SHA256="0ddca977deb6d9db4bd866485f9408e72e2869d0dea0737b18d4bfe472858ace"

TEMP_DIR=""
STAGING_DIR=""
INSTALL_BASE="/opt/geekbench6"
INSTALL_DIR="${INSTALL_BASE}/${VERSION}"
COMMAND="/usr/local/bin/geekbench6"

info() {
    printf '[INFO] %s\n' "$*"
}
tmpdir=""
stagedir=""

warn() {
    printf '[WARN] %s\n' "$*" >&2
fail() {
    echo "Error: $*" >&2
    exit 1
}

die() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
ask() {
    local answer
    read -r -p "$1 [y/N]: " answer || return 1
    [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

confirm() {
    local reply
valid_install() {
    local dir="$1"

    read -r -p "$1 [y/N]: " reply || return 1
    [[ "${reply,,}" == "y" || "${reply,,}" == "yes" ]]
    [[ -x "$dir/geekbench6" ]] &&
        [[ -x "$dir/geekbench_avx2" ]] &&
        [[ -x "$dir/geekbench_x86_64" ]] &&
        [[ -f "$dir/geekbench.plar" ]] &&
        [[ -f "$dir/geekbench-workload.plar" ]]
}

cleanup() {
    if [[ -n "$TEMP_DIR" &&
          "$TEMP_DIR" == /tmp/geekbench6-install.* &&
          -d "$TEMP_DIR" ]]; then
        rm -rf -- "$TEMP_DIR"
    if [[ -n "$tmpdir" &&
          "$tmpdir" == /tmp/geekbench6-install.* &&
          -d "$tmpdir" ]]; then
        rm -rf -- "$tmpdir"
    fi

    if [[ -n "$STAGING_DIR" &&
          "$STAGING_DIR" == "$INSTALL_ROOT/.${VERSION}.install."* &&
          -d "$STAGING_DIR" ]]; then
        rm -rf -- "$STAGING_DIR"
    if [[ -n "$stagedir" &&
          "$stagedir" == "$INSTALL_BASE/.${VERSION}.install."* &&
          -d "$stagedir" ]]; then
        rm -rf -- "$stagedir"
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
trap cleanup EXIT

    warn "$count Docker container(s) are currently running:"
    printf '%s\n' "$containers"
    warn "The installer will not stop them automatically."
}
[[ "$EUID" -eq 0 ]] ||
    fail "run this script with: sudo bash install-geekbench6.sh"

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
[[ "$(uname -m)" == "x86_64" ]] ||
    fail "x86_64 is required (detected: $(uname -m))"

    info "Verifying SHA-256 checksum"
    printf '%s  %s\n' "$EXPECTED_SHA256" "$TEMP_DIR/$ARCHIVE" |
        sha256sum --check --status ||
        die "Checksum verification failed. Nothing was installed."
command -v apt-get >/dev/null 2>&1 ||
    fail "this installer only supports Ubuntu and Debian systems using apt"

    info "Validating archive structure"
    tar -tzf "$TEMP_DIR/$ARCHIVE" >"$TEMP_DIR/archive-list.txt"
echo
echo "Geekbench ${VERSION} Linux installer"
echo
echo "Geekbench will use every CPU core while it runs."
echo "Stop game servers first if you do not want players to experience lag."
echo

    if grep -Eq '(^/|(^|/)\.\.(/|$))' "$TEMP_DIR/archive-list.txt"; then
        die "The downloaded archive contains an unsafe path."
if command -v docker >/dev/null 2>&1; then
    containers="$(docker ps --format '  {{.Names}}  {{.Status}}' 2>/dev/null || true)"
    if [[ -n "$containers" ]]; then
        container_count="$(printf '%s\n' "$containers" | wc -l)"
        container_count="${container_count//[[:space:]]/}"
        echo "Warning: ${container_count} Docker container(s) are running:" >&2
        printf '%s\n' "$containers"
        echo "They will not be stopped by this installer." >&2
