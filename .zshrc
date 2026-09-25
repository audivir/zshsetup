#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
# expect $USER and $HOME to be set

export ZSHSETUP_REPO="https://github.com/audivir/zshsetup"
export ZSHSETUP_HOME="$HOME/.config/zshsetup"

# drop duplicate PATH entries, e.g. when .zshrc is sourced again
# shellcheck disable=SC2034
typeset -U path

rm() {
  local arg root mounts target hits after_options

  after_options=false
  mounts=""

  for arg in "$@"; do
    if ! $after_options; then
      case "$arg" in
        --)
          after_options=true
          continue
          ;;
        -*)
          continue
          ;;
      esac
    fi

    [[ -e "$arg" || -L "$arg" ]] || continue

    # rm deletes a symlink itself, so only its parent directory is resolved
    if [[ -L "$arg" && "$arg" != */ ]]; then
      root="${arg:h:A}"
      root="${root%/}/${arg:t}"
    else
      root="${arg:A}"
    fi

    # Fetch all mount targets once depending on the OS
    if [[ -z "$mounts" ]]; then
      mounts=$(
        if command -v findmnt >/dev/null 2>&1; then
          findmnt -rn -o TARGET
        else
          mount | awk 'match($0, / on \/.* \(/) { print substr($0, RSTART+4, RLENGTH-6) }'
        fi
      )
    fi

    hits=""
    while IFS= read -r target; do
      if [[ "$target" == "$root" || ("$root" != "/" && "$target" == "$root"/*) ]]; then
        hits+="$target"$'\n'
      fi
    done <<<"$mounts"

    if [[ -n "$hits" ]]; then
      printf 'rm: refusing to remove %q\n' "$arg" >&2
      printf 'rm: mounted filesystem(s):\n%s' "$hits" >&2
      return 1
    fi
  done

  /bin/rm "$@"
}

__eprint() {
  echo "$1" >&2
  return 1
}

__assure_link() {
  local link_file expected_target
  link_file="$1"
  expected_target="$2"
  if [ -L "$link_file" ]; then
    actual_target=$(readlink "$link_file") || return 1
    if [ "$actual_target" != "$expected_target" ]; then
      __eprint "$link_file points to $actual_target. Rewriting to $expected_target..."
      ln -snf "$expected_target" "$link_file"
    fi
  elif [ -d "$link_file" ] || [ -f "$link_file" ]; then
    __eprint "$link_file is a directory or file, please backup and move it first"
  else
    ln -s "$expected_target" "$link_file"
  fi
}

__assure_dir() {
  local dir_to_check
  dir_to_check="$1"
  mkdir -p "$dir_to_check" || __eprint "$dir_to_check not found and not creatable"
}

__package_manager() {
  python3 "$ZSHSETUP_HOME/package_manager.py" "$@"
}

__source() {
  local env
  env=$("$@") || return 1
  eval "$env"
}

# looks up the executable without running it, ignoring functions and aliases
__available() {
  whence -p "$1" &>/dev/null
}

__init_cache() {
  local user_cache scratch_cache
  user_cache="$HOME/.cache"
  scratch_cache="/scratch/$USER/.cache"
  # if /home is mounted, look for /scratch to use as cache directory
  if [ -z "$ZSHSETUP_IGNORESCRATCH" ] && [ -d "/scratch" ] \
    && [ ! -f "$user_cache/.zshsetup_do_not_use_scratch" ]; then
    if [ -d "$user_cache" ] && [ ! -L "$user_cache" ]; then
      __eprint "zshsetup stopped: /scratch exists, but $user_cache is a directory.
Move it to /scratch with:
  mkdir -p ${scratch_cache:h} && mv $user_cache $scratch_cache
or keep it with:
  touch $user_cache/.zshsetup_do_not_use_scratch"
      return 1
    fi
    __assure_dir "$scratch_cache" || return 1
    __assure_link "$user_cache" "$scratch_cache" || return 1
    CACHE_DIR="$scratch_cache"
  else
    CACHE_DIR="$user_cache"
  fi
}

__init_zshsetup() {
  __init_cache || return 1

  export LOCAL_HOME="$HOME/.local"
  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_DATA_HOME="$LOCAL_HOME/share"
  export XDG_BIN_HOME="$LOCAL_HOME/bin"
  export XDG_CACHE_HOME="$CACHE_DIR"
  export XDG_STATE_HOME="$LOCAL_HOME/state"
  # systemd sets it on Linux, and macOS has no equivalent besides the per-user TMPDIR
  # an inherited value is replaced when its directory does not exist
  if [ ! -d "$XDG_RUNTIME_DIR" ]; then
    if [ -d "/run/user/$UID" ]; then
      export XDG_RUNTIME_DIR="/run/user/$UID"
    elif [[ "$OSTYPE" == darwin* ]] && [ -n "$TMPDIR" ]; then
      export XDG_RUNTIME_DIR="${TMPDIR%/}"
    fi
  fi

  for dir in "$LOCAL_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_BIN_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"; do
    __assure_dir "$dir" || return 1
  done

  # BEGIN OH-MY-ZSH
  export ZSH="$ZSHSETUP_HOME/oh-my-zsh"
  if [ ! -d "$ZSH" ]; then
    "$ZSHSETUP_HOME/packages/oh-my-zsh.sh" || return 1
  fi
  # oh-my-zsh bundles zsh-autosuggestions and zsh-syntax-highlighting itself
  # shellcheck disable=SC2034
  plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
  ZSH_CACHE="$XDG_CACHE_HOME/zsh"
  __assure_dir "$ZSH_CACHE" || return 1
  # shellcheck disable=SC2034
  ZSH_COMPDUMP="$ZSH_CACHE/zcompdump-${HOST%%.*}-${ZSH_VERSION}"
  # shellcheck disable=SC2034
  ZSH_CUSTOM="$ZSH/custom"
  # shellcheck disable=SC2034
  ZSH_THEME="robbyrussell"
  . "$ZSH/oh-my-zsh.sh" || return 1
  # END OH-MY-ZSH

  HISTFILE="$ZSHSETUP_HOME/zsh_history"

  # BEGIN HOMEBREW
  if [ -f "/opt/homebrew/bin/brew" ]; then
    __source /opt/homebrew/bin/brew shellenv || return 1
    alias homebrewupdate='brew update; brew upgrade --formulae --yes && brew cu --yes && cd /opt/homebrew && git stash pop &>/dev/null || true && cd -'
  fi
  # END HOMEBREW

  PATH="$XDG_BIN_HOME:$HOME/bin:$PATH"

  # BEGIN GAWK
  if ! __available gawk; then
    # zig and make are only needed to build gawk from source
    # cc and make are run, since macOS ships shims for them without the Command Line Tools
    if ! 2>/dev/null >/dev/null cc --version && ! __available zig; then
      __package_manager zig zig "" || return 1
    fi
    if ! 2>/dev/null >/dev/null make --version; then
      __package_manager make "" make || return 1
    fi
    __package_manager gawk gawk gawk || return 1
  fi
  showhist() {
    gawk -F'[:;]' '$2 ~ /^[[:space:]]*[0-9]+$/ {cmd=$0; sub(/^: [0-9]+:0;/,"",cmd); print ": " strftime("%Y-%m-%d %H:%M:%S",$2) ":0;" cmd; next} {print}' "$HISTFILE"
  }
  # END GAWK

  # BEGIN JQ
  if ! __available jq; then
    __package_manager jq jq jq || return 1
  fi
  # END JQ

  # BEGIN MICROMAMBA
  if ! __available micromamba; then
    __package_manager micromamba micromamba-static micromamba || return 1
  fi
  alias conda='micromamba'
  __source command micromamba shell hook --shell zsh || return 1
  export MAMBA_ROOT_PREFIX="$XDG_DATA_HOME/micromamba"
  # END MICROMAMBA

  # BEGIN GO
  PATH="$XDG_DATA_HOME/go/bin:$XDG_DATA_HOME/golang/bin:$PATH"
  if ! __available go; then
    __package_manager go go golang || return 1
  fi
  if [ -d "$XDG_DATA_HOME/golang" ]; then
    export GOROOT="$XDG_DATA_HOME/golang"
  fi
  export GOPATH="$XDG_DATA_HOME/go"
  # END GO

  # BEGIN RUST
  PATH="$XDG_DATA_HOME/cargo/bin:/opt/homebrew/opt/rustup/bin:$PATH"
  export RUSTUP_HOME="$XDG_DATA_HOME/rustup"
  export CARGO_HOME="$XDG_DATA_HOME/cargo"
  if ! __available rustup; then
    __package_manager rustup rustup rustup || return 1
  fi
  # END RUST

  # BEGIN PYTHON
  if ! __available uv; then
    __package_manager uv uv "" || return 1
  fi
  if ! __available uvc; then
    __package_manager uvc uvc "" || return 1
  fi
  __source command uvc shell zsh || return 1
  # END PYTHON

  # BEGIN JAVASCRIPT
  export BUN_INSTALL="$XDG_DATA_HOME/bun"
  export BUN_INSTALL_CACHE_DIR="$XDG_CACHE_HOME/bun/install"
  export BUN_RUNTIME_TRANSPILER_CACHE_PATH="$XDG_CACHE_HOME/bun/runtime"
  export BUN_CONFIG_DIR="$XDG_CONFIG_HOME/bun"
  PATH="$BUN_INSTALL/bin:$PATH"
  if ! __available bun; then
    __package_manager bun bun "" || return 1
  fi
  # END JAVASCRIPT

  # BEGIN EXTRA TOOLS
  if ! __available bat; then
    __package_manager bat bat bat || return 1
  fi

  if ! __available micro; then
    __package_manager micro micro micro || return 1
  fi

  if ! __available kv; then
    __package_manager kv kv kv || return 1
  fi
  # END EXTRA TOOLS

  # BEGIN ALIASES
  alias b="bat --paging=never --style=plain --tabs=4"
  alias sb="sudo bat --paging=never --style=plain --tabs=4"
  # END ALIASES

  # BEGIN ENVIRONMENT
  export GNUPGHOME="$XDG_DATA_HOME/gnupg"
  export MPLCONFIGDIR="$XDG_CONFIG_HOME/matplotlib"
  export PYTHON_HISTORY="$XDG_DATA_HOME/python/python_history"
  # END ENVIRONMENT

  export PATH

  # BEGIN THEME VIEWER
  . "$ZSHSETUP_HOME/theme_viewer.sh" || return 1
  # END THEME VIEWER
  # typeset -U only deduplicates array assignments, not PATH="...:$PATH"
  path=("${path[@]}")
}

__install_zshsetup() {
  if [ -d "$ZSHSETUP_HOME" ]; then
    __assure_link "$HOME/.zshrc" "$ZSHSETUP_HOME/.zshrc" || return 1
    __eprint "$ZSHSETUP_HOME already exists, updating instead"
    __update_zshsetup
    return 0
  fi
  trap 'rm -rf "$ZSHSETUP_HOME"' EXIT INT TERM
  if ! git clone "$ZSHSETUP_REPO" "$ZSHSETUP_HOME"; then
    __eprint "Failed to clone $ZSHSETUP_REPO to $ZSHSETUP_HOME"
    return 1
  fi
  __assure_link "$HOME/.zshrc" "$ZSHSETUP_HOME/.zshrc" || return 1
  trap - EXIT INT TERM
  __eprint "zshsetup installed and linked"
  return 0
}

__update_zshsetup() {
  if [ ! -d "$ZSHSETUP_HOME" ]; then
    __eprint "$ZSHSETUP_HOME does not exist, installing instead"
    __install_zshsetup
    return "$?"
  fi
  pushd "$ZSHSETUP_HOME" || return 1
  git fetch || __eprint "Failed to fetch new data from $ZSHSETUP_REPO"
  # only stashes and reapplies when there are local changes
  git merge --autostash || __eprint "Failed to merge updates"
  popd || true

  packages=(zig make gawk jq micromamba go rustup uv uvc bun bat micro kv)
  for p in "${packages[@]}"; do
    "$ZSHSETUP_HOME/packages/$p.sh" upgrade
  done

  omz update
}

__uninstall_manual() {
  for p in "$@"; do
    "$ZSHSETUP_HOME/packages/$p.sh" uninstall || __eprint "Failed to uninstall $p"
  done
}

if [ "$1" = "install" ]; then
  __install_zshsetup
  exit "$?"
elif [ "$1" = "update" ]; then
  __update_zshsetup
  exit "$?"
fi

__init_zshsetup

# BEGIN CUSTOM
