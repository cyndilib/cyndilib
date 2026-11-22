"""
Base module for wrapping the |NDI| :term:`Send Listener` and :term:`Receive Listener` API

.. versionadded:: 0.1.4
"""
from types import GenericAlias
from typing import Generic, NamedTuple, Iterator, Literal, Self
from collections.abc import Callable, KeysView, ItemsView, ValuesView


from .exceptions import InvalidStateError, DiscoveryServerNotFoundError
from .types import (
    DiscoveredPeerT,
    DiscoveredReceiver,
    DiscoveredSender,
    ListenerEventCallback,
    ListenerEventT,
    PeerCallback,
    ReceiveListenerEvent,
    SendListenerEvent,
)


cdef const uint32_t UINT32_NEGATIVE_ONE = 0xFFFFFFFF




cdef class BaseListener:
    """Base class for the |NDI| :term:`Send Listener` and :term:`Receive Listener` API

    Arguments:
        url_address (str | None): The URL address to use for the listener.
            Port numbers may be specified using the format ``"address:port"``.
            If no port is specified, the default port of 5959 will be used.
            If None (the default), the URL address from the
            :term:`Discovery Configuration` will be used.
        auto_subscribe (bool): Whether the listener should automatically
            subscribe to discovered peers. Defaults to True.

    Attributes:
        auto_subscribe (bool): Indicates whether the listener automatically
            subscribes to discovered peers.
    """

    # Set generic parameters manually since a cdef class can't use Generic directly.
    # This sets the class signature to:
    # BaseListener(Generic[DiscoveredPeerT, ListenerEventT])
    __parameters__ = (DiscoveredPeerT, ListenerEventT)
    __orig_bases__ = (Generic[DiscoveredPeerT, ListenerEventT],)
    @classmethod
    def __class_getitem__(cls, item):
        return GenericAlias(cls, item)

    def __init__(self, url_address: str | None = None, auto_subscribe: bool = True):
        if url_address is None:
            self._use_default_url_address = True
        else:
            self._use_default_url_address = False
            self._url_address_bytes = url_address.encode()
        self.auto_subscribe = auto_subscribe
        self._discovered_peers = {}
        self._peer_callback = Callback()
        self._event_callback = Callback()

    def open(self) -> None:
        """Open the listener

        Raises:
            InvalidStateError: If the listener is already open.
            DiscoveryServerNotFoundError: If the discovery server is not found or
                there was an error creating the listener.
        """
        self._open()

    def close(self) -> None:
        """Close the listener
        """
        self._close()

    def is_connected(self) -> bool:
        """Check if the listener is connected

        Returns:
            bool: True if connected, False otherwise.
        """
        return self._is_connected()

    def get_url_address(self) -> str:
        """Get the URL address of :term:`Discovery Server` that the
        listener is connected to.

        Returns:
            str: The URL address as a string. Returns an empty string if the
            connection to the :term:`Discovery Server` could not be established.

        Raises:
            InvalidStateError: If the listener is not open.
        """
        cdef cpp_string url_address = self._get_url_address()
        if url_address.empty():
            return ''
        return url_address.decode('utf-8')

    def set_peer_callback(self, cb: PeerCallback[DiscoveredPeerT]) -> None:
        """Set the callback for peer events

        This can be used to track when peers are added, removed, or updated.

        Arguments:
            cb: The function to be called when a
                peer event occurs.

        .. warning::
            The :meth:`close` method should **never** be called inside of this callback.

            This could lead to undefined behavior.

        """
        self._peer_callback.set_callback(cb)

    def remove_peer_callback(self) -> None:
        """Remove the callback previously set through :meth:`set_peer_callback`
        """
        self._peer_callback.remove_callback()

    def set_event_callback(self, cb: ListenerEventCallback[ListenerEventT]) -> None:
        """Set the callback for listener events

        This can be used for handling events from discovered peers and is
        invoked for each event during a call to :meth:`get_events`.

        Arguments:
            cb: The function to be called when a listener event occurs.


        .. warning::
            The :meth:`close` method should **never** be called inside of this callback.

            This could lead to undefined behavior.

        """
        self._event_callback.set_callback(cb)

    def remove_event_callback(self) -> None:
        """Remove the event callback previously set through :meth:`set_event_callback`
        """
        self._event_callback.remove_callback()

    def get_peers(self) -> tuple[list[DiscoveredPeerT], bool]:
        """Update and get the list of discovered peers

        Each item in the returned list will be an instance of :obj:`.DiscoveredPeerT`.

        Since :obj:`.DiscoveredPeerT` is a :class:`~typing.NamedTuple`,
        it is immutable and each subsequent call to this method may contain different
        instances of the same peer.

        Use the :attr:`~.DiscoveredSender.uuid` attribute to uniquely identify each peer.


        .. danger::

            This method should **not** be called more than once concurrently
            (i.e., it is not thread-safe).

            The internal memory structures used in this method are only
            valid within a single call to this method.

            Once this method returns, all internal references have been copied
            and are safe.

        Returns:
            A tuple containing the list of discovered peers and a boolean indicating
            if the any item has changed since the last call.

        Raises:
            InvalidStateError: If the listener is not open.
        """
        changed = self._get_peers()
        return list(self._discovered_peers.values()), changed

    def wait_for_peer_change(self, float timeout) -> bool:
        """Wait for a change in the list of discovered peers

        If *timeout* is 0, this method will not block and will return
        whether a peer change has occurred.  Otherwise, it will block
        until a change occurs or the timeout is reached.

        Arguments:
            timeout: The maximum time to wait for a peer change, in seconds.

        Returns:
            bool: True if a peer change occurred within the timeout, False otherwise.

        Raises:
            InvalidStateError: If the listener is not open.
        """
        if timeout < 0:
            raise ValueError("Timeout must be non-negative")
        cdef uint32_t timeout_ms = round(timeout * 1000)
        return self._wait_for_peer_change(timeout_ms)

    def get_events(self, float timeout) -> list[tuple[DiscoveredPeerT, ListenerEventT]]:
        """Get the list of listener events within the specified timeout

        If *timeout* is any positive value, the method will block until
        an event is available or the timeout is reached.
        If *timeout* is 0, the method will not block and any available events
        will be returned immediately.
        If *timeout* is -1, the method will block indefinitely until at least
        one event is available.

        If a callback is set from :meth:`set_event_callback`, it will be invoked
        for each event received. The callbacks will occur before this method returns.

        Arguments:

            timeout: The maximum time to wait for events, in seconds.

        Returns:
            A list of tuples containing the peer and its corresponding event.

        Raises:
            InvalidStateError: If the listener is not open.
        """
        if timeout < -1:
            raise ValueError("Timeout must be -1 or non-negative")
        cdef uint32_t timeout_ms
        if timeout == -1:
            timeout_ms = UINT32_NEGATIVE_ONE
        else:
            timeout_ms = round(timeout * 1000)
        cdef list events = self._get_events(timeout_ms)
        cdef object event
        result = []
        for event in events:
            if event.uuid in self._discovered_peers:
                peer = self._discovered_peers[event.uuid]
                result.append((peer, event))
        return result

    def get_peer(self, uuid: str | bytes) -> DiscoveredPeerT | None:
        """Get the discovered peer with the given UUID

        This is equivalent to calling :meth:`get` with a default of None.

        Arguments:
            uuid: The UUID of the peer to retrieve.

        Returns:
            The discovered peer with the given UUID, or None if not found.
        """
        cdef bytes uuid_bytes
        if isinstance(uuid, str):
            uuid_bytes = uuid.encode('utf-8')
        else:
            uuid_bytes = uuid
        return self._discovered_peers.get(uuid_bytes)

    def get(
        self,
        uuid: str | bytes,
        default: DiscoveredPeerT | None = None
    ) -> DiscoveredPeerT | None:
        """Get the discovered peer with the given UUID or *default* if not found

        Arguments:
            uuid: The UUID of the peer to retrieve.
            default: The value to return if the peer is not found.

        Returns:
            The discovered peer with the given UUID,
            or the default if not found.
        """
        cdef bytes uuid_bytes
        if isinstance(uuid, str):
            uuid_bytes = uuid.encode('utf-8')
        else:
            uuid_bytes = uuid
        return self._discovered_peers.get(uuid_bytes, default)

    def subscribe(self, uuid: bytes) -> None:
        """Subscribe to events from the peer with the given UUID

        .. note::
            If :attr:`auto_subscribe` is enabled, it is not necessary to
            call this method manually.

        Arguments:
            uuid: The UUID of the peer to subscribe to.

        Raises:
            InvalidStateError: If the listener is not open.
        """
        self._subscribe_events(uuid)

    def unsubscribe(self, uuid: bytes) -> None:
        """Unsubscribe from events from the peer with the given UUID

        Arguments:
            uuid: The UUID of the peer to unsubscribe from.

        Raises:
            InvalidStateError: If the listener is not open.
        """
        self._unsubscribe_events(uuid)

    def keys(self) -> KeysView[bytes]:
        """Get a view of the discovered peer UUID's
        """
        return self._discovered_peers.copy().keys()

    def values(self) -> ValuesView[DiscoveredPeerT]:
        """Get a view of the discovered peer instances
        """
        return self._discovered_peers.copy().values()

    def items(self) -> ItemsView[bytes, DiscoveredPeerT]:
        """Get a view of the discovered peer UUID's
        and their corresponding discovered peer instances
        """
        return self._discovered_peers.copy().items()

    def __contains__(self, uuid: str | bytes) -> bool:
        cdef bytes uuid_bytes
        if isinstance(uuid, str):
            uuid_bytes = uuid.encode('utf-8')
        else:
            uuid_bytes = uuid
        return uuid_bytes in self._discovered_peers

    def __getitem__(self, uuid: str | bytes) -> DiscoveredPeerT:
        cdef bytes uuid_bytes
        if isinstance(uuid, str):
            uuid_bytes = uuid.encode('utf-8')
        else:
            uuid_bytes = uuid
        return self._discovered_peers[uuid_bytes]

    def __iter__(self) -> Iterator[DiscoveredPeerT]:
        yield from self._discovered_peers.copy().values()

    def __len__(self) -> int:
        return len(self._discovered_peers)

    def __enter__(self) -> Self:
        self._open()
        return self

    def __exit__(self, exc_type, exc_value, traceback) -> None:
        self._close()

    cdef int _open(self) except -1:
        raise NotImplementedError()

    cdef int _close(self) except -1:
        raise NotImplementedError()

    cdef bint _is_connected(self) except -1 nogil:
        raise NotImplementedError()

    cdef int _ensure_open(self) except -1 nogil:
        raise NotImplementedError()

    cdef cpp_string _get_url_address(self):
        raise NotImplementedError()

    cdef bint _get_peers(self) except -1:
        self._ensure_open()
        cdef GetPeersResult_s get_peers_result
        cdef dict current_peers = self._discovered_peers
        cdef dict new_peers = self._fill_peers_result_internal(&get_peers_result)

        if not get_peers_result.any_changed:
            return False

        events: list[tuple[str, DiscoveredPeerT]] = []

        cdef cpp_string uuid_cpp
        cdef bytes uuid_bytes
        cdef object peer_obj
        for event_pair in get_peers_result.events:
            uuid_cpp = event_pair.second
            uuid_bytes = uuid_cpp
            if event_pair.first == PeerEvent_e.PEER_ADDED:
                peer_obj = new_peers[uuid_bytes]
                events.append(("added", peer_obj))
                if self.auto_subscribe:
                    self._subscribe_events(uuid_cpp.c_str())
            elif event_pair.first == PeerEvent_e.PEER_UPDATED:
                peer_obj = new_peers[uuid_bytes]
                events.append(("updated", peer_obj))
            elif event_pair.first == PeerEvent_e.PEER_REMOVED:
                peer_obj = current_peers[uuid_bytes]
                events.append(("removed", peer_obj))
                self._unsubscribe_events(uuid_cpp.c_str())
            else:
                raise ValueError("Unknown event type")

        self._discovered_peers.clear()
        self._discovered_peers.update(new_peers)
        for event_type, peer_obj in events:
            self._trigger_peer_callback(event_type, peer_obj)

        return True

    cdef dict _fill_peers_result_internal(self, GetPeersResult_s* get_peers_result):
        """Use in subclasses to fill peers result with :func:`_get_and_update_peers`
        """
        raise NotImplementedError()

    cdef bint _wait_for_peer_change(self, uint32_t timeout_ms) except -1 nogil:
        raise NotImplementedError()

    cdef int _subscribe_events(self, const char* sender_uuid) except -1 nogil:
        raise NotImplementedError()

    cdef int _unsubscribe_events(self, const char* sender_uuid) except -1 nogil:
        raise NotImplementedError()

    cdef list _get_events(self, uint32_t timeout_ms):
        raise NotImplementedError()

    cdef _trigger_peer_callback(self, str event_type, object discovered_peer):
        cdef tuple callback_args = (event_type, discovered_peer)
        self._peer_callback.trigger_callback(callback_args)
        return 0

    cdef _trigger_event_callback(self, object event):
        cdef tuple callback_args = (event,)
        self._event_callback.trigger_callback(callback_args)
        return 0



cdef _DiscoveredPeer_from_ptr(const NDIlib_peer_ft* peer):
    """Create a discovered peer from a pointer

    Args:
        peer: The peer pointer as a fused type of `NDIlib_sender_t` or `NDIlib_receiver_t`

    Returns:
        discovered_peer (DiscoveredSender | DiscoveredReceiver): The created peer instance,
            depending on the *peer* type.
    """
    cdef bytes uuid = peer.p_uuid
    cdef str name = peer.p_name.decode('utf-8')
    cdef str address = peer.p_address.decode('utf-8')
    cdef bint events_subscribed = peer.events_subscribed
    cdef str metadata
    cdef int port
    cdef str group
    cdef list groups
    cdef list commands
    cdef bytes input_uuid
    cdef str input_name
    cdef list stream_types
    cdef NDIlib_receiver_type_e stream_type_ptr
    cdef NDIlib_receiver_command_e command_ptr
    cdef uint32_t i

    if NDIlib_peer_ft is NDIlib_sender_t:
        groups = []
        metadata = peer.p_metadata.decode('utf-8')
        port = peer.port
        for i in range(peer.num_groups):
            group = peer.p_groups[i].decode('utf-8')
            groups.append(group)
        return DiscoveredSender(
            uuid=uuid,
            name=name,
            address=address,
            metadata=metadata,
            port=port,
            groups=groups,
            events_subscribed=events_subscribed,
        )
    elif NDIlib_peer_ft is NDIlib_receiver_t:
        stream_types = []
        input_uuid = peer.p_input_uuid
        input_name = peer.p_input_name.decode('utf-8')
        for i in range(peer.num_streams):
            stream_type_ptr = peer.p_streams[i]
            if stream_type_ptr == NDIlib_receiver_type_e.NDIlib_receiver_type_none:
                continue
            if stream_type_ptr == NDIlib_receiver_type_e.NDIlib_receiver_type_metadata:
                stream_types.append("metadata")
            elif stream_type_ptr == NDIlib_receiver_type_e.NDIlib_receiver_type_video:
                stream_types.append("video")
            elif stream_type_ptr == NDIlib_receiver_type_e.NDIlib_receiver_type_audio:
                stream_types.append("audio")
            else:
                continue
        commands = []
        for i in range(peer.num_commands):
            command_ptr = peer.p_commands[i]
            if command_ptr == NDIlib_receiver_command_e.NDIlib_receiver_command_none:
                continue
            elif command_ptr == NDIlib_receiver_command_e.NDIlib_receiver_command_connect:
                commands.append("connect")
            else:
                continue
        return DiscoveredReceiver(
            uuid=uuid,
            name=name,
            input_uuid=input_uuid,
            input_name=input_name,
            address=address,
            stream_types=tuple(stream_types),
            commands=tuple(commands),
            events_subscribed=events_subscribed,
        )
    else:
        raise ValueError("Unknown peer type")



cdef _ListenerEvent_from_ptr(const NDIlib_listener_instance_ft instance, const NDIlib_listener_event* event):
    """Create a :class:`.ReceiveListenerEvent` or :class:`.SendListenerEvent`
    instance from an ``NDIlib_listener_event`` pointer

    Arguments:
        instance: The listener instance pointer as a fused type.
            This is used to select the appropriately-typed specialization.
        event: The listener event pointer

    Returns:
        listener_event (ReceiveListenerEvent | SendListenerEvent): The created event instance.
    """
    cdef bytes uuid = event.p_uuid
    cdef str name = event.p_name.decode('utf-8')
    cdef str value = event.p_value.decode('utf-8')
    if NDIlib_listener_instance_ft is NDIlib_recv_listener_instance_t:
        return ReceiveListenerEvent(uuid, name, value)
    elif NDIlib_listener_instance_ft is NDIlib_send_listener_instance_t:
        return SendListenerEvent(uuid, name, value)
    else:
        raise ValueError("Unknown listener type")


cdef list _get_events_for_instance_ptr(const NDIlib_listener_instance_ft instance, uint32_t timeout_ms):
    """Get events for a listener instance pointer

    Arguments:
        instance: The listener instance pointer as a fused type of
            `NDIlib_recv_listener_instance_t` or `NDIlib_send_listener_instance_t`
        timeout_ms: Timeout in milliseconds

    Returns:
        events (list[ReceiveListenerEvent | SendListenerEvent]): The events retrieved.
    """
    if instance == NULL:
        raise InvalidStateError("Listener is not open")
    cdef list results = []
    cdef uint32_t num_events = 0
    cdef const NDIlib_listener_event* p_events
    with nogil:
        # The following cases are compiled in for each specialization of the fused type.
        # They are not evaluated at runtime.
        if NDIlib_listener_instance_ft is NDIlib_recv_listener_instance_t:
            p_events = NDIlib_recv_listener_get_events(
                instance, &num_events, timeout_ms
            )
        elif NDIlib_listener_instance_ft is NDIlib_send_listener_instance_t:
            p_events = NDIlib_send_listener_get_events(
                instance, &num_events, timeout_ms
            )
        else:
            raise ValueError("Unknown listener type")
    if p_events == NULL:
        return results
    cdef object event
    cdef uint32_t i
    try:
        for i in range(num_events):
            event = _ListenerEvent_from_ptr(instance, &p_events[i])
            results.append(event)
    finally:
        # The following cases are compiled in for each specialization of the fused type.
        # They are not evaluated at runtime.
        if NDIlib_listener_instance_ft is NDIlib_recv_listener_instance_t:
            # Important!
            # `NDIlib_recv_listener_free_events` must be called after
            # each call to `NDIlib_recv_listener_get_events`.
            NDIlib_recv_listener_free_events(instance, p_events)
        elif NDIlib_listener_instance_ft is NDIlib_send_listener_instance_t:
            # Important!
            # `NDIlib_send_listener_free_events` must be called after
            # each call to `NDIlib_send_listener_get_events`.
            NDIlib_send_listener_free_events(instance, p_events)
        else:
            raise ValueError("Unknown listener type")
    return results


cdef dict _get_and_update_peers(
    const NDIlib_peer_ft* p_peers,
    uint32_t p_num_peers,
    dict discovered_peers,
    GetPeersResult_s* get_peers_result
):
    """Get peers and update result

    Arguments:
        p_peers: pointer to peers
        p_num_peers: number of peers
        discovered_peers: The current peers as a `dict[bytes, DiscoveredSender | DiscoveredReceiver]`.
            This will not be modified in place.
        get_peers_result: struct to store changes

    Returns: The new discovered peers dict
    """
    if not get_peers_result.events.empty():
        raise ValueError("Unexpected events")
    get_peers_result.any_changed = False
    cdef bint any_changed = False
    cdef dict discovered_peer_dict = {}
    cdef object discovered_peer
    cdef bytes peer_uuid_bytes
    if p_peers == NULL or p_num_peers == 0:
        # If there are no receivers, clear all and trigger removed callbacks
        for discovered_peer in discovered_peers.values():
            peer_uuid_bytes = discovered_peer.uuid
            get_peers_result.events.push_back(
                (PeerEvent_e.PEER_REMOVED, peer_uuid_bytes)
            )
            any_changed = True
        get_peers_result.any_changed = any_changed
        return discovered_peer_dict

    cdef uint32_t i
    cdef object new_discovered_peer
    cdef bint existing = False
    cdef bint changed = False
    cdef set previous_uuids_bytes = set(discovered_peers.keys())
    for i in range(p_num_peers):
        peer_uuid_bytes = p_peers[i].p_uuid
        existing = peer_uuid_bytes in previous_uuids_bytes
        if existing:
            discovered_peer = discovered_peers[peer_uuid_bytes]
            new_discovered_peer = _DiscoveredPeer_from_ptr(&p_peers[i])
            changed = discovered_peer != new_discovered_peer
            if changed:
                discovered_peer = new_discovered_peer
                any_changed = True
                get_peers_result.events.push_back(
                    (PeerEvent_e.PEER_UPDATED, peer_uuid_bytes)
                )
        else:
            discovered_peer = _DiscoveredPeer_from_ptr(&p_peers[i])
            get_peers_result.events.push_back(
                (PeerEvent_e.PEER_ADDED, peer_uuid_bytes)
            )
            any_changed = True
        discovered_peer_dict[peer_uuid_bytes] = discovered_peer
        previous_uuids_bytes.discard(peer_uuid_bytes)
    for peer_uuid_bytes in previous_uuids_bytes:
        get_peers_result.events.push_back(
            (PeerEvent_e.PEER_REMOVED, peer_uuid_bytes)
        )
        any_changed = True
    get_peers_result.any_changed = any_changed
    return discovered_peer_dict
