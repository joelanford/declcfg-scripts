#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

. "$(dirname "$0")/lib/funcs.sh"

fmt "$1" "$2"
opm alpha validate "$2"
