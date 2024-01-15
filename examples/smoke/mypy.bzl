"""
Mypy aspect instantiation
"""

load("@rules_mypy//mypy:defs.bzl", "mypy_aspect")
load("@pypi//:requirements.bzl", "requirement")

mypy = mypy_aspect(
    mypy = requirement("mypy"),
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
