"""
File-based event bus for kanban state changes.

Instead of agents polling the kanban DB on cron intervals, state changes
write to a shared event file that agents check before starting work.
Eliminates the polling lag that causes stale context windows.

Usage:
    from kanban_event_bus import EventBus
    
    bus = EventBus(board_slug="rollsiege")
    
    # When a task changes state (called by the kanban tool layer):
    bus.emit("task_completed", {"task_id": "t_abc123", "title": "Fix login"})
    
    # When an agent starts work:
    events = bus.get_events(since=last_check_timestamp)
    for event in events:
        if event["type"] == "task_completed":
            # React to the state change immediately
            ...

Storage: ~/.hermes/kanban/events/<board_slug>.jsonl
Format: JSON Lines, one event per line
Retention: Events older than 24h are pruned on read
"""

from __future__ import annotations
import json
import time
import os
from pathlib import Path
from typing import Optional

EVENTS_DIR = Path.home() / ".hermes" / "kanban" / "events"
RETENTION_SECONDS = 86400  # 24 hours


class EventBus:
    def __init__(self, board_slug: str):
        self.board_slug = board_slug
        self.events_dir = EVENTS_DIR
        self.events_dir.mkdir(parents=True, exist_ok=True)
        self.events_file = self.events_dir / f"{board_slug}.jsonl"

    def emit(self, event_type: str, data: dict) -> dict:
        """Emit a state change event.
        
        Args:
            event_type: Type of event (task_completed, task_blocked, task_created, etc.)
            data: Event-specific data (task_id, title, assignee, etc.)
        
        Returns:
            The event dict that was written
        """
        event = {
            "timestamp": int(time.time()),
            "type": event_type,
            "board": self.board_slug,
            "data": data,
        }
        with open(self.events_file, "a") as f:
            f.write(json.dumps(event) + "\n")
        return event

    def get_events(
        self,
        since: Optional[int] = None,
        event_type: Optional[str] = None,
        limit: int = 100,
    ) -> list[dict]:
        """Get events, optionally filtered by time and type.
        
        Args:
            since: Only return events after this timestamp (unix epoch)
            event_type: Only return events of this type
            limit: Max events to return (most recent first)
        
        Returns:
            List of event dicts, sorted oldest-first
        """
        events = self._read_all()
        
        if since is not None:
            events = [e for e in events if e["timestamp"] > since]
        
        if event_type is not None:
            events = [e for e in events if e["type"] == event_type]
        
        # Return most recent first, limited
        events.sort(key=lambda e: e["timestamp"], reverse=True)
        events = events[:limit]
        events.sort(key=lambda e: e["timestamp"])  # oldest-first for processing
        
        return events

    def get_latest(self) -> Optional[dict]:
        """Get the single most recent event, or None."""
        events = self._read_all()
        if not events:
            return None
        return max(events, key=lambda e: e["timestamp"])

    def prune_old(self) -> int:
        """Remove events older than RETENTION_SECONDS. Returns count removed."""
        cutoff = int(time.time()) - RETENTION_SECONDS
        events = self._read_all()
        kept = [e for e in events if e["timestamp"] >= cutoff]
        removed = len(events) - len(kept)
        if removed > 0:
            self._write_all(kept)
        return removed

    def _read_all(self) -> list[dict]:
        """Read all events from the JSONL file."""
        if not self.events_file.exists():
            return []
        events = []
        with open(self.events_file, "r") as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        events.append(json.loads(line))
                    except json.JSONDecodeError:
                        continue  # Skip corrupted lines
        return events

    def _write_all(self, events: list[dict]) -> None:
        """Overwrite the events file with the given list."""
        with open(self.events_file, "w") as f:
            for event in events:
                f.write(json.dumps(event) + "\n")


# --- Convenience functions for common kanban events ---

def emit_task_completed(board_slug: str, task_id: str, title: str, assignee: str, summary: str = "") -> dict:
    bus = EventBus(board_slug)
    return bus.emit("task_completed", {
        "task_id": task_id,
        "title": title,
        "assignee": assignee,
        "summary": summary,
    })

def emit_task_blocked(board_slug: str, task_id: str, title: str, reason: str) -> dict:
    bus = EventBus(board_slug)
    return bus.emit("task_blocked", {
        "task_id": task_id,
        "title": title,
        "reason": reason,
    })

def emit_task_created(board_slug: str, task_id: str, title: str, assignee: str, parent_id: str = None) -> dict:
    bus = EventBus(board_slug)
    return bus.emit("task_created", {
        "task_id": task_id,
        "title": title,
        "assignee": assignee,
        "parent_id": parent_id,
    })

def emit_task_claimed(board_slug: str, task_id: str, title: str, assignee: str) -> dict:
    bus = EventBus(board_slug)
    return bus.emit("task_claimed", {
        "task_id": task_id,
        "title": title,
        "assignee": assignee,
    })
