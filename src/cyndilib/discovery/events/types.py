from typing import Literal

__all__ = ["ReceiverEventName", "SenderEventName"]

SenderEventName = Literal[
    "source-name",
    "source-url",
    "connection-state",
    "connected-receivers",
    "metadata-frames-sent",
    "metadata-bytes-sent",
    "audio-present",
    "audio-codec",
    "audio-channels",
    "audio-sample-rate",
    "audio-frames-sent",
    "audio-bytes-sent",
    "video-present",
    "video-codec",
    "video-resolution",
    "video-frame-rate",
    "video-frame-type",
    "video-has-alpha",
    "video-color-primaries",
    "video-transfer-function",
    "video-matrix-coefficients",
    "video-frames-sent",
    "video-bytes-sent",
    "tally-on-program",
    "tally-on-preview",
    "sdk-version"
]
"""Event names used in the :term:`Send Listener` API"""

ReceiverEventName = Literal[
    "source-name",
    "source-url",
    "connection-state",
    "audio-present",
    "audio-codec",
    "audio-channels",
    "audio-sample-rate",
    "audio-receive-mode",
    "video-present",
    "video-codec",
    "video-resolution",
    "video-frame-rate",
    "video-frame-type",
    "video-has-alpha",
    "video-color-primaries",
    "video-transfer-function",
    "video-matrix-coefficients",
    "video-receive-mode",
    "sdk-version"
]
"""Event names used in the :term:`Receive Listener` API"""
