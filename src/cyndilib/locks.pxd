# cython: language_level=3
# distutils: language = c++

from libc.stdint cimport int64_t
from libcpp.mutex cimport timed_mutex, unique_lock
from libcpp.list cimport list as cpp_list
from cpython.pythread cimport PyThread_get_thread_ident
from cpython.ref cimport PyObject

cdef extern from *:
    ctypedef Py_ssize_t Py_intptr_t

ctypedef long long PY_TIMEOUT_T

ctypedef cpp_list[Py_intptr_t] obj_ptr_list_t

cdef struct UniqueLockStatus_s:
    long owner
    int acquire_count
    int pending_requests

cdef class Lock:
    cdef UniqueLockStatus_s _unique_lock_status
    cdef timed_mutex _mutex
    cdef public str name

    cdef bint _is_locked(self) except -1 nogil
    cdef bint _do_acquire_gil_held(self, long owner) except -1
    cdef bint _do_acquire_nogil(self, long owner) except -1 nogil
    cdef bint _do_acquire_timed_gil_held(self, long owner, PY_TIMEOUT_T num_microseconds) except -1
    cdef bint _do_acquire_timed_nogil(self, long owner, PY_TIMEOUT_T num_microseconds) except -1 nogil
    cdef int _do_release(self) except -1 nogil
    cdef int _check_acquire(self) except -1 nogil
    cdef int _check_release(self) except -1
    cdef int _check_release_nogil(self, long owner) except -1 nogil
    cdef bint _acquire(self, bint block, double timeout) except -1
    cdef bint _acquire_nogil(self, long owner, bint block, double timeout) except -1 nogil
    cdef bint _release(self) except -1
    cdef bint _release_nogil(self, long owner) except -1 nogil
    cpdef bint acquire(self, bint block=*, double timeout=*) except -1
    cpdef bint release(self) except -1

cdef class RLock(Lock):

    cdef bint _is_owned_c(self, long owner) except -1 nogil
    cpdef bint _is_owned(self) except -1
    cdef int _acquire_restore_c_gil_held(self, long current_owner, int count, long owner) except -1
    cdef int _acquire_restore_c_nogil(self, long current_owner, int count, long owner) except -1 nogil
    cdef int _acquire_restore(self, (int, long) state) except -1
    cdef (int, long) _release_save_c(self) except *
    cdef (int, long) _release_save(self) except *

cdef class Condition:
    cdef readonly RLock rlock
    # cdef readonly object _waiters
    cdef obj_ptr_list_t _waiters

    cpdef bint acquire(self, bint block=*, double timeout=*) except -1
    cdef bint _acquire(self, bint block, double timeout) except -1
    cpdef bint release(self) except -1
    cdef bint _release(self) except -1
    # cpdef _acquire_restore(self, state)
    cdef int _acquire_restore(self, (int, long) state) except -1
    cdef (int, long) _release_save(self) except *
    cpdef bint _is_owned(self) except -1
    cdef int _ensure_owned(self) except -1
    cpdef bint wait(self, object timeout=*)
    cdef bint _wait(self, bint block, double timeout=*) except -1
    cpdef bint wait_for(self, object predicate, object timeout=*) except -1
    cdef int _notify(self, Py_ssize_t n=*) except -1
    cdef int _notify_all(self) except -1


cdef class Event:
    cdef readonly Condition _cond
    cdef readonly bint _flag

    cdef bint _is_set(self) noexcept nogil
    cdef int _set(self) except -1
    cdef int _clear(self) except -1
    cdef bint _wait(self, bint block, double timeout) except -1
