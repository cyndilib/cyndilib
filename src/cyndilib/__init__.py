import importlib.resources as importlib_resources
import os
import sys

if sys.platform == 'win32':
    dll_dir = importlib_resources.files('cyndilib') / 'wrapper' / 'bin'
    os.add_dll_directory(dll_dir)

def get_include() -> str:
    return str(importlib_resources.files('cyndilib.wrapper.include'))


from .audio_frame import *
from .audio_reference import AudioReference
from .finder import Finder, Source
from .framesync import FrameSync
from .metadata_frame import *
from .receiver import Receiver
from .router import Router, RoutingMatrix
from .sender import Sender
from .video_frame import *
from .wrapper import (
    FourCC,
    FrameFormat,
    FrameType,
    RecvBandwidth,
    RecvColorFormat,
    get_ndi_version,
    ndi_version,
)

__all__ = [
    "AudioFrameSync",
    "AudioReference",
    "Finder",
    "FourCC",
    "FrameFormat",
    "FrameSync",
    "FrameType",
    "MetadataFrame",
    "Receiver",
    "RecvBandwidth",
    "RecvColorFormat",
    "Router",
    "RoutingMatrix",
    "Sender",
    "Source",
    "VideoFrameSync",
    "get_include",
    "get_ndi_version",
    "ndi_version",
]
