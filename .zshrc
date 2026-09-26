#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
# expects $USER and $HOME to be set

# drops duplicate PATH and FPATH entries, when .zshrc is sourced again
# shellcheck disable=SC2034
typeset -U path fpath

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
  # if /home is mounted, looks for /scratch to use as cache directory
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
  fi
}

# inits the environment before running any failable commands
__init_zshsetup_env() {
  export ZSHSETUP_REPO="https://github.com/audivir/zshsetup"
  export ZSHSETUP_HOME="$HOME/.config/zshsetup"

  # SETUP XDG SPEC
  export LOCAL_HOME="$HOME/.local"
  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_DATA_HOME="$LOCAL_HOME/share"
  export XDG_BIN_HOME="$LOCAL_HOME/bin"
  export XDG_CACHE_HOME="$HOME/.cache"
  export XDG_STATE_HOME="$LOCAL_HOME/state"

  # systemd / macOS runtime dir
  if [ ! -d "$XDG_RUNTIME_DIR" ]; then
    if [ -d "/run/user/$UID" ]; then
      export XDG_RUNTIME_DIR="/run/user/$UID"
    elif [[ "$OSTYPE" == darwin* ]] && [ -n "$TMPDIR" ]; then
      export XDG_RUNTIME_DIR="${TMPDIR%/}"
    fi
  fi

  # SETUP HISTORY
  HISTFILE="$ZSHSETUP_HOME/zsh_history"
  HISTSIZE=50000
  # shellcheck disable=SC2034
  SAVEHIST=1000

  # SETUP OH-MY-ZSH
  export ZSH="$ZSHSETUP_HOME/oh-my-zsh"
  # shellcheck disable=SC2034
  plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
  ZSH_CACHE_DIR="$XDG_CACHE_HOME/zsh"
  # shellcheck disable=SC2034
  ZSH_COMPDUMP="$ZSH_CACHE_DIR/zcompdump-${HOST%%.*}-${ZSH_VERSION}"
  # shellcheck disable=SC2034
  ZSH_CUSTOM="$ZSH/custom"
  # shellcheck disable=SC2034
  ZSH_THEME="robbyrussell"

  # SETUP PATH
  PATH="$XDG_BIN_HOME:$HOME/bin:$PATH"

  # SETUP OTHER ENVIRONMENT
  export GNUPGHOME="$XDG_DATA_HOME/gnupg"
  export MPLCONFIGDIR="$XDG_CONFIG_HOME/matplotlib"
  export PYTHON_HISTORY="$XDG_DATA_HOME/python/python_history"
}

# runs the setup functions
__init_zshsetup() {
  __init_cache || return 1

  local dir
  for dir in "$LOCAL_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_BIN_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"; do
    __assure_dir "$dir" || return 1
  done

  # BEGIN OH-MY-ZSH
  if [ ! -d "$ZSH" ]; then
    "$ZSHSETUP_HOME/packages/oh-my-zsh.sh" || return 1
  fi
  __assure_dir "$ZSH_CACHE_DIR" || return 1
  # shellcheck disable=SC2034
  . "$ZSH/oh-my-zsh.sh" || return 1
  # END OH-MY-ZSH

  # BEGIN HOMEBREW
  if [ -f "/opt/homebrew/bin/brew" ]; then
    __source /opt/homebrew/bin/brew shellenv || return 1
    alias homebrewupdate='brew update; brew upgrade --formulae --yes && brew cu --yes && cd /opt/homebrew && git stash pop &>/dev/null || true && cd -'
  fi
  # END HOMEBREW

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

  # typeset -U only deduplicates array assignments, not PATH="...:$PATH"
  path=("${path[@]}")
  export PATH

  # BEGIN THEME VIEWER
  . "$ZSHSETUP_HOME/theme_viewer.sh" || return 1
  # END THEME VIEWER

  # BEGIN CUSTOM FUNCTIONS
  . "$ZSHSETUP_HOME/custom_functions.sh" || return 1
  # END CUSTOM FUNCTIONS
}

# installs zshsetup from github
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

# updates zshsetup itself and all packages
update_zshsetup() {
  if [ ! -d "$ZSHSETUP_HOME" ]; then
    __eprint "$ZSHSETUP_HOME does not exist, installing instead"
    __install_zshsetup
    return "$?"
  fi
  pushd "$ZSHSETUP_HOME" || return 1
  git fetch || __eprint "Failed to fetch new data from $ZSHSETUP_REPO"
  git merge || __eprint "Failed to merge updates"
  popd || true

  local packages
  packages=(zig make gawk jq micromamba go rustup uv uvc bun bat micro kv)
  for p in "${packages[@]}"; do
    "$ZSHSETUP_HOME/packages/$p.sh" upgrade
  done

  # omz only exists once oh-my-zsh is sourced, so run its upgrade script directly
  local omz_dir
  omz_dir="${ZSH:-$ZSHSETUP_HOME/oh-my-zsh}"
  ZSH="$omz_dir" zsh -f "$omz_dir/tools/upgrade.sh" -v default || __eprint "Failed to update oh-my-zsh"
  # keeps oh-my-zsh from asking to update again, like omz update does
  zmodload zsh/datetime
  echo "LAST_EPOCH=$((EPOCHSECONDS / 60 / 60 / 24))" >|"${ZSH_CACHE_DIR:-$omz_dir/cache}/.zsh-update"
}

# uninstalls a single package
uninstall_manual() {
  for p in "$@"; do
    "$ZSHSETUP_HOME/packages/$p.sh" uninstall || __eprint "Failed to uninstall $p"
  done
}

# edits pre- or post-init files with $EDITOR or micro
edit_zshsetup() {
  local target
  case "${1:-pre}" in
    pre)
      target="$ZSHSETUP_HOME/preinit.zsh"
      ;;
    post)
      target="$ZSHSETUP_HOME/postinit.zsh"
      ;;
    *)
      __eprint "Usage: edit_zshsetup <pre|post>"
      return 1
      ;;
  esac
  if [ ! -f "$target" ]; then
    printf '#!/usr/bin/env zsh\n# shellcheck shell=bash\n' >"$target" || return 1
    chmod +x "$target" || return 1
  fi
  ${=EDITOR:-micro} "$target"
}

# runs cli commands or displays usage
run_zshsetup() {
  case "$1" in
    install)
      __install_zshsetup
      ;;
    update)
      update_zshsetup
      ;;
    *)
      __eprint "Usage: run_zshsetup <install|update>"
      return 1
      ;;
  esac
}

# INITIALIZE ENVIRONMENT
__init_zshsetup_env

# CLI
if [ "$#" -gt 0 ]; then
  run_zshsetup "$@"
  exit "$?"
fi

# SOURCE PRE-INIT
if [ ! -f "$ZSHSETUP_HOME/preinit.zsh" ]; then
  printf '#!/usr/bin/env zsh\n# shellcheck shell=bash\n' >"$ZSHSETUP_HOME/preinit.zsh" || return 1
  chmod +x "$ZSHSETUP_HOME/preinit.zsh" || return 1
fi
. "$ZSHSETUP_HOME/preinit.zsh" || return 1

# INITIALIZE DIRECTORIES/OMZ/PACKAGES
__init_zshsetup || return 1

# CLEANUP
unfunction __assure_link __assure_dir __package_manager __source __available
unfunction __init_cache __init_zshsetup_env __init_zshsetup __install_zshsetup

# SOURCE POST-INIT
if [ ! -f "$ZSHSETUP_HOME/postinit.zsh" ]; then
  printf '#!/usr/bin/env zsh\n# shellcheck shell=bash\n' >"$ZSHSETUP_HOME/postinit.zsh" || return 1
  chmod +x "$ZSHSETUP_HOME/postinit.zsh" || return 1
fi
. "$ZSHSETUP_HOME/postinit.zsh" || return 1
