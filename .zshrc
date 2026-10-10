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
  local link_file expected_target actual_target backup
  link_file="$1"
  expected_target="$2"
  if [ -L "$link_file" ]; then
    actual_target=$(readlink "$link_file") || return 1
    if [ "$actual_target" != "$expected_target" ]; then
      echo "$link_file points to $actual_target. Rewriting to $expected_target..." >&2
      ln -snf "$expected_target" "$link_file"
    fi
  elif [ -e "$link_file" ]; then
    backup="$link_file.pre-zshsetup"
    if [ -e "$backup" ] || [ -L "$backup" ]; then
      __eprint "$link_file exists, but backup $backup already exists"
      return 1
    fi
    echo "$link_file exists, moving to $backup..." >&2
    mv "$link_file" "$backup" || return 1
    ln -s "$expected_target" "$link_file"
  else
    ln -s "$expected_target" "$link_file"
  fi
}

__assure_dir() {
  local dir_to_check
  dir_to_check="$1"
  mkdir -p "$dir_to_check" || __eprint "$dir_to_check not found and not creatable"
}

# chooses the manager of a package from ZSHSETUP_CHOICE_<PACKAGE>, ZSHSETUP_CHOICE, or a menu, and
# sets REPLY to it and reply to the names of the package there; manual installs with pmg, brew and
# apt/apk with the names from the spec of the package
# shellcheck disable=SC2206,SC2296,SC2299
__choose_manager() {
  local package choice choice_var manager name
  local -a options
  local -A names
  package="$1"
  choice_var="ZSHSETUP_CHOICE_${${package:u}//-/_}"
  choice="${(P)choice_var:-${ZSHSETUP_CHOICE:-}}"
  options=()
  # manual needs no names from the spec, which would start pmg once more
  if [ "$choice" != manual ]; then
    while read -r manager name; do
      names[$manager]="$name"
    done < <(pmg external "$package" 2>/dev/null)
    if [[ "$OSTYPE" == darwin* ]]; then
      [ -n "${names[brew]}" ] && __available brew && options+=(brew)
    else
      [ -n "${names[apt]}" ] && __available apt-get && options+=(apt)
      [ -n "${names[apk]}" ] && __available apk && options+=(apk)
      [ -n "${names[dnf]}" ] && __available dnf && options+=(dnf)
      # yum of Rocky Linux 8 and later is dnf
      [ -n "${names[yum]}" ] && __available yum && ! __available dnf && options+=(yum)
    fi
  fi
  options+=(manual)

  echo "Install $package via:" >&2
  if [ -n "$choice" ]; then
    # an unavailable choice (e.g. apt on macOS) falls back to manual
    ((${options[(Ie)$choice]})) || choice="manual"
  elif ((${#options} == 1)); then
    # nothing to choose from
    choice="manual"
  elif { : </dev/tty; } 2>/dev/null; then
    # read instead of select, which goes through the line editor, where plugins like
    # zsh-syntax-highlighting break it during the shell start
    local answer i
    local -a numbered
    for ((i = 1; i <= ${#options}; i++)); do
      numbered+=("$i) ${options[i]}")
    done
    while [ -z "$choice" ]; do
      print -r -- "${(j:  :)numbered}" >/dev/tty
      printf 'choice: ' >/dev/tty
      read -r answer </dev/tty || break
      if [[ "$answer" =~ ^[0-9]+$ ]] && ((answer >= 1 && answer <= ${#options})); then
        choice="${options[answer]}"
      elif ((${options[(Ie)$answer]})); then
        choice="$answer"
      fi
    done
  fi
  if [ -z "$choice" ]; then
    __eprint "No install choice for $package, set ZSHSETUP_CHOICE or $choice_var"
    return 1
  fi
  echo "$choice" >&2
  REPLY="$choice"
  # a spec may list several packages, e.g. "curl ca-certificates"
  reply=(${=names[$choice]})
}

# installs a package with the manager __choose_manager chooses
__package_manager() {
  __choose_manager "$1" || return 1
  if [ "$REPLY" = manual ]; then
    pmg install "$1" || return 1
  else
    __system_install "$REPLY" "${reply[@]}" || return 1
  fi
}

# prints the last path matching a glob pattern, e.g. the dir of the newest version of a package
# shellcheck disable=SC2206,SC2296
__last_match() {
  setopt local_options null_glob
  local -a matches
  matches=(${~1})
  ((${#matches})) && echo "${matches[-1]}"
}

# checks whether pmg installed a package, for packages without a command, like glibc
__pmg_installed() {
  [ -n "$(__last_match "${PMG_HOME:-$XDG_DATA_HOME/pmg}/installed/$1@*.json")" ]
}

# checks whether a tool is missing and to be installed: ZSHSETUP_DISABLE_<PACKAGE> skips the
# install, but a package installed anyway (e.g. as a dependency) is used, and a failed install is
# skipped for a day
# shellcheck disable=SC2296,SC2299
__wants_install() {
  local package marker disable_var failed_at
  package="$1"
  marker="$ZSHSETUP_HOME/failed/$package"
  disable_var="ZSHSETUP_DISABLE_${${package:u}//-/_}"
  __available "$package" && return 1
  [ -n "${(P)disable_var}" ] && return 1
  __pmg_installed "$package" && return 1
  # the marker holds the time of the failure
  zmodload zsh/datetime
  if [ -f "$marker" ]; then
    failed_at="$(<"$marker")"
    case "$failed_at" in
      "" | *[!0-9]*) failed_at=0 ;;
    esac
    ((EPOCHSECONDS - failed_at < 86400)) && return 1
  fi
  return 0
}

# checks whether an install of a tool worked, and otherwise warns and skips it for a day
__record_install() {
  local package marker
  package="$1"
  marker="$ZSHSETUP_HOME/failed/$package"
  # rehash, as zsh would otherwise keep running a command it found before
  rehash
  if __available "$package" || __pmg_installed "$package"; then
    . "${PMG_HOME:-$XDG_DATA_HOME/pmg}/env.sh" 2>/dev/null
    rm -f "$marker"
    return 0
  fi
  zmodload zsh/datetime
  mkdir -p "${marker%/*}" && echo "$EPOCHSECONDS" >"$marker"
  __eprint "zshsetup: installing $package failed, skipping it for a day (retry with install_manual $package)"
}

# installs a missing tool, warns instead of aborting, see __wants_install
__require() {
  if ! __wants_install "$1"; then
    __available "$1" || __pmg_installed "$1"
    return
  fi
  __package_manager "$1"
  __record_install "$1"
}

# installs the missing tools of a list together, so that the __require of each finds it: all
# choices are asked first, then pmg installs the manual ones in one run, which checks their
# releases and downloads them in parallel and runs their install scripts as soon as their
# dependencies are installed, and each system package manager installs its packages in one call
# shellcheck disable=SC2086,SC2206,SC2296
__require_all() {
  local package manager
  local -a missing manual
  local -A system
  # a package listed twice, e.g. micromamba with ZSHSETUP_REQUIRE_MICROMAMBA, is installed once
  typeset -U missing
  for package in "$@"; do
    __wants_install "$package" && missing+=("$package")
  done
  ((${#missing})) || return 0
  for package in "${missing[@]}"; do
    # without a choice, the check below records the failure
    __choose_manager "$package" || continue
    if [ "$REPLY" = manual ]; then
      manual+=("$package")
    else
      system[$REPLY]+=" ${reply[*]}"
    fi
  done
  for manager in ${(k)system}; do
    __system_install "$manager" ${=system[$manager]}
  done
  # an error that stops all of pmg, e.g. a spec missing for one package, or one failing download
  # in pmg before v2.3.0, leaves the others to install one by one
  if ((${#manual})) && ! pmg install "${manual[@]}"; then
    rehash
    for package in "${manual[@]}"; do
      __available "$package" || __pmg_installed "$package" || pmg install "$package"
    done
  fi
  for package in "${missing[@]}"; do
    __record_install "$package"
  done
  return 0
}

# checks whether micromamba is wanted: conda-forge packages need glibc, see packages/musl/micromamba
__wants_micromamba() {
  [ -n "$ZSHSETUP_REQUIRE_MICROMAMBA" ] || { [ ! -e /lib/ld-musl-x86_64.so.1 ] && [ ! -e /lib/ld-musl-aarch64.so.1 ]; }
}

# sets reply to the non-default packages from ZSHSETUP_REQUIRE_<PACKAGE>, e.g. ZSHSETUP_REQUIRE_ZIG
# shellcheck disable=SC2296,SC2299
__extra_packages() {
  local required_var
  reply=()
  for required_var in ${(k)parameters[(I)ZSHSETUP_REQUIRE_*]}; do
    [ -n "${(P)required_var}" ] && reply+=("${${${required_var#ZSHSETUP_REQUIRE_}:l}//_/-}")
  done
  return 0
}

# sets reply to the packages that __init_zshsetup requires, in its order, for __require_all
__required_packages() {
  local -a extra
  __extra_packages
  extra=("${reply[@]}")
  reply=(ghostty-terminfo tzdata curl git uv uvc jq gawk)
  __wants_micromamba && reply+=(micromamba)
  reply+=("${extra[@]}" bat micro)
}

__source() {
  local env
  env=$("$@") || return 1
  eval "$env"
}

# sets reply to the existing <name> of each plugin in plugins/, e.g. bin or preinit.sh
__plugin_paths() {
  setopt localoptions nullglob
  local file
  reply=()
  for file in "$ZSHSETUP_HOME"/plugins/*/"$1"; do
    [ -e "$file" ] && reply+=("$file")
  done
  return 0
}

# pulls a git clone without asking for credentials, so it can also run in the background
__pull_quietly() {
  GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes" git -C "$1" pull -q --ff-only
}

# pulls the plugins that are git clones, e.g. of private repositories
__pull_plugins() {
  local git_dir plugin
  __plugin_paths .git
  for git_dir in "${reply[@]}"; do
    plugin="${git_dir%/.git}"
    __pull_quietly "$plugin" || __eprint "Failed to update the plugin ${plugin##*/}"
  done
  return 0
}

# pulls zshsetup and its plugins in the background once a day, so that later shells get their
# changes; the packages of pmg stay with update_zshsetup
__pull_daily() {
  local stamp last
  stamp="$XDG_STATE_HOME/zshsetup/pulled"
  zmodload zsh/datetime
  last="$(cat "$stamp" 2>/dev/null)"
  ((EPOCHSECONDS - ${last:-0} >= 86400)) || return 0
  __assure_dir "$XDG_STATE_HOME/zshsetup" || return 0
  echo "$EPOCHSECONDS" >"$stamp"
  # started from a subshell, so the job table of this shell never reports it as done
  ({ __pull_quietly "$ZSHSETUP_HOME" && __pull_plugins; } >/dev/null 2>&1 &)
  return 0
}

# sources <name>.sh of each plugin in plugins/, a failing plugin only prints an error
__source_plugins() {
  local file
  __plugin_paths "$1.sh"
  for file in "${reply[@]}"; do
    # shellcheck source=/dev/null
    . "$file" || __eprint "zshsetup: sourcing $file failed"
  done
  return 0
}

# links the files and directories in config/ of each plugin in plugins/ into XDG_CONFIG_HOME
__link_plugin_configs() {
  setopt localoptions nullglob
  local config_dir entry
  __plugin_paths config
  for config_dir in "${reply[@]}"; do
    for entry in "$config_dir"/*; do
      [ -e "$entry" ] || [ -L "$entry" ] || continue
      __assure_link "$XDG_CONFIG_HOME/${entry##*/}" "$entry" || return 1
    done
  done
  return 0
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

# checks whether a terminfo entry exists, in the letter (Linux) or hex (macOS) dirs that ncurses uses
# shellcheck disable=SC2153,SC2296
__has_terminfo() {
  local dir
  for dir in "$TERMINFO" "$HOME/.terminfo" ${(s.:.)TERMINFO_DIRS} /etc/terminfo /lib/terminfo \
    /usr/share/terminfo /usr/lib/terminfo; do
    [ -n "$dir" ] && { [ -e "$dir/${1:0:1}/$1" ] || [ -e "$dir/$(printf %x "'${1:0:1}")/$1" ]; } && return 0
  done
  return 1
}

# loads the terminfo entry of a terminal type that zsh did not find at its start, like that of
# ghostty-terminfo through the TERMINFO_DIRS of pmg; falls back to xterm-256color for one without
# an entry, and for plain xterm, as docker run -t sets it, which every current terminal exceeds;
# so that the line editor and colors work
# shellcheck disable=SC2154
__fallback_term() {
  [ -n "$TERM" ] || return 0
  zmodload zsh/terminfo 2>/dev/null || return 0
  if [ -z "${terminfo[cols]}" ] && __has_terminfo "$TERM"; then
    # assigning TERM makes zsh read the entry again
    export TERM="$TERM"
  elif [ -z "${terminfo[cols]}" ] || { [ "$TERM" = xterm ] && __has_terminfo xterm-256color; }; then
    export TERM=xterm-256color
  fi
}

# inits the environment before running any failable commands
__init_zshsetup_env() {
  export ZSHSETUP_REPO="${ZSHSETUP_REPO:-https://github.com/audivir/zshsetup}"
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
  HISTSIZE=200000
  # shellcheck disable=SC2034
  SAVEHIST=100000

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
  PATH="$ZSHSETUP_HOME/bin:$XDG_BIN_HOME:$HOME/bin:$PATH"
  # the bin directories of the plugins in plugins/
  __plugin_paths bin
  path=("${reply[@]}" "${path[@]}")

  # SETUP OTHER ENVIRONMENT
  export GNUPGHOME="$XDG_DATA_HOME/gnupg"
  export MPLCONFIGDIR="$XDG_CONFIG_HOME/matplotlib"
  export PYTHON_HISTORY="$XDG_DATA_HOME/python/python_history"
  # without system certificates, git and micromamba use the ones bundled with git-static
  local git_certs
  git_certs="$(__last_match "${PMG_HOME:-$XDG_DATA_HOME/pmg}/packages/git@*/share/git-core/certs")"
  if [ ! -e /etc/ssl/cert.pem ] && [ -z "$(ls -A /etc/ssl/certs 2>/dev/null)" ] && [ -n "$git_certs" ]; then
    export GIT_SSL_CAPATH="$git_certs"
    export MAMBA_SSL_VERIFY="$GIT_SSL_CAPATH/cacert.pem"
  fi
}

# runs the setup functions
__init_zshsetup() {
  # __available, __system_install, and the other functions shared with install.sh and packages/pmg
  # shellcheck disable=SC2016
  ZSHSETUP_INSTALL_LIB=1 emulate sh -c '. "$ZSHSETUP_HOME/install.sh"' || return 1
  __init_cache || return 1

  local dir
  # site-functions for the completion of pmg, which pmg only creates when it installs a package
  for dir in "$LOCAL_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_BIN_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME" \
    "$ZSHSETUP_HOME/bin" "$XDG_DATA_HOME/zsh/site-functions"; do
    __assure_dir "$dir" || return 1
  done

  __link_plugin_configs || return 1

  # BEGIN PMG
  # pmg installs the packages, see packages/pmg; completions call it by name, so it is linked into PATH
  __assure_link "$ZSHSETUP_HOME/bin/pmg" "$ZSHSETUP_HOME/packages/pmg" || return 1
  # the completions pmg installs, and that of pmg itself, before oh-my-zsh runs compinit
  fpath=("$XDG_DATA_HOME/zsh/site-functions" "${fpath[@]}")
  # pmg writes its completion whenever it changes something, a system without changes gets it here
  [ -f "$XDG_DATA_HOME/zsh/site-functions/_pmg" ] || pmg completion >"$XDG_DATA_HOME/zsh/site-functions/_pmg"
  # mandoc (Alpine) does not find man pages next to the bin dirs in PATH, the trailing colon keeps the defaults
  export MANPATH="$XDG_DATA_HOME/man:"
  # the environment and PATH entries of packages like go and rustup
  [ -f "${PMG_HOME:-$XDG_DATA_HOME/pmg}/env.sh" ] && . "${PMG_HOME:-$XDG_DATA_HOME/pmg}/env.sh"
  # END PMG

  # BEGIN HOMEBREW
  # before oh-my-zsh, whose compinit only sees the site-functions of Homebrew already in fpath
  if [ -f "/opt/homebrew/bin/brew" ]; then
    __source /opt/homebrew/bin/brew shellenv || return 1
    alias homebrewupdate='brew update; brew upgrade --formulae --yes && brew cu --yes && cd /opt/homebrew && git stash pop &>/dev/null || true && cd -'
  fi
  # END HOMEBREW

  # BEGIN GO
  # for go from other package managers, pmg sets GOROOT, GOPATH, and PATH in its env file
  export GOPATH="${GOPATH:-$XDG_DATA_HOME/go}"
  PATH="$GOPATH/bin:$PATH"
  # END GO

  # BEGIN RUST
  # for rustup from other package managers, pmg sets RUSTUP_HOME, CARGO_HOME, and PATH in its env file
  export RUSTUP_HOME="${RUSTUP_HOME:-$XDG_DATA_HOME/rustup}"
  export CARGO_HOME="${CARGO_HOME:-$XDG_DATA_HOME/cargo}"
  PATH="$CARGO_HOME/bin:/opt/homebrew/opt/rustup/bin:$PATH"
  # END RUST

  # BEGIN JAVASCRIPT
  export BUN_INSTALL="$XDG_DATA_HOME/bun"
  export BUN_INSTALL_CACHE_DIR="$XDG_CACHE_HOME/bun/install"
  export BUN_RUNTIME_TRANSPILER_CACHE_PATH="$XDG_CACHE_HOME/bun/runtime"
  export BUN_CONFIG_DIR="$XDG_CONFIG_HOME/bun"
  PATH="$BUN_INSTALL/bin:$PATH"
  # END JAVASCRIPT

  # BEGIN MISSING PACKAGES
  # all at once, once PATH has the dirs of Homebrew and the toolchains, where a tool may already
  # be; the __require of each package below then finds it
  __required_packages
  __require_all "${reply[@]}"
  # END MISSING PACKAGES

  # BEGIN TERMINFO AND TZDATA
  # the terminfo entry of Ghostty, whose TERM the hosts it connects to lack, in TERMINFO_DIRS
  __require ghostty-terminfo
  __fallback_term
  # the zone files for a TZ, also on hosts without tzdata like most containers, in TZDIR
  __require tzdata
  # END TERMINFO AND TZDATA

  # BEGIN CURL AND GIT
  # oh-my-zsh installs with both
  __require curl
  __require git
  # END CURL AND GIT

  # BEGIN OH-MY-ZSH
  if [ ! -d "$ZSH" ]; then
    "$ZSHSETUP_HOME/packages/oh-my-zsh.sh" || return 1
  fi
  __assure_dir "$ZSH_CACHE_DIR" || return 1
  # shellcheck disable=SC2034
  . "$ZSH/oh-my-zsh.sh" || return 1
  # the exit code of the last command after the prompt of the theme, if it is not 0
  PROMPT+="%(?..%B%F{red}%1{⟨%}%?%1{⟩%}%f%b )"
  # END OH-MY-ZSH

  # BEGIN PYTHON
  __require uv
  # a uv in PATH replaces the one packages/pmg bootstrapped for itself
  __available uv && rm -rf "$XDG_CACHE_HOME/zshsetup/uv"
  if __require uvc; then
    __source command uvc shell zsh
  fi
  # END PYTHON

  # BEGIN JQ
  __require jq
  # END JQ

  # BEGIN GAWK
  __require gawk
  # END GAWK
  #
  # BEGIN MICROMAMBA
  if __wants_micromamba && __require micromamba; then
    alias conda='micromamba'
    export MAMBA_ROOT_PREFIX="$XDG_DATA_HOME/micromamba"
    local real_exe
    real_exe="$(__last_match "${PMG_HOME:-$XDG_DATA_HOME/pmg}/packages/micromamba@*/micromamba")"
    if [ -n "$real_exe" ]; then
      # on musl, the hook calls the real binary by path, but the wrapper also patches new programs for glibc
      local hook
      hook="$(command micromamba shell hook --shell zsh)" && eval "${hook//$real_exe/$XDG_BIN_HOME/micromamba}"
    else
      __source command micromamba shell hook --shell zsh
    fi
  fi
  # END MICROMAMBA

  # BEGIN RUST TOOLCHAIN
  # the cc of pmg is zig, which links musl programs itself
  if [[ "$(whence -p cc)" == "$XDG_BIN_HOME/cc" ]] && [ -e "/lib/ld-musl-$(uname -m).so.1" ]; then
    export "CARGO_TARGET_$(uname -m | tr '[:lower:]' '[:upper:]')_UNKNOWN_LINUX_MUSL_RUSTFLAGS=-C link-self-contained=no"
  fi
  # musl toolchains need libgcc_s
  local musl_libs
  musl_libs="$(__last_match "${PMG_HOME:-$XDG_DATA_HOME/pmg}/packages/musl-libs@*/usr/lib")"
  if [ -n "$musl_libs" ] && [ ! -e /usr/lib/libgcc_s.so.1 ]; then
    export LD_LIBRARY_PATH="$musl_libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  fi
  # END RUST TOOLCHAIN

  # BEGIN REQUIRED PACKAGES
  local package
  __extra_packages
  for package in "${reply[@]}"; do
    __require "$package"
  done
  # END REQUIRED PACKAGES

  # BEGIN EXTRA TOOLS
  __require bat
  __require micro
  # END EXTRA TOOLS

  # the metadata of apt, dnf, and yum that installs downloaded onto a system without any
  __clean_metadata

  # BEGIN ALIASES
  alias b="bat --paging=never --style=plain --tabs=4"
  alias sb="sudo bat --paging=never --style=plain --tabs=4"
  # END ALIASES

  # zshsetup's own links (e.g. pmg) come first, then the bin directories of the plugins, then
  # the commands of pmg in $XDG_BIN_HOME before those of Homebrew and the toolchains
  # typeset -U only deduplicates array assignments, not PATH="...:$PATH"
  __plugin_paths bin
  path=("$ZSHSETUP_HOME/bin" "${reply[@]}" "$XDG_BIN_HOME" "${path[@]}")
  export PATH

  # BEGIN THEME VIEWER
  . "$ZSHSETUP_HOME/theme_viewer.sh" || return 1
  # END THEME VIEWER

  # BEGIN CUSTOM FUNCTIONS
  . "$ZSHSETUP_HOME/custom_functions.sh" || return 1
  # END CUSTOM FUNCTIONS
}

# keeps the ZSHSETUP_* settings and the toolchain of pmg given at installation for later shells
# shellcheck disable=SC2296
__save_settings() {
  local preinit var
  preinit="$ZSHSETUP_HOME/preinit.zsh"
  if [ ! -f "$preinit" ]; then
    printf '#!/usr/bin/env zsh\n# shellcheck shell=bash\n' >"$preinit" || return 1
    chmod +x "$preinit" || return 1
  fi
  for var in ZSHSETUP_CHOICE ${(k)parameters[(I)ZSHSETUP_CHOICE_*]} ${(k)parameters[(I)ZSHSETUP_REQUIRE_*]} \
    ${(k)parameters[(I)ZSHSETUP_DISABLE_*]} ZSHSETUP_IGNORESCRATCH PMG_RUST_TOOLCHAIN; do
    if [ -n "${(P)var}" ]; then
      echo "export $var=${(q)${(P)var}}" >>"$preinit" || return 1
    fi
  done
}

# installs zshsetup from github
__install_zshsetup() {
  if [ -d "$ZSHSETUP_HOME" ]; then
    __assure_link "$HOME/.zshrc" "$ZSHSETUP_HOME/.zshrc" || return 1
    __eprint "$ZSHSETUP_HOME already exists, updating instead"
    update_zshsetup
    return 0
  fi
  trap 'rm -rf "$ZSHSETUP_HOME"' EXIT INT TERM
  if ! git clone "$ZSHSETUP_REPO" "$ZSHSETUP_HOME"; then
    __eprint "Failed to clone $ZSHSETUP_REPO to $ZSHSETUP_HOME"
    return 1
  fi
  if ! __assure_link "$HOME/.zshrc" "$ZSHSETUP_HOME/.zshrc"; then
    __eprint "Failed to link .zshrc"
    return 1
  fi
  if ! __save_settings; then
    __eprint "Failed to save settings to preinit.zsh"
    return 1
  fi
  if ! __init_zshsetup; then
    __eprint "Failed to initialize zsh"
    return 1
  fi
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
  (
    cd "$ZSHSETUP_HOME" || exit 1
    git fetch || __eprint "Failed to fetch new data from $ZSHSETUP_REPO"
    git merge || __eprint "Failed to merge updates"
  )
  __pull_plugins
  # the pulled .zshrc upgrades, as the functions of this shell may be from before the pull
  zsh "$ZSHSETUP_HOME/.zshrc" upgrade
}

# upgrades the packages of pmg and oh-my-zsh, after update_zshsetup pulled
__upgrade_zshsetup() {
  rm -rf "$ZSHSETUP_HOME/failed"

  # pmg itself to its latest tag, see packages/pmg
  pmg self-upgrade || __eprint "Failed to upgrade pmg"
  pmg update || __eprint "Failed to update the specs of pmg"
  pmg upgrade || __eprint "Failed to upgrade the packages of pmg"

  # omz only exists once oh-my-zsh is sourced, so run its upgrade script directly
  local omz_dir omz_cache
  omz_dir="${ZSH:-$ZSHSETUP_HOME/oh-my-zsh}"
  [ -f "$omz_dir/tools/upgrade.sh" ] || return 0
  ZSH="$omz_dir" zsh -f "$omz_dir/tools/upgrade.sh" -v default || __eprint "Failed to update oh-my-zsh"
  # keeps oh-my-zsh from asking to update again, like omz update does
  zmodload zsh/datetime
  omz_cache="${ZSH_CACHE_DIR:-$omz_dir/cache}"
  mkdir -p "$omz_cache" && echo "LAST_EPOCH=$((EPOCHSECONDS / 60 / 60 / 24))" >|"$omz_cache/.zsh-update"
}

# installs packages with pmg, see pmg --help for all its commands
install_manual() {
  local p
  for p in "$@"; do
    rm -f "$ZSHSETUP_HOME/failed/$p"
  done
  pmg install "$@" && rehash
}

# uninstalls packages with pmg
uninstall_manual() {
  pmg uninstall "$@" && rehash
}

# edits the local pre- or post-init file, or that of a plugin, with $EDITOR or micro
edit_zshsetup() {
  local name target
  case "${1:-pre}" in
    pre)
      name=preinit
      ;;
    post)
      name=postinit
      ;;
    *)
      __eprint "Usage: edit_zshsetup <pre|post> [plugin]"
      return 1
      ;;
  esac
  if [ -n "$2" ]; then
    if [ ! -d "$ZSHSETUP_HOME/plugins/$2" ]; then
      __eprint "No plugin $2 in $ZSHSETUP_HOME/plugins"
      return 1
    fi
    target="$ZSHSETUP_HOME/plugins/$2/$name.sh"
  else
    target="$ZSHSETUP_HOME/$name.zsh"
  fi
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
    upgrade)
      __upgrade_zshsetup
      ;;
    *)
      __eprint "Usage: run_zshsetup <install|update|upgrade>"
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
# plugins first, so that the local preinit.zsh can override them
__source_plugins preinit
if [ ! -f "$ZSHSETUP_HOME/preinit.zsh" ]; then
  printf '#!/usr/bin/env zsh\n# shellcheck shell=bash\n' >"$ZSHSETUP_HOME/preinit.zsh" || return 1
  chmod +x "$ZSHSETUP_HOME/preinit.zsh" || return 1
fi
. "$ZSHSETUP_HOME/preinit.zsh" || return 1

# INITIALIZE DIRECTORIES/OMZ/PACKAGES
__init_zshsetup || return 1

# SOURCE POST-INIT
__source_plugins postinit
if [ ! -f "$ZSHSETUP_HOME/postinit.zsh" ]; then
  printf '#!/usr/bin/env zsh\n# shellcheck shell=bash\n' >"$ZSHSETUP_HOME/postinit.zsh" || return 1
  chmod +x "$ZSHSETUP_HOME/postinit.zsh" || return 1
fi
. "$ZSHSETUP_HOME/postinit.zsh" || return 1

# PULL ZSHSETUP AND ITS PLUGINS ONCE A DAY
__pull_daily

# CLEANUP
unfunction __assure_link __assure_dir __package_manager __last_match __pmg_installed __require __source __source_plugins
unfunction __pull_daily
unfunction __has_terminfo __fallback_term __init_cache __init_zshsetup_env __init_zshsetup __install_zshsetup __save_settings __upgrade_zshsetup
unfunction __which __available __download __uv_libc __bootstrap_uv __has_metadata __system_install __clean_metadata
unfunction __install_chosen __install_main __link_plugin_configs
unset __PMG_TAG __METADATA_CREATED
