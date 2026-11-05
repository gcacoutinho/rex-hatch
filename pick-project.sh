#!/bin/zsh
# Run in a Rex terminal so fzf has a TTY. zsh reads FZF_DEFAULT_OPTS from .zshenv.
# Preferred folder picker: fzf or finder. Can also be set in the environment.
PROJECT_PICKER=${PROJECT_PICKER:-fzf}

set -eu
set -o pipefail

case "$PROJECT_PICKER" in
    fzf)
        command -v fzf >/dev/null 2>&1 || PROJECT_PICKER=finder
        ;;
    finder) ;;
    *) print -u2 "Unknown PROJECT_PICKER: $PROJECT_PICKER (use fzf or finder)"; exit 1 ;;
esac

if [[ "$PROJECT_PICKER" == finder ]]; then
    # Native macOS folder dialog; cancellation returns an empty path.
    dir=$(osascript <<'APPLESCRIPT'
try
    return POSIX path of (choose folder with prompt "Hatch project in:" default location (path to home folder))
on error messageText number errorNumber
    if errorNumber is -128 then return ""
    error messageText number errorNumber
end try
APPLESCRIPT
    )
    [[ -n "$dir" ]] || exit 0
    [[ "$dir" == / ]] || dir=${dir%/}
    label="$dir"
    [[ "$dir" == "$HOME"/* ]] && label="~${dir#$HOME}"
else

# Optional arguments replace the default project roots.
roots=()
if (( $# )); then
    roots=("$@")
else
    roots=("$HOME")
fi
if (( ${#roots} == 0 )); then
    print -u2 'No project roots found. Pass project folders to pick-project.sh.'
    exit 1
fi

# Finish discovery first so its failures cannot be mistaken for cancellation.
projects=$(find "${roots[@]}" -mindepth 1 -maxdepth 1 -type d -not -name '.*' |
    sed "s|^$HOME|~|" | sort) || exit $?
if label=$(printf '%s\n' "$projects" | fzf --prompt 'Project: '); then
    :
else
    picker_status=$?
    case "$picker_status" in
        1|130) exit 0 ;; # No match or Escape/Control-C.
        *) exit "$picker_status" ;;
    esac
fi
[[ -n "$label" ]] || exit 0
dir="$HOME${label#\~}"
# Explicit roots outside HOME remain absolute paths.
[[ "$label" == '~/'* ]] || dir="$label"
fi

session=$(rex ls --json | jq -r --arg label "$label" '[.sessions[] | select(.label == $label)][0].session_id // empty')
if [[ -z "$session" ]]; then
    # Hatch, rather than rex new, preserves the project's .rex-egg.lua layout.
    rex do "${0:A:h}/hatch.lua" dir="$dir" name="$label"
else
    "${0:A:h}/select-session.sh" "$session" "$label"
fi
