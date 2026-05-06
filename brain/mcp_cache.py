"""brain/mcp_cache.py — In-memory LRU cache with TTL for read-only MCP tools."""

import json
import time

DEFAULT_TTL = 300  # seconds
MAX_SIZE = 100

_cache: dict[str, tuple[dict, float]] = {}  # key → (result, expiry)
_hits = 0
_misses = 0


def _make_key(tool_name: str, args: dict | None) -> str:
    return tool_name + ":" + json.dumps(args or {}, sort_keys=True)


def cache_get(tool_name: str, args: dict | None) -> dict | None:
    global _hits, _misses
    key = _make_key(tool_name, args)
    entry = _cache.get(key)
    if entry is None or entry[1] < time.monotonic():
        if entry is not None:
            del _cache[key]  # expired
        _misses += 1
        return None
    _hits += 1
    return entry[0]


def cache_set(tool_name: str, args: dict | None, result: dict,
              ttl: int = DEFAULT_TTL) -> None:
    key = _make_key(tool_name, args)
    if len(_cache) >= MAX_SIZE and key not in _cache:
        oldest_key = next(iter(_cache))
        del _cache[oldest_key]
    _cache[key] = (result, time.monotonic() + ttl)


def cache_clear() -> None:
    _cache.clear()


def cache_stats() -> dict:
    return {"hits": _hits, "misses": _misses, "size": len(_cache)}
