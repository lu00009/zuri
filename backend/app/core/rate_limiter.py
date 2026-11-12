import time
from collections import defaultdict
from threading import Lock
from fastapi import HTTPException, status


class InMemoryRateLimiter:
    """
    Thread-safe in-memory sliding-window rate limiter for sensitive authentication actions.
    Tracks attempts by key (e.g., client IP or composite 'ip:email').
    """

    def __init__(self):
        self._attempts: dict[str, list[float]] = defaultdict(list)
        self._lock = Lock()

    def check_rate_limit(
        self,
        key: str,
        max_attempts: int = 5,
        window_seconds: int = 300,
        action_name: str = "requests",
    ) -> None:
        """
        Check if the key has exceeded max_attempts within window_seconds.
        Raises HTTPException(429) if exceeded.
        """
        now = time.time()
        cutoff = now - window_seconds

        with self._lock:
            # Filter out attempts older than window
            timestamps = [t for t in self._attempts[key] if t > cutoff]
            self._attempts[key] = timestamps

            if len(timestamps) >= max_attempts:
                wait_seconds = int(window_seconds - (now - timestamps[0]))
                wait_minutes = max(1, (wait_seconds + 59) // 60)
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail=(
                        f"Too many failed {action_name}. For security, this service has been "
                        f"temporarily locked. Please try again in {wait_minutes} minute{'s' if wait_minutes > 1 else ''}."
                    ),
                )

    def record_attempt(self, key: str) -> None:
        """Record a single attempt (e.g. failed login or recovery attempt)."""
        now = time.time()
        with self._lock:
            self._attempts[key].append(now)

    def reset(self, key: str) -> None:
        """Reset attempts for a key upon successful authentication."""
        with self._lock:
            self._attempts.pop(key, None)

    def clear_all(self) -> None:
        """Clear all rate limit tracking (primarily for testing)."""
        with self._lock:
            self._attempts.clear()


auth_rate_limiter = InMemoryRateLimiter()

