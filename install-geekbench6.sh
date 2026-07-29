#!/usr/bin/env bash

# Installs and runs Geekbench 6 on Ubuntu/Debian x86_64.

set -euo pipefail

VERSION="6.7.1"
FILE="Geekbench-${VERSION}-Linux.tar.gz"
FOLDER="Geekbench-${VERSION}-Linux"
URL="https://cdn.geekbench.com/${FILE}"
SHA256="0ddca977deb6d9db4bd866485f9408e72e2869d0dea0737b18d4bfe472858ace"
INSTALL_DIR="/opt/geekbench6/${VERSION}"
COMMAND="/usr/local/bin/geekbench6"

TEMP_DIR=""
STAGE_DIR=""

fail() {
    echo "Error: $*" >&2
    exit 1
}

valid_install() {
    [[ -x "$1/geekbench6" &&
       -x "$1/geekbench_avx2" &&
       -x "$1/geekbench_x86_64" &&
       -f "$1/geekbench.plar" &&
       -f "$1/geekbench-workload.plar" ]]
}

cleanup() {
    if [[ -n "$TEMP_DIR" && "$TEMP_DIR" == /tmp/geekbench6.* ]]; then
        rm -rf -- "$TEMP_DIR"
    fi
    if [[ -n "$STAGE_DIR" && "$STAGE_DIR" == /opt/geekbench6/.install.* ]]; then
        rm -rf -- "$STAGE_DIR"
    fi
}

trap cleanup EXIT

[[ "$EUID" -eq 0 ]] ||
    fail "run this script with: sudo bash install-geekbench6.sh"

[[ "$(uname -m)" == "x86_64" ]] ||
    fail "this installer requires an AMD/Intel x86_64 system"

for cmd in curl tar sha256sum mktemp install cp grep chown chmod mv rm; do
    command -v "$cmd" >/dev/null 2>&1 ||
        fail "required command not found: $cmd"
done

echo "Geekbench will use all CPU cores. Stop important workloads first."

TEMP_DIR="$(mktemp -d /tmp/geekbench6.XXXXXX)"

if ! valid_install "$INSTALL_DIR"; then
    [[ ! -e "$INSTALL_DIR" ]] ||
        fail "an incomplete installation exists at $INSTALL_DIR"

    echo "Downloading Geekbench ${VERSION}..."
    curl -fL --show-error \
        --proto '=https' --proto-redir '=https' \
        --retry 3 \
        -o "$TEMP_DIR/$FILE" "$URL"

    echo "Verifying download..."
    printf '%s  %s\n' "$SHA256" "$TEMP_DIR/$FILE" |
        sha256sum -c --status ||
        fail "checksum verification failed"

    tar -tzf "$TEMP_DIR/$FILE" >"$TEMP_DIR/files.txt"
    if grep -Eq '(^/|(^|/)\.\.(/|$))' "$TEMP_DIR/files.txt"; then
        fail "unsafe path found in archive"
    fi

    tar -xzf "$TEMP_DIR/$FILE" -C "$TEMP_DIR" \
        --no-same-owner --no-same-permissions

    valid_install "$TEMP_DIR/$FOLDER" ||
        fail "downloaded Geekbench files are incomplete"

    install -d -m 0755 /opt/geekbench6
    STAGE_DIR="$(mktemp -d /opt/geekbench6/.install.XXXXXX)"
    cp -a "$TEMP_DIR/$FOLDER/." "$STAGE_DIR/"
    chown -R root:root "$STAGE_DIR"
    chmod -R u=rwX,go=rX "$STAGE_DIR"

    valid_install "$STAGE_DIR" ||
        fail "installation check failed"

    mv -T "$STAGE_DIR" "$INSTALL_DIR"
    STAGE_DIR=""
else
    echo "Geekbench ${VERSION} is already installed."
fi

printf '%s\n' \
    '#!/usr/bin/env bash' \
    "cd \"$INSTALL_DIR\" || exit 1" \
    "exec \"$INSTALL_DIR/geekbench6\" \"\$@\"" \
    >"$TEMP_DIR/geekbench6"

install -d -m 0755 /usr/local/bin
install -m 0755 "$TEMP_DIR/geekbench6" "$COMMAND"

echo "Starting Geekbench..."
trap - EXIT
cleanup
exec "$COMMAND" --cpu
