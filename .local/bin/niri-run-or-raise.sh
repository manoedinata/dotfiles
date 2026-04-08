#!/usr/bin/env bash

# The first argument is the Niri app_id we are looking for
APP_ID="$1"
shift

# Find the Niri window ID matching the app_id
WIN_ID=$(niri msg --json windows | jq -r ".[] | select(.app_id == \"$APP_ID\") | .id" | head -n 1)

if [ -n "$WIN_ID" ] && [ "$WIN_ID" != "null" ]; then
    # App is already running. 
    # Get the index of the currently focused workspace
    CUR_WS=$(niri msg --json workspaces | jq -r '.[] | select(.is_focused == true) | .idx')
    
    # Move the existing window to the current workspace
    niri msg action move-window-to-workspace --window-id "$WIN_ID" "$CUR_WS"
    
    # Focus the window so you can interact with it immediately
    niri msg action focus-window --id "$WIN_ID"
else
    # App is not running, so we spawn it using the remaining arguments
    exec "$@"
fi

