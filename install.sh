#!/bin/sh
# shellcheck shell=sh

__available() {
  cmd="$1"
  shift
  command "$cmd" "$@" >/dev/null 2>&1
}

__download() {
  url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O - "$url"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import shutil, sys, urllib.request; res = urllib.request.urlopen(sys.argv[1]); shutil.copyfileobj(res, sys.stdout.buffer)' "$url"
  elif [ -x "/usr/lib/apt/apt-helper" ]; then
    tmp="$(mktemp)"
    if ! /usr/lib/apt/apt-helper -o Acquire::https::Verify-Peer=false download-file "$url" "$tmp" >/dev/null 2>&1; then
      rm -f "$tmp"
      exit 1
    fi
    cat "$tmp"
    rm -f "$tmp"
  else
    echo "curl, wget, python3, or apt-helper required!" >&2
    exit 1
  fi
}

if [ -z "$HOME" ]; then
  echo "HOME must be set"
  exit 1
fi

if [ "$(uname)" = "Darwin" ] && [ "$(uname -m)" != "arm64" ]; then
  echo "Only macOS arm64 is supported" >&2
  exit 1
fi

if ! __available curl --help && ! __available wget --help && [ ! -x /usr/lib/apt/apt-helper ] && ! __available python3 --version; then
  echo "curl (or wget/apt-helper/python3) required!"
  exit 1
fi

if ! __available zsh --help; then
  export PATH="$PATH:$HOME/.local/bin"
  if ! __available zsh --help; then
    zsh_tmp="$(mktemp -d)"
    zsh_archive=""
    # the zsh-bin installer only downloads with curl or wget, so otherwise hand it the archive
    if ! __available curl --help && ! __available wget --help; then
      zsh_archive="$zsh_tmp/zsh.tar.gz"
      zsh_platform="$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)"
      if ! __download "https://github.com/romkatv/zsh-bin/releases/download/v6.1.1/zsh-5.8-$zsh_platform.tar.gz" >"$zsh_archive"; then
        rm -rf "$zsh_tmp"
        exit 1
      fi
    fi
    # runs the installer only when fully downloaded
    if ! __download https://raw.githubusercontent.com/romkatv/zsh-bin/v6.1.1/install >"$zsh_tmp/install" \
      || ! sh "$zsh_tmp/install" -d "$HOME/.local" -e "no" ${zsh_archive:+-f "$zsh_archive"}; then
      rm -rf "$zsh_tmp"
      echo "Failed to install zsh" >&2
      exit 1
    fi
    rm -rf "$zsh_tmp"
  fi
fi

# for tests/docker_smoke_test.sh
if [ -n "${ZSHSETUP_ZSH_ONLY:-}" ]; then
  exit 0
fi

if ! __available git --version; then
  snapshot="$(mktemp -d)"
  mkdir -p "$HOME/.local/bin" "$HOME/.local/share"
  if ! __download https://github.com/audivir/zshsetup/archive/refs/heads/main.tar.gz | tar -xzC "$snapshot" \
    || ! ZSHSETUP_HOME="$snapshot/zshsetup-main" XDG_BIN_HOME="$HOME/.local/bin" XDG_DATA_HOME="$HOME/.local/share" \
      zsh "$snapshot/zshsetup-main/packages/git.sh" package; then
    rm -rf "$snapshot"
    echo "Failed to install git" >&2
    exit 1
  fi
  rm -rf "$snapshot"
  export PATH="$HOME/.local/bin:$PATH"
fi

# runs .zshrc only when fully downloaded
zshrc="$(mktemp)"
if ! __download https://github.com/audivir/zshsetup/raw/refs/heads/main/.zshrc >"$zshrc"; then
  rm -f "$zshrc"
  echo "Failed to download .zshrc" >&2
  exit 1
fi
zsh "$zshrc" install
status=$?
rm -f "$zshrc"
exit "$status"
