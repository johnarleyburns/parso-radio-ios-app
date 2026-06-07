#!/bin/bash
# Tests for the merge-curation CLI tool
# Run from Tools/merge-curation directory: bash Tests/test.sh

set -euo pipefail

TOOL="./.build/debug/merge-curation"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "=== Building merge-curation ==="
swift build 2>&1

# Create test JSONs
cat > "$TMPDIR/exported.json" << 'EOF'
{
  "approved" : [
    {
      "creator" : "Bach",
      "duration" : 300,
      "id" : "new-track-1",
      "parentIdentifier" : null,
      "title" : "New Track 1"
    },
    {
      "creator" : "Mozart",
      "duration" : 400,
      "id" : "existing-track-1",
      "parentIdentifier" : null,
      "title" : "Existing Track"
    }
  ],
  "channel" : {
    "iaQuery" : "test",
    "icon" : "star",
    "id" : "test-channel",
    "name" : "Test Channel"
  },
  "rejected" : [],
  "updatedAt" : "2026-01-01",
  "version" : 1
}
EOF

cat > "$TMPDIR/bundled.json" << 'EOF'
{
  "approved" : [
    {
      "creator" : "Beethoven",
      "duration" : 600,
      "id" : "existing-track-1",
      "parentIdentifier" : null,
      "title" : "Existing Track"
    }
  ],
  "channel" : {
    "iaQuery" : "original-query",
    "icon" : "star",
    "id" : "test-channel",
    "name" : "Original Channel Name"
  },
  "rejected" : [],
  "updatedAt" : "2026-01-01",
  "version" : 1
}
EOF

# TEST 1: merge --dry-run adds new tracks, skips duplicates
echo ""
echo "=== TEST 1: merge --dry-run (add 1 new, skip 1 duplicate) ==="
OUTPUT=$("$TOOL" merge --dry-run \
    --input "$TMPDIR/exported.json" \
    --target "$TMPDIR/bundled.json" 2>&1)
echo "$OUTPUT"
echo "$OUTPUT" | grep "added:         1" > /dev/null || { echo "FAIL: expected 1 added"; exit 1; }
echo "$OUTPUT" | grep "skipped:       1" > /dev/null || { echo "FAIL: expected 1 skipped"; exit 1; }
echo "$OUTPUT" | grep "total after:   2" > /dev/null || { echo "FAIL: expected total 2"; exit 1; }
echo "PASS: Merge dry-run correct"

# TEST 2: merge actually writes
echo ""
echo "=== TEST 2: merge (actual write) ==="
cp "$TMPDIR/bundled.json" "$TMPDIR/bundled-write.json"
"$TOOL" merge --input "$TMPDIR/exported.json" --target "$TMPDIR/bundled-write.json" 2>&1
python3 -c "
import json
with open('$TMPDIR/bundled-write.json') as f:
    d = json.load(f)
assert len(d['approved']) == 2, f'Expected 2 approved, got {len(d[\"approved\"])}'
assert d['channel']['name'] == 'Original Channel Name', 'Channel name should be preserved'
assert d['approved'][0]['title'] == 'Existing Track', 'Existing should stay first'
print('PASS: Merged file has 2 entries, channel info preserved')
"

# TEST 3: replace --dry-run
echo ""
echo "=== TEST 3: replace --dry-run ==="
OUTPUT=$("$TOOL" replace --dry-run \
    --input "$TMPDIR/exported.json" \
    --target "$TMPDIR/bundled.json" 2>&1)
echo "$OUTPUT"
echo "$OUTPUT" | grep "total after:   2" > /dev/null || { echo "FAIL: expected total 2 after replace"; exit 1; }
echo "PASS: Replace dry-run correct"

# TEST 4: replace actually writes but preserves channel info
echo ""
echo "=== TEST 4: replace (preserves channel info) ==="
cp "$TMPDIR/bundled.json" "$TMPDIR/bundled-replace.json"
"$TOOL" replace --input "$TMPDIR/exported.json" --target "$TMPDIR/bundled-replace.json" 2>&1
python3 -c "
import json
with open('$TMPDIR/bundled-replace.json') as f:
    d = json.load(f)
assert len(d['approved']) == 2, f'Expected 2 approved, got {len(d[\"approved\"])}'
assert d['channel']['name'] == 'Original Channel Name', 'Channel info MUST be preserved'
assert d['channel']['iaQuery'] == 'original-query', 'Channel query MUST be preserved'
print('PASS: Replace preserved channel info, replaced approved list')
"

# TEST 5: merge with completely new channel (all new tracks)
echo ""
echo "=== TEST 5: merge all-new tracks ==="
cat > "$TMPDIR/all-new.json" << 'EOF'
{
  "approved" : [
    {
      "creator" : "Vivaldi",
      "duration" : 200,
      "id" : "vivaldi-1",
      "parentIdentifier" : null,
      "title" : "Four Seasons"
    }
  ],
  "channel" : { "iaQuery" : "x", "icon" : "star", "id" : "test-channel", "name" : "X" },
  "rejected" : [],
  "updatedAt" : "2026-01-01",
  "version" : 1
}
EOF
OUTPUT=$("$TOOL" merge --dry-run \
    --input "$TMPDIR/all-new.json" \
    --target "$TMPDIR/bundled.json" 2>&1)
echo "$OUTPUT"
echo "$OUTPUT" | grep "added:         1" > /dev/null || { echo "FAIL: expected 1 added"; exit 1; }
echo "$OUTPUT" | grep "skipped:       0" > /dev/null || { echo "FAIL: expected 0 skipped"; exit 1; }
echo "PASS: All-new merge adds correctly"

echo ""
echo "=== ALL TESTS PASSED ==="
