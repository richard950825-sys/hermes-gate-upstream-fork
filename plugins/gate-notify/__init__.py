import json
import time
from datetime import datetime
from pathlib import Path

SIGNAL_DIR = Path.home() / ".hermes" / "gate-signals"
MAX_AGE_SECONDS = 600  # Auto-delete signal files older than 10 minutes


def on_complete(session_id, user_message, assistant_response, **kwargs):
    SIGNAL_DIR.mkdir(parents=True, exist_ok=True)

    # Cleanup stale files on every write
    now = time.time()
    for f in SIGNAL_DIR.glob("done-*.json"):
        try:
            if now - f.stat().st_mtime > MAX_AGE_SECONDS:
                f.unlink()
        except OSError:
            pass

    signal = {
        "session_id": session_id,
        "timestamp": datetime.now().isoformat(),
        "message_preview": (user_message or "")[:80],
        "response_preview": (assistant_response or "")[:80],
    }
    fname = f"done-{datetime.now().strftime('%Y%m%d%H%M%S%f')}.json"
    (SIGNAL_DIR / fname).write_text(json.dumps(signal))


def register(ctx):
    ctx.register_hook("post_llm_call", on_complete)
