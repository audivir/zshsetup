#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="make"
brew=""
apt=""
local_bin="$XDG_BIN_HOME/make"

# checks the currently installed version, echoes "" if not installed
check() {
  2>/dev/null "$local_bin" --version | awk 'NR == 1 {print $3}' || echo ""
}

# fetches the latest version
fetch() {
  curl_or_wget "https://ftp.gnu.org/gnu/make/" \
    | grep -o 'make-[0-9.]*\.tar\.gz"' \
    | sed 's/^make-//; s/\.tar\.gz"$//' \
    | sort -t. -k1,1n -k2,2n -k3,3n \
    | tail -n 1
}

# installs the most recent version
# build.sh bootstraps make without an existing make, using the system compiler or zig
install() {
  require_cmd zig || return 1
  local version url tmpdir
  version="$1"
  url="https://ftp.gnu.org/gnu/make/make-$version.tar.gz"
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT INT TERM
  curl_or_wget "$url" | tar -xzC "$tmpdir"
  (
    cd "$tmpdir/make-$version"
    ARFLAGS="cr" AR="zig ar" RANLIB="zig ranlib" CC="zig cc -w" LD="zig cc" \
      ./configure --disable-nls --disable-dependency-tracking --without-guile >/dev/null
    ARFLAGS="cr" AR="zig ar" RANLIB="zig ranlib" CC="zig cc -w" LD="zig cc" \
      sh build.sh >/dev/null
  )
  mv "$tmpdir/make-$version/make" "$local_bin"
  rm -rf "$tmpdir"
  trap - EXIT INT TERM
}

# uninstalls the installed package
uninstall() {
  rm "$local_bin"
}

main "$name" "$brew" "$apt" "$@"
