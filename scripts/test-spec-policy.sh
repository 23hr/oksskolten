#!/usr/bin/env bash
set -euo pipefail

POLICY_DIR="policy/spec"
SPEC_DIR="docs/spec"
REMARK="./node_modules/.bin/remark"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# Phase 1: Convert all markdown specs to JSON ASTs in parallel
for file in "$SPEC_DIR"/*.md; do
  [ -f "$file" ] || continue
  name=$(basename "$file")

  is_feature=false
  if [[ "$name" == *_feature_* ]]; then
    is_feature=true
  fi

  metadata=$(printf '{"metadata":{"is_feature":%s}}' "$is_feature")

  (
    "$REMARK" --tree-out < "$file" 2>/dev/null \
      | jq -M -s ".[0] * $metadata" \
      > "$tmpdir/$name"
  ) &
done

wait

# Phase 2: Run conftest once on all files, show PASS and FAIL in table format
conftest test --parser json --policy "$POLICY_DIR" "$tmpdir"/*.md \
  | sed "s|$tmpdir/||g"
