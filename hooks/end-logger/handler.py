"""Log session end events. Extend for custom monitoring."""
import json
import logging
from datetime import datetime
from pathlib import Path

logger = logging.getLogger("hooks.session-end")
LOG_FILE = Path.home() / ".hermes" / "logs" / "session_events.jsonl"


async def handle(event_type: str, context: dict) -> None:
    entry = {
        "ts": datetime.now().isoformat(),
        "event": event_type,
        "platform": context.get("platform", ""),
        "session": context.get("session_key", ""),
        "user": context.get("user_id", ""),
    }
    try:
        LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry) + "\n")
    except Exception as e:
        logger.warning("session-end-logger: could not write log: %s", e)
    logger.debug("session-end: platform=%s session=%s", entry["platform"], entry["session"])