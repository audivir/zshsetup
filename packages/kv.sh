#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="kv"
brew="kv"
apt=""
local_bin="$XDG_BIN_HOME/kv"

# checks the currently installed version, echoes "" if not installed
check() {
  2>/dev/null "$local_bin" --version | awk '{print $2}' || echo ""
}

# fetches the latest version
fetch() {
  local version
  version=$(get_latest_github "audivir/kv")
  echo "${version#v}"
}

# checks for glibc's libmvec, which the gnu build needs
has_libmvec() {
  local dir
  for dir in /lib64 /usr/lib64 "/lib/$(uname -m)-linux-gnu" "/usr/lib/$(uname -m)-linux-gnu"; do
    [ -e "$dir/libmvec.so.1" ] && return 0
  done
  return 1
}

# installs the most recent version
install() {
  local version url tmpfile loader
  version="$1"
  loader=""
  set_os_arch "unknown-linux-gnu" "x86_64" "unknown-linux-gnu" "aarch64" "apple-darwin" "aarch64" "unknown-linux-musl"
  # glibc hosts that cannot run the gnu build run the musl build with a user-space musl;
  # a static build would lose pdfium, which kv loads at runtime
  if [ "$os" = "unknown-linux-gnu" ] && { ! __glibc_at_least 2.39 || ! has_libmvec; }; then
    require_cmd patchelf musl || return 1
    os="unknown-linux-musl"
    loader="$(echo "$XDG_DATA_HOME"/musl/ld-musl-*.so.1)"
  fi
  url="https://github.com/audivir/kv/releases/download/v$version/kv-$arch-$os"
  tmpfile="$(mktemp)"
  trap 'rm -f "$tmpfile"' EXIT INT TERM
  curl -fsSL "$url" -o "$tmpfile"
  chmod +x "$tmpfile"
  [ -z "$loader" ] || patchelf --set-interpreter "$loader" "$tmpfile"
  mv "$tmpfile" "$local_bin"
  trap - EXIT INT TERM
}

# uninstalls the installed package
uninstall() {
  rm "$local_bin"
}

main "$name" "$brew" "$apt" "$@"
