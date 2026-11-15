# cython: language_level=3
# distutils: language = c++

"""
Wrapper module for the |NDI| :term:`Receive Listener` API

.. versionadded:: 0.1.4
"""

from typing import NamedTuple, Iterator, Literal, Self
from collections.abc import Callable, KeysView, ItemsView, ValuesView

from .exceptions import InvalidStateError, DiscoveryServerNotFoundError
from .types import (
    DiscoveredReceiver,
    ReceiveListenerEvent,
    ReceiverCallback,
    ReceiverEventCallback,
)

cdef const uint32_t UINT32_NEGATIVE_ONE = 0xFFFFFFFF


cdef _DiscoveredReceiver_from_ptr(const NDIlib_receiver_t* receiver):
    cdef bytes uuid = receiver.p_uuid
    cdef str name = receiver.p_name.decode('utf-8')
    cdef bytes input_uuid = receiver.p_input_uuid
    cdef str input_name = receiver.p_input_name.decode('utf-8')
    cdef str address = receiver.p_address.decode('utf-8')
    cdef list stream_types = []
    cdef uint32_t i
    cdef NDIlib_receiver_type_e stream_type_ptr
    for i in range(receiver.num_streams):
        stream_type_ptr = receiver.p_streams[i]
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
    cdef list commands = []
    cdef NDIlib_receiver_command_e command_ptr
    for i in range(receiver.num_commands):
        command_ptr = receiver.p_commands[i]
        if command_ptr == NDIlib_receiver_command_e.NDIlib_receiver_command_none:
            continue
        elif command_ptr == NDIlib_receiver_command_e.NDIlib_receiver_command_connect:
            commands.append("connect")
        else:
            continue
    cdef bint events_subscribed = receiver.events_subscribed
    return DiscoveredReceiver(
        uuid=uuid,
        name=name,
        input_uuid=input_uuid,
        input_name=input_name,
        address=address,
        stream_types=tuple(stream_types),
        commands=tuple(commands),
        events_subscribed=events_subscribed
    )

cdef _ListenerEvent_from_ptr(const NDIlib_recv_listener_event* event):
    """Create a :class:`.ReceiveListenerEvent` instance from an ``NDIlib_recv_listener_event`` pointer
    """
    cdef bytes uuid = event.p_uuid
    cdef str name = event.p_name.decode('utf-8')
    cdef str value = event.p_value.decode('utf-8')
    return ReceiveListenerEvent(uuid, name, value)


cdef class RecvListener:
    """A wrapper for the |NDI| :term:`Receive Listener` API

    Arguments:
        url_address (str | None): The URL address to use for the listener.
            Multiple addresses may be specified, separated by commas.
            Port numbers may also be specified using the format ``"address:port"``.
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
        self.auto_subscribe = auto_subscribe
        self._discovered_receivers = {}
        self._receiver_callback = Callback()
        self._event_callback = Callback()

    def __dealloc__(self):
        cdef NDIlib_recv_listener_instance_t instance = self._instance
        self._instance = NULL
        if instance != NULL:
            NDIlib_recv_listener_destroy(instance)

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

    def set_receiver_callback(self, cb: ReceiverCallback) -> None:
        """Set the callback for receiver events

        This can be used to track when receivers are added, removed, or updated.

        Arguments:
            cb (ReceiverCallback): The function to be called when a
                receiver event occurs.
        """
        self._receiver_callback.set_callback(cb)

    def remove_receiver_callback(self) -> None:
        """Remove the callback previously set through :meth:`set_receiver_callback`
        """
        self._receiver_callback.remove_callback()

    def set_event_callback(self, cb: ReceiverEventCallback) -> None:
        """Set the callback for listener events

        This can be used for handling events from discovered receivers and is
        invoked for each event during a call to :meth:`get_events`.

        Arguments:
            cb (ReceiverEventCallback): The function to be called
                when a listener event occurs.

        """
        self._event_callback.set_callback(cb)

    def remove_event_callback(self) -> None:
        """Remove the event callback previously set through :meth:`set_event_callback`
        """
        self._event_callback.remove_callback()

    def get_receivers(self) -> tuple[list[DiscoveredReceiver], bool]:
        """Update and get the list of discovered receivers

        Each item in the returned list will be a :class:`.DiscoveredReceiver` instance.

        Since :class:`.DiscoveredReceiver` is a :class:`~typing.NamedTuple`,
        it is immutable and each subsequent call to this method may contain different
        instances of the same receiver.

        Use the :attr:`~.DiscoveredReceiver.uuid` attribute to uniquely identify
        each receiver.


        .. danger::

            This method should **not** be called more than once concurrently
            (i.e., it is not thread-safe).

            The internal memory structures used in this method are only
            valid within a single call to this method.

            Once this method returns, all internal references have been copied
            and are safe.

        Returns:
            tuple[list[DiscoveredReceiver], bool]: A tuple containing the list of
            discovered receivers and a boolean indicating if the any item has
            changed since the last call.

        Raises:
            InvalidStateError: If the listener is not open.
        """
        changed = self._get_receivers()
        return list(self._discovered_receivers.values()), changed

    def wait_for_receiver_change(self, float timeout) -> bool:
        """Wait for a change in the list of discovered receivers

        If *timeout* is 0, this method will not block and will return
        whether a receiver change has occurred.  Otherwise, it will block
        until a change occurs or the timeout is reached.

        Arguments:
            timeout: The maximum time to wait for a receiver change, in seconds.

        Returns:
            bool: True if a receiver change occurred within the timeout, False otherwise.

        Raises:
            InvalidStateError: If the listener is not open.
        """
        if timeout < 0:
            raise ValueError("Timeout must be non-negative")
        cdef uint32_t timeout_ms = round(timeout * 1000)
        return self._wait_for_receiver_change(timeout_ms)

    def get_events(self, float timeout) -> list[tuple[DiscoveredReceiver, ReceiveListenerEvent]]:
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
            list[tuple[DiscoveredReceiver, ReceiveListenerEvent]]: A list of tuples containing:

            - The :class:`.DiscoveredReceiver`
            - The corresponding :class:`.ReceiveListenerEvent`.

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
            if event.uuid in self._discovered_receivers:
                receiver = self._discovered_receivers[event.uuid]
                result.append((receiver, event))
        return result

    def get_receiver(self, uuid: str | bytes) -> DiscoveredReceiver | None:
        """Get the discovered receiver with the given :attr:`~.DiscoveredReceiver.uuid`

        This is equivalent to calling :meth:`get` with a default of None.

        Arguments:
            uuid: The UUID of the receiver to retrieve.

        Returns:
            DiscoveredReceiver | None: The discovered receiver with the given UUID,
            or None if not found.
        """
        cdef bytes uuid_bytes
        if isinstance(uuid, str):
            uuid_bytes = uuid.encode('utf-8')
        else:
            uuid_bytes = uuid
        return self._discovered_receivers.get(uuid_bytes)

    def get(
        self,
        uuid: str | bytes,
        default: DiscoveredReceiver | None = None
    ) -> DiscoveredReceiver | None:
        """Get the discovered receiver with the given :attr:`~.DiscoveredReceiver.uuid`,
        or the *default* if not found

        Arguments:
            uuid: The UUID of the receiver to retrieve.
            default: The value to return if the receiver is not found.

        Returns:
            DiscoveredReceiver | None: The discovered receiver with the given UUID,
            or the default if not found.
        """
        cdef bytes uuid_bytes
        if isinstance(uuid, str):
            uuid_bytes = uuid.encode('utf-8')
        else:
            uuid_bytes = uuid
        return self._discovered_receivers.get(uuid_bytes, default)

    def subscribe(self, uuid: bytes) -> None:
        """Subscribe to events from the receiver with the given UUID

        .. note::
            If :attr:`auto_subscribe` is enabled, it is not necessary to
            call this method manually.

        Arguments:
            uuid: The UUID of the receiver to subscribe to.

        Raises:
            InvalidStateError: If the listener is not open.
        """
        self._subscribe_events(uuid)

    def unsubscribe(self, uuid: bytes) -> None:
        """Unsubscribe from events from the receiver with the given UUID

        Arguments:
            uuid: The UUID of the receiver to unsubscribe from.

        Raises:
            InvalidStateError: If the listener is not open.
        """
        self._unsubscribe_events(uuid)

    def keys(self) -> KeysView[bytes]:
        """Get a view of the discovered receiver :attr:`UUID's <.DiscoveredReceiver.uuid>`
        """
        return self._discovered_receivers.copy().keys()

    def values(self) -> ValuesView[DiscoveredReceiver]:
        """Get a view of the :class:`.DiscoveredReceiver` instances
        """
        return self._discovered_receivers.copy().values()

    def items(self) -> ItemsView[bytes, DiscoveredReceiver]:
        """Get a view of the discovered receiver :attr:`UUID's <.DiscoveredReceiver.uuid>`
        and their corresponding :class:`.DiscoveredReceiver` instances
        """
        return self._discovered_receivers.copy().items()

    def __contains__(self, uuid: str | bytes) -> bool:
        cdef bytes uuid_bytes
        if isinstance(uuid, str):
            uuid_bytes = uuid.encode('utf-8')
        else:
            uuid_bytes = uuid
        return uuid_bytes in self._discovered_receivers

    def __getitem__(self, uuid: str | bytes) -> DiscoveredReceiver:
        cdef bytes uuid_bytes
        if isinstance(uuid, str):
            uuid_bytes = uuid.encode('utf-8')
        else:
            uuid_bytes = uuid
        return self._discovered_receivers[uuid_bytes]

    def __iter__(self) -> Iterator[DiscoveredReceiver]:
        yield from self._discovered_receivers.copy().values()

    def __len__(self) -> int:
        return len(self._discovered_receivers)

    def __enter__(self) -> Self:
        self._open()
        return self

    def __exit__(self, exc_type, exc_value, traceback) -> None:
        self._close()

    cdef int _open(self) except -1:
        if self._instance != NULL:
            raise InvalidStateError("Recv listener is already open")
        self._discovered_receivers.clear()
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
        self._discovered_receivers.clear()
        return 0

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
        # if self._instance == NULL:
        #     return cpp_string()
        cdef const char* server_url = NDIlib_recv_listener_get_server_url(self._instance)
        if server_url == NULL:
            return cpp_string()
        return cpp_string(server_url)

    cdef bint _get_receivers(self) except -1:
        self._ensure_open()
        cdef uint32_t p_num_receivers = 0
        cdef const NDIlib_receiver_t* p_receivers = NDIlib_recv_listener_get_receivers(
            self._instance, &p_num_receivers
        )
        cdef bint any_changed = False
        cdef object discovered_receiver
        events: list[tuple[str, DiscoveredReceiver]] = []
        if p_receivers == NULL or p_num_receivers == 0:
            # If there are no receivers, clear all and trigger removed callbacks
            for discovered_receiver in self._discovered_receivers.values():
                events.append(("removed", discovered_receiver))
                any_changed = True
            self._discovered_receivers.clear()
            for event_type, discovered_receiver in events:
                self._trigger_receiver_callback(event_type, discovered_receiver)
            return any_changed
        cdef uint32_t i
        cdef dict discovered_receiver_dict = {}
        cdef object new_discovered_receiver
        cdef bytes receiver_uuid_bytes
        cdef bint existing = False
        cdef bint changed = False
        cdef set previous_uuids_bytes = set(self._discovered_receivers.keys())
        for i in range(p_num_receivers):
            receiver_uuid_bytes = p_receivers[i].p_uuid
            existing = receiver_uuid_bytes in previous_uuids_bytes
            if existing:
                discovered_receiver = self._discovered_receivers[receiver_uuid_bytes]
                new_discovered_receiver = _DiscoveredReceiver_from_ptr(&p_receivers[i])
                changed = discovered_receiver != new_discovered_receiver
                if changed:
                    discovered_receiver = new_discovered_receiver
                    any_changed = True
                    self._trigger_receiver_callback("updated", discovered_receiver)
            else:
                discovered_receiver = _DiscoveredReceiver_from_ptr(&p_receivers[i])
                self._trigger_receiver_callback("added", discovered_receiver)
                if self.auto_subscribe:
                    self._subscribe_events(receiver_uuid_bytes)
                any_changed = True
            discovered_receiver_dict[receiver_uuid_bytes] = discovered_receiver
            previous_uuids_bytes.discard(receiver_uuid_bytes)
        for receiver_uuid_bytes in previous_uuids_bytes:
            discovered_receiver = self._discovered_receivers[receiver_uuid_bytes]
            # discovered_receiver._unsubscribe_events()
            self._unsubscribe_events(receiver_uuid_bytes)
            # discovered_receiver.parent = None
            # del self._discovered_receivers[receiver_uuid_bytes]
            self._trigger_receiver_callback("removed", discovered_receiver)
            any_changed = True
        self._discovered_receivers.clear()
        self._discovered_receivers.update(discovered_receiver_dict)
        return any_changed

    cdef bint _wait_for_receiver_change(self, uint32_t timeout_ms) except -1 nogil:
        self._ensure_open()
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
        self._ensure_open()
        cdef list results = []
        cdef uint32_t num_events = 0
        cdef const NDIlib_listener_event* p_events = NDIlib_recv_listener_get_events(
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
            # `NDIlib_recv_listener_free_events` must be called after
            # each call to `NDIlib_send_listener_get_events`.
            NDIlib_recv_listener_free_events(self._instance, p_events)
        return results

    cdef _trigger_receiver_callback(self, str event_type, object discovered_receiver):
        cdef tuple callback_args = (event_type, discovered_receiver)
        self._receiver_callback.trigger_callback(callback_args)
        return 0

    cdef _trigger_event_callback(self, object event):
        cdef tuple callback_args = (event,)
        self._event_callback.trigger_callback(callback_args)
        return 0
