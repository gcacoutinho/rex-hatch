#!/bin/zsh
# Switch the app to the selected session.
set -eu
rex do session.select session_id="$1"
