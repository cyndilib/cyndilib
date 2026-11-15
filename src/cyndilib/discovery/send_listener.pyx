# cython: language_level=3
# distutils: language = c++

"""
Wrapper module for the |NDI| :term:`Send Listener` API

.. versionadded:: 0.1.4
"""

from typing import Iterator, NamedTuple, Self
from collections.abc import Callable, KeysView, ItemsView, ValuesView

from .exceptions import DiscoveryServerNotFoundError, InvalidStateError
from .types import (
    DiscoveredSender,
    SenderCallback,
    SenderEventCallback,
    SendListenerEvent,
)


cdef const uint32_t UINT32_NEGATIVE_ONE = 0xFFFFFFFF



cdef _DiscoveredSender_from_ptr(const NDIlib_sender_t* sender):
    """Create a :class:`.DiscoveredSender` instance from an ``NDIlib_sender_t`` pointer
    """
    cdef bytes uuid = sender.p_uuid
    cdef str name = sender.p_name.decode('utf-8')
    cdef str address = sender.p_address.decode('utf-8')
    cdef str metadata = sender.p_metadata.decode('utf-8')
    cdef int port = sender.port
    cdef str group
    cdef list groups = []
    cdef uint32_t i
    for i in range(sender.num_groups):
        group = sender.p_groups[i].decode('utf-8')
        groups.append(group)
    cdef bint events_subscribed = sender.events_subscribed
    return DiscoveredSender(uuid, name, address, metadata, port, groups, events_subscribed)



cdef _ListenerEvent_from_ptr(const NDIlib_send_listener_event* event):
    """Create a :class:`.SendListenerEvent` instance from an ``NDIlib_send_listener_event`` pointer
    """
    cdef bytes uuid = event.p_uuid
    cdef str name = event.p_name.decode('utf-8')
    cdef str value = event.p_value.decode('utf-8')
    return SendListenerEvent(uuid, name, value)


cdef class SendListener:
    """A wrapper for the |NDI| :term:`Send Listener` API

    Arguments:
        url_address (str | None): The URL address to use for the listener.
            Port numbers may be specified using the format ``"address:port"``.
            If no port is specified, the default port of 5959 will be used.
            If None (the default), the URL address from the
            :term:`Discovery Configuration` will be used.
        auto_subscribe (bool): Whether the listener should automatically
            subscribe to discovered senders. Defaults to True.


    After initialization, the listener can be opened using the :meth:`open` method
    and closed using the :meth:`close` method.
    This class also implements the context manager protocol, allowing use with the
    :keyword:`with` statement:

    >>> with SendListener() as send_listener:
    ...     ...

    After opening the listener, the :meth:`get_senders` method can be used to
    retrieve the list of currently discovered senders.  This should be done periodically
    to keep track of changes from the network.

    To wait until a change in the list of discovered senders occurs, the
    :meth:`wait_for_sender_change` method can be used with a specified timeout.

    To receive events related to discovered senders, the :meth:`get_events` method
    can be used with a specified timeout.  This should also be done periodically.

    If :attr:`auto_subscribe` is set to True, the listener will automatically subscribe
    to discovered senders. Otherwise, manual subscription is required using the
    :meth:`subscribe` method.  The :meth:`unsubscribe` method can be used to stop
    receiving events from a particular sender.


    The :class:`.DiscoveredSender` instances can also be accessed via the :meth:`get`
    method or by subscript access using the sender's :attr:`UUID <.DiscoveredSender.uuid>`:

    >>> send_listener[b'd5bd1191-1b32-4bee-a5d0-9f5b95d4cd30']
    ... ...

    or via iteration:

    >>> for sender in send_listener:
    ...     ...


    Attributes:
        auto_subscribe (bool): Indicates whether the listener automatically
            subscribes to discovered senders.
    """
    def __cinit__(self, *args, **kwargs):
        self._instance = NULL
        self._create_settings.p_url_address = b''

    def __init__(self, url_address: str | None = None, auto_subscribe: bool = True):
        if url_address is None:
            self._use_default_url_address = True
        else:
            self._use_default_url_address = False
            self._url_address_bytes = url_address.encode('utf-8')
            self._create_settings.p_url_address = self._url_address_bytes
        self._discovered_senders = {}
        self._sender_callback = Callback()
        self._event_callback = Callback()
        self.auto_subscribe = auto_subscribe

    def __dealloc__(self):
        cdef NDIlib_send_listener_instance_t instance = self._instance
        self._instance = NULL
        if instance != NULL:
            NDIlib_send_listener_destroy(instance)

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

    def set_sender_callback(self, cb: SenderCallback) -> None:
        """Set the callback for sender events

        This can be used to track when senders are added, removed, or updated.

        Arguments:

            cb (SenderCallback): The function to be called when a sender event occurs.
        """
        self._sender_callback.set_callback(cb)

    def remove_sender_callback(self) -> None:
        """Remove the callback previously set through :meth:`set_sender_callback`
        """
        self._sender_callback.remove_callback()

    def set_event_callback(self, cb: SenderEventCallback) -> None:
        """Set the callback for listener events

        This can be used for handling events from discovered senders and is
        invoked for each event during a call to :meth:`get_events`.

        Arguments:

            cb (SenderEventCallback): The function to be called when a listener event occurs.

        """
        self._event_callback.set_callback(cb)

    def remove_event_callback(self) -> None:
        """Remove the event callback previously set through :meth:`set_event_callback`
        """
        self._event_callback.remove_callback()

    def get_senders(self) -> tuple[list[DiscoveredSender], bool]:
        """Update and get the list of discovered senders

        Each item in the returned list will be a :class:`.DiscoveredSender` instance.

        Since :class:`.DiscoveredSender` is a :class:`~typing.NamedTuple`,
        it is immutable and each subsequent call to this method may contain different
        instances of the same sender.

        Use the :attr:`~.DiscoveredSender.uuid` attribute to uniquely identify
        each sender.


        .. danger::

            This method should **not** be called more than once concurrently
            (i.e., it is not thread-safe).

            The internal memory structures used in this method are only
            valid within a single call to this method.

            Once this method returns, all internal references have been copied
            and are safe.

        Returns:
            tuple[list[DiscoveredSender], bool]: A tuple containing the list of
            discovered senders and a boolean indicating if the any item has
            changed since the last call.

        Raises:
            InvalidStateError: If the listener is not open.
        """
        changed = self._get_senders()
        return list(self._discovered_senders.values()), changed

    def wait_for_sender_change(self, float timeout) -> bool:
        """Wait for a change in the list of discovered senders

        If *timeout* is 0, this method will not block and will return
        whether a sender change has occurred.  Otherwise, it will block
        until a change occurs or the timeout is reached.

        Arguments:
            timeout: The maximum time to wait for a sender change, in seconds.

        Returns:
            bool: True if a sender change occurred within the timeout, False otherwise.

        Raises:
            InvalidStateError: If the listener is not open.
        """
        if timeout < 0:
            raise ValueError("Timeout must be non-negative")
        cdef uint32_t timeout_ms = round(timeout * 1000)
        return self._wait_for_sender_change(timeout_ms)

    def get_events(self, float timeout) -> list[tuple[DiscoveredSender, SendListenerEvent]]:
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
            list[tuple[DiscoveredSender, SendListenerEvent]]: A list of tuples containing:

            - The :class:`.DiscoveredSender`
            - The corresponding :class:`.SendListenerEvent`.

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
            if event.uuid in self._discovered_senders:
                sender = self._discovered_senders[event.uuid]
                result.append((sender, event))
        return result

    def get_sender(self, uuid: str | bytes) -> DiscoveredSender | None:
        """Get the discovered sender with the given :attr:`~.DiscoveredSender.uuid`

        This is equivalent to calling :meth:`get` with a default of None.

        Arguments:
            uuid: The UUID of the sender to retrieve.

        Returns:
            DiscoveredSender | None: The discovered sender with the given UUID,
            or None if not found.
        """
        cdef bytes uuid_bytes
        if isinstance(uuid, str):
            uuid_bytes = uuid.encode('utf-8')
        else:
            uuid_bytes = uuid
        return self._discovered_senders.get(uuid_bytes)

    def get(
        self,
        uuid: str | bytes,
        default: DiscoveredSender | None = None
    ) -> DiscoveredSender | None:
        """Get the discovered sender with the given :attr:`~.DiscoveredSender.uuid`,
        or the *default* if not found

        Arguments:
            uuid: The UUID of the sender to retrieve.
            default: The value to return if the sender is not found.

        Returns:
            DiscoveredSender | None: The discovered sender with the given UUID,
            or the default if not found.
        """
        cdef bytes uuid_bytes
        if isinstance(uuid, str):
            uuid_bytes = uuid.encode('utf-8')
        else:
            uuid_bytes = uuid
        return self._discovered_senders.get(uuid_bytes, default)

    def subscribe(self, uuid: bytes) -> None:
        """Subscribe to events from the sender with the given UUID

        .. note::
            If :attr:`auto_subscribe` is enabled, it is not necessary to
            call this method manually.

        Arguments:
            uuid: The UUID of the sender to subscribe to.

        Raises:
            InvalidStateError: If the listener is not open.
        """
        self._subscribe_events(uuid)

    def unsubscribe(self, uuid: bytes) -> None:
        """Unsubscribe from events from the sender with the given UUID

        Arguments:
            uuid: The UUID of the sender to unsubscribe from.

        Raises:
            InvalidStateError: If the listener is not open.
        """
        self._unsubscribe_events(uuid)

    def keys(self) -> KeysView[bytes]:
        """Get a view of the discovered sender :attr:`UUID's <.DiscoveredSender.uuid>`
        """
        return self._discovered_senders.copy().keys()

    def values(self) -> ValuesView[DiscoveredSender]:
        """Get a view of the :class:`.DiscoveredSender` instances
        """
        return self._discovered_senders.copy().values()

    def items(self) -> ItemsView[bytes, DiscoveredSender]:
        """Get a view of the discovered sender :attr:`UUID's <.DiscoveredSender.uuid>`
        and their corresponding :class:`.DiscoveredSender` instances
        """
        return self._discovered_senders.copy().items()

    def __contains__(self, uuid: str | bytes) -> bool:
        cdef bytes uuid_bytes
        if isinstance(uuid, str):
            uuid_bytes = uuid.encode('utf-8')
        else:
            uuid_bytes = uuid
        return uuid_bytes in self._discovered_senders

    def __getitem__(self, uuid: str | bytes) -> DiscoveredSender:
        cdef bytes uuid_bytes
        if isinstance(uuid, str):
            uuid_bytes = uuid.encode('utf-8')
        else:
            uuid_bytes = uuid
        return self._discovered_senders[uuid_bytes]

    def __iter__(self) -> Iterator[DiscoveredSender]:
        yield from self._discovered_senders.copy().values()

    def __len__(self) -> int:
        return len(self._discovered_senders)

    def __enter__(self) -> Self:
        self._open()
        return self

    def __exit__(self, exc_type, exc_value, traceback) -> None:
        self._close()

    cdef int _open(self) except -1:
        if self._instance != NULL:
            raise InvalidStateError("Send listener is already open")
        self._discovered_senders.clear()
        if self._use_default_url_address:
            self._instance = NDIlib_send_listener_create()
        else:
            self._instance = NDIlib_send_listener_create(&self._create_settings)
        if self._instance == NULL:
            raise DiscoveryServerNotFoundError("Failed to create listener")
        return 0

    cdef int _close(self) except -1:
        cdef NDIlib_send_listener_instance_t instance = self._instance
        self._instance = NULL
        if instance != NULL:
            NDIlib_send_listener_destroy(instance)
        self._discovered_senders.clear()
        return 0

    cdef bint _is_connected(self) except -1 nogil:
        if self._instance == NULL:
            return False
        return NDIlib_send_listener_is_connected(self._instance)

    cdef int _ensure_open(self) except -1 nogil:
        """Convenience method to ensure that the listener is open
        """
        if self._instance == NULL:
            raise InvalidStateError("Send listener is not open")
        return 0

    cdef cpp_string _get_url_address(self):
        self._ensure_open()
        # if self._instance == NULL:
        #     return cpp_string()
        cdef const char* server_url = NDIlib_send_listener_get_server_url(self._instance)
        if server_url == NULL:
            return cpp_string()
        return cpp_string(server_url)

    cdef bint _get_senders(self) except -1:
        self._ensure_open()
        cdef uint32_t p_num_senders = 0
        cdef const NDIlib_sender_t* p_senders = NDIlib_send_listener_get_senders(
            self._instance, &p_num_senders
        )
        cdef bint any_changed = False
        cdef object discovered_sender
        events: list[tuple[str, DiscoveredSender]] = []
        if p_senders == NULL or p_num_senders == 0:
            # If there are no senders, clear all existing and trigger removal callbacks
            for discovered_sender in self._discovered_senders.values():
                events.append(("removed", discovered_sender))
                any_changed = True
            self._discovered_senders.clear()
            for event_type, discovered_sender in events:
                self._trigger_sender_callback(event_type, discovered_sender)
            return any_changed
        cdef uint32_t i
        cdef NDIlib_sender_t ndi_sender
        cdef dict discovered_sender_dict = {}
        cdef object new_discovered_sender
        # cdef cpp_string sender_uuid_cpp
        cdef bytes sender_uuid_bytes
        cdef bint existing = False
        cdef bint changed = False
        cdef set previous_uuids_bytes = set(self._discovered_senders.keys())
        for i in range(p_num_senders):
            ndi_sender = p_senders[i]
            sender_uuid_bytes = ndi_sender.p_uuid
            existing = sender_uuid_bytes in previous_uuids_bytes
            if existing:
                discovered_sender = self._discovered_senders[sender_uuid_bytes]
                new_discovered_sender = _DiscoveredSender_from_ptr(&ndi_sender)
                changed = discovered_sender != new_discovered_sender
                if changed:
                    discovered_sender = new_discovered_sender
                    # self._discovered_senders[sender_uuid_bytes] = discovered_sender
                    any_changed = True
                    events.append(("updated", discovered_sender))
            else:
                # discovered_sender = DiscoveredSender._from_ptr(&ndi_sender)
                discovered_sender = _DiscoveredSender_from_ptr(&ndi_sender)
                # discovered_sender.parent = self
                # self._discovered_senders[sender_uuid_bytes] = discovered_sender
                events.append(("added", discovered_sender))
                if self.auto_subscribe:
                    # discovered_sender._subscribe_events()
                    self._subscribe_events(sender_uuid_bytes)
                any_changed = True
            discovered_sender_dict[sender_uuid_bytes] = discovered_sender
            previous_uuids_bytes.discard(sender_uuid_bytes)
        for sender_uuid_bytes in previous_uuids_bytes:
            discovered_sender = self._discovered_senders[sender_uuid_bytes]
            # discovered_sender._unsubscribe_events()
            self._unsubscribe_events(sender_uuid_bytes)
            # discovered_sender.parent = None
            # del self._discovered_senders[sender_uuid_bytes]
            any_changed = True
        # if any_changed:
        self._discovered_senders.clear()
        self._discovered_senders.update(discovered_sender_dict)
        for event_type, discovered_sender in events:
            self._trigger_sender_callback(event_type, discovered_sender)
        return any_changed

    # cdef bint _wait_for_senders(self, uint32_t timeout_ms) except -1 nogil:
    #     self._ensure_open()
    #     return NDIlib_send_listener_wait_for_senders(self._instance, timeout_ms)

    cdef bint _wait_for_sender_change(self, uint32_t timeout_ms) except -1 nogil:
        self._ensure_open()
        with nogil:
            return NDIlib_send_listener_wait_for_senders(self._instance, timeout_ms)

    cdef int _subscribe_events(self, const char* sender_uuid) except -1 nogil:
        self._ensure_open()
        NDIlib_send_listener_subscribe_events(self._instance, sender_uuid)
        return 0

    cdef int _unsubscribe_events(self, const char* sender_uuid) except -1 nogil:
        self._ensure_open()
        NDIlib_send_listener_unsubscribe_events(self._instance, sender_uuid)
        return 0

    cdef list _get_events(self, uint32_t timeout_ms):
        self._ensure_open()
        cdef list results = []
        cdef uint32_t num_events = 0
        cdef const NDIlib_send_listener_event* p_events
        with nogil:
            p_events = NDIlib_send_listener_get_events(
                self._instance, &num_events, timeout_ms
            )
        if p_events == NULL:
            return results
        cdef object event
        cdef uint32_t i
        try:
            for i in range(num_events):
                event = _ListenerEvent_from_ptr(&p_events[i])
                results.append(event)
                self._trigger_event_callback(event)
        finally:
            # Important!
            # `NDIlib_send_listener_free_events` must be called after
            # each call to `NDIlib_send_listener_get_events`.
            NDIlib_send_listener_free_events(self._instance, p_events)

        return results

    cdef _trigger_sender_callback(self, str event_type, object discovered_sender):
        cdef tuple callback_args = (event_type, discovered_sender)
        self._sender_callback.trigger_callback(callback_args)
        return 0

    cdef _trigger_event_callback(self, object event):
        cdef tuple callback_args = (event,)
        self._event_callback.trigger_callback(callback_args)
        return 0
