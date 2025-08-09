#!/usr/bin/bash

set -eou pipefail

jq 'map(select(.proof_kind != null)) | sort_by(.file, .func)' merge_diff.json >merge_diff-proofs-only.json
