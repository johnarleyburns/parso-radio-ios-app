from datetime import datetime, UTC, timedelta
import json
import urllib.parse
import urllib.request

# 1. Calculate the 7-day UTC time window
today = datetime.now(UTC).date()
one_week_ago = today - timedelta(days=60)

# Explicitly format date objects as strings for the query
today_str = today.isoformat()
one_week_ago_str = one_week_ago.isoformat()

# 2. Build the exact Lucene query string explicitly
query_string = f"collection:librivoxaudio AND addeddate:[{one_week_ago_str} TO {today_str}]"

# 3. Handle parameter encoding safely
params = {
    "q": query_string,
    "sort[]": "downloads desc",
    "output": "json",
    "rows": "20",
}
encoded_params = urllib.parse.urlencode(params)

# FIXED: Point to the advanced search endpoint instead of the root domain
full_url = f"https://archive.org/advancedsearch.php?{encoded_params}"

# 4. Construct request with strict, polite User-Agent header definitions
req = urllib.request.Request(full_url)
# FIXED: Replaced generic string with a descriptive User-Agent containing contact info
req.add_header("User-Agent", "LibriVoxTop5Script/1.0 (mailto:your-email@example.com)")
req.add_header("Accept", "application/json")

try:
    with urllib.request.urlopen(req) as response:
        # Read the raw stream body and convert to text representation
        raw_payload = response.read().decode("utf-8")
        
        # Verify body content exists before parsing to avoid DecodeErrors
        if not raw_payload.strip():
            raise ValueError("The server returned a blank response body.")
            
        data = json.loads(raw_payload)

    # 5. Extract item collections
    items = data.get("response", {}).get("docs", [])

    print(f"Top 10 Popular LibriVox Releases ({one_week_ago_str} to {today_str}):")
    print("-" * 50)
    
    if not items:
        print("No audiobooks were uploaded or modified during this 7-day window.")
    
    for index, item in enumerate(items, 1):
        title = item.get("title", "Unknown Title")
        downloads = item.get("downloads", 0)
        identifier = item.get("identifier", "")

        print(f"#{index} | Downloads: {downloads} | Title: {title}")
        # FIXED: Prepend /details/ to the identifier to create a working URL
        print(f"    Link: https://archive.org/details/{identifier}\n")

except Exception as e:
    print(f"An error occurred while fetching the data: {e}")
