#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="git"
brew="git"
apt="git"
local_bin="$XDG_BIN_HOME/git"
prefix="${XDG_BIN_HOME%/*}"

# checks the currently installed version, echoes "" if not installed
check() {
  2>/dev/null "$local_bin" --version | awk '{print "v"$3}' || echo ""
}

# fetches the latest version
fetch() {
  get_latest_github "audivir/git-static"
}

# installs the most recent version
install() {
  local version url tmpdir
  version="$1"
  set_os_arch "linux" "amd64" "linux" "arm64" "macos" "arm64" "linux-musl"
  url="https://github.com/audivir/git-static/releases/download/$version/git-static-$os-$arch.tar.gz"
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT INT TERM
  curl_or_wget "$url" | tar -xzC "$tmpdir"
  mkdir -p "$prefix/bin" "$prefix/libexec" "$prefix/share"
  cp -R "$tmpdir/bin/." "$prefix/bin/"
  cp -R "$tmpdir/libexec/." "$prefix/libexec/"
  cp -R "$tmpdir/share/." "$prefix/share/"
  rm -rf "$tmpdir"
  trap - EXIT INT TERM
}

# uninstalls the installed package
uninstall() {
  rm -f "$local_bin" "$prefix/bin/git-receive-pack" "$prefix/bin/git-upload-archive" \
    "$prefix/bin/git-upload-pack" "$prefix/share/bash-completion/completions/git"
  rm -rf "$prefix/libexec/git-core" "$prefix/share/git-core"
}

main "$name" "$brew" "$apt" "$@"
