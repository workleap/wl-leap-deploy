#!/bin/bash
set -euo pipefail

FILE_PATH="$1"
ENVIRONMENT="$2"
REGION="${3:-}"
SHOW_SOURCES="${4:-false}"

# Get the directory of the input file for resolving relative paths
# Can be overridden by LEAP_DEPLOY_BASE_DIR environment variable for deterministic test paths
if [[ -n "${LEAP_DEPLOY_BASE_DIR:-}" ]]; then
  FILE_DIR="$LEAP_DEPLOY_BASE_DIR"
else
  FILE_DIR=$(dirname "$(realpath "$FILE_PATH")")
fi

# Convert YAML to JSON once
JSON_CONFIG=$(yq eval -o=json '.' "$FILE_PATH")

# Get ID (required field)
ID=$(echo "$JSON_CONFIG" | jq -r '.id')

# Get version (required field)
VERSION=$(echo "$JSON_CONFIG" | jq -r '.version')

# Get defaults
DEFAULTS=$(echo "$JSON_CONFIG" | jq -c '.defaults // {}')

# Get list of workload names
WORKLOADS=$(echo "$JSON_CONFIG" | jq -r '.workloads | keys | .[]')

# jq function to merge with source tracking
read -r -d '' JQ_MERGE_WITH_SOURCE <<'EOF' || true
def merge_with_metadata($current; $overlay; $source_path; $metadata):
  # Recursively merge objects while tracking sources in metadata
  def deep_merge($cur; $new; $src; $path; $meta):
    if ($cur | type) == "object" and ($new | type) == "object" then
      # Both are objects - merge recursively
      reduce ($new | keys_unsorted[]) as $key (
        {current: $cur, metadata: $meta};
        if $new[$key] != null then
          . as $state |
          deep_merge($state.current[$key] // {}; $new[$key]; $src; ($path + [$key]); $state.metadata) as $result |
          {
            current: ($state.current + {($key): $result.current}),
            metadata: $result.metadata
          }
        else
          .
        end
      )
    elif $new != null then
      # New value overrides - record source in metadata
      {
        current: $new,
        metadata: ($meta + {($path | join(".")): $src})
      }
    else
      {current: $cur, metadata: $meta}
    end;

  deep_merge($current; $overlay; $source_path; []; $metadata);
EOF

# Start building output JSON
echo "{"
if [[ "$VERSION" != "null" && -n "$VERSION" ]]; then
  echo "  \"version\": \"$VERSION\","
fi
echo "  \"id\": \"$ID\","
echo "  \"workloads\": {"
FIRST=true

while IFS= read -r WORKLOAD; do
  if [[ "$FIRST" == "false" ]]; then
    echo ","
  fi
  FIRST=false

  # Start with defaults and empty metadata
  CURRENT_DATA="$DEFAULTS"
  CURRENT_METADATA="{}"

  # Layer 1: Merge workload-level config (excluding environments/regions)
  WORKLOAD_BASE=$(echo "$JSON_CONFIG" | jq -c ".workloads[\"$WORKLOAD\"] | del(.environments, .regions)")
  MERGE_RESULT=$(jq -n \
    --argjson current "$CURRENT_DATA" \
    --argjson overlay "$WORKLOAD_BASE" \
    --argjson metadata "$CURRENT_METADATA" \
    --arg source "workloads.$WORKLOAD" \
    "$JQ_MERGE_WITH_SOURCE"'
    merge_with_metadata($current; $overlay; $source; $metadata)
  ')
  CURRENT_DATA=$(echo "$MERGE_RESULT" | jq -c '.current')
  CURRENT_METADATA=$(echo "$MERGE_RESULT" | jq -c '.metadata')

  # Layer 2: Merge environment-level config (cross-region)
  ENV_CONFIG=$(echo "$JSON_CONFIG" | jq -c ".workloads[\"$WORKLOAD\"].environments[\"$ENVIRONMENT\"] // {} | del(.regions)")
  MERGE_RESULT=$(jq -n \
    --argjson current "$CURRENT_DATA" \
    --argjson overlay "$ENV_CONFIG" \
    --argjson metadata "$CURRENT_METADATA" \
    --arg source "workloads.$WORKLOAD.environments.$ENVIRONMENT" \
    "$JQ_MERGE_WITH_SOURCE"'
    merge_with_metadata($current; $overlay; $source; $metadata)
  ')
  CURRENT_DATA=$(echo "$MERGE_RESULT" | jq -c '.current')
  CURRENT_METADATA=$(echo "$MERGE_RESULT" | jq -c '.metadata')

  # Layer 3: Merge region-level config (if region specified)
  if [[ -n "$REGION" ]]; then
    REGION_CONFIG=$(echo "$JSON_CONFIG" | jq -c ".workloads[\"$WORKLOAD\"].regions[\"$REGION\"] // {} | del(.environments)")
    MERGE_RESULT=$(jq -n \
      --argjson current "$CURRENT_DATA" \
      --argjson overlay "$REGION_CONFIG" \
      --argjson metadata "$CURRENT_METADATA" \
      --arg source "workloads.$WORKLOAD.regions.$REGION" \
      "$JQ_MERGE_WITH_SOURCE"'
      merge_with_metadata($current; $overlay; $source; $metadata)
    ')
    CURRENT_DATA=$(echo "$MERGE_RESULT" | jq -c '.current')
    CURRENT_METADATA=$(echo "$MERGE_RESULT" | jq -c '.metadata')

    # Layer 4: Merge region+environment config (most specific)
    REGION_ENV_CONFIG=$(echo "$JSON_CONFIG" | jq -c ".workloads[\"$WORKLOAD\"].regions[\"$REGION\"].environments[\"$ENVIRONMENT\"] // {}")
    MERGE_RESULT=$(jq -n \
      --argjson current "$CURRENT_DATA" \
      --argjson overlay "$REGION_ENV_CONFIG" \
      --argjson metadata "$CURRENT_METADATA" \
      --arg source "workloads.$WORKLOAD.regions.$REGION.environments.$ENVIRONMENT" \
      "$JQ_MERGE_WITH_SOURCE"'
      merge_with_metadata($current; $overlay; $source; $metadata)
    ')
    CURRENT_DATA=$(echo "$MERGE_RESULT" | jq -c '.current')
    CURRENT_METADATA=$(echo "$MERGE_RESULT" | jq -c '.metadata')
  fi

  # Apply schema defaults and resolve paths
  CURRENT_DATA=$(echo "$CURRENT_DATA" | jq --arg fileDir "$FILE_DIR" '
    if .projectSource != null then
      if .projectSource.type == null then
        .projectSource = {type: "auto"} + .projectSource
      else
        .
      end |
      if .projectSource.path != null and (.projectSource.path | startswith("/") | not) then
        .projectSource.path = ($fileDir + "/" + .projectSource.path)
      else
        .
      end
    else
      .projectSource = null
    end |
    # Reconstruct object with correct field ordering
    {
      kind: .kind,
      image: .image,
      projectSource: .projectSource
    } + (. | del(.kind, .image, .projectSource))
  ')

  # Output based on SHOW_SOURCES flag
  if [[ "$SHOW_SOURCES" == "true" ]]; then
    # Output with metadata at root level
    OUTPUT=$(jq -n \
      --argjson data "$CURRENT_DATA" \
      --argjson metadata "$CURRENT_METADATA" \
      '$data + {"_metadata": $metadata}')
    echo -n "  \"$WORKLOAD\": $(echo "$OUTPUT" | jq -c '.')"
  else
    # Output just the data (no metadata)
    echo -n "  \"$WORKLOAD\": $(echo "$CURRENT_DATA" | jq -c '.')"
  fi

done <<< "$WORKLOADS"

echo ""
echo "  }"
echo "}"
