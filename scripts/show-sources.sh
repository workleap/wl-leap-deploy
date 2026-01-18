#!/bin/bash
set -euo pipefail

# This script displays configuration sources in a human-readable format
# Usage: ./fold-config.sh file.yaml env region true | ./show-sources.sh [workload-name]

WORKLOAD_FILTER="${1:-}"

# Read the JSON with source metadata from stdin
CONFIG_JSON=$(cat)

# jq script to extract and format source information
echo "$CONFIG_JSON" | jq -r --arg workload "$WORKLOAD_FILTER" '
def get_value_at_path($root; $path):
  $path | split(".") | reduce .[] as $key ($root; .[$key]);

def format_sources($root):
  if has("_metadata") then
    ._metadata | to_entries[] | {
      path: .key,
      value: get_value_at_path($root; .key),
      source: .value
    }
  else
    empty
  end;

if $workload == "" then
  # Show all workloads
  .workloads | to_entries[] | 
  ("=== " + .key + " ==="),
  (.value | format_sources(.) | 
   "  \(.path): \(.value | tostring)\n    └─ from: \(.source)")
else
  # Show specific workload
  if .workloads | has($workload) then
    ("=== " + $workload + " ==="),
    (.workloads[$workload] | format_sources(.) | 
     "  \(.path): \(.value | tostring)\n    └─ from: \(.source)")
  else
    ("Error: Workload '\''" + $workload + "'\'' not found" | halt_error(1))
  end
end
'
