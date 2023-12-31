"""
Mypy utilities for bazel. Currently just an aspect.
"""

MyPyCacheInfo = provider(
    "Provider that aggregates mypy cached files",
    fields = {
        "cache_files": "depset of cache files",
        "cache_map": "Flattened list of transitive cache_map entries. Always a multiple of 3",
    },
)

VALID_EXTENSIONS = ["py", "pyi"]

def _extract_python_files(labels):
    """
    Get all .py or .pyi files in labels (generally srcs or data of a target)
    """

    direct_files = []
    for label in labels:
        for f in label.files.to_list():
            if f.extension in VALID_EXTENSIONS:
                direct_files.append(f)
    return direct_files

def _generate_direct_cache_map(ctx, direct_python_files):
    """
    Generate the direct cache map while also declaring output meta and data json files
    """

    triples_as_flat_list = []
    meta_files = []
    data_files = []

    for f in direct_python_files:
        package = ctx.label.package
        if not package.endswith("/"):
            package += "/"
        offset = 1 if package == "/" else 0
        relative_path = f.path[len(package) - offset:]
        meta = ctx.actions.declare_file(relative_path + ".meta.json")
        data = ctx.actions.declare_file(relative_path + ".data.json")
        triples_as_flat_list.extend([f.path, meta.path, data.path])
        meta_files.append(meta)
        data_files.append(data)
    return depset(meta_files), depset(data_files), triples_as_flat_list

def _generate_transitive_cache_map(deps):
    """
    Collect cache map entries from all dependencies
    """

    cache_files = []
    cache_map = []
    for dep in deps:
        if MyPyCacheInfo in dep:
            cache_files.append(dep[MyPyCacheInfo].cache_files)
            cache_map.extend(dep[MyPyCacheInfo].cache_map)
    return depset(transitive = cache_files), cache_map

def _deduplicate_cache_map(direct_cache_map, transitive_cache_map):
    """
    Deduplicate any duplicate cache map entries
    """

    merged = direct_cache_map + transitive_cache_map
    deduplicated = []
    for i in range(0, len(merged), 3):
        if merged[i] not in deduplicated:
            deduplicated.extend([merged[i], merged[i + 1], merged[i + 2]])
    return deduplicated

def _clean_direct_python_files(direct_python_files):
    """
    Clean direct python files. If both foo.py and foo.pyi exist, ignore foo.py
    """

    cleaned = []
    file_names = [f.path for f in direct_python_files]
    for file in direct_python_files:
        if file.path + "i" in file_names:
            continue
        cleaned.append(file)
    return cleaned

def _mypy_aspect_impl(target, ctx):
    # Do not run on external targets, targets that aren't python targets,
    # and targets that don't have a "mypy" or "mypy-strict" tag when in opt_in mode
    if target.label.workspace_root.startswith("external/") or PyInfo not in target:
        return []

    mypy = "mypy" in ctx.rule.attr.tags
    strict = "mypy-strict" in ctx.rule.attr.tags
    if ctx.attr.opt_in and not mypy and not strict:
        return []

    # Gather variables
    direct_python_files = _extract_python_files(ctx.rule.attr.srcs)
    direct_python_files += _extract_python_files(ctx.rule.attr.data)
    direct_python_files = _clean_direct_python_files(direct_python_files)

    import_paths = ["external/" + f for f in target[PyInfo].imports.to_list()]
    plugin_import_paths = ["external/" + i for plugin in ctx.attr._plugins for i in plugin[PyInfo].imports.to_list()]
    plugin_paths = [plugin.label.workspace_root + "/site-packages" for plugin in ctx.attr._plugins]
    python_path = ["."] + import_paths + plugin_import_paths + plugin_paths

    meta_files, data_files, direct_cache_map = _generate_direct_cache_map(ctx, direct_python_files)
    cache_files, transitive_cache_map = _generate_transitive_cache_map(ctx.rule.attr.deps)
    cache_map = _deduplicate_cache_map(direct_cache_map, transitive_cache_map)

    plugin_runfiles = depset(transitive = [plugin[DefaultInfo].default_runfiles.files for plugin in ctx.attr._plugins])

    # Declare junit output file
    junit = ctx.actions.declare_file("%s_mypy.junit" % ctx.rule.attr.name)

    # Mypy arguments
    args = ctx.actions.args()
    if ctx.attr.verbose:
        args.add("--verbose")
    if strict:
        args.add("--strict")
    args.add("--bazel")
    args.add("--skip-cache-mtime-checks")
    args.add("--no-error-summary")
    args.add("--config-file")
    args.add(ctx.file._config)
    if ctx.attr._mypy.label.workspace_root != "":
        args.add("--custom-typeshed-dir")
        args.add(ctx.attr._mypy.label.workspace_root + "/site-packages/mypy/typeshed")
    args.add("--junit-xml")
    args.add(junit)
    args.add("--incremental")
    args.add("--follow-imports")
    args.add("silent")
    args.add("--explicit-package-bases")
    args.add("--cache-map")
    args.add_all(cache_map)
    args.add("--")
    args.add_all(direct_python_files)

    ctx.actions.run(
        outputs = [junit] + meta_files.to_list() + data_files.to_list(),
        inputs = depset([ctx.file._config], transitive = [target[DefaultInfo].default_runfiles.files, ctx.attr._mypy[DefaultInfo].default_runfiles.files, cache_files, plugin_runfiles]),
        arguments = [args],
        executable = ctx.executable._mypy,
        mnemonic = "MyPy",
        progress_message = "Type-checking %s" % ctx.label,
        env = {
            "PYTHONPATH": ":".join(python_path),
        },
    )

    return [
        OutputGroupInfo(
            _validation = depset([junit]),
        ),
        MyPyCacheInfo(
            cache_files = depset(transitive = [meta_files, data_files, cache_files]),
            cache_map = cache_map,
        ),
    ]

def mypy_aspect(binary, config, plugins = None, verbose = False, opt_in = True):
    """
    Create a mypy bazel aspect to typecheck python targets.

    Args:
        binary: The mypy binary to use. Expect to be either a rules_python entry_point or py_console_script_binary
        config: A config file to pass to mypy. Generally a pyproject.toml or mypy.ini
        plugins: A list of plugins that are passed to mypy. Plugins are expected to be sourced from rules_python `pip_parse`.

            Note: You must also define these plugins in your mypy config file for mypy to use them.
        verbose: Run mypy in verbose mode. Likely not needed for general use.
        opt_in: Should the mypy aspect be opt-in or opt-out (default opt-in).

            When in opt-in mode python targets must have either a `mypy` or `mypy-strict` tag in order to be typechecked. When
            in opt-out mode, all python targets are typechecked.
    """

    return aspect(
        implementation = _mypy_aspect_impl,
        attr_aspects = ["deps"],
        attrs = {
            "_mypy": attr.label(
                default = binary,
                executable = True,
                cfg = "exec",
                allow_files = True,
                providers = [PyInfo],
            ),
            "_config": attr.label(
                default = config,
                allow_single_file = True,
            ),
            "_plugins": attr.label_list(
                default = plugins or [],
                allow_files = True,
                providers = [PyInfo],
            ),
            "verbose": attr.bool(default = verbose),
            "opt_in": attr.bool(default = opt_in),
        },
    )
