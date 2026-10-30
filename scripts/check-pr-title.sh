#!/usr/bin/env bash
# Checks that a PR title follows the commit convention in CONTRIBUTING.md.
#
# Usage: check-pr-title.sh <title> <pr-number>
set -euo pipefail

title="$1"
number="$2"

types="feat|fix|docs|test|refactor|perf|build|ci|chore"
pattern="^($types)(\([a-z0-9-]+\))?!?: [^ ]"

if ! [[ "$title" =~ $pattern ]]; then
  echo "PR title must look like '<type>(<optional scope>)!?: <summary>'," >&2
  echo "with <type> one of: ${types//|/, }." >&2
  echo "Got: $title" >&2
  exit 1
fi

# Squash merge makes "<title> (#N)" the subject on main; that's what must fit.
# A UTF-8 locale makes ${#…} count characters instead of bytes.
export LC_ALL=C.UTF-8
subject="$title (#$number)"
max=72
if [[ ${#subject} -gt $max ]]; then
  echo "PR title is too long: with \" (#$number)\" appended by the squash merge," >&2
  echo "the subject on main has ${#subject} chars, max $max." >&2
  echo "Shorten the title to $((max - ${#subject} + ${#title})) chars or fewer." >&2
  exit 1
fi
