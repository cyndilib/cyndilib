from __future__ import annotations
import threading

import pytest

from cyndilib.locks import Lock, RLock, Condition, Event
from _bench_helpers import ( # type: ignore[missing-import]
    cy_lock_direct_benchmark,
    cy_lock_direct_benchmark_nogil,
    cy_lock_direct_nonblocking_benchmark,
    cy_lock_direct_nonblocking_benchmark_nogil,
    cy_lock_reentrant_benchmark,
    cy_lock_reentrant_benchmark_nogil,
    cy_lock_reentrant_context_benchmark,
)


@pytest.fixture(
    params=[False, True],
    ids=['Python', 'Cython'],
)
def use_cython(request) -> bool:
    return request.param


@pytest.fixture(
    params=[False, True],
    ids=['withgil', 'nogil'],
)
def nogil(request) -> bool:
    return request.param



NUM_ITERATIONS = 5


@pytest.mark.benchmark(group="locks")
def test_lock_direct_benchmark(benchmark, use_cython: bool, nogil: bool):
    if nogil and not use_cython:
        pytest.skip('Python cannot run nogil tests')
    # if bench_config.std_lib:
    #     if bench_config.nogil:
    #         pytest.skip('stdlib does not support nogil')
    #     l = threading.RLock()
    # else:
    #     l = RLock()
    l = RLock()
    owner = threading.get_ident()

    if use_cython:
        if nogil:
            def run_lock_test():
                cy_lock_direct_benchmark_nogil(l, owner, NUM_ITERATIONS)
        else:
            def run_lock_test():
                cy_lock_direct_benchmark(l, owner, NUM_ITERATIONS)
    else:
        def run_lock_test():
            for _ in range(NUM_ITERATIONS):
                l.acquire()
                l.release()

    benchmark(run_lock_test)


@pytest.mark.benchmark(group="locks")
def test_lock_direct_nonblocking_benchmark(benchmark, use_cython: bool, nogil: bool):
    if nogil and not use_cython:
        pytest.skip('Python cannot run nogil tests')
    # if bench_config.std_lib:
    #     if bench_config.nogil:
    #         pytest.skip('stdlib does not support nogil')
    #     l = threading.RLock()
    # else:
    #     l = RLock()
    l = RLock()
    owner = threading.get_ident()
    if use_cython:
        if nogil:
            def run_lock_test():
                cy_lock_direct_nonblocking_benchmark_nogil(l, owner, NUM_ITERATIONS)
        else:
            def run_lock_test():
                cy_lock_direct_nonblocking_benchmark(l, owner, NUM_ITERATIONS)
    else:
        def run_lock_test():
            for _ in range(NUM_ITERATIONS):
                if l.acquire(False):
                    l.release()
    benchmark(run_lock_test)


@pytest.mark.benchmark(group="locks")
def test_lock_reentrant_benchmark(benchmark, use_cython: bool, nogil: bool):
    if nogil and not use_cython:
        pytest.skip('Python cannot run nogil tests')
    # if bench_config.std_lib:
    #     if bench_config.nogil:
    #         pytest.skip('stdlib does not support nogil')
    #     l = threading.RLock()
    # else:
    #     l = RLock()
    l = RLock()
    owner = threading.get_ident()
    if use_cython:
        if nogil:
            def run_lock_test():
                cy_lock_reentrant_benchmark_nogil(l, owner, NUM_ITERATIONS)
        else:
            def run_lock_test():
                cy_lock_reentrant_benchmark(l, owner, NUM_ITERATIONS)
    else:
        def run_lock_test():
            for _ in range(NUM_ITERATIONS):
                l.acquire()
            for _ in range(NUM_ITERATIONS):
                l.release()

    benchmark(run_lock_test)


@pytest.mark.benchmark(group="locks")
def test_lock_reentrant_context_benchmark(benchmark, use_cython: bool, nogil: bool):
    if nogil:
        pytest.skip('nogil cannot use context manager')
    # if bench_config.std_lib:
    #     if bench_config.nogil:
    #         pytest.skip('stdlib does not support nogil')
    #     l = threading.RLock()
    # else:
    #     l = RLock()
    l = RLock()
    owner = threading.get_ident()
    if use_cython:
        def run_lock_test():
            cy_lock_reentrant_context_benchmark(l, owner)
    else:
        def run_lock_test():
            with l: pass
            with l:
                with l:
                    with l: pass
                    with l: pass
                with l:
                    with l: pass
                with l:
                    with l: pass
                    with l: pass
            with l: pass
            with l:
                with l:
                    with l: pass
                    with l: pass
                    with l:
                        with l: pass
            with l: pass

    benchmark(run_lock_test)
