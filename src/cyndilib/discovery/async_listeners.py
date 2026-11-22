"""
Async listeners for the |NDI| :term:`Send Listener` and :term:`Receive Listener` API

.. versionadded:: 0.1.4
"""
from __future__ import annotations

import asyncio
from abc import ABC, abstractmethod
from collections.abc import AsyncIterator, ItemsView, Iterator, KeysView, ValuesView
from typing import Generic, Self

from .base_listener import BaseListener
from .recv_listener import RecvListener
from .send_listener import SendListener
from .types import (
    DiscoveredPeerT,
    DiscoveredReceiver,
    DiscoveredSender,
    ListenerEventT,
    PeerEvent,
    ReceiveListenerEvent,
    SendListenerEvent,
)


class AsyncListenerBase(ABC, Generic[DiscoveredPeerT, ListenerEventT]):
    """Base class for async listeners

    Arguments:
        url_address: The URL address to use for the listener.
            Port numbers may be specified using the format ``"address:port"``.
            If no port is specified, the default port of 5959 will be used.
            If None (the default), the URL address from the
            :term:`Discovery Configuration` will be used.
        auto_subscribe: Whether the listener should automatically
            subscribe to discovered peers. Defaults to True.
        max_queue_size: Maximum size of the event queues. Defaults to 100.

    """
    def __init__(
        self,
        url_address: str | None = None,
        auto_subscribe: bool = True,
        max_queue_size: int = 100,
    ) -> None:
        listener_cls = self._get_listener_cls()
        self._listener = listener_cls(
            url_address=url_address,
            auto_subscribe=auto_subscribe,
        )
        self._update_lock = asyncio.Lock()
        self._event_lock = asyncio.Lock()
        self._peer_task: asyncio.Task | None = None
        self._listener_task: asyncio.Task | None = None
        self._peer_event_queue = asyncio.Queue[PeerEvent[DiscoveredPeerT]](
            maxsize=max_queue_size,
        )
        self._listener_event_queue = asyncio.Queue[ListenerEventT](
            maxsize=max_queue_size,
        )
        self._running = False

    @classmethod
    @abstractmethod
    def _get_listener_cls(cls) -> type[BaseListener[DiscoveredPeerT, ListenerEventT]]:
        raise NotImplementedError()

    async def open(self) -> None:
        """Open the listener and start background tasks
        """
        if self._running:
            return
        if self._listener.is_open():
            raise RuntimeError("Listener already open")
        self._running = True
        if self._peer_task is not None or self._listener_task is not None:
            raise RuntimeError("Tasks already running")
        await self._clear_queue(self._peer_event_queue)
        await self._clear_queue(self._listener_event_queue)
        try:
            self._listener.open()
        except:
            self._running = False
            raise
        self._peer_task = asyncio.create_task(self._peer_update_loop())
        self._listener_task = asyncio.create_task(self._listener_event_loop())

    async def close(self) -> None:
        """Close the listener and stop background tasks
        """
        self._running = False
        peer_task, listener_task = self._peer_task, self._listener_task
        self._peer_task, self._listener_task = None, None

        # Clear the queues in case they're full since this could prevent tasks
        # from finishing cleanly.
        await self._clear_queue(self._peer_event_queue)
        await self._clear_queue(self._listener_event_queue)
        await self._cancel_task(peer_task)
        await self._cancel_task(listener_task)
        self._listener.close()

    def is_open(self) -> bool:
        """Check if listener is open
        """
        return self._running and self._listener.is_open()

    def is_connected(self) -> bool:
        """Check if listener is connected
        """
        return self._listener.is_connected()

    def get_url_address(self) -> str:
        """Get the URL address of the :term:`Discovery Server` that the
        listener is connected to.

        See :meth:`.BaseListener.get_url_address` for details.
        """
        return self._listener.get_url_address()

    def get_peer(self, uuid: str | bytes) -> DiscoveredPeerT | None:
        """Get the discovered peer with the given UUID

        See :meth:`.BaseListener.get_peer` for details.
        """
        return self._listener.get_peer(uuid)

    def get(self, uuid: str | bytes, default: DiscoveredPeerT | None = None) -> DiscoveredPeerT | None:
        """Get the discovered peer with the given UUID or *default* if not found

        See :meth:`.BaseListener.get` for details.
        """
        return self._listener.get(uuid, default)

    def subscribe(self, uuid: bytes) -> None:
        """Subscribe to events from the peer with the given UUID

        See :meth:`.BaseListener.subscribe` for details.
        """
        self._listener.subscribe(uuid)

    def unsubscribe(self, uuid: bytes) -> None:
        """Unsubscribe from events from the peer with the given UUID

        See :meth:`.BaseListener.unsubscribe` for details.
        """
        self._listener.unsubscribe(uuid)

    def keys(self) -> KeysView[bytes]:
        """Get a view of the discovered peer UUID's
        """
        return self._listener.keys()

    def values(self) -> ValuesView[DiscoveredPeerT]:
        """Get a view of the discovered peer instances
        """
        return self._listener.values()

    def items(self) -> ItemsView[bytes, DiscoveredPeerT]:
        """Get a view of the discovered peer UUID's
        and their corresponding discovered peer instances
        """
        return self._listener.items()

    async def wait_for_peer_event(self) -> PeerEvent[DiscoveredPeerT]:
        """Wait for the next available peer event
        """
        event = await self._peer_event_queue.get()
        self._peer_event_queue.task_done()
        return event

    async def wait_for_listener_event(self) -> ListenerEventT:
        """Wait for the next listener event
        """
        event = await self._listener_event_queue.get()
        self._listener_event_queue.task_done()
        return event

    async def peer_events(self) -> AsyncIterator[PeerEvent[DiscoveredPeerT]]:
        """Asyncronously iterate through received peer events

        This is an :term:`asynchronous iterator` and can be used with in an
        :keyword:`async for` loop:

        >>> async for e in listener.peer_events():
        ...     print(e)

        .. important::
            If using this method, avoid calls to :meth:`wait_for_peer_event`
            directly as it may lead to missed events.
        """
        while self._running:
            event = await self.wait_for_peer_event()
            yield event

    async def listener_events(self) -> AsyncIterator[ListenerEventT]:
        """Asyncronously iterate through received listener events

        This is an :term:`asynchronous iterator` and can be used with in an
        :keyword:`async for` loop:

        >>> async for e in listener.listener_events():
        ...     print(e)

        .. important::
            If using this method, avoid calls to :meth:`wait_for_listener_event`
            directly as it may lead to missed events.
        """
        while self._running:
            event = await self.wait_for_listener_event()
            yield event

    def __contains__(self, uuid: str | bytes) -> bool:
        return uuid in self._listener

    def __getitem__(self, uuid: str | bytes) -> DiscoveredPeerT:
        return self._listener[uuid]

    def __iter__(self) -> Iterator[DiscoveredPeerT]:
        yield from self._listener

    def __len__(self) -> int:
        return len(self._listener)

    async def _cancel_task(self, t: asyncio.Task | None) -> None:
        if t is not None:
            t.cancel()
            try:
                await t
            except asyncio.CancelledError:
                pass

    async def _clear_queue(self, queue: asyncio.Queue) -> None:
        while not queue.empty():
            try:
                queue.get_nowait()
            except asyncio.QueueEmpty:
                break

    async def _peer_update_loop(self) -> None:
        """Periodically check for peer changes

        Each iteration first waits for a change to be reported using
        :func:`asyncio.to_thread` for the blocking operation.

        If a change is reported, :meth:`.BaseListener.get_peers` (which is
        non-blocking) is used to get the peer events and place them in the queue.
        """
        wait_timeout = .2
        async def wait_for_change() -> bool:
            task = asyncio.to_thread(
                self._listener.wait_for_peer_change, wait_timeout
            )

            # Shield the threaded call from cancellation. With a short enough
            # wait timeout, this should be acceptable versus a possible thread hang.
            changed = await asyncio.shield(task)
            return changed

        while self._running:
            async with self._update_lock:
                changed = await wait_for_change()
                if not self._running:
                    break
                if not changed:
                    continue
                events = self._listener.get_peers(return_events=True)
            for e in events:
                await self._peer_event_queue.put(e)
                if not self._running:
                    break

    async def _listener_event_loop(self) -> None:
        """Periodically check for listener events

        Each iteration waits for and retrieves events using
        :meth:`.BaseListener.get_events` (which is blocking). The operation is
        wrapped in :func:`asyncio.to_thread` to avoid blocking the event loop.
        """
        wait_timeout = .2
        async def get_events() -> list[tuple[DiscoveredPeerT, ListenerEventT]]:
            task = asyncio.to_thread(
                self._listener.get_events, wait_timeout
            )
            # Shield the threaded call from cancellation.
            return await asyncio.shield(task)

        while self._running:
            async with self._event_lock:
                events = await get_events()
                if not self._running:
                    break
            for _peer, event in events:
                await self._listener_event_queue.put(event)
                if not self._running:
                    break

    async def __aenter__(self) -> Self:
        await self.open()
        return self

    async def __aexit__(self, exc_type, exc, tb) -> None:
        await self.close()


class AsyncRecvListener(AsyncListenerBase[DiscoveredReceiver, ReceiveListenerEvent]):
    """Asynchronous version of :class:`.RecvListener`

    Arguments:
        url_address: The URL address to use for the listener.
            Port numbers may be specified using the format ``"address:port"``.
            If no port is specified, the default port of 5959 will be used.
            If None (the default), the URL address from the
            :term:`Discovery Configuration` will be used.
        auto_subscribe: Whether the listener should automatically
            subscribe to discovered peers. Defaults to True.
        max_queue_size: Maximum size of the event queues. Defaults to 100.


    This class can be used as an :term:`asynchronous context manager`, supporting
    use with in an :keyword:`async with` block:

    >>> async with AsyncRecvListener(...) as listener:
    >>>     ...

    Or alternatively, the :meth:`open` and :meth:`close` methods can be used.

    Listener events and peer updates are managed internally.

    Peer updates can be retrieved via :meth:`wait_for_peer_event` or iterating
    over :meth:`peer_events`:

    >>> async for peer in listener.peer_events():
    >>>     ...

    Events can be retrieved via the :meth:`wait_for_peer_event` or iterating
    over the :meth:`listener_events`:

    >>> async for event in listener.listener_events():
    >>>     ...

    Accessing the discovered peers is similar to the
    :class:`synchronous listener<.RecvListener>`, including indexing, iteration,
    containment and length:

    >>> if b"uuid" in listener:
    >>>     ...
    >>> listener[b"uuid"]
    >>> len(listener)
    >>> for peer in listener:
    >>>     ...


    """
    @classmethod
    def _get_listener_cls(cls) -> type[RecvListener]:
        return RecvListener


class AsyncSendListener(AsyncListenerBase[DiscoveredSender, SendListenerEvent]):
    """Asynchronous version of :class:`.SendListener`

    Arguments:
        url_address: The URL address to use for the listener.
            Port numbers may be specified using the format ``"address:port"``.
            If no port is specified, the default port of 5959 will be used.
            If None (the default), the URL address from the
            :term:`Discovery Configuration` will be used.
        auto_subscribe: Whether the listener should automatically
            subscribe to discovered peers. Defaults to True.
        max_queue_size: Maximum size of the event queues. Defaults to 100.


    This class can be used as an :term:`asynchronous context manager`, supporting
    use with in an :keyword:`async with` block:

    >>> async with AsyncSendListener(...) as listener:
    >>>     ...

    Or alternatively, the :meth:`open` and :meth:`close` methods can be used.

    Listener events and peer updates are managed internally.

    Peer updates can be retrieved via :meth:`wait_for_peer_event` or iterating
    over :meth:`peer_events`:

    >>> async for peer in listener.peer_events():
    >>>     ...

    Events can be retrieved via the :meth:`wait_for_peer_event` or iterating
    over the :meth:`listener_events`:

    >>> async for event in listener.listener_events():
    >>>     ...

    Accessing the discovered peers is similar to the
    :class:`synchronous listener<.SendListener>`, including indexing, iteration,
    containment and length:

    >>> if b"uuid" in listener:
    >>>     ...
    >>> listener[b"uuid"]
    >>> len(listener)
    >>> for peer in listener:
    >>>     ...


    """
    @classmethod
    def _get_listener_cls(cls) -> type[SendListener]:
        return SendListener
