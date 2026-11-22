# cython: language_level=3
# distutils: language = c++

from libc.stdint cimport *
from libcpp.string cimport string as cpp_string
from libcpp.vector cimport vector
from libcpp.pair cimport pair


from ..wrapper.ndi_structs cimport NDIlib_listener_event
from ..wrapper.ndi_send_listener cimport NDIlib_sender_t, NDIlib_send_listener_event
from ..wrapper.ndi_recv_listener cimport (
    # types
    NDIlib_recv_listener_instance_t,
    NDIlib_recv_listener_create_t,
    NDIlib_receiver_type_e,
    NDIlib_receiver_command_e,
    NDIlib_receiver_t,
    NDIlib_recv_listener_event,
    # functions
    NDIlib_recv_listener_get_events,
    NDIlib_recv_listener_free_events,
)
from ..wrapper.ndi_send_listener cimport (
    # types
    NDIlib_send_listener_instance_t,
    NDIlib_send_listener_create_t,
    NDIlib_sender_t,
    NDIlib_send_listener_event,
    # functions
    NDIlib_send_listener_get_events,
    NDIlib_send_listener_free_events,
)

from ..callback cimport Callback


# Fused type for listener create structs
ctypedef fused NDIlib_listener_create_ft:
    NDIlib_send_listener_create_t
    NDIlib_recv_listener_create_t


# Fused type for listener instances
ctypedef fused NDIlib_listener_instance_ft:
    NDIlib_send_listener_instance_t
    NDIlib_recv_listener_instance_t


# Fused type for peers
ctypedef fused NDIlib_peer_ft:
    NDIlib_sender_t
    NDIlib_receiver_t

cdef enum PeerEvent_e:
    PEER_ADDED
    PEER_REMOVED
    PEER_UPDATED

ctypedef pair[PeerEvent_e, cpp_string] PeerEventPair

# Result container for peer updates
cdef struct GetPeersResult_s:
    vector[PeerEventPair] events
    bint any_changed



cdef class BaseListener:
    cdef bytes _url_address_bytes
    cdef bint _use_default_url_address
    cdef readonly bint auto_subscribe
    cdef dict _discovered_peers
    cdef Callback _peer_callback
    cdef Callback _event_callback

    cdef int _open(self) except -1
    cdef int _close(self) except -1
    cdef bint _is_connected(self) except -1 nogil
    cdef int _ensure_open(self) except -1 nogil
    cdef cpp_string _get_url_address(self)
    cdef bint _get_peers(self) except -1
    cdef dict _fill_peers_result_internal(self, GetPeersResult_s* get_peers_result)
    cdef bint _wait_for_peer_change(self, uint32_t timeout_ms) except -1 nogil
    cdef int _subscribe_events(self, const char* peer_uuid) except -1 nogil
    cdef int _unsubscribe_events(self, const char* peer_uuid) except -1 nogil
    cdef list _get_events(self, uint32_t timeout_ms)
    cdef _trigger_peer_callback(self, str event_type, object discovered_peer)
    cdef _trigger_event_callback(self, object event)



cdef _DiscoveredPeer_from_ptr(const NDIlib_peer_ft* peer)
cdef _ListenerEvent_from_ptr(const NDIlib_listener_instance_ft instance, const NDIlib_listener_event* event)
cdef list _get_events_for_instance_ptr(const NDIlib_listener_instance_ft instance, uint32_t timeout_ms)
cdef dict _get_and_update_peers(
    const NDIlib_peer_ft* p_peers,
    uint32_t p_num_peers,
    dict discovered_peers,
    GetPeersResult_s* get_peers_result
)
