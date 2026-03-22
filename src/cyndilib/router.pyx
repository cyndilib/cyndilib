"""
Module implementing the `NDI Routing API`_.

.. versionadded:: 0.1.1

.. _NDI Routing API: https://docs.ndi.video/all/developing-with-ndi/sdk/ndi-routing

"""

__all__ = ("Router", "RoutingMatrix")


cdef class Router:
    """Class representing an |NDI| router instance

    With |NDI| routing, you can create virtual outputs on the network
    which 'look' like normal sources, but are actually just routing
    to other sources on the network.

    Arguments:
        name (str): The name of the router instance.
            This is the name that will appear on the network.
        groups (str, optional): The groups that this router instance belongs to.
            This is a comma-separated list of group names. Defaults to "".

    .. versionadded:: 0.1.1

    Attributes:
        name (str, readonly): The name of the router instance.
            This is the name that will appear on the network.
        groups (str, readonly): The groups that this router instance belongs to.
            This is a comma-separated list of group names.
        source (Source, readonly): The current source that this router is routing from.
            This will be ``None`` if there is no source currently connected.
        dest (Source, readonly): The current destination that this router is routing to.
            This will be ``None`` if there is no destination currently connected.

    """
    def __cinit__(self, *args, **kwargs):
        self.ptr = NULL
        self.source_ptr = NULL
        self.dest_ptr = NULL

    def __init__(self, str name, str groups = ""):
        self.name = name
        self.groups = groups
        self.cpp_name = name.encode('utf-8')
        self.cpp_groups = groups.encode('utf-8')
        self._b_name = self.cpp_name
        self._b_groups = self.cpp_groups
        self._is_open = False

    def __dealloc__(self):
        self.source_ptr = NULL
        self.dest_ptr = NULL
        self.source = None
        self.dest = None
        cdef NDIlib_routing_instance_t ptr = self.ptr
        self.ptr = NULL
        if ptr is not NULL:
            NDIlib_routing_destroy(ptr)

    @property
    def source_host_name(self):
        """The current :attr:`~.finder.Source.host_name` of the :attr:`source`

        This will be ``None`` if there is no :attr:`source` currently connected.
        """
        if self.source is not None:
            return self.source.host_name
        return None

    @property
    def source_stream_name(self):
        """The current :attr:`~.finder.Source.stream_name` of the :attr:`source`

        This will be ``None`` if there is no :attr:`source` currently connected.
        """
        if self.source is not None:
            return self.source.stream_name
        return None

    @property
    def dest_host_name(self):
        """The current :attr:`~.finder.Source.host_name` of the :attr:`dest`

        This will be ``None`` if there is no :attr:`dest` currently connected.
        """
        if self.dest is not None:
            return self.dest.host_name
        return None

    @property
    def dest_stream_name(self):
        """The current :attr:`~.finder.Source.stream_name` of the :attr:`dest`

        This will be ``None`` if there is no :attr:`dest` currently connected.
        """
        if self.dest is not None:
            return self.dest.stream_name
        return None

    cdef int _open(self) except -1:
        if self._is_open:
            return 0
        self._is_open = True
        self.create_settings.p_ndi_name = self._b_name
        self.create_settings.p_groups = self._b_groups
        cdef const NDIlib_routing_create_t* p_create_settings = &self.create_settings
        self.ptr = NDIlib_routing_create(p_create_settings)
        if not self.ptr:
            raise MemoryError("Failed to create NDI routing instance")
        cdef const NDIlib_source_t* p_dest = NDIlib_routing_get_source_name(self.ptr)
        self.dest_ptr = <NDIlib_source_t*>p_dest
        self.dest = Source.create_no_parent(self.dest_ptr)
        return 0

    cdef int _close(self) except -1:
        if not self._is_open:
            return 0
        self._is_open = False
        self.dest = None
        self.source = None
        self.source_ptr = NULL
        self.dest_ptr = NULL
        cdef NDIlib_routing_instance_t ptr = self.ptr
        self.ptr = NULL
        if ptr is not NULL:
            NDIlib_routing_destroy(ptr)
        return 0

    cdef bint _routing_change(self, Source source) except -1:
        self._ensure_open()
        if source is None:
            return self._routing_clear()
        cdef const NDIlib_source_t* p_source = source.ptr
        cdef bint result = NDIlib_routing_change(self.ptr, p_source)
        if result:
            self.source = source
            self.source_ptr = <NDIlib_source_t*>p_source
        else:
            self.source = None
            self.source_ptr = NULL
        return result

    cdef bint _routing_clear(self) except -1:
        self._ensure_open()
        if self.source_ptr is NULL:
            return False
        cdef bint result = NDIlib_routing_clear(self.ptr)
        if result:
            self.source_ptr = NULL
            self.source = None
        return result

    cdef int _get_num_connections(self) except -1 nogil:
        if self.ptr is NULL:
            return 0
        cdef int num_connections = NDIlib_routing_get_no_connections(self.ptr, 0)
        if num_connections < 0:
            num_connections = 0
        return num_connections

    cdef int _ensure_open(self) except -1:
        if not self._is_open:
            raise RuntimeError("Router is not open")
        return 0

    cdef bint _get_is_active(self) except -1:
        if not self._is_open:
            return False
        if self.source_ptr is NULL or self.dest_ptr is NULL:
            return False
        if not self.source.valid:
            return False
        return True

    def open(self):
        """Open the routing instance
        """
        self._open()

    def close(self):
        """Close the routing instance
        """
        self._close()

    @property
    def is_open(self):
        """Whether the routing instance is currently open
        """
        return self._is_open

    @property
    def is_active(self):
        """Whether the routing instance is currently active
        (i.e. has a valid source connected and is open)
        """
        return self._get_is_active()

    def routing_change(self, Source source):
        """Change the routing to the specified source

        Raises:
            RuntimeError: If the router is not open.

        """
        return self._routing_change(source)

    def routing_clear(self):
        """Clear the current routing

        Raises:
            RuntimeError: If the router is not open.

        """
        return self._routing_clear()

    def get_num_connections(self):
        """Get the current number of receivers connected to this router
        """
        return self._get_num_connections()

    def __enter__(self):
        self._open()
        return self

    def __exit__(self, *args):
        self._close()

    def __repr__(self):
        return f"<Router name={self.name} groups={self.groups} source={self.source} dest={self.dest}>"

    def __str__(self):
        return f"Router(name={self.name}, groups={self.groups}, source={self.source}, dest={self.dest})"



cdef class RoutingMatrix:
    """Class representing a routing matrix, which manages multiple :class:`Router` instances
    and their routing definitions.

    This class also manages its own :class:`~.Finder` instance to discover
    available sources on the network.

    .. versionadded:: 0.1.1

    Attributes:
        finder (Finder, readonly): The Finder instance used to discover sources on the network.

    """
    def __init__(self):
        self._is_open = False
        self.finder = Finder()
        self.routers = []
        self.routers_by_name = {}
        self.routing_table = {}
        self.finder_callback = Callback()
        self.finder.set_change_callback(self._on_finder_change)

    def _on_finder_change(self):
        self._update_all_routes()
        self.finder_callback.trigger_callback()

    def set_finder_callback(self, object cb):
        """Set a callback function to be called whenever the finder's
        :attr:`~.Finder.change_callback` is triggered
        """
        self.finder_callback.set_callback(cb)

    cdef int _open(self) except -1:
        if self._is_open:
            return 0
        self._is_open = True
        self.finder.open()

        cdef Router router
        for router in self.routers:
            router._open()
        self._update_all_routes()
        return 0

    cdef int _close(self) except -1:
        if not self._is_open:
            return 0
        self._is_open = False
        cdef Router router
        for router in self.routers:
            router._close()
        self.finder.close()
        return 0

    def open(self):
        """Open the routing matrix and all contained routers
        """
        self._open()

    def close(self):
        """Close the routing matrix and all contained routers
        """
        self._close()

    @property
    def is_open(self):
        """Whether the routing matrix is currently open
        """
        return self._is_open

    def __enter__(self):
        self._open()
        return self

    def __exit__(self, *args):
        self._close()

    def __iter__(self):
        return iter(self.routers)

    def __len__(self):
        return len(self.routers)

    cdef bint _router_exists(self, cpp_string name) except -1:
        if self.dest_names.count(name) > 0:
            return True
        return False

    cdef Router _get_router_by_cpp_name(self, cpp_string name):
        return self.routers_by_name[name.decode('utf-8')]

    cdef int _add_router(self, Router router) except -1:
        if self._router_exists(router.cpp_name):
            raise KeyError(f"Router with name '{router.name}' already exists")
        self.dest_names.insert(router.cpp_name)
        self.routers.append(router)
        self.routers_by_name[router.name] = router
        self.routing_table[router.name] = None
        if self._is_open:
            router._open()
        return 0

    cdef int _remove_router(self, Router router) except -1:
        if not self._router_exists(router.cpp_name):
            raise KeyError(f"Router with name '{router.name}' does not exist")
        if router._is_open:
            router._close()
        self.dest_names.erase(router.cpp_name)
        self.routers.remove(router)
        del self.routers_by_name[router.name]
        del self.routing_table[router.name]
        return 0

    cdef int _make_route(self, Router router, cpp_string cpp_source_name) except -1:
        self.routing_table[router.name] = cpp_source_name.decode('utf-8')
        if self._is_open:
            self._update_routes(router)
        return 0

    cdef int _clear_route(self, Router router) except -1:
        self.routing_table[router.name] = None
        if self._is_open:
            router._routing_clear()
        return 0

    cdef int _update_all_routes(self) except -1:
        if not self._is_open:
            return 0
        cdef Router router
        for router in self.routers:
            self._update_routes(router)
        return 0

    cdef int _update_routes(self, Router router) except -1:
        if not self._is_open:
            return 0
        if router.name not in self.routing_table:
            return 0
        source_name = self.routing_table[router.name]
        if source_name is None:
            if router.source is not None:
                router._routing_clear()
            return 0
        cdef Source source
        source = self.finder.get_source(source_name)
        if source is None:
            return 0
        router._routing_change(source)
        return 0

    def get_routing_table(self):
        """Get the current routing table as a dictionary mapping router names to source names

        The returned dictionary is formatted as ``{router_name: source_name, ...}``
        and is a copy of the internal routing table, so modifying it will not
        affect the routing matrix.

        For routers that do not have a source currently connected,
        the source name will be ``None``.
        """
        return self.routing_table.copy()

    def set_routing_table(self, dict routing_table):
        """Set the routing table from a dictionary mapping router names to source names

        The *routing_table* argument should be formatted as ``{router_name: source_name, ...}``.

        For routers that do not have a source currently connected,
        the source name should be ``None``.
        """
        cdef str dest_name
        cdef object source_name
        for dest_name, source_name in routing_table.items():
            if source_name is not None:
                self.make_route(dest_name, source_name)
            else:
                if not self.router_exists(dest_name):
                    self.add_router_by_name(dest_name)
                else:
                    self.clear_route(dest_name)

    def router_exists(self, str name):
        """Check if a router with the given name exists in the routing matrix
        """
        cdef cpp_string cpp_name = name.encode('utf-8')
        return self._router_exists(cpp_name)

    def add_router_by_name(self, str name, str groups = ""):
        """Add a router with the given name to the routing matrix

        Raises:
            KeyError: If a router with the given name already exists in the routing matrix
        """
        cdef Router router = Router(name, groups)
        self._add_router(router)
        return router

    def get_router_by_name(self, str name):
        """Get a router with the given name from the routing matrix

        Raises:
            KeyError: If a router with the given name does not exist in the routing matrix
        """
        return self.routers_by_name[name]

    def add_router(self, Router router):
        """Add the given router to the routing matrix

        Raises:
            KeyError: If a router with the same name as the given router already exists
                in the routing matrix
        """
        self._add_router(router)

    def remove_router_by_name(self, str name):
        """Remove a router with the given name from the routing matrix

        Raises:
            KeyError: If a router with the given name does not exist in the routing matrix
        """
        cdef cpp_string cpp_name = name.encode('utf-8')
        cdef Router router = self._get_router_by_cpp_name(cpp_name)
        self._remove_router(router)

    def remove_router(self, Router router):
        """Remove the given router from the routing matrix

        Raises:
            KeyError: If the given router does not exist in the routing matrix
        """
        self._remove_router(router)

    def make_route(self, str dest_name, str source_name):
        """Make a route from the source with the given name to the router with the given name

        If a router with the given destination name does not already exist, it will be created.
        """
        cdef Router router
        cdef cpp_string cpp_dest_name = dest_name.encode('utf-8')
        if not self._router_exists(cpp_dest_name):
            router = Router(dest_name)
            self._add_router(router)
        else:
            router = self._get_router_by_cpp_name(cpp_dest_name)
        cdef cpp_string cpp_source_name = source_name.encode('utf-8')
        self._make_route(router, cpp_source_name)
        return router

    def clear_route(self, str dest_name):
        """Clear the route for the router with the given name

        .. note::

            This will not remove the router from the routing matrix,
            it will just clear its current routing to any source.


        Raises:
            KeyError: If a router with the given name does not exist in the routing matrix
        """
        cdef cpp_string cpp_dest_name = dest_name.encode('utf-8')
        if not self._router_exists(cpp_dest_name):
            raise KeyError(f"Router with name '{dest_name}' does not exist")
        cdef Router router = self._get_router_by_cpp_name(cpp_dest_name)
        self._clear_route(router)
        return router
