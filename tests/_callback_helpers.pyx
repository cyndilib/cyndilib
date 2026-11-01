from cyndilib.callback cimport Callback as BaseCallback


cdef class Callback(BaseCallback):
    """Helper class to expose C-only methods of the Callback class
    """
    def set(self, cb: object) -> None:
        """Set the callback
        """
        self.set_callback(cb)

    def remove(self) -> None:
        """Remove the callback
        """
        self.remove_callback()

    def trigger_no_args_no_kwargs(self) -> None:
        """Trigger the callback with no arguments and no keyword arguments
        """
        self.trigger_callback()

    def trigger_with_args(self, *args: object, **kwargs) -> None:
        """Trigger the callback with positional arguments
        """
        self.trigger_callback(args)

    def trigger_with_kwargs(self, *args: object, **kwargs) -> None:
        """Trigger the callback with keyword arguments
        """
        self.trigger_callback((), kwargs)

    def trigger_with_args_and_kwargs(self, *args: object, **kwargs) -> None:
        """Trigger the callback with both positional and keyword arguments
        """
        self.trigger_callback(args, kwargs)
