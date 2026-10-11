#!/bin/sh
# shellcheck shell=sh disable=SC3043
# installs zshsetup: bootstraps uv, installs zsh and git where missing, then runs .zshrc
# with ZSHSETUP_INSTALL_LIB set, sourcing it only defines the functions .zshrc and packages/pmg
# share; zsh sources it with emulate sh, so they keep the semantics of sh

# the oldest tag of pmg zshsetup works with, which install.sh runs; packages/pmg installs the
# latest tag and keeps an installed one while it is not older
__PMG_TAG="v2.3.4"
__PMG_REPO="https://github.com/zshsetup/pmg"

# checks whether the version of the tag $1 is at least that of $2, e.g. v1.10.0 and v1.9.2; in the
# shell, as packages/pmg checks it on every call
__version_at_least() {
  local a b x y
  a="${1#v}"
  b="${2#v}"
  while [ -n "$a$b" ]; do
    x="${a%%.*}"
    y="${b%%.*}"
    case "${x:-0}${y:-0}" in
      *[!0-9]*) return 1 ;;
    esac
    [ "${x:-0}" -gt "${y:-0}" ] && return 0
    [ "${x:-0}" -lt "${y:-0}" ] && return 1
    case "$a" in *.*) a="${a#*.}" ;; *) a="" ;; esac
    case "$b" in *.*) b="${b#*.}" ;; *) b="" ;; esac
  done
}

# prints the latest vX.Y.Z tag of pmg, with git, which every zshsetup has, and no API limit
__latest_pmg_tag() {
  local tag latest
  latest=""
  for tag in $(git ls-remote --tags --refs "$__PMG_REPO" 'v*' 2>/dev/null | sed 's|.*refs/tags/||'); do
    case "$tag" in
      v*[!0-9.]* | v | v.* | *..* | *.) continue ;;
    esac
    if [ -z "$latest" ] || __version_at_least "$tag" "$latest"; then
      latest="$tag"
    fi
  done
  [ -n "$latest" ] && echo "$latest"
}

# prints the Python for pmg with the uv $1: an installed one from 3.10 on, outside of any venv,
# if it has the tarfile data filter (backported to 3.10.12 and 3.11.4), else 3.12 for uv to install
__pmg_python() {
  local python
  if python="$("$1" python find --system --no-project '>=3.10' 2>/dev/null)" \
    && "$python" -c 'import tarfile; tarfile.data_filter' 2>/dev/null; then
    echo "$python"
  else
    echo 3.12
  fi
}

# prints the path of an executable in PATH without running it, ignoring functions and aliases
__which() {
  local dir IFS
  IFS=:
  for dir in $PATH; do
    if [ -f "${dir:-.}/$1" ] && [ -x "${dir:-.}/$1" ]; then
      echo "${dir:-.}/$1"
      return 0
    fi
  done
  return 1
}

# checks whether an executable is in PATH
__available() {
  local cmd_path
  cmd_path="$(__which "$1")" || return 1
  # macOS's stubs in /usr/bin (git, make, cc, ...) only offer to install the missing developer tools
  if [ "$(uname)" = "Darwin" ] && [ "$cmd_path" -ef /usr/bin/cc ] && ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
    return 1
  fi
}

# installs pmg from a spec, the archive of a tag or a local checkout (installed editable), into the
# venv that packages/pmg runs, with an installed Python, else 3.12 of uv; the source is written
# last, so an interrupted install is redone
__install_pmg_venv() {
  local uv venv source spec
  uv="$1"
  venv="$2"
  source="$3"
  spec="$4"
  "$uv" venv --quiet --clear --python "$(__pmg_python "$uv")" "$venv" || return 1
  if [ -d "$spec" ]; then
    "$uv" pip install --quiet --python "$venv/bin/python" --editable "$spec" || return 1
  else
    "$uv" pip install --quiet --python "$venv/bin/python" "$spec" || return 1
  fi
  printf '%s\n' "$source" >"$venv/.source"
}

# prints a URL with curl, wget, python3, or apt-helper, for bootstrapping uv
__download() {
  local tmp
  if __available curl; then
    curl -fsSL "$1"
  elif __available wget; then
    wget -q -O - "$1"
  elif __available python3; then
    python3 -c 'import shutil, sys, urllib.request; res = urllib.request.urlopen(sys.argv[1]); shutil.copyfileobj(res, sys.stdout.buffer)' "$1"
  elif [ -x "/usr/lib/apt/apt-helper" ]; then
    # without CA certificates, the checksum of uv still guards the download
    tmp="$(mktemp)"
    if ! /usr/lib/apt/apt-helper -o Acquire::https::Verify-Peer=false download-file "$1" "$tmp" >/dev/null 2>&1; then
      rm -f "$tmp"
      return 1
    fi
    cat "$tmp"
    rm -f "$tmp"
  else
    echo "curl, wget, python3, or apt-helper required!" >&2
    return 1
  fi
}

# the gnu build of uv needs glibc 2.28, older glibc and musl get the static musl build
__uv_libc() {
  local glibc minor
  glibc="$(getconf GNU_LIBC_VERSION 2>/dev/null | cut -d ' ' -f 2)"
  minor="${glibc#2.}"
  if [ -n "$glibc" ] && [ "${minor%%.*}" -ge 28 ]; then
    echo gnu
  else
    echo musl
  fi
}

# installs a fixed uv into $1, checked against its sha256
__bootstrap_uv() {
  local target sha256 asset url uv_tmp actual rc
  case "$(uname -s)-$(uname -m)-$(__uv_libc)" in
    Linux-x86_64-gnu) target="x86_64-unknown-linux-gnu" sha256="23bf5552d220e0842b65c862097b2ebaeba0064b74eda5e565e77fd25969d8c8" ;;
    Linux-aarch64-gnu) target="aarch64-unknown-linux-gnu" sha256="0804e9b164c64b6914182d5920c08551958a095986f10a3731056df701126436" ;;
    Linux-x86_64-musl) target="x86_64-unknown-linux-musl" sha256="db7278c9f57981338fddff1fb250e11964bc0a4fafcb9eed8303fdb117dc067b" ;;
    Linux-aarch64-musl) target="aarch64-unknown-linux-musl" sha256="ad8d8448a2ff642ba62c2f684d7dd22a03f8eb3fc9918c2c3e8ec975f4ed6710" ;;
    Darwin-arm64-*) target="aarch64-apple-darwin" sha256="a9a8df1eedeb192f2e47e40e2faabfb387db4b850209118786d42f89dde3e0ba" ;;
    *)
      echo "no uv for $(uname -s) $(uname -m)" >&2
      return 1
      ;;
  esac
  asset="uv-$target.tar.gz"
  url="https://github.com/astral-sh/uv/releases/download/0.12.19/$asset"
  uv_tmp="$(mktemp -d)"
  __download "$url" >"$uv_tmp/$asset" || {
    rm -rf "$uv_tmp"
    return 1
  }
  if __available sha256sum; then
    actual="$(sha256sum "$uv_tmp/$asset" | cut -d ' ' -f 1)"
  else
    actual="$(shasum -a 256 "$uv_tmp/$asset" | cut -d ' ' -f 1)"
  fi
  if [ "$actual" != "$sha256" ]; then
    echo "sha256 mismatch for $url" >&2
    rm -rf "$uv_tmp"
    return 1
  fi
  tar -xzf "$uv_tmp/$asset" -C "$uv_tmp" && mkdir -p "$1" && mv "$uv_tmp/${asset%.tar.gz}/uv" "$1/uv"
  rc=$?
  rm -rf "$uv_tmp"
  return "$rc"
}

# prints whether the apt lists hold any package index
# checks whether the package index of apt, or the repo metadata of dnf or yum, is on the system;
# with globs, as the image of Rocky Linux has no find
__has_metadata() { # manager
  local file
  case "$1" in
    apt) set -- /var/lib/apt/lists/* ;;
    dnf) set -- /var/cache/dnf/*/repodata/repomd.xml ;;
    yum) set -- /var/cache/yum/*/*/*/repomd.xml ;;
    *) return 1 ;;
  esac
  for file; do
    [ -f "$file" ] && [ "${file##*/}" != lock ] && return 0
  done
  return 1
}

# installs packages with brew, apt, apk, dnf, or yum, as root or with sudo; fails if the manager is
# missing; apk keeps no index, and the metadata the others download onto a system without any is
# removed by __clean_metadata
__system_install() { # manager, packages
  local manager command sudo
  manager="$1"
  shift
  case "$manager" in
    apt) command=apt-get ;;
    brew | apk | dnf | yum) command="$manager" ;;
    *) return 1 ;;
  esac
  __available "$command" || return 1
  sudo=""
  if [ "$manager" != brew ] && [ "$(id -u)" -ne 0 ]; then
    __available sudo || return 1
    sudo="sudo"
  fi
  if [ "$manager" != brew ] && [ "$manager" != apk ] && ! __has_metadata "$manager"; then
    __METADATA_CREATED="${__METADATA_CREATED:-} $manager"
  fi
  case "$manager" in
    brew)
      NONINTERACTIVE=1 brew install "$@"
      ;;
    apk)
      $sudo apk add --no-cache "$@"
      ;;
    apt)
      # fresh systems and containers have no lists, others may have outdated ones
      if ! __has_metadata apt; then
        $sudo apt-get update || return 1
      fi
      $sudo env DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends --yes "$@" \
        || { $sudo apt-get update && $sudo env DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends --yes "$@"; }
      ;;
    dnf)
      # weak dependencies are the recommends of apt
      $sudo dnf install --assumeyes --setopt=install_weak_deps=False "$@"
      ;;
    yum)
      $sudo yum install --assumeyes "$@"
      ;;
  esac
}

# removes the metadata __system_install downloaded onto a system without any, as images have none
__clean_metadata() {
  local manager sudo
  sudo=""
  [ "$(id -u)" -eq 0 ] || sudo="sudo"
  for manager in ${__METADATA_CREATED:-}; do
    case "$manager" in
      apt) $sudo sh -c 'rm -rf /var/lib/apt/lists/*' ;;
      dnf | yum) $sudo "$manager" clean all >/dev/null ;;
    esac
  done
  __METADATA_CREATED=""
}

# checks whether a system package manager is available
__manager_available() {
  case "$1" in
    apt) __available apt-get ;;
    brew | apk | dnf | yum) __available "$1" ;;
    *) return 1 ;;
  esac
}

# installs a package with the manager ZSHSETUP_CHOICE_<PACKAGE> or ZSHSETUP_CHOICE picks, if the
# package has a name there; $2 has "manager names" lines, as pmg external prints them
__install_chosen() { # package, names
  local choice_var choice manager names
  choice_var="ZSHSETUP_CHOICE_$(printf '%s' "$1" | tr 'a-z-' 'A-Z_')"
  eval "choice=\${$choice_var:-\${ZSHSETUP_CHOICE:-}}"
  [ -n "$choice" ] && [ "$choice" != manual ] || return 1
  while read -r manager names; do
    if [ "$manager" = "$choice" ] || { [ "$choice" = "os" ] && __manager_available "$manager"; }; then
      echo "Install $1 via $choice" >&2
      # a spec may list several packages, e.g. "curl ca-certificates"
      # shellcheck disable=SC2086
      __system_install "$manager" $names
      return
    fi
  done <<EOF
$2
EOF
  return 1
}

__install_main() {
  local uv venv installed source spec zshrc rc
  if [ -z "$HOME" ]; then
    echo "HOME must be set"
    exit 1
  fi

  if [ "$(uname)" = "Darwin" ] && [ "$(uname -m)" != "arm64" ]; then
    echo "Only macOS arm64 is supported" >&2
    exit 1
  fi

  trap __clean_metadata EXIT
  export PATH="$HOME/.local/bin:$PATH"

  # uv from the chosen package manager, or bootstrapped where packages/pmg would put it, so it is
  # reused and cleaned up by .zshrc
  uv="$(__which uv)"
  if [ -z "$uv" ] && __install_chosen uv "$(printf 'apk uv\nbrew uv\n')"; then
    uv="$(__which uv)"
    # a packaged uv may be too old to download Python for the machine, e.g. 0.7 of Alpine 3.22 on arm64
    if [ -n "$uv" ] && [ "$(__pmg_python "$uv")" = 3.12 ] && ! "$uv" python install --quiet 3.12; then
      echo "The uv of the package manager cannot install Python 3.12, bootstrapping one" >&2
      uv=""
    fi
  fi
  if [ -z "$uv" ]; then
    uv="${XDG_CACHE_HOME:-$HOME/.cache}/zshsetup/uv/uv"
    if [ ! -x "$uv" ] && ! __bootstrap_uv "${uv%/uv}"; then
      echo "Failed to bootstrap uv" >&2
      exit 1
    fi
  fi

  # pmg at its minimum tag, as git may be missing to find the latest, in the venv packages/pmg runs,
  # so the first shell need not install it again; uv checks certificates with its own, so the
  # system needs none
  venv="$HOME/.local/share/zshsetup/pmg"
  if [ -n "${ZSHSETUP_PMG:-}" ]; then
    source="$ZSHSETUP_PMG"
    spec="$ZSHSETUP_PMG"
  else
    source="$__PMG_TAG"
    spec="$__PMG_REPO/archive/refs/tags/$__PMG_TAG.tar.gz"
  fi
  # a venv that packages/pmg would run as it is, e.g. of an earlier install, is kept
  installed="$(cat "$venv/.source" 2>/dev/null || true)"
  if [ ! -x "$venv/bin/python" ] || { [ -n "${ZSHSETUP_PMG:-}" ] && [ "$installed" != "$source" ]; } \
    || { [ -z "${ZSHSETUP_PMG:-}" ] && ! __version_at_least "$installed" "$__PMG_TAG"; }; then
    if ! __install_pmg_venv "$uv" "$venv" "$source" "$spec"; then
      echo "Failed to install pmg" >&2
      exit 1
    fi
  fi
  pmg() {
    XDG_BIN_HOME="$HOME/.local/bin" XDG_DATA_HOME="$HOME/.local/share" "$venv/bin/python" -m pmg "$@"
  }

  if ! __available zsh && ! pmg install zsh; then
    echo "Failed to install zsh" >&2
    exit 1
  fi

  # for tests/lib.sh
  if [ -n "${ZSHSETUP_ZSH_ONLY:-}" ]; then
    exit 0
  fi

  if ! __available git && ! { __install_chosen git "$(pmg external git)" && __available git; } && ! pmg install git; then
    echo "Failed to install git" >&2
    exit 1
  fi

  # runs .zshrc only when fully downloaded, with the certificates of certifi, a dependency of pmg
  zshrc="$(mktemp)"
  if ! "$venv/bin/python" -c 'import shutil, ssl, sys, urllib.request, certifi
context = ssl.create_default_context(cafile=certifi.where())
shutil.copyfileobj(urllib.request.urlopen(sys.argv[1], context=context), sys.stdout.buffer)' \
    https://github.com/zshsetup/zshsetup/raw/refs/heads/main/.zshrc >"$zshrc"; then
    rm -f "$zshrc"
    echo "Failed to download .zshrc" >&2
    exit 1
  fi
  zsh "$zshrc" install
  rc=$?
  rm -f "$zshrc"
  exit "$rc"
}

if [ -z "${ZSHSETUP_INSTALL_LIB:-}" ]; then
  __install_main
fi
