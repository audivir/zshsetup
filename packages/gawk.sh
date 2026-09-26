#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="gawk"
brew="gawk"
apt="gawk"
local_bin="$XDG_BIN_HOME/gawk"

# checks the currently installed version, echoes "" if not installed
check() {
  2>/dev/null "$local_bin" --version | awk 'NR == 1 { sub(",", "", $3); print $3 }' || echo ""
}

# fetches the latest version
fetch() {
  curl_or_wget "https://ftp.gnu.org/gnu/gawk/" \
    | grep -o 'gawk-[0-9.]*\.tar\.xz"' \
    | sed 's/^gawk-//; s/\.tar\.xz"$//' \
    | sort -t. -k1,1n -k2,2n -k3,3n \
    | tail -n 1
}

# installs the most recent version
# GNU only ships sources, so build them with the system compiler or zig
install() {
  require_cmd make zig python3 || return 1
  local version url tmpdir
  version="$1"
  url="https://ftp.gnu.org/gnu/gawk/gawk-$version.tar.xz"
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT INT TERM
  curl_or_wget "$url" "$tmpdir/gawk.tar.xz"
  python3 -m tarfile -e "$tmpdir/gawk.tar.xz" "$tmpdir"
  (
    cd "$tmpdir/gawk-$version"
    # zig cannot link the loadable extensions as macOS bundles
    ARFLAGS="cr" AR="zig ar" RANLIB="zig ranlib" CC="zig cc" LD="zig cc" ./configure --disable-nls --disable-dependency-tracking --disable-pma --disable-extensions \
      --without-readline --without-mpfr >/dev/null
    make -j4 ARFLAGS="cr" AR="zig ar" RANLIB="zig ranlib" CC="zig cc" LD="zig cc" >/dev/null
  )
  mv "$tmpdir/gawk-$version/gawk" "$local_bin"
  rm -rf "$tmpdir"
  trap - EXIT INT TERM
}

# uninstalls the installed package
uninstall() {
  rm "$local_bin"
}

main "$name" "$brew" "$apt" "$@"
