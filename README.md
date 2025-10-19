
# JSONs

* `hash.json`: hash values for all functions; generated from core.sqlite3
* `merge_diff.json`: merge kani-list.json and hash json; non-core functions may have no hash value
* `merge_diff-proofs-only.json`: filter in core-based functions; proof_kind and hash value must exist
* `results-core.json`: extract core-based verification info from `results.json`
  * `results.json` contains verification results from core and deps, including stadndard/contract harnesses and autoharness
* `merge_results-core.json`: merge `results-core` (verification info) and `merge_diff-proofs-only` (hash info)
* In chart folder:
  * `time.json`: group time info by mod from `merge_results-core`
  * `count.json`: merge dv stat JSONs which are function counts of proof_kind in mods
  * `merged.json`: merge time and count by mod
