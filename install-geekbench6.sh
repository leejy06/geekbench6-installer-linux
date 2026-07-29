#!/usr/bin/env bash

# Unofficial Geekbench 6 installer for Ubuntu/Debian x86_64.

set -euo pipefail

VERSION="6.7.1"
ARCHIVE="Geekbench-${VERSION}-Linux.tar.gz"
ARCHIVE_DIR="Geekbench-${VERSION}-Linux"
URL="https://cdn.geekbench.com/${ARCHIVE}"
SHA256="0ddca977deb6d9db4bd866485f9408e72e2869d0dea0737b18d4bfe472858ace"

INSTALL_BASE="/opt/geekbench6"
INSTALL_DIR="${INSTALL_BASE}/${VERSION}"
COMMAND="/usr/local/bin/geekbench6"

tmpdir=""
stagedir=""

fail() {
    echo "Error: $*" >&2
    exit 1
}

ask() {
    local answer
    read -r -p "$1 [y/N]: " answer || return 1
    [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

valid_install() {
    local dir="$1"

    [[ -x "$dir/geekbench6" ]] &&
        [[ -x "$dir/geekbench_avx2" ]] &&
        [[ -x "$dir/geekbench_x86_64" ]] &&
        [[ -f "$dir/geekbench.plar" ]] &&
        [[ -f "$dir/geekbench-workload.plar" ]]
}

cleanup() {
    if [[ -n "$tmpdir" &&
          "$tmpdir" == /tmp/geekbench6-install.* &&
          -d "$tmpdir" ]]; then
        rm -rf -- "$tmpdir"
    fi

    if [[ -n "$stagedir" &&
          "$stagedir" == "$INSTALL_BASE/.${VERSION}.install."* &&
          -d "$stagedir" ]]; then
        rm -rf -- "$stagedir"
    fi
}

trap cleanup EXIT

[[ "$EUID" -eq 0 ]] ||
    fail "run this script with: sudo bash install-geekbench6.sh"

[[ "$(uname -m)" == "x86_64" ]] ||
    fail "x86_64 is required (detected: $(uname -m))"

command -v apt-get >/dev/null 2>&1 ||
    fail "this installer only supports Ubuntu and Debian systems using apt"

echo
echo "Geekbench ${VERSION} Linux installer"
echo
echo "Geekbench will use every CPU core while it runs."
echo "Stop game servers first if you do not want players to experience lag."
echo

if command -v docker >/dev/null 2>&1; then
    containers="$(docker ps --format '  {{.Names}}  {{.Status}}' 2>/dev/null || true)"
    if [[ -n "$containers" ]]; then
        container_count="$(printf '%s\n' "$containers" | wc -l)"
        container_count="${container_count//[[:space:]]/}"
        echo "Warning: ${container_count} Docker container(s) are running:" >&2
        printf '%s\n' "$containers"
        echo "They will not be stopped by this installer." >&2
        echo
    fi
fi

if ! ask "Continue?"; then
    echo "Cancelled. Nothing was changed."
    exit 0
fi

echo
echo "Installing required packages..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates coreutils curl grep libgcc-s1 tar zlib1g

tmpdir="$(mktemp -d /tmp/geekbench6-install.XXXXXX)"

if valid_install "$INSTALL_DIR"; then
    echo "Geekbench ${VERSION} is already installed; skipping the download."
elif [[ -e "$INSTALL_DIR" ]]; then
    fail "an incomplete installation already exists at ${INSTALL_DIR}"
else
    echo "Downloading ${ARCHIVE}..."
    curl --fail --location --show-error \
        --proto '=https' --proto-redir '=https' --tlsv1.2 \
        --connect-timeout 20 --retry 3 --retry-delay 2 \
        --output "$tmpdir/$ARCHIVE" "$URL"

    echo "Checking download..."
    printf '%s  %s\n' "$SHA256" "$tmpdir/$ARCHIVE" |
        sha256sum --check --status ||
        fail "the SHA-256 checksum did not match"

    tar -tzf "$tmpdir/$ARCHIVE" >"$tmpdir/archive-list.txt"

    if grep -Eq '(^/|(^|/)\.\.(/|$))' "$tmpdir/archive-list.txt"; then
        fail "the archive contains an unsafe path"
    fi

    grep -Fxq "${ARCHIVE_DIR}/geekbench6" "$tmpdir/archive-list.txt" ||
        fail "the Geekbench launcher is missing from the archive"

    tar -xzf "$tmpdir/$ARCHIVE" \
        -C "$tmpdir" --no-same-owner --no-same-permissions

    valid_install "$tmpdir/$ARCHIVE_DIR" ||
        fail "the extracted Geekbench files are incomplete"

    echo "Installing to ${INSTALL_DIR}..."
    install -d -m 0755 "$INSTALL_BASE"
    stagedir="$(mktemp -d "$INSTALL_BASE/.${VERSION}.install.XXXXXX")"

    cp -a -- "$tmpdir/$ARCHIVE_DIR/." "$stagedir/"
    chown -R root:root "$stagedir"
    chmod -R u=rwX,go=rX "$stagedir"

    valid_install "$stagedir" ||
        fail "the staged installation is incomplete"

    mv -T -- "$stagedir" "$INSTALL_DIR"
    stagedir=""
fi

cat >"$tmpdir/geekbench6-wrapper" <<EOF
#!/usr/bin/env bash
cd "$INSTALL_DIR" || exit 1
exec "$INSTALL_DIR/geekbench6" "\$@"
EOF

install -d -m 0755 /usr/local/bin
install -m 0755 "$tmpdir/geekbench6-wrapper" "$COMMAND"

echo
echo "Geekbench ${VERSION} is installed."
echo "Run it with: geekbench6 --cpu"
echo

if ask "Run the CPU benchmark now?"; then
    echo
    echo "Starting Geekbench..."
    trap - EXIT
    cleanup
    exec "$COMMAND" --cpu
fi
