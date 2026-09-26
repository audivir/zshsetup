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
  curl --fail-with-body -sL "https://ftp.gnu.org/gnu/gawk/" \
    | grep -o 'gawk-[0-9.]*\.tar\.xz"' \
    | sed 's/^gawk-//; s/\.tar\.xz"$//' \
    | sort -t. -k1,1n -k2,2n -k3,3n \
    | tail -n 1
}

# installs the most recent version
# GNU only ships sources, so build them with the system compiler or zig
install() {
  require_cmd make cc || return 1
  local version url tmpdir cc
  version="$1"
  # TODO: move this to a own cc package!
  if 2>/dev/null >/dev/null cc --version; then
    cc="cc"
  elif 2>/dev/null >/dev/null zig version; then
    cc="zig cc"
  else
    echo "cc or zig is required to build $name" >&2
    return 1
  fi
  url="https://ftp.gnu.org/gnu/gawk/gawk-$version.tar.xz"
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT INT TERM
  curl_or_wget "$url" | tar -xJC "$tmpdir"
  (
    cd "$tmpdir/gawk-$version"
    # zig cannot link the loadable extensions as macOS bundles
    ARFLAGS="cr" CC="$cc" ./configure --disable-nls --disable-pma --disable-extensions \
      --without-readline --without-mpfr >/dev/null
    make -j4 ARFLAGS="cr" >/dev/null
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
