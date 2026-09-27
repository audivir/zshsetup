#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="curl"
brew=""
apt="curl"
local_bin="$XDG_BIN_HOME/curl"
bootstrap_version="8.22.0"

# checks the currently installed version, echoes "" if not installed
check() {
  2>/dev/null "$local_bin" --version | awk 'NR == 1 {print $2}' || echo ""
}

# fetches the latest version
fetch() {
  if [ -z "$(check)" ]; then
    echo "$bootstrap_version"
  else
    get_latest_github "stunnel/static-curl"
  fi
}

# installs the most recent version
install() {
  require_cmd python3 || return 1
  local version url tmpdir expected
  version="${1:-$bootstrap_version}"
  # the static musl build also runs on glibc; the glibc one crashes on older glibc (CentOS 7)
  set_os_arch "linux" "x86_64-musl" "linux" "aarch64-musl" "macos" "arm64"
  url="https://github.com/stunnel/static-curl/releases/download/$version/curl-$os-$arch-$version.tar.xz"
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT INT TERM
  __bootstrap_download "$url" "$tmpdir/curl.tar.xz"
  # the bootstrap download may come from apt-helper without TLS verification
  if [ "$version" = "$bootstrap_version" ]; then
    case "$os-$arch" in
      linux-x86_64-musl) expected=dfb02460ba2abe513087538f12a3cf79b74b64a5ea3787ce8ac0cdb11251f884 ;;
      linux-aarch64-musl) expected=cf94cbeaae1b3c1944a4a761ef04478f8f0b23e93a324b5ed009b2082eda11f3 ;;
      macos-arm64) expected=416cadcd491e57846d23301e4c56e1a1517668c62f63d4ac991ad6caf4feabea ;;
    esac
    if [ "$(sha256 "$tmpdir/curl.tar.xz")" != "$expected" ]; then
      echo "sha256 mismatch for $url" >&2
      return 1
    fi
  fi
  python3 -m tarfile --filter data -e "$tmpdir/curl.tar.xz" "$tmpdir"
  chmod +x "$tmpdir/curl"
  mv "$tmpdir/curl" "$local_bin"
  rm -rf "$tmpdir"
  trap - EXIT INT TERM
}

# uninstalls the installed package
uninstall() {
  rm "$local_bin"
}

main "$name" "$brew" "$apt" "$@"
