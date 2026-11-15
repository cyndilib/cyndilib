
class DiscoveryServerNotFoundError(UserWarning):
    """Warning raised when the discovery server is not found
    """


class DiscoveryServerUnavailableError(UserWarning):
    """Warning raised when the built-in discovery server is unavailable for the
    current platform
    """

class InvalidStateError(RuntimeError):
    """Exception raised when the :class:`.SendListener` is in an invalid state
    """
