#!/usr/bin/env python3
"""
Seed shipped curation JSONs with approved track entries from Internet Archive queries.

For each curated books channel, runs its iaQuery against the IA search API,
fetches the top N tracks by download count, filters by quality heuristics
(duration > 60s, excludes items without audio), and writes approved entries
back into the bundled JSON file.

Usage:
    python3 Tools/seed-curation.py [--depth N] [--dry-run] [channel-id...]

    --depth N     Max tracks to seed per channel (default: 50)
    --dry-run     Print what would happen without writing files
    channel-id    Only seed specified channels (default: all books channels)

Examples:
    # Seed all 5 books channels with 50 tracks each
    python3 Tools/seed-curation.py

    # Seed only Ancient Greece with 100 tracks, dry run
    python3 Tools/seed-curation.py --depth 100 --dry-run ancient-greece

    # Seed specific channels
    python3 Tools/seed-curation.py ancient-greece great-books
"""

import json
import os
import sys
import time
import urllib.parse
import urllib.request
import ssl
from datetime import datetime, timezone

# ── Config ──────────────────────────────────────────────────────────────────

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHANNELS_DIR = os.path.join(BASE_DIR, "ParsoRadio", "Resources", "curated-channels")
IA_QUERIES_PATH = os.path.join(BASE_DIR, "ParsoRadio", "Resources", "ia_queries.json")
IA_SEARCH_URL = "https://archive.org/advancedsearch.php"
IA_METADATA_URL = "https://archive.org/metadata/{}"
REQUEST_DELAY = 0.5  # seconds between API calls (be polite)

BOOKS_CHANNELS = [
    "ancient-greece",
    "great-books",
    "popular-literature",
    "greater-books",
    "childrens-books",
]

# ── Helpers ─────────────────────────────────────────────────────────────────

def load_json(path):
    with open(path, "r") as f:
        return json.load(f)

def save_json(path, data):
    with open(path, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")

def http_get(url, retries=3):
    ctx = ssl.create_default_context()
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "LorewaveSeedBot/1.0"})
            with urllib.request.urlopen(req, context=ctx, timeout=30) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except Exception as e:
            if attempt == retries - 1:
                raise
            time.sleep(2 ** attempt)


def parse_runtime(rt):
    """Parse IA runtime field: seconds (int) or HH:MM:SS (string)."""
    if rt is None:
        return 0.0
    if isinstance(rt, (int, float)):
        return float(rt)
    if isinstance(rt, str):
        parts = rt.strip().split(":")
        if len(parts) == 3:
            return int(parts[0]) * 3600 + int(parts[1]) * 60 + float(parts[2])
        elif len(parts) == 2:
            return int(parts[0]) * 60 + float(parts[1])
        try:
            return float(rt)
        except ValueError:
            return 0.0
    return 0.0


def resolve_duration(identifier):
    """Try to get a better duration from the item metadata (sum of audio file lengths)."""
    try:
        data = http_get(IA_METADATA_URL.format(identifier))
        files = data.get("files", [])
        total = 0.0
        for f in files:
            fmt = (f.get("format") or "").lower()
            name = (f.get("name") or "").lower()
            ext = os.path.splitext(name)[1]
            if fmt in ("vbr mp3", "128kbps mp3", "64kbps mp3", "mp3", "ogg vorbis") or ext in (".mp3", ".ogg", ".m4a", ".aac", ".opus", ".flac", ".wav"):
                length = f.get("length")
                if length:
                    total += parse_runtime(length)
        return total if total > 0 else None
    except Exception:
        return None


def search_ia(query, rows=100, page=1):
    """Run an IA advanced search query and return docs."""
    params = {
        "q": query,
        "fl[]": ["identifier", "title", "creator", "runtime", "downloads", "year", "date"],
        "output": "json",
        "rows": str(rows),
        "page": str(page),
        "sort[]": ["downloads desc"],
    }
    qs = urllib.parse.urlencode(params, doseq=True)
    url = f"{IA_SEARCH_URL}?{qs}"
    data = http_get(url)
    return data.get("response", {}).get("docs", [])


def seed_channel(channel_id, depth, dry_run, ia_registry=None):
    json_path = os.path.join(CHANNELS_DIR, f"{channel_id}.json")
    if not os.path.exists(json_path):
        print(f"  SKIP: {json_path} not found")
        return 0

    data = load_json(json_path)
    channel = data.get("channel", {})

    # iaQuery from JSON first, then fall back to registry
    ia_query = channel.get("iaQuery")
    if not ia_query and ia_registry:
        for entry in ia_registry:
            if entry.get("channelId") == channel_id:
                ia_query = entry.get("iaQuery")
                break

    if not ia_query:
        print(f"  SKIP: {channel_id} has no iaQuery")
        return 0

    name = channel.get("name", channel_id)
    print(f"\n── {name} ({channel_id}) ──")

    # Fetch top results
    existing_ids = {e["id"] for e in data.get("approved", [])}
    rejected_ids = set(data.get("rejected", []))
    new_entries = []
    page = 1
    needed = depth

    while needed > 0 and page <= 10:
        try:
            docs = search_ia(ia_query, rows=min(100, needed), page=page)
        except Exception as e:
            print(f"  ERROR searching IA: {e}")
            break

        if not docs:
            break

        for doc in docs:
            if len(new_entries) >= depth:
                break

            identifier = doc.get("identifier", "")
            if not identifier:
                continue
            if identifier in existing_ids or identifier in rejected_ids:
                continue

            title = doc.get("title", identifier)
            creator = doc.get("creator", "Unknown")
            if isinstance(creator, list):
                creator = creator[0] if creator else "Unknown"

            # Get duration from search result
            duration = parse_runtime(doc.get("runtime"))
            if duration < 60:
                # Try metadata for better duration
                resolved = resolve_duration(identifier)
                if resolved and resolved >= 60:
                    duration = resolved
                else:
                    continue  # Too short or no audio

            # Acceptable: has duration >= 60s
            entry = {
                "id": identifier,
                "title": title,
                "creator": creator,
                "duration": duration,
            }
            # Include parentIdentifier for multi-file items (same as id for parent-level entries)
            new_entries.append(entry)
            existing_ids.add(identifier)
            time.sleep(REQUEST_DELAY)

        page += 1
        if len(docs) < 100:
            break

    if not new_entries:
        print(f"  No new tracks found (existing: {len(data.get('approved', []))})")
        return 0

    print(f"  Found {len(new_entries)} new tracks to approve")
    for e in new_entries[:5]:
        print(f"    • {e['title'][:60]} — {e['creator'][:40]} ({e['duration']:.0f}s)")
    if len(new_entries) > 5:
        print(f"    … and {len(new_entries) - 5} more")

    if not dry_run:
        data.setdefault("approved", []).extend(new_entries)
        # Preserve existing rejected
        data["rejected"] = list(set(data.get("rejected", [])))
        data["updatedAt"] = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        save_json(json_path, data)
        print(f"  ✓ Wrote {json_path}")
    else:
        print(f"  [dry-run] Would write {json_path}")

    return len(new_entries)


# ── Main ────────────────────────────────────────────────────────────────────

def main():
    depth = 50
    dry_run = False
    channel_ids = None

    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--depth":
            i += 1
            if i < len(args):
                depth = int(args[i])
        elif args[i] == "--dry-run":
            dry_run = True
        elif args[i] in ("--help", "-h"):
            print(__doc__)
            return
        else:
            if channel_ids is None:
                channel_ids = []
            channel_ids.append(args[i])
        i += 1

    if channel_ids is None:
        channel_ids = BOOKS_CHANNELS

    # Load IA query registry for fallback queries
    ia_registry = None
    if os.path.exists(IA_QUERIES_PATH):
        try:
            with open(IA_QUERIES_PATH) as f:
                ia_registry = json.load(f)
        except Exception:
            pass

    print(f"Seeding {len(channel_ids)} channel(s) with depth={depth}" + (" [DRY RUN]" if dry_run else ""))
    total = 0
    for ch_id in channel_ids:
        count = seed_channel(ch_id, depth, dry_run, ia_registry)
        total += count
        time.sleep(1)  # Polite pause between channels

    print(f"\n{'Would seed' if dry_run else 'Seeded'} {total} total track(s) across {len(channel_ids)} channel(s).")


if __name__ == "__main__":
    main()
