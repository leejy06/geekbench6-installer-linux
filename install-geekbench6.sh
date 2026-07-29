#!/usr/bin/env bash
#
# Beginner-safe installer for Geekbench 6.7.1 on Ubuntu/Debian x86_64.
# Downloads only from the official Primate Labs CDN.
#

set -Eeuo pipefail

VERSION="6.7.1"
ARCHIVE="Geekbench-${VERSION}-Linux.tar.gz"
SOURCE_DIR="Geekbench-${VERSION}-Linux"
DOWNLOAD_URL="https://cdn.geekbench.com/${ARCHIVE}"
EXPECTED_SHA256="0ddca977deb6d9db4bd866485f9408e72e2869d0dea0737b18d4bfe472858ace"
INSTALL_DIR="/opt/geekbench6/${VERSION}"
COMMAND_LINK="/usr/local/bin/geekbench6"
TEMP_DIR=""

die() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

cleanup() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf -- "$TEMP_DIR"
    fi
}

trap cleanup EXIT

if [[ "${EUID}" -ne 0 ]]; then
    die "Run this installer with: sudo bash install-geekbench6.sh"
fi

if [[ "$(uname -m)" != "x86_64" ]]; then
    die "This package is for AMD/Intel x86_64 servers. Detected: $(uname -m)"
fi

if ! command -v apt-get >/dev/null 2>&1; then
    die "This installer supports Ubuntu and Debian systems using apt."
fi

printf '\nGeekbench 6 installer\n'
printf 'Version: %s\n' "$VERSION"
printf 'Source:  %s\n\n' "$DOWNLOAD_URL"
printf 'Geekbench will use all CPU cores and can cause player lag.\n'
printf 'Run it only when customer game servers are stopped or during maintenance.\n\n'

if command -v docker >/dev/null 2>&1; then
    RUNNING_CONTAINER_IDS="$(docker ps -q 2>/dev/null || true)"
    if [[ -n "$RUNNING_CONTAINER_IDS" ]]; then
        RUNNING_CONTAINERS="$(
            printf '%s\n' "$RUNNING_CONTAINER_IDS" | wc -l
        )"
        RUNNING_CONTAINERS="${RUNNING_CONTAINERS//[[:space:]]/}"
        printf '[WARN] %s Docker container(s) are currently running:\n' \
            "$RUNNING_CONTAINERS"
        docker ps --format '  {{.Names}}  {{.Status}}' || true
        printf '\nThe installer will not stop them automatically.\n'
    fi
fi

read -r -p "Continue with installation? [y/N]: " ANSWER
if [[ ! "${ANSWER,,}" =~ ^(y|yes)$ ]]; then
    printf 'Cancelled; nothing was changed.\n'
    exit 0
fi

printf '\n[INFO] Installing download requirements\n'
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl tar zlib1g libgcc-s1

TEMP_DIR="$(mktemp -d /tmp/geekbench6-install.XXXXXX)"

printf '[INFO] Downloading approximately 220 MB from Primate Labs\n'
curl \
    --fail \
    --location \
    --proto '=https' \
    --tlsv1.2 \
    --retry 3 \
    --retry-delay 2 \
    --output "$TEMP_DIR/$ARCHIVE" \
    "$DOWNLOAD_URL"

printf '[INFO] Verifying SHA-256 checksum\n'
printf '%s  %s\n' \
    "$EXPECTED_SHA256" "$TEMP_DIR/$ARCHIVE" |
    sha256sum --check --status ||
    die "Checksum verification failed. The archive was not installed."

printf '[INFO] Validating archive structure\n'
tar -tzf "$TEMP_DIR/$ARCHIVE" >"$TEMP_DIR/archive-list.txt"

if grep -Eq '(^/|(^|/)\.\.(/|$))' "$TEMP_DIR/archive-list.txt"; then
    die "The downloaded archive contains an unsafe path."
fi

grep -Fxq "${SOURCE_DIR}/geekbench6" "$TEMP_DIR/archive-list.txt" ||
    die "The official Geekbench launcher was not found in the archive."

tar -xzf "$TEMP_DIR/$ARCHIVE" -C "$TEMP_DIR"

[[ -x "$TEMP_DIR/$SOURCE_DIR/geekbench6" ]] ||
    die "Geekbench launcher is missing or not executable."
[[ -f "$TEMP_DIR/$SOURCE_DIR/geekbench.plar" ]] ||
    die "Geekbench data file is missing."
[[ -f "$TEMP_DIR/$SOURCE_DIR/geekbench-workload.plar" ]] ||
    die "Geekbench workload file is missing."

if [[ -e "$INSTALL_DIR" ]]; then
    printf '[INFO] Geekbench %s is already installed; preserving it.\n' "$VERSION"
else
    printf '[INFO] Installing into %s\n' "$INSTALL_DIR"
    install -d -m 0755 "$INSTALL_DIR"
    cp -a "$TEMP_DIR/$SOURCE_DIR/." "$INSTALL_DIR/"
fi

[[ -x "$INSTALL_DIR/geekbench6" ]] ||
    die "Installed Geekbench launcher is not executable."
[[ -f "$INSTALL_DIR/geekbench.plar" ]] ||
    die "Installed Geekbench data file is missing."
[[ -f "$INSTALL_DIR/geekbench-workload.plar" ]] ||
    die "Installed Geekbench workload file is missing."

printf '%s\n' \
    '#!/usr/bin/env bash' \
    "cd \"$INSTALL_DIR\"" \
    "exec \"$INSTALL_DIR/geekbench6\" \"\$@\"" \
    >"$TEMP_DIR/geekbench6-wrapper"
install -m 0755 "$TEMP_DIR/geekbench6-wrapper" "$COMMAND_LINK"

printf '\n[OK] Geekbench %s is installed.\n' "$VERSION"
printf 'Command: %s\n\n' "$COMMAND_LINK"

read -r -p "Run the full CPU benchmark now? [y/N]: " RUN_ANSWER
if [[ "${RUN_ANSWER,,}" =~ ^(y|yes)$ ]]; then
    printf '\nStarting Geekbench. Do not start game servers until it finishes.\n\n'
    trap - EXIT
    cleanup
    exec "$COMMAND_LINK" --cpu
fi

printf '\nRun it later with:\n  geekbench6 --cpu\n'
