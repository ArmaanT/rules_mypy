<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Public API re-exports

<a id="mypy_aspect"></a>

## mypy_aspect

<pre>
mypy_aspect(<a href="#mypy_aspect-binary">binary</a>, <a href="#mypy_aspect-config">config</a>, <a href="#mypy_aspect-plugins">plugins</a>, <a href="#mypy_aspect-verbose">verbose</a>, <a href="#mypy_aspect-opt_in">opt_in</a>)
</pre>

    Create a mypy bazel aspect to typecheck python targets.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="mypy_aspect-binary"></a>binary |  The mypy binary to use. Expect to be either a rules_python entry_point or py_console_script_binary   |  none |
| <a id="mypy_aspect-config"></a>config |  A config file to pass to mypy. Generally a pyproject.toml or mypy.ini   |  none |
| <a id="mypy_aspect-plugins"></a>plugins |  A list of plugins that are passed to mypy. Plugins are expected to be sourced from rules_python <code>pip_parse</code>.<br><br>Note: You must also define these plugins in your mypy config file for mypy to use them.   |  <code>None</code> |
| <a id="mypy_aspect-verbose"></a>verbose |  Run mypy in verbose mode. Likely not needed for general use.   |  <code>False</code> |
| <a id="mypy_aspect-opt_in"></a>opt_in |  Should the mypy aspect be opt-in or opt-out (default opt-in).<br><br>When in opt-in mode python targets must have either a <code>mypy</code> or <code>mypy-strict</code> tag in order to be typechecked. When in opt-out mode, all python targets are typechecked.   |  <code>True</code> |


