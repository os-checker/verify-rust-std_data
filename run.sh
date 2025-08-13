#!/usr/bin/bash

set -eou pipefail

merge_diff() {
  jq '
    map(select(.proof_kind != null) | .harness = .func | del(.func))
    | sort_by(.file, .harness)
  ' merge_diff.json >merge_diff-proofs-only.json
}

results() {
  jq '[
    .[] | select(.result.crate == "core") # filter in core results
    | .result #+{ thread_id: .thread_id } # merge thread_id into result
    | select(.is_autoharness | not) | del(.is_autoharness) # remove autoharness
    | .file_name |= sub("^/home/runner/work/verify-rust-std/verify-rust-std/library/"; "") # strip local path
    | del(.n_failed_properties | select(. == 0)) # remove .n_failed_properties field if zero
    | . += (if (.result // "" | startswith("SUCCESSFUL") | not) then {ok: false} else {} end) # convert SUCCESSFUL to ok, omission as true
    | .props = .n_total_properties | del(.n_total_properties) # shorten long field names
    | .file = .file_name | del(.file_name) # shorten long field names
    | .func_ = { name: .function, safe: .function_safeness } | del(.function, .function_safeness) # shorten long field names
    | del(.time | select(. == null))      # remove null time
    | del(.output | select(. == []))      # remove .output field if empty
    | del(.crate, .result, .public_target, .autoharness_result)  # remove less important fields to save space
    | (.time | select(. != null)) |= (sub("s$"; "") | tonumber * 1000 | floor) # convert time into milliseconds
  ]' ../../tmp/ubuntu-latest-results.json/results.json >results-core.json
}

merge_results() {
  jq --slurp '
    (.[0] + .[1])
    | group_by(.harness + "#" + .file)
    | map(
        add | { file, harness , proof_kind, time, props, with_contract, func, hash }
      )
    | walk(if type == "object" then with_entries(select(.value != null)) else . end)
  ' results-core.json merge_diff-proofs-only.json >merge_results-core.json
}

declare -A cmds=(
  [merge_diff]=merge_diff
  [results]=results
  [merge_results]=merge_results
)

[[ $# -eq 0 ]] && {
  echo "Usage: $0 {merge_diff|results} [args...]"
  exit 1
}

cmd=$1
shift
if [[ -n ${cmds[$cmd]} ]]; then
  ${cmds[$cmd]} "$@"
else
  echo "Unknown command '$cmd'" >&2
  exit 1
fi
