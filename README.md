# Bazel rules for mypy

A mypy aspect that ensures bazel python targets typecheck. Similar to [bazel-mypy-integration](https://github.com/bazel-contrib/bazel-mypy-integration) except `rules_mypy` is incremental and will _not_ attempt to repeatidly typecheck all dependencies.

Bazel 6+ is supported

## Features

- Incremental mypy typechecking for python targets
- Allow mypy to be run in an opt-in or opt-opt fashion
- Allow targets to opt-into mypy strict mode
- Writes a junit result file into `bazel-bin`

## Example usage and documentation

Documentation for public rules is located [here](./docs/rules.md).

See `examples/smoke` for a complete example of how to use `rules_mypy`.

The minimal configuration needed to use `rules_mypy` looks something like a `mypy.bzl` file with the following:

```bazel
load("@rules_mypy//mypy:defs.bzl", "mypy_aspect")
load("@pypi//:requirements.bzl", "entry_point", "requirement")

mypy = mypy_aspect(
    binary = entry_point("mypy"),
    config = Label(":pyproject.toml"),
    plugins = [
        requirement("pydantic"),
    ],
)
```

and adding `common --aspects //:mypy.bzl%mypy` to your bazelrc.

If you want full incremental typechecking you must also create a `mypy_stdlib_cache` target to generate a mypy cache of the python standard library (through mypy's included typeshed directory):

```bazel
load("@pypi//:requirements.bzl", "requirement")

mypy_stdlib_cache(
    name = "stdlib_cache",
    config = "//:pyproject.toml",
    mypy = "//:mypy",
    plugins = [
        requirement("pydantic"),
    ],
    visibility = ["//visibility:public"],
)
```

and add `mypy_stdlib_cache = Label("//:stdlib_cache")` to your `mypy_aspect` definition in `mypy.bzl`.

## Installation

From the release you wish to use:
<https://github.com/ArmaanT/rules_mypy/releases>
copy the WORKSPACE snippet into your `WORKSPACE` file.

To use a commit rather than a release, you can point at any SHA of the repo.

For example to use commit `abc123`:

1. Replace `url = "https://github.com/ArmaanT/rules_mypy/releases/download/v0.1.0/rules_mypy-v0.1.0.tar.gz"` with a GitHub-provided source archive like `url = "https://github.com/ArmaanT/rules_mypy/archive/abc123.tar.gz"`
1. Replace `strip_prefix = "rules_mypy-0.1.0"` with `strip_prefix = "rules_mypy-abc123"`
1. Update the `sha256`. The easiest way to do this is to comment out the line, then Bazel will
   print a message with the correct value. Note that GitHub source archives don't have a strong
   guarantee on the sha256 stability, see
   <https://github.blog/2023-02-21-update-on-the-future-stability-of-source-code-archives-and-hashes/>

## Using mypy_stdlib_cache

You will likely have to tell mypy to ignore various mypy stdlib pyi files that don't actually exist in your version of python. Nomally these are modules that have been removed in a previous version of python or modules that are added in future versions. An easy way of doing this is to add the following snippet to your mypy config file (`pyproject.toml` in this example):

```toml
[[tool.mypy.overrides]]
module = [
    # Needed for python 3.8 since these modules don't exist in its stdlib
    "asyncio.mixins",
    "asyncio.taskgroups",
    "asyncio.threads",
    "asyncio.timeouts",
    "graphlib",
    "importlib.metadata._meta",
    "importlib.readers",
    "importlib.resources.abc",
    "importlib.resources.readers",
    "importlib.resources.simple",
    "importlib.simple",
    "macpath",
    "sys._monitoring",
    "tomllib",
    "unittest._log",
    "wsgiref.types",
    "zoneinfo",
]
ignore_missing_imports = true
```

## Known limitations

- `rules_mypy` only contains a mypy aspect. Eventually it should also provide a test target and possibly indpendent rule
- `rules_mypy` assumes all python imports are relative from the root of the workspace, custom python target `imports` likely won't work
- Windows is not supported or tested
- When in opt-in mode, python targets that depend on targets which aren't typechecked will have mypy typecheck its untyped dependencies each time mypy runs

## Acknowledgements

Both [bazel-mypy-integration](https://github.com/bazel-contrib/bazel-mypy-integration) and [Dropbox's mypy aspect](https://github.com/dropbox/dbx_build_tools/blob/master/build_tools/py/mypy.bzl) were used as inspiration for rules_mypy.
