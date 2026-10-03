#!/usr/bin/env zsh
# shellcheck shell=bash

update_theme() {
  # an LC_THEME not set by update_theme wins (e.g. forwarded over SSH or exported by hand).
  # unsetting LC_THEME returns to the detected theme.
  [ -n "$LC_THEME" ] && [ "$LC_THEME" != "$ZSHSETUP_DETECTED_THEME" ] && return 0
  if [ -z "$SSH_CONNECTION" ] && [[ "$OSTYPE" == darwin* ]]; then
    # macOS: check dark mode
    defaults read -g AppleInterfaceStyle >/dev/null 2>&1
  else
    # elsewhere: night time (19-7 => dark). a UTC system time zone, the default of most
    # containers, is replaced by the time zone of the IP address, which is cached for a day.
    local hour tz="" cached_at=0 cache="${XDG_CACHE_HOME:-$HOME/.cache}/zshsetup/timezone"
    if [ "$(date +%Z 2>/dev/null)" = "UTC" ]; then
      zmodload zsh/datetime
      [ -f "$cache" ] && read -r cached_at tz <"$cache"
      case "$cached_at" in
        "" | *[!0-9]*) cached_at=0 ;;
      esac
      if ((EPOCHSECONDS - cached_at >= 86400)) && command -v curl >/dev/null 2>&1; then
        tz=$(curl -fsSL --connect-timeout 2 --max-time 3 https://ipinfo.io/timezone 2>/dev/null ||
          curl -fsSL --connect-timeout 2 --max-time 3 "http://ip-api.com/line?fields=timezone" 2>/dev/null)
        case "$tz" in
          "" | *[!A-Za-z0-9_+/-]*) tz="" ;;
        esac
        # a failed lookup is cached as well, so it does not delay every shell.
        mkdir -p "${cache%/*}" && echo "$EPOCHSECONDS $tz" >|"$cache"
      fi
    fi
    # TZ is only set for this date call.
    hour=$(
      [ -n "$tz" ] && export TZ="$tz"
      date +%H
    )
    hour=${hour#0}
    [ "${hour:-0}" -lt 7 ] || [ "${hour:-0}" -ge 19 ]
  fi
  # shellcheck disable=SC2181
  [ $? -eq 0 ] && LC_THEME="dark" || LC_THEME="light"
  export LC_THEME ZSHSETUP_DETECTED_THEME="$LC_THEME"
}

__init_theme_viewer() {
  # format: app|light_theme|dark_theme|command_with_placeholder
  # use [] as placeholder
  local apps="${THEMEABLE_APPS:-
micro|sunny-day|one-dark|micro --colorscheme
bat|Monokai Extended Light|Monokai Extended|bat --theme
kv|light|dark|kv --theme
}"

  local app light dark template
  while IFS='|' read -r app light dark template; do
    [ -z "$app" ] && continue

    # skip if app is not installed
    if ! command -v "$app" >/dev/null; then
      echo "$app not found, cannot create themed functions" >&2
      continue
    fi

    eval "\
$app() {
  local theme
  update_theme
  if [[ \"\$LC_THEME\" == 'light' ]]; then
    theme=\"$light\"
  else
    theme=\"$dark\"
  fi
  command $template \"\$theme\" \"\$@\"
}
s$app() {
  local theme
  update_theme
  if [[ \"\$LC_THEME\" == 'light' ]]; then
    theme=\"$light\"
  else
    theme=\"$dark\"
  fi
  sudo $template \"\$theme\" \"\$@\"
}
  "
  done <<EOF
$apps
EOF

  update_theme

  ssh() {
    update_theme
    command ssh -o SendEnv=LC_THEME "$@"
  }
}

__init_theme_viewer
unfunction __init_theme_viewer
