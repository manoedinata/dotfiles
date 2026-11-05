#!/usr/bin/env bash
# Copy files that stow can't link into this repo.
# Each line of copy.txt is a path relative to /, stored at the same path here.

cd "$(dirname "$(readlink -f "$0")")" || exit 1

while IFS= read -r path || [ -n "$path" ]; do
    [ -z "$path" ] && continue
    mkdir -p "$(dirname "$path")"
    cp -v "/$path" "$path"
done < copy.txt
