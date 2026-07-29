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
