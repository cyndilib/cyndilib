from __future__ import annotations

import pytest

from cyndilib import Router, RoutingMatrix



def build_unique_name(request: pytest.FixtureRequest, suffix: str = '') -> str:
    mod_name = request.node.nodeid.split('::')[0].split('/')[-1].split('.')[0]
    test_name = request.node.nodeid.split('::')[-1]
    name = f'{mod_name}_{test_name}'
    if suffix:
        name = f"{name}_{suffix}"
    return name

@pytest.fixture
def unique_sender_name(request):
    return build_unique_name(request)



def test_router(unique_sender_name):
    router = Router(unique_sender_name)
    assert router.name == unique_sender_name
    assert router.groups == ''
    assert router.source is None
    assert router.dest is None
    assert router.source_host_name is None
    assert router.source_stream_name is None
    assert router.dest_host_name is None
    assert router.dest_stream_name is None
    assert not router.is_open
    with pytest.raises(RuntimeError):
        router.routing_change(None)
    with pytest.raises(RuntimeError):
        router.routing_clear()
    with router:
        assert router.is_open
        assert router.dest is not None
        assert router.dest.stream_name == unique_sender_name
        assert router.dest_stream_name == unique_sender_name
        assert not router.routing_change(None)
        assert not router.routing_clear()
    assert not router.is_open


def test_routing_matrix(request):
    matrix = RoutingMatrix()
    assert not matrix.is_open
    router_names = [
        build_unique_name(request, suffix=f'router{i}')
        for i in range(3)
    ]
    source_names = [
        build_unique_name(request, suffix=f'source{i}')
        for i in range(3)
    ]
    assert not matrix.is_open
    assert not matrix.finder.is_open
    assert not len(matrix)
    with matrix:
        assert matrix.is_open
        assert matrix.finder.is_open

        for i, name in enumerate(router_names):
            assert not matrix.router_exists(name)
            router = matrix.add_router_by_name(name)
            assert len(matrix) == i + 1
            assert matrix.router_exists(name)
            assert matrix.get_router_by_name(name) is router
            assert router.is_open
            assert router.dest_stream_name == name
            with pytest.raises(KeyError):
                matrix.add_router_by_name(name)
            with pytest.raises(KeyError):
                matrix.add_router(Router(name))

        assert set(router.name for router in matrix) == set(router_names)

        for dest_name, source_name in zip(router_names, source_names):
            # When testing in CI, we can't depend on any sources present,
            # so we can only check that the routing table is updated correctly.
            matrix.make_route(dest_name=dest_name, source_name=source_name)
            routing_table = matrix.get_routing_table()
            assert routing_table[dest_name] == source_name
            matrix.clear_route(dest_name=dest_name)
            routing_table = matrix.get_routing_table()
            assert routing_table[dest_name] is None
            assert matrix.router_exists(dest_name)

        # Remove one router and check that it is removed correctly
        matrix.remove_router_by_name(router_names[0])
        assert not matrix.router_exists(router_names[0])
        del router_names[0]
    assert not matrix.is_open
    assert not matrix.finder.is_open
    for name in router_names:
        router = matrix.get_router_by_name(name)
        assert router is not None
        assert not router.is_open


def test_routing_matrix_prepopulated(request):
    router_names = [
        build_unique_name(request, suffix=f'router{i}')
        for i in range(3)
    ]
    source_names = [
        build_unique_name(request, suffix=f'source{i}')
        for i in range(3)
    ]
    routing_table = {rname: sname for rname, sname in zip(router_names, source_names)}
    matrix = RoutingMatrix()
    matrix.set_routing_table(routing_table)
    for rname, sname in routing_table.items():
        router = matrix.get_router_by_name(rname)
        assert router is not None
        assert router.name == rname
        assert not router.is_open
        # we don't have a dest stream until the router is open, so we can't check that here

    assert matrix.get_routing_table() == routing_table
    with matrix:
        for rname, sname in routing_table.items():
            router = matrix.get_router_by_name(rname)
            assert router is not None
            assert router.is_open
            assert router.dest_stream_name == rname
            # we don't have a source stream since it doesn't exist,
            # so we can only check that the routing table is correct
            assert matrix.get_routing_table()[rname] == sname
        assert matrix.get_routing_table() == routing_table


def test_routing_matrix_reassignment(request):
    router_names = [
        build_unique_name(request, suffix=f'router{i}')
        for i in range(3)
    ]
    source_names = [
        build_unique_name(request, suffix=f'source{i}')
        for i in range(3)
    ]
    routing_table = {rname: sname for rname, sname in zip(router_names, source_names)}
    matrix = RoutingMatrix()
    with matrix:
        matrix.set_routing_table(routing_table)
        for rname, sname in routing_table.items():
            router = matrix.get_router_by_name(rname)
            assert router is not None
            assert router.is_open
            assert router.dest_stream_name == rname
            # we don't have a source stream since it doesn't exist,
            # so we can only check that the routing table is correct
            assert matrix.get_routing_table()[rname] == sname

        # Assign `None` to all routes and check that they are cleared correctly
        for rname in router_names:
            matrix.set_routing_table({rname: None})
            router = matrix.get_router_by_name(rname)
            assert router is not None
            assert router.is_open
            assert router.dest_stream_name == rname
            assert matrix.get_routing_table()[rname] is None

        # Reassign original routing table and check that it is updated correctly
        matrix.set_routing_table(routing_table)
        for rname, sname in routing_table.items():
            router = matrix.get_router_by_name(rname)
            assert router is not None
            assert router.is_open
            assert router.dest_stream_name == rname
            # we don't have a source stream since it doesn't exist,
            # so we can only check that the routing table is correct
            assert matrix.get_routing_table()[rname] == sname
