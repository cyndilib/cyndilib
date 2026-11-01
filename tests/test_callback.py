from typing import Literal

import pytest
from _callback_helpers import Callback

CallbackType = Literal["function_callback", "method_callback"]

@pytest.fixture(
    params=["function_callback", "method_callback"],
)
def callback_type(request) -> CallbackType:
    return request.param


def test_callback_no_args(callback_type: CallbackType) -> None:
    """Test callback with no arguments and no keyword arguments
    """
    called = False

    class TestClass:
        def method(self) -> None:
            nonlocal called
            called = True

    instance = TestClass()

    if callback_type == "function_callback":
        def callback() -> None:
            nonlocal called
            called = True
    else:
        callback = instance.method

    cb = Callback()
    cb.set(callback)
    cb.trigger_no_args_no_kwargs()
    assert called


def test_callback_remove(callback_type: CallbackType) -> None:
    """Test removing a callback and ensuring it is not called afterwards
    """
    called = False

    class TestClass:
        def method(self) -> None:
            nonlocal called
            called = True
    instance = TestClass()

    if callback_type == "function_callback":
        def callback() -> None:
            nonlocal called
            called = True
    else:
        callback = instance.method

    cb = Callback()
    cb.set(callback)
    cb.trigger_no_args_no_kwargs()
    assert called
    called = False
    cb.remove()
    cb.trigger_no_args_no_kwargs()
    assert not called


def test_callback_with_args(callback_type: CallbackType) -> None:
    """Test callback with positional arguments
    """
    called = False
    args_received: tuple[int, str] | None = None

    class TestClass:
        def method(self, a: int, b: str) -> None:
            nonlocal called, args_received
            called = True
            args_received = (a, b)
    instance = TestClass()

    if callback_type == "function_callback":
        def callback(a: int, b: str) -> None:
            nonlocal called, args_received
            called = True
            args_received = (a, b)
    else:
        callback = instance.method

    cb = Callback()
    cb.set(callback)
    cb.trigger_with_args(42, "hello")
    assert called
    assert args_received == (42, "hello")


def test_callback_with_varargs(callback_type: CallbackType) -> None:
    """Test callback with variable positional arguments
    """
    called = False
    args_received: tuple[int, int] | None = None

    class TestClass:
        def method(self, *args: int) -> None:
            nonlocal called, args_received
            called = True
            assert len(args) == 2
            args_received = args
    instance = TestClass()

    if callback_type == "function_callback":
        def callback(*args: int) -> None:
            nonlocal called, args_received
            called = True
            assert len(args) == 2
            args_received = args
    else:
        callback = instance.method

    cb = Callback()
    cb.set(callback)
    cb.trigger_with_args(1, 2)
    assert called
    assert args_received == (1, 2)


def test_callback_with_kwargs(callback_type: CallbackType) -> None:
    """Test callback with keyword arguments
    """
    called = False
    kwargs_received: dict[str, int] | None = None

    class TestClass:
        def method(self, *, a: int, b: int) -> None:
            nonlocal called, kwargs_received
            called = True
            kwargs_received = {"a": a, "b": b}
    instance = TestClass()

    if callback_type == "function_callback":
        def callback(*, a: int, b: int) -> None:
            nonlocal called, kwargs_received
            called = True
            kwargs_received = {"a": a, "b": b}
    else:
        callback = instance.method

    cb = Callback()
    cb.set(callback)
    cb.trigger_with_kwargs(a=1, b=2)
    assert called
    assert kwargs_received == {"a": 1, "b": 2}


def test_callback_with_args_and_kwargs(callback_type: CallbackType) -> None:
    """Test callback with both positional and keyword arguments
    """
    called = False
    args_received: tuple[int, int] | None = None
    kwargs_received: dict[str, int] | None = None

    class TestClass:
        def method(self, a: int, b: int, *, c: int) -> None:
            nonlocal called, args_received, kwargs_received
            called = True
            args_received = (a, b)
            kwargs_received = {"c": c}
    instance = TestClass()

    if callback_type == "function_callback":
        def callback(a: int, b: int, *, c: int) -> None:
            nonlocal called, args_received, kwargs_received
            called = True
            args_received = (a, b)
            kwargs_received = {"c": c}
    else:
        callback = instance.method

    cb = Callback()
    cb.set(callback)
    cb.trigger_with_args_and_kwargs(1, 2, c=3)
    assert called
    assert args_received == (1, 2)
    assert kwargs_received == {"c": 3}
