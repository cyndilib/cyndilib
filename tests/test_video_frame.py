import time
import numpy as np
import pytest
from fractions import Fraction

from cyndilib.video_frame import VideoFrame, VideoRecvFrame, VideoSendFrame, VideoFrameSync
from cyndilib.wrapper import FourCC
from _test_video_frame import (             # type: ignore[missing-import]
    build_test_frame, build_test_frames,
    buffer_into_video_frame, video_frame_process_events,
)
from _test_send_frame_status import (       # type: ignore[missing-import]
    set_send_frame_sender_status, set_send_frame_send_complete,
    check_video_send_frame, get_null_idx, get_max_frame_buffers,
)
from _framesync_helpers import (   # type: ignore[missing-import]
    VideoFrameSyncHelper
)
from conftest import VideoParams

MAX_FRAME_BUFFERS = get_max_frame_buffers()
NULL_INDEX = get_null_idx()

def test():
    width, height = 1920, 1080

    vf = VideoRecvFrame()
    for i in range(30):
        expected_data = build_test_frame(width, height, False, True, False, i)
        buffer_into_video_frame(vf, width, height, expected_data)
        assert vf.get_buffer_depth() == 1
        assert vf.get_view_count() == 0
        assert vf.get_buffer_size() == width * height * 4
        result = np.frombuffer(vf, dtype=np.uint8)
        assert vf.get_view_count() == 1
        result = result.copy()
        assert vf.get_buffer_depth() == 0
        assert result.size == expected_data.size
        assert np.array_equal(result, expected_data)



def test_frame_builder():
    width, height = 640, 360
    num_frames = 160

    a = arr_uint32 = build_test_frame(width, height, True, False, False)
    b = arr_uint8_flat = build_test_frame(width, height, False, True, False)
    c = arr_struct = build_test_frame(width, height, False, False, True)
    d = arr_uint8_3d = build_test_frame(width, height, False, False, False)

    assert a.tobytes() == b.tobytes() == c.tobytes() == d.tobytes()

    a = arr_uint32 = build_test_frames(width, height, num_frames, True, False, False)
    b = arr_uint8_flat = build_test_frames(width, height, num_frames, False, True, False)
    c = arr_struct = build_test_frames(width, height, num_frames, False, False, True)
    d = arr_uint8_3d = build_test_frames(width, height, num_frames, False, False, False)

    x_inc = width // num_frames
    for i in range(num_frames):
        x_offset = i * x_inc
        f = build_test_frame(width, height, False, False, False, x_offset)
        assert a[i].tobytes() == f.tobytes()
        assert a[i].tobytes() == b[i].tobytes() == c[i].tobytes() == d[i].tobytes()


def test_video_send_frame(fake_video_frames: VideoParams):
    width, height, fr, num_frames, fake_frames = fake_video_frames

    vf = VideoSendFrame()
    vf.set_fourcc(FourCC.RGBA)
    vf.set_frame_rate(fr)
    vf.set_resolution(width, height)

    expected_write_idx = 0
    expected_read_idx = NULL_INDEX

    assert vf.ndim == 1
    assert vf.shape == (0,)
    assert vf.write_index == expected_write_idx
    assert vf.read_index == expected_read_idx


    set_send_frame_sender_status(vf, True)
    assert vf.write_index == expected_write_idx
    assert vf.read_index == expected_read_idx
    check_video_send_frame(vf)

    for i in range(num_frames):
        print(f'{i=}')
        assert vf.write_index == expected_write_idx
        assert vf.read_index == expected_read_idx

        vf.write_data(fake_frames[i])

        expected_read_idx = expected_write_idx
        expected_write_idx = (expected_write_idx + 1) % MAX_FRAME_BUFFERS
        assert vf.write_index == expected_write_idx
        assert vf.read_index == expected_read_idx
        check_video_send_frame(vf)

        set_send_frame_send_complete(vf)

        expected_read_idx = NULL_INDEX
        assert vf.write_index == expected_write_idx
        assert vf.read_index == expected_read_idx
        check_video_send_frame(vf)

    set_send_frame_sender_status(vf, False)

    vf.destroy()
    assert vf.write_index == 0
    assert vf.read_index == NULL_INDEX


@pytest.fixture(
    params=[
        (0, 0),
        (640, 360),
        (1280, 720),
        (1920, 1080),
        (2560, 1440),
        (3840, 2160),
    ]
)
def video_resolution_with_zeros(request) -> tuple[int, int]:
    """Include a resolution beyond the `video_resolution` fixture, but with
    zero dimensions to test handling of edge cases.
    """
    return request.param

@pytest.fixture(
    params=[
        Fraction(24, 1),
        Fraction(25, 1),
        Fraction(30, 1),
        Fraction(30000, 1001),  # ~29.97
        Fraction(60, 1),
        Fraction(60000, 1001),  # ~59.94
    ]
)
def video_frame_rate_extended(request) -> Fraction:
    """Extra frame rates to test beyond the common ones found in the
    `video_frame_rate` fixture.

    Added here to avoid adding more time-consuming test cases to the rest of
    the test suite.
    """
    return request.param


@pytest.mark.parametrize(['is_progressive'], [
    (True,),
    (False,),
])
def test_video_frame_format_string(
    video_resolution_with_zeros: tuple[int, int],
    video_frame_rate_extended: Fraction,
    is_progressive: bool
):
    width, height = video_resolution_with_zeros
    fr = video_frame_rate_extended
    vf = VideoFrame()
    vf.set_resolution(width, height)
    vf.set_frame_rate(fr)
    vf.set_progressive(is_progressive)
    fr_float = float(fr)
    if fr_float % 1 == 0:
        fr_str = f'{fr_float:.0f}'
    else:
        fr_str = f'{fr_float:.2f}'
    field_str = 'p' if is_progressive else 'i'
    if height == 0:
        expected_fmt_str = 'unknown'
    else:
        expected_fmt_str = f'{height}{field_str}{fr_str}'
    assert vf.get_format_string() == expected_fmt_str


def test_frame_sync(fake_video_frames: VideoParams):
    width, height, fr, num_frames, fake_frames = fake_video_frames

    vf = VideoFrameSync()
    vf.set_frame_rate(fr)
    vf.set_fourcc(FourCC.RGBA)

    fs_helper = VideoFrameSyncHelper()
    fs_helper.set_video_frame(vf)

    timestamps = np.arange(num_frames) * (1 / float(fr))

    results = np.zeros_like(fake_frames)

    for i in range(num_frames):
        fs_helper.fill_data(
            fake_frames[i], width, height, timestamps[i]
        )
        assert fs_helper.num_outstanding == 1
        r = vf.get_array()
        results[i] = r.copy()
        assert fs_helper.num_outstanding == 0
        assert vf.get_timestamp_posix() == pytest.approx(timestamps[i], abs=1e-7)

    assert np.array_equal(results, fake_frames)
