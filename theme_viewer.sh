#!/usr/bin/env bash

update_theme() {
  # locally: detect dark mode
  # over SSH: keep the forwarded LC_THEME, falling back to time of day if unset
  if [ -z "$SSH_CONNECTION" ]; then
    # macOS: check dark mode
    if [[ "$OSTYPE" == darwin* ]]; then
      defaults read -g AppleInterfaceStyle >/dev/null 2>&1
    else
      # Linux: not yet implemented, falls back to time of day
      # detect local night time (19-7 => dark)
      local hour
      hour=$(date +%H)
      hour=${hour#0}
      [ "${hour:-0}" -lt 7 ] || [ "${hour:-0}" -ge 19 ]
    fi
    # shellcheck disable=SC2181
    [ $? -eq 0 ] && LC_THEME="dark" || LC_THEME="light"
  elif [ -z "$LC_THEME" ]; then
    local hour
    hour=$(date +%H)
    hour=${hour#0}
    if [ "${hour:-0}" -lt 7 ] || [ "${hour:-0}" -ge 19 ]; then
      LC_THEME="dark"
    else
      LC_THEME="light"
    fi
  fi
  export LC_THEME
}

__init_theme_viewer() {
  # format: app|light_theme|dark_theme|command_with_placeholder
  # use [] as placeholder
  THEMEABLE_APPS="${THEMEABLE_APPS:-
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
$THEMEABLE_APPS
EOF

  update_theme

  ssh() {
    update_theme
    command ssh -o SendEnv=LC_THEME "$@"
  }
}

__init_theme_viewer
unset -f __init_theme_viewer
