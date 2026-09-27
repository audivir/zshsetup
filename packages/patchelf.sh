#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="patchelf"
brew="patchelf"
apt="patchelf"
local_bin="$XDG_BIN_HOME/patchelf"

# checks the currently installed version, echoes "" if not installed
check() {
  2>/dev/null "$local_bin" --version | awk '{print $2}' || echo ""
}

# fetches the latest version
fetch() {
  get_latest_github "NixOS/patchelf"
}

# installs the most recent version
# the release binaries are static, so they run on glibc and musl
install() {
  local version url
  version="$1"
  set_os_arch "linux" "x86_64" "linux" "aarch64" "" ""
  if [ "$os" != "linux" ]; then
    echo "$name only has Linux release binaries" >&2
    return 1
  fi
  url="https://github.com/NixOS/patchelf/releases/download/$version/patchelf-$version-$arch.tar.gz"
  tmpfile="$(mktemp)"
  trap 'rm -f "$tmpfile"' EXIT INT TERM
  curl -fsSL "$url" | tar -xzO ./bin/patchelf >"$tmpfile"
  chmod +x "$tmpfile"
  mv "$tmpfile" "$local_bin"
  trap - EXIT INT TERM
}

# uninstalls the installed package
uninstall() {
  rm "$local_bin"
}

main "$name" "$brew" "$apt" "$@"
