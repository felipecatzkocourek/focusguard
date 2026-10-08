#!/usr/bin/env bash
# Runs the test suite.
#
# With full Xcode installed, plain `swift test` works. With only the Command Line Tools,
# the Swift Testing framework ships in a non-default location, so we point the compiler
# and linker at it explicitly.
set -euo pipefail
cd "$(dirname "$0")/.."

extra_flags=()
developer_dir="$(xcode-select -p)"
if [[ "$developer_dir" == *CommandLineTools* ]]; then
  frameworks="$developer_dir/Library/Developer/Frameworks"
  libs="$developer_dir/Library/Developer/usr/lib"
  extra_flags=(
    -Xswiftc -F -Xswiftc "$frameworks"
    -Xlinker -F -Xlinker "$frameworks"
    -Xlinker -rpath -Xlinker "$frameworks"
    -Xlinker -rpath -Xlinker "$libs"
  )
fi

swift test "${extra_flags[@]}" "$@"
