import pytest
import threading
import time
import traceback

from cyndilib import locks

class WaitThread(threading.Thread):
    def __init__(self, condition, timeout=5):
        super().__init__()
        self.condition = condition
        self.timeout = timeout
        self.result = None
        self.finished = threading.Event()
        self.exception = None
    def run(self):
        try:
            with self.condition:
                self.result = self.condition.wait(self.timeout)
        except Exception as exc:
            traceback.print_exc()
            self.exception = exc
        finally:
            self.finished.set()

class NotifyThread(threading.Thread):
    def __init__(self, condition, sleep_time=1):
        super().__init__()
        self.condition = condition
        self.sleep_time = sleep_time
        self.finished = threading.Event()
        self.exception = None
    def run(self):
        time.sleep(self.sleep_time)
        try:
            with self.condition:
                self.condition.notify_all()
        except Exception as exc:
            traceback.print_exc()
            self.exception = exc
        finally:
            self.finished.set()


def test_locks_basic():
    lock = locks.Lock()

    print(f'Lock created, locked={lock.locked}')
    assert not lock.locked
    print(f'{lock.locked=}')
    print('Acquiring lock...')
    with lock:
        assert lock.locked
    assert not lock.locked

def test_conditions():
    condition = locks.Condition()
    wait_threads = [WaitThread(condition) for i in range(10)]
    # wt = WaitThread(condition)
    nt = NotifyThread(condition)
    for wt in wait_threads:
        wt.start()
    nt.start()
    try:
        nt.finished.wait()
        assert nt.exception is None
        for wt in wait_threads:
            wt.finished.wait()
            assert wt.exception is None
            assert wt.result is True
    finally:
        nt.join()
        for wt in wait_threads:
            wt.join()


def test_lock_ownership():
    lock = locks.Lock()
    main_thread_id = threading.get_ident()

    print(f'Lock created, locked={lock.locked}')
    assert not lock.locked
    print('Acquiring lock...')
    with lock:
        assert lock.locked
        assert lock.owner == main_thread_id
        print(f'Lock acquired by main thread {main_thread_id}, owner={lock.owner}')

    assert not lock.locked
    assert lock.owner == -1


def test_rlock_ownership():
    rlock = locks.RLock()
    assert not rlock.locked
    main_thread_id = threading.get_ident()

    thread_count = 5
    print(f'RLock created, locked={rlock.locked}')

    barrier = threading.Barrier(thread_count + 1)

    def rlock_thread_func():
        nonlocal rlock, main_thread_id
        t_id = threading.get_ident()
        print(f'Thread {t_id} barrier wait')
        barrier.wait()
        # print(f'Thread {t_id} barrier passed')
        assert not rlock._is_owned(), f'Thread {t_id} unexpectedly owns RLock before acquire'
        print(f'Thread {t_id} waiting to acquire RLock...')
        with rlock:
            print(f'Thread {t_id} acquired RLock')
            assert rlock.locked, f'Thread {t_id} failed to acquire RLock'
            assert rlock.owner == t_id, f'Thread {t_id} sees wrong owner {rlock.owner}'
            assert rlock._is_owned(), f'Thread {t_id} does not own RLock after acquire'
            print(f'Thread {t_id} reacquiring RLock...')
            with rlock:
                print(f'Thread {t_id} reacquired RLock')
                assert rlock.locked, f'Thread {t_id} failed to reacquire RLock'
                assert rlock.owner == t_id, f'Thread {t_id} sees wrong owner {rlock.owner}'
                assert rlock._is_owned(), f'Thread {t_id} does not own RLock after reacquire'
            assert rlock.locked, f'Thread {t_id} lost RLock after inner with'
            assert rlock.owner == t_id, f'Thread {t_id} sees wrong owner {rlock.owner} after inner with'
            assert rlock._is_owned(), f'Thread {t_id} does not own RLock after inner with'
            time.sleep(.2)  # Hold the lock for a moment


        print(f'Thread {t_id} released RLock')
        assert not rlock.locked or rlock.owner != t_id, f'Thread {t_id} failed to release RLock'
        assert not rlock._is_owned(), f'Thread {t_id} still owns RLock after release'

    threads = [threading.Thread(target=rlock_thread_func) for _ in range(thread_count)]
    for t in threads:
        t.start()
    barrier.wait()  # Wait for all threads to acquire the lock
    for t in threads:
        t.join()
    assert not rlock.locked
    assert rlock.owner == -1
