from unittest.mock import MagicMock

import pytest

pytest.importorskip("textual")

from hermes_gate.app import HermesGateApp


def test_notify_formats_additive_payload_for_file_signal():
    app = HermesGateApp()
    notify_payloads = []

    app._emit_host_notification = lambda title, message, sound="complete.wav", **extra: notify_payloads.append(
        {"title": title, "message": message, "sound": sound, **extra}
    )

    app._notify("gate-7", "Assistant finished the requested fix")

    assert notify_payloads == [
        {
            "title": "Hermes Gate",
            "message": "Hermes gate-7: Assistant finished the requested fix",
            "sound": "complete.wav",
            "session_name": "gate-7",
            "response_preview": "Assistant finished the requested fix",
        }
    ]


@pytest.mark.asyncio
async def test_check_completion_uses_response_preview_instead_of_message_preview():
    app = HermesGateApp()
    app.session_mgr = MagicMock()
    app.session_mgr.check_completion_signals = MagicMock(
        return_value=[
            {
                "session_id": 3,
                "message_preview": "old user prompt",
                "response_preview": "new assistant response",
            }
        ]
    )
    app._notify = MagicMock()

    await HermesGateApp._check_completion.__wrapped__(app)

    app._notify.assert_called_once_with("gate-3", "new assistant response")


@pytest.mark.asyncio
async def test_check_completion_falls_back_when_response_preview_missing():
    app = HermesGateApp()
    app.session_mgr = MagicMock()
    app.session_mgr.check_completion_signals = MagicMock(
        return_value=[{"session_id": 5}]
    )
    app._notify = MagicMock()

    await HermesGateApp._check_completion.__wrapped__(app)

    app._notify.assert_called_once_with("gate-5", "task completed")


def test_get_preview_prefers_response_preview_then_message_preview_then_default():
    app = HermesGateApp()

    assert (
        app._get_preview(
            {"response_preview": "assistant reply", "message_preview": "user prompt"}
        )
        == "assistant reply"
    )
    assert app._get_preview({"message_preview": "user prompt"}) == "user prompt"
    assert app._get_preview({}) == "task completed"


def test_start_bg_poll_uses_notify_path_instead_of_file_only_signal() -> None:
    app = HermesGateApp()
    app._notify = MagicMock()

    class _Mgr:
        def __init__(self) -> None:
            self.calls = 0

        def check_completion_signals(self):
            self.calls += 1
            if self.calls == 1:
                return [{"session_id": 8, "response_preview": "done"}]
            app._bg_poll_stop.set()
            return []

    mgr = _Mgr()
    app._start_bg_poll(mgr)
    app._bg_poll_thread.join(timeout=2)

    app._notify.assert_called_once_with("gate-8", "done")
