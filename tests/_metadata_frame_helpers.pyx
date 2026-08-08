# cython: language_level=3
# cython: linetrace=True
# cython: profile=True
# distutils: language = c++
# distutils: include_dirs=DISTUTILS_INCLUDE_DIRS
# distutils: extra_compile_args=DISTUTILS_EXTRA_COMPILE_ARGS
# distutils: define_macros=CYTHON_TRACE_NOGIL=1


from cyndilib.metadata_frame cimport MetadataFrame, MetadataRecvFrame, MetadataSendFrame
from cyndilib.wrapper.ndi_structs cimport NDIlib_metadata_frame_t
from cyndilib.wrapper.ndi_recv cimport NDIlib_recv_instance_t


def set_metadata_frame_data(MetadataRecvFrame frame, str xml_data) -> None:
    # We only need this for the method arguments, but it doesn't have to be a recv instance
    cdef NDIlib_recv_instance_t recv_ptr = NULL
    cdef NDIlib_metadata_frame_t* frame_ptr = frame.ptr
    cdef bytes data_bytes = xml_data.encode('UTF-8')
    frame_ptr.p_data = data_bytes
    frame_ptr.length = len(data_bytes)
    frame._prepare_incoming(recv_ptr)
    frame._process_incoming(recv_ptr)


def get_metadata_frame_data(MetadataFrame frame) -> str:
    cdef NDIlib_metadata_frame_t* frame_ptr = frame.ptr
    if frame_ptr.p_data is not NULL and frame_ptr.length > 0:
        return (<bytes>frame_ptr.p_data)[:frame_ptr.length - 1].decode('UTF-8')
    else:
        return ''
