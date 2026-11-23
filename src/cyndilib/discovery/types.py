"""
Types used in the |NDI| :term:`Discovery API`

.. versionadded:: 0.1.4
"""

from __future__ import annotations

from collections.abc import Callable
from typing import Generic, Literal, NamedTuple, TypeVar

from .events import ReceiverEventName, SenderEventName

DiscoveredPeerT = TypeVar("DiscoveredPeerT", "DiscoveredSender", "DiscoveredReceiver")
"""Type for discovered peers

This may be a :class:`DiscoveredSender` or :class:`DiscoveredReceiver`
"""

ListenerEventT = TypeVar("ListenerEventT", "SendListenerEvent", "ReceiveListenerEvent")
"""Type for listener events

This may be a :class:`SendListenerEvent` or :class:`ReceiveListenerEvent`
"""

EventName = TypeVar("EventName")
"""Type for event names"""



ReceiveStreamType = Literal["video", "audio", "metadata"]
ReceiveCommandType = Literal["connect"]


class DiscoveredSender(NamedTuple):
    """A representation of a sender discovered by the :class:`.SendListener`
    """
    uuid: bytes
    """The unique identifier of the sender"""
    name: str
    """The name of the sender"""
    address: str
    """The address of the sender"""
    metadata: str
    """The metadata associated with the sender"""
    port: int
    """The port of the sender"""
    groups: list[str]
    """The groups this sender belongs to"""
    events_subscribed: bool
    """Whether events are subscribed for this sender"""


class DiscoveredReceiver(NamedTuple):
    """A representation of a receiver discovered by the :class:`.RecvListener`
    """
    uuid: bytes
    """The unique identifier of the receiver"""
    name: str
    """The name of the receiver"""
    input_uuid: bytes
    """The unique identifier for the input group that the receiver belongs to"""
    input_name: str
    """The human-readable name of the input group that the receiver belongs to"""
    address: str
    """The known IP address of the receiver"""
    stream_types: tuple[ReceiveStreamType, ...]
    """An array of streams that the receiver is set to receive"""
    commands: tuple[ReceiveCommandType, ...]
    """An array of commands that the receiver can process"""
    events_subscribed: bool
    """Whether events are subscribed for this receiver"""


ListenerEventName = Literal["added", "removed", "updated"]
"""Listener event name type

- "added": A sender or receiver was added.
- "removed": A sender or receiver was removed.
- "updated": A sender or receiver was updated.
"""


PeerEvent = tuple[ListenerEventName, DiscoveredPeerT]
"""A peer event as a tuple of :obj:`ListenerEventName` and :obj:`DiscoveredPeerT`
"""


PeerCallback = Callable[[ListenerEventName, DiscoveredPeerT], None]
"""Callback for changes in discovered peers

This is used when a peer is added, removed, or updated.

:param event_name: The type of event.
:type event_name: ListenerEventName
:param peer: The discovered peer.
:type peer: DiscoveredPeerT
"""

SenderCallback = Callable[[ListenerEventName, DiscoveredSender], None]
"""Callback signature for changes in discovered senders

This is used when a sender is added, removed, or updated
by :meth:`.SendListener.get_peers` (if the callback is set via
:meth:`.SendListener.set_peer_callback`).

:param event_name: The name of the sender event.
:type event_name: ListenerEventName
:param sender: The discovered sender associated with the event.
:type sender: DiscoveredSender
"""


ReceiverCallback = Callable[[ListenerEventName, DiscoveredReceiver], None]
"""Callback signature for changes in discovered receivers

This is used when a receiver is added, removed, or updated
by :meth:`.RecvListener.get_peers` (if the callback is set via
:meth:`.RecvListener.set_peer_callback`).

:param event_name: The name of the receiver event.
:type event_name: ListenerEventName
:param receiver: The discovered receiver associated with the event.
:type receiver: DiscoveredReceiver
"""



class ListenerEvent(NamedTuple, Generic[EventName]):
    """An event received from a :class:`.DiscoveredSender` or
    :class:`.DiscoveredReceiver`
    """
    uuid: bytes
    """The unique identifier of the source"""
    name: EventName
    """The name of the event"""
    value: str
    """The event value"""



class SendListenerEvent(ListenerEvent[SenderEventName]):
    """An event received from a :class:`DiscoveredSender`

    This is used in :meth:`.SendListener.get_events` and its associated callback
    set via :meth:`.SendListener.set_event_callback`.
    """


class ReceiveListenerEvent(ListenerEvent[ReceiverEventName]):
    """An event from a :class:`DiscoveredReceiver`

    This is used in :meth:`.RecvListener.get_events` and its associated callback
    set via :meth:`.RecvListener.set_event_callback`.
    """



ListenerEventCallback = Callable[[ListenerEventT], None]
"""Callback for listener events

:param event: The event received from the listener.
:type event: ListenerEventT
"""


SenderEventCallback = ListenerEventCallback[SendListenerEvent]
"""Callback signature for events received from
:class:`DiscoveredSenders <DiscoveredSender>`

:param event: The event received from the listener.
:type event: SendListenerEvent
"""

ReceiverEventCallback = ListenerEventCallback[ReceiveListenerEvent]
"""Callback signature for events received from
:class:`DiscoveredReceivers <DiscoveredReceiver>`

:param event: The event received from the listener.
:type event: ReceiveListenerEvent
"""
