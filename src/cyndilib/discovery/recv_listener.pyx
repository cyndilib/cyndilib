# cython: language_level=3
# distutils: language = c++

"""
Wrapper module for the |NDI| :term:`Receive Listener` API

.. versionadded:: 0.1.4
"""


from .exceptions import InvalidStateError, DiscoveryServerNotFoundError
from .types import (
    DiscoveredReceiver,
    ReceiveListenerEvent,
    ReceiverEventCallback,
)

from .base_listener cimport (
    GetPeersResult_s,
    _get_events_for_instance_ptr,
    _get_and_update_peers,
)



cdef class RecvListener(BaseListener):
    """A wrapper for the |NDI| :term:`Receive Listener` API

    Arguments:
        url_address (str | None): The URL address to use for the listener.
            Port numbers may be specified using the format ``"address:port"``.
            If no port is specified, the default port of 5959 will be used.
            If None (the default), the URL address from the
            :term:`Discovery Configuration` will be used.
        auto_subscribe (bool): Whether the listener should automatically
            subscribe to discovered receivers. Defaults to True.


    After initialization, the listener can be opened using the :meth:`open` method
    and closed using the :meth:`close` method.
    This class also implements the context manager protocol, allowing use with the
    :keyword:`with` statement:

    >>> with RecvListener() as recv_listener:
    ...     ...

    After opening the listener, the :meth:`get_receivers` method can be used to
    retrieve the list of currently discovered receivers.  This should be done periodically
    to keep track of changes from the network.

    To wait until a change in the list of discovered receivers occurs, the
    :meth:`wait_for_receiver_change` method can be used with a specified timeout.

    To receive events related to discovered receivers, the :meth:`get_events` method
    can be used with a specified timeout.  This should also be done periodically.

    If :attr:`auto_subscribe` is set to True, the listener will automatically subscribe
    to discovered receivers. Otherwise, manual subscription is required using the
    :meth:`subscribe` method.  The :meth:`unsubscribe` method can be used to stop
    receiving events from a particular receiver.


    The :class:`.DiscoveredReceiver` instances can also be accessed via the :meth:`get`
    method or by subscript access using the receiver's :attr:`UUID <.DiscoveredReceiver.uuid>`:

    >>> recv_listener[b'd5bd1191-1b32-4bee-a5d0-9f5b95d4cd30']
    ... ...

    or via iteration:

    >>> for receiver in recv_listener:
    ...     ...


    Attributes:
        auto_subscribe (bool): Indicates whether the listener automatically
            subscribes to discovered receivers.
    """
    __orig_bases__ = (BaseListener[DiscoveredReceiver, ReceiveListenerEvent],)
    __parameters__ = ()

    def __cinit__(self, *args, **kwargs):
        self._instance = NULL
        self._create_settings.p_url_address = b''

    def __init__(self, url_address: str | None = None, auto_subscribe: bool = True):
        super().__init__(url_address, auto_subscribe)
        if not self._use_default_url_address:
            self._create_settings.p_url_address = self._url_address_bytes

    def __dealloc__(self):
        cdef NDIlib_recv_listener_instance_t instance = self._instance
        self._instance = NULL
        if instance != NULL:
            NDIlib_recv_listener_destroy(instance)

    cdef int _open(self) except -1:
        if self._instance != NULL:
            raise InvalidStateError("Recv listener is already open")
        self._discovered_peers.clear()
        if self._use_default_url_address:
            self._instance = NDIlib_recv_listener_create()
        else:
            self._instance = NDIlib_recv_listener_create(&self._create_settings)
        if self._instance == NULL:
            raise DiscoveryServerNotFoundError("Failed to create listener")
        return 0

    cdef int _close(self) except -1:
        cdef NDIlib_recv_listener_instance_t instance = self._instance
        self._instance = NULL
        if instance != NULL:
            NDIlib_recv_listener_destroy(instance)
        self._discovered_peers.clear()
        return 0

    cdef bint _is_open(self) except -1 nogil:
        return self._instance != NULL

    cdef bint _is_connected(self) except -1 nogil:
        if self._instance == NULL:
            return False
        return NDIlib_recv_listener_is_connected(self._instance)

    cdef int _ensure_open(self) except -1 nogil:
        """Convenience method to ensure that the listener is open
        """
        if self._instance == NULL:
            raise InvalidStateError("Recv listener is not open")
        return 0

    cdef cpp_string _get_url_address(self):
        self._ensure_open()
        cdef const char* server_url = NDIlib_recv_listener_get_server_url(self._instance)
        if server_url == NULL:
            return cpp_string()
        return cpp_string(server_url)

    cdef dict _fill_peers_result_internal(self, GetPeersResult_s* get_peers_result):
        # Fill peers result for recv listener so it can be processed by
        # `BaseListener._get_peers`
        self._ensure_open()
        cdef uint32_t p_num_peers = 0
        cdef const NDIlib_receiver_t* p_peers = NDIlib_recv_listener_get_receivers(
            self._instance, &p_num_peers
        )
        cdef dict current_peers = self._discovered_peers
        cdef dict new_peers = _get_and_update_peers(
            p_peers=p_peers,
            p_num_peers=p_num_peers,
            discovered_peers=current_peers,
            get_peers_result=get_peers_result,
        )
        return new_peers

    cdef bint _wait_for_peer_change(self, uint32_t timeout_ms) except -1 nogil:
        self._ensure_open()
        with nogil:
            return NDIlib_recv_listener_wait_for_receivers(self._instance, timeout_ms)

    cdef int _subscribe_events(self, const char* sender_uuid) except -1 nogil:
        self._ensure_open()
        NDIlib_recv_listener_subscribe_events(self._instance, sender_uuid)
        return 0

    cdef int _unsubscribe_events(self, const char* sender_uuid) except -1 nogil:
        self._ensure_open()
        NDIlib_recv_listener_unsubscribe_events(self._instance, sender_uuid)
        return 0

    cdef list _get_events(self, uint32_t timeout_ms):
        # Instead of `self._ensure_open()`, get a local instance pointer
        # and check its state.
        # This is to avoid calling `NDIlib_recv_listener_free_events`
        # with a possibly NULL instance pointer.
        cdef NDIlib_recv_listener_instance_t instance = self._instance
        if instance == NULL:
            raise InvalidStateError("Recv listener is not open")
        cdef list results = _get_events_for_instance_ptr(instance, timeout_ms)
        for event in results:
            self._trigger_event_callback(event)
        return results
