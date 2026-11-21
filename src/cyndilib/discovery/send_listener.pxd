# cython: language_level=3
# distutils: language = c++


from libc.stdint cimport *
from libcpp.string cimport string as cpp_string


from ..wrapper.ndi_structs cimport NDIlib_listener_event
from ..wrapper.ndi_send_listener cimport (
    # types
    NDIlib_send_listener_instance_t,
    NDIlib_send_listener_create_t,
    NDIlib_sender_t,
    NDIlib_send_listener_event,
    # functions
    NDIlib_send_listener_create,
    NDIlib_send_listener_destroy,
    NDIlib_send_listener_is_connected,
    NDIlib_send_listener_get_server_url,
    NDIlib_send_listener_get_senders,
    NDIlib_send_listener_wait_for_senders,
    NDIlib_send_listener_subscribe_events,
    NDIlib_send_listener_unsubscribe_events,
    NDIlib_send_listener_get_events,
    NDIlib_send_listener_free_events,
)
from ..callback cimport Callback
from .base_listener cimport BaseListener


cdef class SendListener(BaseListener):
    cdef NDIlib_send_listener_create_t _create_settings
    cdef NDIlib_send_listener_instance_t _instance
