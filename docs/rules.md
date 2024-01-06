<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Public API re-exports

<a id="mypy_stdlib_cache"></a>

## mypy_stdlib_cache

<pre>
mypy_stdlib_cache(<a href="#mypy_stdlib_cache-name">name</a>, <a href="#mypy_stdlib_cache-config">config</a>, <a href="#mypy_stdlib_cache-mypy">mypy</a>, <a href="#mypy_stdlib_cache-plugins">plugins</a>)
</pre>

Rule to generate a mypy cache of the python stdlib.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="mypy_stdlib_cache-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="mypy_stdlib_cache-config"></a>config |  A config file to pass to mypy. Generally a pyproject.toml or mypy.ini   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="mypy_stdlib_cache-mypy"></a>mypy |  The mypy binary to use. Expected to be either a rules_python entry_point or py_console_script_binary   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="mypy_stdlib_cache-plugins"></a>plugins |  A list of plugins that are passed to mypy. Plugins are expected to be sourced from rules_python <code>pip_parse</code>   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional | <code>[]</code> |


<a id="mypy_aspect"></a>

## mypy_aspect

<pre>
mypy_aspect(<a href="#mypy_aspect-binary">binary</a>, <a href="#mypy_aspect-config">config</a>, <a href="#mypy_aspect-plugins">plugins</a>, <a href="#mypy_aspect-to_ignore">to_ignore</a>, <a href="#mypy_aspect-cache_third_party">cache_third_party</a>, <a href="#mypy_aspect-mypy_stdlib_cache">mypy_stdlib_cache</a>, <a href="#mypy_aspect-verbose">verbose</a>,
            <a href="#mypy_aspect-opt_in">opt_in</a>)
</pre>

    Create a mypy bazel aspect to typecheck python targets.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="mypy_aspect-binary"></a>binary |  The mypy binary to use. Expected to be either a rules_python entry_point or py_console_script_binary   |  none |
| <a id="mypy_aspect-config"></a>config |  A config file to pass to mypy. Generally a pyproject.toml or mypy.ini   |  none |
| <a id="mypy_aspect-plugins"></a>plugins |  A list of plugins that are passed to mypy. Plugins are expected to be sourced from rules_python <code>pip_parse</code>.<br><br>Note: You must also define these plugins in your mypy config file for mypy to use them.   |  <code>None</code> |
| <a id="mypy_aspect-to_ignore"></a>to_ignore |  A list of external python targets to skip caching. Only relevant when <code>cache_third_party</code> is true.   |  <code>None</code> |
| <a id="mypy_aspect-cache_third_party"></a>cache_third_party |  Should the mypy aspect cache third party dependencies.   |  <code>True</code> |
| <a id="mypy_aspect-mypy_stdlib_cache"></a>mypy_stdlib_cache |  An optional instantiation of <code>mypy_stdlib_cache</code>. Required to get full incremental typechecking.   |  <code>None</code> |
| <a id="mypy_aspect-verbose"></a>verbose |  Run mypy in verbose mode. Likely not needed for general use.   |  <code>False</code> |
| <a id="mypy_aspect-opt_in"></a>opt_in |  Should the mypy aspect be opt-in or opt-out (default opt-in).<br><br>When in opt-in mode python targets must have either a <code>mypy</code> or <code>mypy-strict</code> tag in order to be typechecked. When in opt-out mode, all python targets are typechecked.   |  <code>True</code> |

**RETURNS**

A mypy_aspect


