# cython: language_level=3
# distutils: language = c++

from libc.stdint cimport *

from .ndi_structs cimport NDIlib_source_t


cdef extern from "Processing.NDI.Routing.h" nogil:
    # // Structures and type definitions required by NDI routing.
    # // The reference to an instance of the router.
    cdef struct NDIlib_routing_instance_type
    ctypedef NDIlib_routing_instance_type* NDIlib_routing_instance_t

    # // The creation structure that is used when you are creating a sender.
    cdef struct NDIlib_routing_create_t:
        # // The name of the NDI source to create. This is a NULL terminated UTF8 string.
        const char* p_ndi_name

        # // What groups should this source be part of.
        const char* p_groups

    # // Create an NDI routing source.
    cdef NDIlib_routing_instance_t NDIlib_routing_create(const NDIlib_routing_create_t* p_create_settings)

    # // Destroy and NDI routing source.
    cdef void NDIlib_routing_destroy(NDIlib_routing_instance_t p_instance)

    # // Change the routing of this source to another destination.
    cdef bint NDIlib_routing_change(NDIlib_routing_instance_t p_instance, const NDIlib_source_t* p_source)

    # // Change the routing of this source to another destination.
    cdef bint NDIlib_routing_clear(NDIlib_routing_instance_t p_instance)

    # // Get the current number of receivers connected to this source. This can be used to avoid even rendering
    # // when nothing is connected to the video source. which can significantly improve the efficiency if you want
    # // to make a lot of sources available on the network. If you specify a timeout that is not 0 then it will
    # // wait until there are connections for this amount of time.
    cdef int NDIlib_routing_get_no_connections(NDIlib_routing_instance_t p_instance, uint32_t timeout_in_ms)

    # // Retrieve the source information for the given router instance.  This pointer is valid until
    # // NDIlib_routing_destroy is called.
    cdef const NDIlib_source_t* NDIlib_routing_get_source_name(NDIlib_routing_instance_t p_instance)
