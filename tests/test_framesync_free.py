"""FrameSync captures must be handed back to the SDK even when they are never read (#147).

No NDI source needed: a real ``FrameSync`` (from a ``Receiver`` with no source),
whose frame's free function is swapped for the counting one of
``_framesync_helpers`` — every "allocation" is a simulated capture
(``fill_data``), every free is counted instead of reaching the SDK.
"""
import numpy as np
import pytest

from cyndilib.audio_frame import AudioFrameSync
from cyndilib.receiver import Receiver
from cyndilib.video_frame import VideoFrameSync
from cyndilib.wrapper import FourCC
from _framesync_helpers import AudioFrameSyncHelper, VideoFrameSyncHelper

WIDTH, HEIGHT = 64, 32


def _video():
    receiver = Receiver()
    vf = VideoFrameSync()
    receiver.frame_sync.set_video_frame(vf)
    helper = VideoFrameSyncHelper()
    helper.set_video_frame(vf)  # count frees instead of calling NDIlib_framesync_free_video
    return receiver, vf, helper


def _fill(helper, i=0):
    """Simulate a capture: a frame the FrameSync now holds."""
    # A real capture with no source leaves an empty frame (no FourCC) behind.
    helper.video_frame.set_fourcc(FourCC.UYVY)
    helper.fill_data(np.full(WIDTH * HEIGHT * 2, i % 256, np.uint8), WIDTH, HEIGHT, float(i))


def test_unread_capture_is_freed_by_the_next_capture():
    receiver, vf, helper = _video()
    _fill(helper)
    assert helper.num_outstanding == 1
    receiver.frame_sync.capture_video()  # real capture call (no source: nothing new arrives)
    assert helper.num_outstanding == 0


def test_many_unread_captures_dont_pile_up():
    receiver, vf, helper = _video()
    for i in range(50):
        _fill(helper, i)
        receiver.frame_sync.capture_video()
    assert helper.num_outstanding == 0
    assert helper.num_frees == helper.num_allocs == 50


def test_read_capture_is_not_freed_twice():
    receiver, vf, helper = _video()
    _fill(helper)
    vf.get_array()                       # reading releases the capture
    assert helper.num_frees == 1
    receiver.frame_sync.capture_video()  # must not free it again
    assert helper.num_frees == 1


def test_capture_with_a_view_held_raises_before_touching_the_frame():
    receiver, vf, helper = _video()
    _fill(helper, 7)
    view = memoryview(vf)
    with pytest.raises(ValueError, match="view active"):
        receiver.frame_sync.capture_video()
    assert helper.num_frees == 0                 # not freed under the view...
    assert np.asarray(view)[0] == 7              # ...nor overwritten by a new capture
    view.release()
    assert helper.num_outstanding == 0           # released with the view, as usual


def test_audio_capture_is_not_freed_twice():
    receiver = Receiver()
    af = AudioFrameSync()
    receiver.frame_sync.set_audio_frame(af)
    helper = AudioFrameSyncHelper()
    helper.set_audio_frame(af)
    helper.fill_data(np.zeros((2, 480), np.float32), 48000, 0.0)
    af.get_array()          # read: freed
    helper.free_previous()  # a second free attempt is a no-op
    assert helper.num_frees == helper.num_allocs == 1
