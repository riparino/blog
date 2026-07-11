#!/usr/bin/env bash
# Create a new post and open it in $EDITOR.
# Usage: ./new-post.sh "My Post Title"
set -eu

if [ "$#" -lt 1 ] || [ -z "$1" ]; then
  echo "usage: $0 \"Post Title\"" >&2
  exit 1
fi

cd "$(dirname "$0")"
title="$*"

slug=$(printf '%s' "$title" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -e "s/'//g" -e 's/[^a-z0-9]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//')
[ -n "$slug" ] || slug="post"

file="_posts/$(date +%Y-%m-%d)-${slug}.md"
if [ -e "$file" ]; then
  echo "error: $file already exists" >&2
  exit 1
fi

# Escape backslashes and double quotes so the title is a valid YAML string.
yaml_title=$(printf '%s' "$title" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')

mkdir -p _posts
cat > "$file" <<EOF
---
title: "$yaml_title"
date: $(date '+%Y-%m-%d %H:%M:%S %z')
---

EOF

echo "created $file"
exec "${EDITOR:-vi}" "$file"
