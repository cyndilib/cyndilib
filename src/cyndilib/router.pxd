# cython: language_level=3
# distutils: language = c++

from libc.stdint cimport *
from libcpp.string cimport string as cpp_string
from libcpp.set cimport set as cpp_set

from .wrapper.ndi_structs cimport NDIlib_source_t
from .wrapper.ndi_routing cimport *
from .finder cimport Source, Finder
from .callback cimport Callback


ctypedef cpp_set[cpp_string] cpp_str_set


cdef class Router:
    cdef object __weakref__  # Allow weak references to Router instances
    cdef bint _is_open
    cdef readonly str name
    cdef readonly str groups
    cdef readonly bytes _b_name
    cdef readonly bytes _b_groups
    cdef cpp_string cpp_name
    cdef cpp_string cpp_groups
    cdef NDIlib_routing_instance_t ptr
    cdef NDIlib_routing_create_t create_settings
    cdef NDIlib_source_t* source_ptr
    cdef NDIlib_source_t* dest_ptr
    cdef readonly Source source
    cdef readonly Source dest

    cdef int _open(self) except -1
    cdef int _close(self) except -1
    cdef bint _routing_change(self, Source source) except -1
    cdef bint _routing_clear(self) except -1
    cdef int _get_num_connections(self) except -1 nogil
    cdef bint _get_is_active(self) except -1
    cdef int _ensure_open(self) except -1


cdef class RoutingMatrix:
    cdef object __weakref__  # Allow weak references to RoutingMatrix instances
    cdef cpp_str_set dest_names
    cdef bint _is_open
    cdef readonly Finder finder
    cdef list routers
    cdef dict routers_by_name
    cdef dict routing_table
    cdef Callback finder_callback

    cdef int _open(self) except -1
    cdef int _close(self) except -1
    cdef bint _router_exists(self, cpp_string name) except -1
    cdef Router _get_router_by_cpp_name(self, cpp_string name)
    cdef int _add_router(self, Router router) except -1
    cdef int _remove_router(self, Router router) except -1
    cdef int _make_route(self, Router router, cpp_string cpp_source_name) except -1
    cdef int _clear_route(self, Router router) except -1
    cdef int _update_all_routes(self) except -1
    cdef int _update_routes(self, Router router) except -1
