#!/usr/bin/env python3

import urllib.request
import urllib.parse
import json
import argparse
import sys

def fetch_ia_results(lucene_query, rows, tier_name):
    """
    Executes a Lucene query against the Internet Archive Advanced Search API.
    """
    base_url = "https://archive.org/advancedsearch.php"
    
    params = {
        'q': lucene_query,
        'fl[]': ['identifier', 'creator', 'venue', 'date', 'downloads'],
        'sort[]': ['downloads desc'],
        'rows': rows,
        'page': 1,
        'output': 'json'
    }
    
    url = f"{base_url}?{urllib.parse.urlencode(params, doseq=True)}"
    
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'EtreeDataScript/1.1'})
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode('utf-8'))
            docs = data.get('response', {}).get('docs', [])
            
            results = []
            for doc in docs:
                artist = doc.get('creator', 'Unknown')
                if isinstance(artist, list):
                    artist = ", ".join(artist)
                    
                venue = doc.get('venue', 'Unknown')
                if isinstance(venue, list):
                    venue = ", ".join(venue)
                    
                date = doc.get('date', 'Unknown')
                if isinstance(date, str) and 'T' in date:
                    date = date.split('T')[0]
                    
                source = doc.get('identifier', 'Unknown')
                downloads = doc.get('downloads', 0)
                
                results.append(f"[{tier_name}] {date} | {artist} | {source} | Downloads: {downloads:,}")
            return results
            
    except urllib.error.URLError as e:
        print(f"Network error executing query for {tier_name}: {e}", file=sys.stderr)
        return []
    except Exception as e:
        print(f"Data parsing error for {tier_name}: {e}", file=sys.stderr)
        return []

def main():
    parser = argparse.ArgumentParser(description="Fetch top Live Music Archive shows for a specific day.")
    parser.add_argument("date", help="The target date in MM-DD format (e.g., 07-09, 10-31)")
    args = parser.parse_args()

    target_date = args.date

    # Basic validation to ensure the input looks like MM-DD
    if len(target_date) != 5 or "-" not in target_date:
        print("Error: Date must be in MM-DD format (e.g., 07-09).", file=sys.stderr)
        sys.exit(1)

    print(f"Executing Lucene queries for {target_date} against the Internet Archive...\n")
    
    # Block A: Extract absolute #1 leader for the target date
# New, more robust query logic
    # Searching for the string directly in the metadata often catches dates 
    # regardless of whether they are indexed under 'date:' or 'title:'
    query_a = f'collection:etree AND "{target_date}"'
    results_a = fetch_ia_results(query_a, 1, "Absolute Top 1 ")
    
    # We use a space-separated search to ensure it catches the format
    query_b = f'collection:etree AND "{target_date}" AND -creator:"Grateful Dead"'
    results_b = fetch_ia_results(query_b, 19, "Top 19 Non-Dead")
    
    # Output the aggregated results
    for r in results_a:
        print(r)
        
    for r in results_b:
        print(r)

if __name__ == "__main__":
    main()
