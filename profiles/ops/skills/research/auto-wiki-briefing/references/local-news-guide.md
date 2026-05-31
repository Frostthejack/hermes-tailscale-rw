# Local News RSS Guide for Small Towns
# =====================================
#
# Small towns and rural areas rarely have dedicated RSS feeds.
# This guide covers practical approaches.

## The Problem

A town of ~10k people like Marshall, MO won't have a newspaper with a working RSS feed. Even mid-size city newspapers frequently break their RSS or put it behind paywalls. Direct station RSS (TV news) is unreliable — we tested KOMU (Columbia, MO) and got 404.

## Solution: Google News Search Proxy

Google News provides a search RSS endpoint that works as a proxy for any geography:

```
https://news.google.com/rss/search?q=SEARCH_TERMS&hl=en-US&gl=US&ceid=US:en
```

### Geography patterns:

```
# City level
q=Marshall+Missouri

# City + state (recommended)
q=Marshall+Missouri+USA

# County level (good for small towns)
q=Saline+County+Missouri

# Combined city OR county
q=Marshall+Missouri+OR+Saline+County+Missouri

# Nearest mid-size city (broaden if town is too small)
q=Columbia+Missouri

# State level
q=Missouri
```

## Testing Geography Queries

Google News RSS returns up to 100 items. For very small towns, you may get few or no results. Test with `web_search` first:

```
web_search(query: "Marshall Missouri news site:news.google.com", limit=3)
```

Then verify the RSS URL returns items:

```bash
python3 -c "
import urllib.request
from xml.etree import ElementTree as ET
url = 'https://news.google.com/rss/search?q=Marshall+Missouri&hl=en-US&gl=US&ceid=US:en'
req = urllib.request.Request(url, headers={'User-Agent': 'Hermes-Watcher/1.0'})
with urllib.request.urlopen(req, timeout=10) as r:
    data = r.read()
    root = ET.fromstring(data)
    entries = list(root.iter('{http://www.w3.org/2005/Atom}entry'))
    print(f'Items: {len(entries)}')
"
```

If < 3 items, broaden the query (add county, or nearest city).

## State Government Sources

State-level government news is often available via States Newsroom (nonprofit state journalism):

```
https://statesnewsroom.com/rss-feeds/
```

Each state typically has its own subdomain:
- Missouri: `https://missouriindependent.com/feed/`
- Kansas: `https://kansasreflector.com/feed/`
- Illinois: `https://illinoisreflector.com/feed/`
- etc.

These are high-quality statewide political and policy reporting.

## Regional Newspaper via Proxy

Even when a newspaper's direct RSS is broken (paywalled or 403), you can often find its stories through Google News:

```
q=site:kansascity.com+Missouri
q=site:stltoday.com+Missouri
q=site:columbiatribune.com+Missouri
```

## Tiered Fallback Strategy

For robust local coverage, configure multiple sources so you always have signal:

1. **Primary**: Google News search for the town + county
2. **Secondary**: Google News for nearest mid-size city (Columbia for Marshall)
3. **Tertiary**: State news source (Missouri Independent)
4. **Safety net**: State-level Google News (catches major stories that mention the town)

This way, even if the town-specific query returns nothing on a quiet day, you still get relevant regional and state news.

## What to Filter

Local news from small towns includes a lot of noise:
- High school sports (usually not newsworthy for a daily briefing)
- Obituaries
- Routine city council meeting minutes
- Community calendar items

The briefing should apply the same "serious news" filter:
- Include: city/county government decisions, major local employer news, school board policy, infrastructure, crime of significance, local politics
- Exclude: sports, obituaries, routine meetings, community events, minor incidents
