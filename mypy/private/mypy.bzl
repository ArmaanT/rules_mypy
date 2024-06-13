"""
Mypy utilities for bazel. Currently just an aspect.
"""

PYTHON_TOOLCHAIN = "@bazel_tools//tools/python:toolchain_type"

MyPyCacheInfo = provider(
    "Provider that aggregates mypy cached files",
    fields = {
        "cache_files": "depset of cache files",
        "cache_map": "Flattened list of transitive cache_map entries. Always a multiple of 3",
    },
)

VALID_EXTENSIONS = ["py", "pyi"]
RESERVED_KEYWORDS = [
    "/and/",
    "/as/",
    "/assert/",
    "/async/",
    "/await/",
    "/break/",
    "/class/",
    "/continue/",
    "/def/",
    "/del/",
    "/elif/",
    "/else/",
    "/except/",
    "/False/",
    "/finally/",
    "/for/",
    "/from/",
    "/global/",
    "/if/",
    "/import/",
    "/in/",
    "/is/",
    "/lambda/",
    "/None/",
    "/nonlocal/",
    "/not/",
    "/or/",
    "/pass/",
    "/raise/",
    "/return/",
    "/True/",
    "/try/",
    "/while/",
    "/with/",
    "/yield/",
]

def _get_mypy_typeshed_dir(mypy_target):
    """
    Get the typeshed directory from a mypy target

    Given a mypy target (generally a rule_python entry_point or
    py_console_script_binary). Determine the path to mypy's included
    typeshed directory
    """

    for file in mypy_target[DefaultInfo].default_runfiles.files.to_list():
        if "site-packages/mypy/typeshed/stdlib" in file.path and file.extension == "pyi":
            path, typeshed, _ = file.path.rpartition("site-packages/mypy/typeshed")
            return path + typeshed
    fail("Could not find mypy typeshed directory for: " + mypy_target)

def _extract_python_files(labels):
    """
    Get all .py or .pyi files in labels (generally srcs or data of a target).

    For external dependencies:
    1. Determine if the external dependency should be type checked:
        a. Search for a py.typed
        b. Check if the python module ends with `-stubs`
    2. Ignore any toplevel files (in site-packages) to:
        a. Ignore the rules_python injected __init__.py
        b. Ignore toplevel python files that shouldn't be typechecked.
    """

    should_type_check = False
    direct_files = []
    for label in labels:
        for f in label.files.to_list():
            if f.basename == "py.typed":
                should_type_check = True

            if f.extension not in VALID_EXTENSIONS:
                continue

            # Ignore toplevel files
            if f.dirname.endswith("/site-packages"):
                continue

            _, _, path = f.path.rpartition("site-packages/")

            # *-stubs packages should be cached
            module_name = path.split("/")[0]
            if module_name.endswith("-stubs"):
                should_type_check = True

                # Remove module name from path for the next check
                path = path.removeprefix(module_name + "/")

            # Skip any files that contain a dash in their path or include a directory that's a
            # python reservered keyword.
            # Various python packages include python files that cause problems for mypy because
            # users are't expected to import them. numpy is the example that caused this check.
            if "-" in path or any([keyword in path for keyword in RESERVED_KEYWORDS]):
                continue

            direct_files.append(f)

    return direct_files, should_type_check

def _generate_direct_cache_map(ctx, direct_python_files, out_dir):
    """
    Generate the direct cache map for a set of direct python files.

    Meta and data json files will be placed inside of out_dir.
    """

    triples_as_flat_list = []

    for f in direct_python_files:
        package = ctx.label.package
        if not package.endswith("/"):
            package += "/"
        offset = 1 if package == "/" else 0
        relative_path = f.path[len(package) - offset:]
        meta = out_dir.path + "/" + relative_path + ".meta.json"
        data = out_dir.path + "/" + relative_path + ".data.json"
        triples_as_flat_list.extend([f.path, meta, data])

    return triples_as_flat_list

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
    # Do not run on non-python targets
    if PyInfo not in target:
        return []

    mypy = "mypy" in ctx.rule.attr.tags
    strict = "mypy-strict" in ctx.rule.attr.tags
    is_external = target.label.workspace_root.startswith("external/")

    # Do not run on internal targets without a mypy tag when in `opt-in` mode
    if ctx.attr.mypy_opt_in and not mypy and not strict and not is_external:
        return []

    # Do not run on external targets if `cache_third_party` is false
    if is_external and not ctx.attr.cache_third_party:
        return []

    # Do not run on external targets that have been added to the ignore list
    if is_external and target.label in [t.label for t in ctx.attr._ignore]:
        return []

    # Gather variables
    toolchain = ctx.toolchains[PYTHON_TOOLCHAIN]

    # Get all direct python files
    direct_python_src_files, _ = _extract_python_files(ctx.rule.attr.srcs)
    direct_python_data_files, should_type_check = _extract_python_files(ctx.rule.attr.data)
    direct_python_files = _clean_direct_python_files(direct_python_src_files + direct_python_data_files)

    # Don't cache external targets that shouldn't be type checked
    if is_external and not should_type_check:
        return []

    # Create PYTHONPATH using python target imports, plugin imports, and plugin directories
    mypy_import_paths = ["external/" + i for i in ctx.attr._mypy[PyInfo].imports.to_list()]
    mypy_path = ctx.attr._mypy.label.workspace_root + "/site-packages"
    import_paths = ["external/" + f for f in target[PyInfo].imports.to_list()]
    plugin_import_paths = ["external/" + i for plugin in ctx.attr._plugins for i in plugin[PyInfo].imports.to_list()]
    plugin_paths = [plugin.label.workspace_root + "/site-packages" for plugin in ctx.attr._plugins]
    python_path = [".", mypy_path] + import_paths + mypy_import_paths + plugin_import_paths + plugin_paths

    # Generate a deduplicated transitive cache_map. Include stdlib cache if provided
    out_dir = ctx.actions.declare_directory(target.label.name + "_mypy_cache")
    direct_cache_map = _generate_direct_cache_map(ctx, direct_python_files, out_dir)
    cache_files, transitive_cache_map = _generate_transitive_cache_map(ctx.rule.attr.deps)
    if ctx.attr._mypy_stdlib_cache:
        transitive_cache_map.extend(ctx.attr._mypy_stdlib_cache[MyPyCacheInfo].cache_map)
    cache_map = _deduplicate_cache_map(direct_cache_map, transitive_cache_map)

    # Inputs to mypy
    python_runfiles = toolchain.py3_runtime.files
    target_runfiles = target[DefaultInfo].default_runfiles.files
    mypy_runfiles = ctx.attr._mypy[DefaultInfo].default_runfiles.files
    plugin_runfiles = depset(transitive = [plugin[DefaultInfo].default_runfiles.files for plugin in ctx.attr._plugins])
    transitive_inputs = [python_runfiles, target_runfiles, mypy_runfiles, cache_files, plugin_runfiles]
    if ctx.attr._mypy_stdlib_cache:
        transitive_inputs.append(ctx.attr._mypy_stdlib_cache[MyPyCacheInfo].cache_files)

    direct_inputs = [ctx.file._config]
    env = {
        "PYTHONPATH": ":".join(python_path),
    }

    # If checking an external target, create a new python file that imports every
    # file in the external target and pass that file as a source to mypy.
    # This results in mypy caching the external target, but not raising any type
    # errors while type checking
    external_importer = None
    if is_external:
        env["MYPYPATH"] = target.label.workspace_root + "site-packages"
        imports = []
        for file in direct_python_files:
            _, _, path = file.path.rpartition("site-packages/")
            path = path.removesuffix(".pyi")
            path = path.removesuffix(".py")
            path = path.removesuffix("__init__")
            path = path.removesuffix("/")
            path = path.replace("-stubs", "")
            module = path.replace("/", ".")
            imports.append("import " + module)

        external_importer = ctx.actions.declare_file(target.label.workspace_root + "_importer.py")
        ctx.actions.write(external_importer, "\n".join(imports))
        direct_inputs.append(external_importer)

    input_depset = depset(direct_inputs, transitive = transitive_inputs)

    # Declare junit output file
    junit = ctx.actions.declare_file("%s_mypy.junit" % ctx.rule.attr.name)

    # Mypy arguments
    python_args = ctx.actions.args()
    python_args.add("-c")
    python_args.add("import sys;from mypy.__main__ import console_entry;sys.exit(console_entry())")
    mypy_args = ctx.actions.args()
    mypy_args.use_param_file("@%s", use_always = True)
    mypy_args.set_param_file_format("multiline")
    if ctx.attr.mypy_verbose:
        mypy_args.add("--verbose")
    if strict:
        mypy_args.add("--strict")
    mypy_args.add("--bazel")
    mypy_args.add("--skip-cache-mtime-checks")
    mypy_args.add("--no-error-summary")
    mypy_args.add("--config-file")
    mypy_args.add(ctx.file._config)
    mypy_args.add("--custom-typeshed-dir")
    mypy_args.add(_get_mypy_typeshed_dir(ctx.attr._mypy))
    mypy_args.add("--junit-xml")
    mypy_args.add(junit)
    mypy_args.add("--incremental")
    mypy_args.add("--follow-imports")
    mypy_args.add("silent")
    mypy_args.add("--explicit-package-bases")
    mypy_args.add("--cache-map")
    mypy_args.add_all(cache_map)
    mypy_args.add("--")
    if is_external:
        mypy_args.add(external_importer)
    else:
        mypy_args.add_all(direct_python_files)

    ctx.actions.run(
        outputs = [junit, out_dir],
        inputs = input_depset,
        arguments = [python_args, mypy_args],
        executable = toolchain.py3_runtime.interpreter,
        mnemonic = "MyPy",
        progress_message = "Type-checking %s" % ctx.label,
        env = env,
    )

    return [
        OutputGroupInfo(
            _validation = depset([junit]),
        ),
        MyPyCacheInfo(
            cache_files = depset([out_dir], transitive = [cache_files]),
            cache_map = cache_map,
        ),
    ]

def mypy_aspect(mypy, config, plugins = None, to_ignore = None, cache_third_party = True, mypy_stdlib_cache = None, verbose = False, opt_in = True):
    """
    Create a mypy bazel aspect to typecheck python targets.

    Args:
        mypy: The mypy package to use. Expected to be a rules_python package from `pip_parse`.
        config: A config file to pass to mypy. Generally a pyproject.toml or mypy.ini
        plugins: A list of plugins that are passed to mypy. Plugins are expected to be sourced from rules_python `pip_parse`.

            Note: You must also define these plugins in your mypy config file for mypy to use them.
        to_ignore: A list of external python targets to skip caching. Only relevant when `cache_third_party` is true.
        cache_third_party: Should the mypy aspect cache third party dependencies.
        mypy_stdlib_cache: An optional instantiation of `mypy_stdlib_cache`. Required to get full incremental typechecking.
        verbose: Run mypy in verbose mode. Likely not needed for general use.
        opt_in: Should the mypy aspect be opt-in or opt-out (default opt-in).

            When in opt-in mode python targets must have either a `mypy` or `mypy-strict` tag in order to be typechecked. When
            in opt-out mode, all python targets are typechecked.

    Returns:
        A mypy_aspect
    """

    attrs = {
        "_mypy": attr.label(
            default = mypy,
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
        "_ignore": attr.label_list(
            default = to_ignore or [],
            providers = [PyInfo],
        ),
        "mypy_verbose": attr.bool(default = verbose),
        "mypy_opt_in": attr.bool(default = opt_in),
        "cache_third_party": attr.bool(default = cache_third_party),
    }

    # Workaround to indicate an empty default for `_mypy_stdlib_cache`
    if mypy_stdlib_cache:
        attrs["_mypy_stdlib_cache"] = attr.label(
            default = mypy_stdlib_cache,
            providers = [MyPyCacheInfo],
        )
    else:
        attrs["_mypy_stdlib_cache"] = attr.bool(
            default = False,
        )

    return aspect(
        implementation = _mypy_aspect_impl,
        attr_aspects = ["deps"],
        attrs = attrs,
        toolchains = [PYTHON_TOOLCHAIN],
    )

def _mypy_stdlib_cache_impl(ctx):
    toolchain = ctx.toolchains[PYTHON_TOOLCHAIN]

    # Get all stdlib pyi files in the mypy typeshed directory
    direct_python_files = []
    for file in ctx.attr.mypy[DefaultInfo].default_runfiles.files.to_list():
        if "site-packages/mypy/typeshed/stdlib" in file.path and file.extension == "pyi":
            direct_python_files.append(file)

    out_dir = ctx.actions.declare_directory(ctx.attr.name)
    cache_map = _generate_direct_cache_map(ctx, direct_python_files, out_dir)

    # Convert the stdlib pyi files into a list of imports
    imports = []
    for file in direct_python_files:
        _, _, path = file.path.rpartition("typeshed/stdlib/")
        path = path.removesuffix(".pyi")
        path = path.removesuffix("__init__")
        path = path.removesuffix("/")
        module = path.replace("/", ".")
        imports.append("import " + module)

    # Write a python file that imports all of the stdlib pyi files
    importer = ctx.actions.declare_file(ctx.attr.name + ".py")
    ctx.actions.write(importer, "\n".join(imports))

    # Create PYTHONPATH using plugin imports and plugin directories
    mypy_import_paths = ["external/" + i for i in ctx.attr.mypy[PyInfo].imports.to_list()]
    mypy_path = ctx.attr.mypy.label.workspace_root + "/site-packages"
    plugin_import_paths = ["external/" + i for plugin in ctx.attr.plugins for i in plugin[PyInfo].imports.to_list()]
    plugin_paths = [plugin.label.workspace_root + "/site-packages" for plugin in ctx.attr.plugins]
    python_path = [".", mypy_path] + mypy_import_paths + plugin_import_paths + plugin_paths

    # Inputs to mypy
    python_runfiles = toolchain.py3_runtime.files
    mypy_runfiles = ctx.attr.mypy[DefaultInfo].default_runfiles.files
    plugin_runfiles = depset(transitive = [plugin[DefaultInfo].default_runfiles.files for plugin in ctx.attr.plugins])
    inputs = [python_runfiles, mypy_runfiles, plugin_runfiles]

    # Mypy arguments. Very large overlap with the mypy aspect.
    args = ctx.actions.args()
    args.add("-c")
    args.add("import sys;from mypy.__main__ import console_entry;sys.exit(console_entry())")
    args.add("--bazel")
    args.add("--skip-cache-mtime-checks")
    args.add("--no-error-summary")
    args.add("--config-file")
    args.add(ctx.file.config)
    args.add("--custom-typeshed-dir")
    args.add(_get_mypy_typeshed_dir(ctx.attr.mypy))
    args.add("--incremental")
    args.add("--follow-imports")
    args.add("silent")
    args.add("--explicit-package-bases")
    args.add("--cache-map")
    args.add_all(cache_map)
    args.add("--")
    args.add(importer)

    ctx.actions.run(
        outputs = [out_dir],
        inputs = depset([ctx.file.config, importer], transitive = inputs),
        arguments = [args],
        executable = toolchain.py3_runtime.interpreter,
        mnemonic = "MyPy",
        progress_message = "Caching mypy typeshed",
        env = {
            "PYTHONPATH": ":".join(python_path),
        },
    )

    cache_files = depset([out_dir])

    return [
        DefaultInfo(files = cache_files),
        MyPyCacheInfo(
            cache_files = cache_files,
            cache_map = cache_map,
        ),
    ]

mypy_stdlib_cache = rule(
    doc = "Rule to generate a mypy cache of the python stdlib.",
    implementation = _mypy_stdlib_cache_impl,
    attrs = {
        "mypy": attr.label(
            doc = "The mypy package to use. Expected to be a rules_python package from `pip_parse`.",
            mandatory = True,
            allow_files = True,
            providers = [PyInfo],
        ),
        "config": attr.label(
            doc = "A config file to pass to mypy. Generally a pyproject.toml or mypy.ini",
            mandatory = True,
            allow_single_file = True,
        ),
        "plugins": attr.label_list(
            doc = "A list of plugins that are passed to mypy. Plugins are expected to be sourced from rules_python `pip_parse`",
            default = [],
            allow_files = True,
            providers = [PyInfo],
        ),
    },
    toolchains = [PYTHON_TOOLCHAIN],
)
