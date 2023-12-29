from basic.example import random
from type_error.example import type_error


def is_complex() -> int:
    """
    This function type-checks even though type_error doesn't.
    """

    return random() if type_error() else 0
