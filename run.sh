#!/usr/bin/bash

set -exou pipefail

all() {
  verify_rust_std merge --hash-json ../../assets/json \
    --kani-list ../../assets/kani-list_verify-rust-std-CI.json \
    --strip-kani-list-prefix /home/runner/work/verify-rust-std/verify-rust-std/library/ >merge_diff.json
  merge_diff
  results
  merge_results
}

merge_diff() {
  jq '
    map(select(.proof_kind != null) | .harness = .func | del(.func))
    | sort_by(.file, .harness)
  ' merge_diff.json >merge_diff-proofs-only.json
}

results() {
  jq '[
    .[] 
    | .result
    # | select(.crate == "core") # filter in core results
    | select(.is_autoharness | not) | del(.is_autoharness) # remove autoharness
    | {
      harness,
      ok: (if (.result // "" | startswith("SUCCESSFUL") | not) then false else null end), # convert SUCCESSFUL to ok, omission as true
      time: (.time | select(. != null) | sub("s$"; "") | tonumber * 1000 | floor), # convert time into milliseconds
      props: .n_total_properties,
      n_failed_properties,
      func: {
        name: .function,
        safe: .function_safeness,
        file: .file_name | sub("^/home/runner/work/verify-rust-std/verify-rust-std/library/"; ""), # strip local path
      },
      output
    }

    | del(.ok | select(. == null)) # remove null time
    | del(.time | select(. == null)) # remove null time
    | del(.output | select(. == [])) # remove .output field if empty
    | del(.n_failed_properties | select(. == 0)) # remove .n_failed_properties field if zero
  ]' ../../tmp/ubuntu-latest-results.json/results.json >results-core.json
}

merge_results() {
  jq --slurp '
    (.[0] + .[1])
    | group_by(.harness)
    | map(
        add | { crate, file, harness, proof_kind, time, props, func, hash }
      )
    | walk(if type == "object" then with_entries(select(.value != null)) else . end)
    | sort_by(.crate, .file, .harness, .proof_kind, .time)
  ' results-core.json merge_diff-proofs-only.json >merge_results-core.json
}

split() {

}

declare -A cmds=(
  [all]=all
  [merge_diff]=merge_diff
  [results]=results
  [merge_results]=merge_results
)

[[ $# -eq 0 ]] && {
  echo "Usage: $0 {all|merge_diff|results|merge_results} [args...]"
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
