"""
Mypy aspect instantiation
"""

load("@rules_mypy//mypy:defs.bzl", "mypy_aspect")
load("@pypi//:requirements.bzl", "entry_point", "requirement")  # @unused

mypy = mypy_aspect(
    binary = Label("//:mypy"),
    # The following also works when not using bzlmod:
    # binary = entry_point("mypy"),
    config = Label("//:pyproject.toml"),
    plugins = [
        requirement("pydantic"),
    ],
    to_ignore = [
        requirement("numpy"),
    ],
    mypy_stdlib_cache = Label("//:stdlib_cache"),
    verbose = True,
)
