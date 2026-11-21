# cython: language_level=3
# distutils: language = c++

from libc.stdint cimport *
from libcpp.string cimport string as cpp_string


from ..wrapper.ndi_structs cimport NDIlib_listener_event
from ..wrapper.ndi_recv_listener cimport (
    # types
    NDIlib_recv_listener_instance_t,
    NDIlib_recv_listener_create_t,
    NDIlib_receiver_type_e,
    NDIlib_receiver_command_e,
    NDIlib_receiver_t,
    NDIlib_recv_listener_event,
    # functions
    NDIlib_recv_listener_create,
    NDIlib_recv_listener_destroy,
    NDIlib_recv_listener_is_connected,
    NDIlib_recv_listener_get_server_url,
    NDIlib_recv_listener_get_receivers,
    NDIlib_recv_listener_wait_for_receivers,
    NDIlib_recv_listener_subscribe_events,
    NDIlib_recv_listener_unsubscribe_events,
    NDIlib_recv_listener_get_events,
    NDIlib_recv_listener_free_events,
    NDIlib_recv_listener_send_connect
)

from ..callback cimport Callback
from .base_listener cimport BaseListener



cdef class RecvListener(BaseListener):
    cdef NDIlib_recv_listener_create_t _create_settings
    cdef NDIlib_recv_listener_instance_t _instance
