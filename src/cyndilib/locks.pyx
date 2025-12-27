
"""Thread synchronization primitives implemented at the C level

This module is **heavily** inspired by the `FastRLock`_ library with a few
adjustments and additions.

.. _FastRLock: https://github.com/scoder/fastrlock
"""

import threading
from itertools import islice
from collections import deque

from cpython.ref cimport Py_INCREF, Py_DECREF
from cpython.mem cimport PyMem_Malloc, PyMem_Free

from .clock cimport time


__all__ = ('Lock', 'RLock', 'Condition', 'Event')


cdef extern from "<ratio>" namespace "std::ratio" nogil:
    cppclass micro:
        pass
    cppclass seconds:
        pass

cdef extern from "<chrono>" namespace "std::chrono" nogil:
    cppclass duration[T, U]:
        duration()
        duration(T)
    cppclass microseconds(duration[long long, micro]):
        microseconds()
        microseconds(long long)



cdef class Lock:
    """Implementation of :class:`threading.Lock`. A Primitive non-reentrant
    lock (or mutex)

    This class supports use as a :term:`context manager` and can be acquired
    and released using the :keyword:`with` statement.
    """
    def __cinit__(self):
        self._unique_lock_status.owner = -1
        self._unique_lock_status.acquire_count = 0
        self._unique_lock_status.pending_requests = 0
        self.name = ''

    @property
    def owner(self):
        """The thread ID of the thread that currently owns the lock, or ``-1``
        if the lock is not acquired.
        """
        return self._unique_lock_status.owner

    @property
    def locked(self):
        """True if the lock is acquired
        """
        return self._is_locked()

    cdef bint _is_locked(self) except -1 nogil:
        cdef bint was_acquired = self._mutex.try_lock()
        if was_acquired:
            self._mutex.unlock()
        return not was_acquired

    cdef bint _do_acquire_gil_held(self, long owner) except -1:
        with nogil:
            return self._do_acquire_nogil(owner)

    cdef bint _do_acquire_nogil(self, long owner) except -1 nogil:
        self._mutex.lock()
        self._unique_lock_status.owner = owner
        self._unique_lock_status.acquire_count += 1
        return True

    cdef bint _do_acquire_timed_gil_held(self, long owner, PY_TIMEOUT_T num_microseconds) except -1:
        with nogil:
            return self._do_acquire_timed_nogil(owner, num_microseconds)

    cdef bint _do_acquire_timed_nogil(self, long owner, PY_TIMEOUT_T num_microseconds) except -1 nogil:
        cdef microseconds dur = microseconds(num_microseconds)
        cdef bint result = self._mutex.try_lock_for(dur)
        if result:
            self._unique_lock_status.owner = owner
            self._unique_lock_status.acquire_count += 1
        return result

    cdef int _do_release(self) except -1 nogil:
        cdef int acquire_count = self._unique_lock_status.acquire_count - 1
        if acquire_count < 0:
            acquire_count = 0
        self._unique_lock_status.acquire_count = acquire_count
        if acquire_count == 0:
            self._unique_lock_status.owner = -1
            self._mutex.unlock()
        return 0

    cdef int _check_acquire(self) except -1 nogil:
        return 0

    cdef int _check_release(self) except -1:
        return 0

    cdef int _check_release_nogil(self, long owner) except -1 nogil:
        return 0

    cdef bint _acquire(self, bint block, double timeout) except -1:
        cdef long owner = PyThread_get_thread_ident()
        with nogil:
            return self._acquire_nogil(owner, block, timeout)

    cdef bint _acquire_nogil(self, long owner, bint block, double timeout) except -1 nogil:
        cdef double microseconds
        cdef double multiplier = 1000000
        self._check_acquire()
        if timeout == 0:
            block = False
        elif timeout < 0:
            block = True
        if block:
            if timeout < 0:
                return self._do_acquire_nogil(owner)
            microseconds = timeout * multiplier
            return self._do_acquire_timed_nogil(owner, <PY_TIMEOUT_T> microseconds)
        cdef bint was_acquired = self._mutex.try_lock()
        if was_acquired:
            self._unique_lock_status.owner = owner
            self._unique_lock_status.acquire_count += 1
        return was_acquired

    cdef bint _release(self) except -1:
        self._check_release()
        self._do_release()
        return self._is_locked()

    cdef bint _release_nogil(self, long owner) except -1 nogil:
        self._check_release_nogil(owner)
        self._do_release()
        return self._is_locked()

    cpdef bint acquire(self, bint block=True, double timeout=-1) except -1:
        """Acquire the lock, blocking or non-blocking

        Arguments:
            block (bool, optional): If ``True`` (the default), block until the
                lock is unlocked. If ``False``, acquire the lock if it it isn't
                already locked and return immediately.
            timeout (float, optional): Maximum time (in seconds) to block
                waiting to acquire the lock. A value of ``-1`` specifies an
                unbounded wait.


        .. note::

            The arguments in this method vary slightly from that of
            :meth:`threading.Lock.acquire` where it is considered an error to
            specify a *timeout* with *blocking* set to ``False``.

            In this implementation, the *block* argument is ignored if *timeout*
            is given.

        Returns:
            bool: ``True`` if the lock was acquired, otherwise ``False``.

        """
        return self._acquire(block, timeout)

    cpdef bint release(self) except -1:
        """Release the lock

        Raises:
            RuntimeError: If the lock is not :attr:`locked`
        """
        return self._release()

    def __enter__(self):
        self._acquire(True, -1)
        return self

    def __exit__(self, *args):
        self._release()

    def __repr__(self):
        return '<{self.__class__} {self.name} (locked={self.locked}, owner={self.owner}) at {id}>'.format(self=self, id=id(self))


cdef class RLock(Lock):
    """Implementation of :class:`threading.RLock`. A reentrant lock that can be
    acquired multiple times by the same thread

    Each call to :meth:`~Lock.acquire` must be followed by corresponding a call
    to :meth:`~Lock.release` before the lock is unlocked.

    This class supports use as a :term:`context manager` and can be acquired
    and released using the :keyword:`with` statement.
    """
    cdef bint _do_acquire_nogil(self, long owner) except -1 nogil:
        cdef bint is_locked = self._is_locked()
        if owner == self._unique_lock_status.owner and is_locked:
            self._unique_lock_status.acquire_count += 1
            return True
        return Lock._do_acquire_nogil(self, owner)

    cdef bint _do_acquire_timed_nogil(self, long owner, PY_TIMEOUT_T microseconds) except -1 nogil:
        cdef bint is_locked = self._is_locked()
        if owner == self._unique_lock_status.owner and is_locked:
            self._unique_lock_status.acquire_count += 1
            return True
        return Lock._do_acquire_timed_nogil(self, owner, microseconds)

    cdef int _check_acquire(self) except -1 nogil:
        return 0

    cdef int _check_release(self) except -1:
        cdef long current_thread = PyThread_get_thread_ident()
        if self._unique_lock_status.owner != current_thread:
            raise RuntimeError('cannot release un-owned lock')
        return 0

    cdef int _check_release_nogil(self, long owner) except -1 nogil:
        if self._unique_lock_status.owner != owner:
            with gil:
                raise RuntimeError('cannot release un-owned lock')
        return 0

    cdef bint _is_owned_c(self, long owner) except -1 nogil:
        return owner == self._unique_lock_status.owner

    cpdef bint _is_owned(self) except -1:
        cdef long tid = PyThread_get_thread_ident()
        return self._is_owned_c(tid)

    cdef int _acquire_restore_c_gil_held(self, long current_owner, int count, long owner) except -1:
        with nogil:
            self._acquire_restore_c_nogil(current_owner, count, owner)
        return 0

    cdef int _acquire_restore_c_nogil(self, long current_owner, int count, long owner) except -1 nogil:
        self._do_acquire_nogil(current_owner)
        self._unique_lock_status.acquire_count = count
        self._unique_lock_status.owner = owner
        return 0

    cdef int _acquire_restore(self, (int, long) state) except -1:
        cdef int count
        cdef long current_owner, owner
        current_owner = PyThread_get_thread_ident()
        count, owner = state
        self._acquire_restore_c_gil_held(current_owner, count, owner)
        return 0

    cdef (int, long) _release_save_c(self) except *:
        cdef int count = self._unique_lock_status.acquire_count
        cdef long owner = self._unique_lock_status.owner

        self._do_release()
        return count, owner

    cdef (int, long) _release_save(self) except *:
        if not self._unique_lock_status.acquire_count:
            raise RuntimeError("cannot release un-acquired lock")
        return self._release_save_c()

cdef class Condition:
    """Implementation of :class:`threading.Condition`. Allows one or more thread
    to wait until they are notified by another thread.

    Arguments:
        init_lock (RLock, optional): If provided, a :class:`RLock` instance to be
            used as the underlying lock. If not provided or ``None`` a new
            :class:`RLock` will be created.

    This class supports use as a :term:`context manager` and can be acquired
    and released using the :keyword:`with` statement.
    """
    def __cinit__(self, init_lock=None, *args, **kwargs):
        cdef RLock lock
        if init_lock is not None:
            assert isinstance(init_lock, RLock)
            lock = init_lock
        else:
            lock = RLock()
        self.rlock = lock
        # self._waiters = deque()

    def __enter__(self):
        self.rlock._acquire(True, -1)
        return self

    def __exit__(self, *args):
        # return self.rlock.__exit__(*args)
        self.rlock._release()

    cpdef bint acquire(self, bint block=True, double timeout=-1) except -1:
        """Acquire the underlying lock

        Arguments and return values match those of :meth:`Lock.acquire`
        """
        return self.rlock._acquire(block, timeout)

    cdef bint _acquire(self, bint block, double timeout) except -1:
        return self.rlock._acquire(block, timeout)

    cpdef bint release(self) except -1:
        """Release the underlying lock

        Arguments and return values match those of :meth:`Lock.release`
        """
        return self.rlock._release()

    cdef bint _release(self) except -1:
        return self.rlock._release()

    cdef int _acquire_restore(self, (int, long) state) except -1:
        self.rlock._acquire_restore(state)
        return 0

    cdef (int, long) _release_save(self) except *:
        return self.rlock._release_save()

    cpdef bint _is_owned(self) except -1:
        cdef long tid = PyThread_get_thread_ident()
        return self.rlock._is_owned_c(tid)

    cdef int _ensure_owned(self) except -1:
        if not self._is_owned():
            raise RuntimeError("cannot wait on un-acquired lock")
        return 0

    def __repr__(self):
        return "<Condition(%s, %d)>" % (self._lock, self._waiters.size())

    cpdef bint wait(self, object timeout=None):
        """Wait until notified or until a timeout occurs

        The underlying lock must be held before a call to this method.
        Once called, releases lock then blocks until awakened by a call to
        :meth:`notify` or :meth:`notify_all` by another thread, or until the
        timeout (if given) has been reached.

        Arguments:
            timeout (float, optional): If provided, the maximum amount of time
                (in seconds) to block. If ``-1`` is given (or ``None``), the
                blocking duration is unbounded.

        Returns:
            bool: ``True`` if notified before the timeout (if any), ``False``
                if a timeout was given and was reached.

        Raises:
            RuntimeError: If the lock was not acquired before this
                method was called
        """
        cdef bint block
        cdef double _timeout

        if timeout is None:
            _timeout = -1
            block = True
        else:
            block = False
            _timeout = <double> timeout
        return self._wait(block, _timeout)

    cdef bint _wait(self, bint block, double timeout=-1) except -1:
        cdef Lock waiter
        cdef bint gotit = False

        self._ensure_owned()
        waiter = Lock()
        waiter._acquire(True, -1)
        # self._waiters.append(waiter)
        cdef PyObject* obj_ptr = <PyObject*>waiter
        cdef Py_intptr_t w_id = <Py_intptr_t>obj_ptr
        self._waiters.push_back(w_id)
        Py_INCREF(waiter)
        cdef (int, long) saved_state = self._release_save()

        try:    # restore state no matter what (e.g., KeyboardInterrupt)
            if block:
                waiter._acquire(True, -1)
                gotit = True
            else:
                if timeout > 0:
                    gotit = waiter._acquire(True, timeout)
                else:
                    gotit = waiter._acquire(False, -1)
            return gotit
        finally:
            self._acquire_restore(saved_state)
            if not gotit:
                # if waiter in self._waiters:
                #     self._waiters.remove(waiter)
                self._waiters.remove(w_id)
                Py_DECREF(waiter)
                # try:
                #     self._waiters.remove(waiter)
                # except ValueError:
                #     pass

    cpdef bint wait_for(self, object predicate, object timeout=None) except -1:
        """Wait until a condition evaluates to ``True``

        Repeatedly calls :meth:`wait` until the given predicate is satisfied or
        the timeout has been reached.

        Arguments:
            predicate (typing.Callable): A callable whose return value will be
                evaluated as a boolean value. Any returned value that can be
                evaluated as ``True`` (``bool(predicate())``) will satisfy the
                condition.
            timeout (float, optional): If provided, the maximum amount of time
                (in seconds) to wait for the condition to be satisfied.
                If ``-1`` is given (or ``None``), waits indefinitely.

        Returns:
            bool: ``True`` if the condition was satisfied before the timeout
            (if given), ``False`` otherwise.

        Raises:
            RuntimeError: If the lock was not acquired before this
                method was called
        """
        cdef double _timeout, endtime, waittime
        cdef bint has_timeout, result

        if timeout is not None:
            has_timeout = True
            _timeout = <double> timeout
            waittime = _timeout
            endtime = -1
        else:
            has_timeout = False

        result = predicate()
        while not result:
            if has_timeout:
                if endtime == -1:
                    endtime = time() + waittime
                else:
                    waittime = endtime - time()
                    if waittime <= 0:
                        break
            self._wait(True, waittime)
            result = predicate()
        return result

    def notify(self, Py_ssize_t n=1):
        """Wake up at least *n* threads waiting for this condition variable

        The lock must be acquired before this method is called. Since waiting
        threads must reacquire the lock before returning from the
        :meth:`wait` method, the caller must release it.

        Arguments:
            n (int): Maximum number of threads to notify. Defaults to ``1``

        Raises:
            RuntimeError: If the lock was not acquired before this
                method was called
        """
        self._notify(n)

    cdef int _notify(self, Py_ssize_t n=1) except -1:
        cdef Lock waiter

        self._ensure_owned()
        # all_waiters = self._waiters
        # waiters_to_notify = deque(islice(all_waiters, n))
        # cdef obj_ptr_list_t waiters_to_notify = [v for v in enumerate(self._waiters) if i >= n]
        # if not waiters_to_notify:
        #     return
        cdef PyObject* obj_ptr# = <PyObject*>waiter
        cdef Py_intptr_t w_id# = <Py_intptr_t>obj_ptr
        # cdef Lock waiter
        cdef size_t i = 0
        while n > 0 and self._waiters.size():
            # i += 1
            # if i < n:
            #     continue
            w_id = self._waiters.front()
            self._waiters.pop_front()
            obj_ptr = <PyObject*>w_id
            waiter = <object>obj_ptr
            waiter._release()
            Py_DECREF(waiter)
            n -= 1
            # waiter = waiters_to_notify.popleft()
            # waiter._release()
        # for waiter in waiters_to_notify:
        #     waiter._release()
        #     try:
        #         all_waiters.remove(waiter)
        #     except ValueError:
        #         pass
        return 0

    def notify_all(self):
        """Like :meth:`notify`, but wakes all waiting threads

        Raises:
            RuntimeError: If the lock was not acquired before this
                method was called
        """
        self._notify(self._waiters.size())

    cdef int _notify_all(self) except -1:
        self._notify(self._waiters.size())
        return 0

cdef class Event:
    """Implementation of :class:`threading.Event`. A simple flag-based thread
    communication primitive where one thread signals an event and other
    threads wait for it.
    """
    def __init__(self):
        self._cond = Condition()
        self._flag = False

    def is_set(self) -> bool:
        """Returns ``True`` if the event has been set
        """
        return self._flag

    cdef bint _is_set(self) noexcept nogil:
        return self._flag

    def set(self):
        """Set the internal flag to ``True``, awakening any threads waiting for it
        """
        self._set()

    cdef int _set(self) except -1:
        self._cond._acquire(True, -1)
        try:
            self._flag = True
            self._cond.notify_all()
        finally:
            self._cond._release()
        return 0

    def clear(self):
        """Reset the internal flag to ``False``.  After this, any threads making
        a call to :meth:`wait` will block until the event is :meth:`set` again
        """
        self._clear()

    cdef int _clear(self) except -1:
        self._cond._acquire(True, -1)
        self._flag = False
        self._cond._release()
        return 0

    def wait(self, object timeout=None) -> bool:
        """Block until the internal flag is ``True`` by a call to :meth:`set`
        by another thread. If the flag is already ``True``, return immediately.

        Arguments:
            timeout (float, optional): If given, the maximum time in seconds to
                block waiting for the flag. If ``-1`` (or ``None``), blocks
                indefinitely.

        Returns:
            bool: ``True`` if the flag was set before a timeout, ``False`` otherwise
        """
        cdef bint block
        cdef double _timeout

        if timeout is None:
            _timeout = -1
            block = True
        else:
            block = False
            _timeout = <double> timeout

        return self._wait(block, timeout)

    cdef bint _wait(self, bint block, double timeout) except -1:
        cdef bint signaled
        self._cond._acquire(True, -1)
        try:
            signaled = self._flag
            if not signaled:
                signaled = self._cond._wait(block, timeout)
            return signaled
        finally:
            self._cond._release()
