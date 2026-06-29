#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
cd "${SCRIPT_DIR}" || exit 1

./b.sh "$@"
if [ $? -ne 0 ]; then
  echo "ffnvcodec prepare failed." >&2
  exit 1
fi