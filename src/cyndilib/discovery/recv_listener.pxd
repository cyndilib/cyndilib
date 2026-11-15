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


cdef class RecvListener:
    cdef NDIlib_recv_listener_create_t _create_settings
    cdef NDIlib_recv_listener_instance_t _instance
    cdef bytes _url_address_bytes
    cdef bint _use_default_url_address
    cdef readonly bint auto_subscribe
    cdef dict _discovered_receivers
    cdef Callback _receiver_callback
    cdef Callback _event_callback

    cdef int _open(self) except -1
    cdef int _close(self) except -1
    cdef bint _is_connected(self) except -1 nogil
    cdef int _ensure_open(self) except -1 nogil
    cdef cpp_string _get_url_address(self)
    cdef bint _get_receivers(self) except -1
    cdef bint _wait_for_receiver_change(self, uint32_t timeout_ms) except -1 nogil
    cdef int _subscribe_events(self, const char* sender_uuid) except -1 nogil
    cdef int _unsubscribe_events(self, const char* sender_uuid) except -1 nogil
    cdef list _get_events(self, uint32_t timeout_ms)
    cdef _trigger_receiver_callback(self, str event_type, object discovered_receiver)
    cdef _trigger_event_callback(self, object event)
