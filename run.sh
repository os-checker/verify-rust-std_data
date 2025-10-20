#!/usr/bin/bash

set -exou pipefail

cwd=$PWD

# Entrypoint.
all() {
  split
  gen
}

split() {
  # Remove entire split folder.
  rm split -rf
  cd ../../
  # Update core.sqlite3
  ./download-artifact.sh
  cd assets
  # Generate new split folder.
  ./split.sh ../artifacts/artifact-libcore/core.sqlite3 split.sql ../ui/verify-rust-std_data/split
  # Generate hash.json
  sqlite3 ../artifacts/artifact-libcore/core.sqlite3 <hash.sql | jq -s '.' >../ui/verify-rust-std_data/hash.json
}

# This relies on latest artifact-libcore, so run split first to update it.
gen() {
  cd "$cwd"
  # The artifacts must accord with split cmd.
  verify_rust_std merge --hash-json ../../artifacts/artifact-libcore/json \
    --kani-list ../../assets/kani-list_verify-rust-std-CI.json \
    --strip-kani-list-prefix /home/runner/work/verify-rust-std/verify-rust-std/library/ >merge_diff.json

  # Filter in contract autoharnesses.
  jq '
    .contracts
    | map(
      select(.harnesses[0] == "kani::internal::automatic_harness")
      | { (.function): "AutoContract" }
    )
    | add
    | to_entries | sort | from_entries
  ' ../../assets/kani-list_verify-rust-std-CI.json >autoharness-contract.json
  # Filter in standard autoharnesses.
  sqlite3 ../../assets/core.sqlite3 <../../assets/proof_kind.sql >proof_kind.json
  jq --slurp '
    {
      proof: .[0] | to_entries | map(.value) | add,
      standard: .[1]."standard-harnesses" | to_entries | map(.value) | add
    }
    | . as $root
    | .standard | map(select($root.proof[.] | not) | { (.): "AutoStandard" } ) | add
    | to_entries | sort | from_entries
  ' proof_kind.json ../../assets/kani-list_verify-rust-std-CI.json >autoharness-standard.json

  # Merge autoharness.
  jq --slurp '.[0] + .[1]
    | to_entries | sort | from_entries
  ' autoharness-contract.json autoharness-standard.json >autoharness.json

  # Add autoharness back by modifying .proof_kind field.
  jq --slurp '
    { auto: .[0], merge: .[1] }
    | . as $root
    | .merge | map(
      if ($root.auto[.func]) then .proof_kind = $root.auto[.func] else . end
    )
  ' autoharness.json merge_diff.json >merge_diff_with_auto.json
  mv merge_diff_with_auto.json merge_diff.json

  merge_diff
  results
  merge_results
}

merge_diff() {

  jq '
    map(
      select(.proof_kind != null) 
      | .harness = .func | del(.func)
    )
    | sort_by(.file, .harness)
  ' merge_diff.json >merge_diff-proofs-only.json
}

results() {
  jq '[
    .[] 
    | .result
    | select(.time != null)
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
    | del(.func.safe | select(. == null)) # remove null .func.safe
  ]' ../../tmp/ubuntu-latest-results.json/results.json >results-core.json
}

merge_results() {
  jq --slurp '
    (.[0] + .[1])
    | group_by(.harness)
    | map(
        add | { crate, file, harness, proof_kind, time, props, func, hash } | select(.time != null)
      )
    | walk(if type == "object" then with_entries(select(.value != null)) else . end)
    | sort_by(.crate, .file, .harness, .proof_kind, .time)
  ' results-core.json merge_diff-proofs-only.json >merge_results-core.json
}

chart() {
  jq 'map(
    select(.crate and .time)
    # extract `crate::submod`
    | { mod: ( .crate + "::" + (.func.name | split("::")[0]) ), time }
  )
  | group_by(.mod)
  | map({
      mod: .[0].mod,
      avg: (map(.time) | add / length) | round,
      time: map(.time) | sort
    })
  ' merge_results-core.json >chart/time.json

  # Merge and flatten data.
  jq --slurp '
    map( .local.count_in_module | to_entries | map({ mod: .key, cnt: .value }) ) | flatten 
  ' ../../assets/json/stat/*.json >chart/count.json

  jq --slurp '
    add | group_by(.mod) | map(
      add
      | select(.mod | startswith("core") or startswith("std") or startswith("alloc"))
    )
  ' chart/count.json chart/time.json >chart/merged.json

  jless chart/merged.json
}

declare -A cmds=(
  [all]=all
  [split]=split
  [gen]=gen
  [merge_diff]=merge_diff
  [results]=results
  [merge_results]=merge_results
  [chart]=chart
)

[[ $# -eq 0 ]] && {
  echo "Usage: $0 {all|split|gen|merge_diff|results|merge_results|chart} [args...]"
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
