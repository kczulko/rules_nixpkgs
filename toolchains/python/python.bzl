"""<!-- Edit the docstring in `toolchains/python/python.bzl` and run `bazel run //docs:update-README.md` to change this repository's `README.md`. -->

Rules for importing a Python toolchain from Nixpkgs.

# Rules

* [nixpkgs_python_configure](#nixpkgs_python_configure)
"""

load(
    "@rules_nixpkgs_core//:nixpkgs.bzl",
    "nixpkgs_package",
)
load(
    "@rules_nixpkgs_core//:util.bzl",
    "is_bazel_version_at_least",
    "ensure_constraints",
    "label_string",
)

def _nixpkgs_python_toolchain_impl(repository_ctx):
    exec_constraints, target_constraints = ensure_constraints(repository_ctx)

    python2_runtime = ""
    if repository_ctx.attr.python2_repo:
        python2_runtime = repository_ctx.attr.python2_repo + ":runtime"

    python3_runtime = ""
    if repository_ctx.attr.python3_repo:
        python3_runtime = repository_ctx.attr.python3_repo + ":runtime"

    repository_ctx.file("BUILD.bazel", executable = False, content = """
load("@bazel_tools//tools/python:toolchain.bzl", "py_runtime_pair")
py_runtime_pair(
    name = "py_runtime_pair",
    py2_runtime = {python2_runtime},
    py3_runtime = {python3_runtime},
)
toolchain(
    name = "toolchain",
    toolchain = ":py_runtime_pair",
    toolchain_type = "@bazel_tools//tools/python:toolchain_type",
    exec_compatible_with = {exec_constraints},
    target_compatible_with = {target_constraints},
)
""".format(
        python2_runtime = label_string(python2_runtime),
        python3_runtime = label_string(python3_runtime),
        exec_constraints = exec_constraints,
        target_constraints = target_constraints,
    ))

    python_repo = repository_ctx.attr.python3_repo
    if not python_repo:
        python_repo = repository_ctx.attr.python2_repo

    repository_ctx.file("defs.bzl", executable = False, content = """
# Generated by rules_nixpkgs/toolchains/python/python.bzl
interpreter = "{}"
    """.format(python_repo + ":bin/python"))

_nixpkgs_python_toolchain = repository_rule(
    _nixpkgs_python_toolchain_impl,
    attrs = {
        # Using attr.string instead of attr.label, so that the repository rule
        # does not explicitly depend on the nixpkgs_package instances. This is
        # necessary, so that builds don't fail on platforms without nixpkgs.
        "python2_repo": attr.string(),
        "python3_repo": attr.string(),
        "exec_constraints": attr.string_list(),
        "target_constraints": attr.string_list(),
    },
)

def _python_nix_file_content(attribute_path, bin_path, version):
    bazel_version_match, bazel_from_source = is_bazel_version_at_least("4.2.0")
    add_shebang = bazel_version_match or bazel_from_source

    return """
with import <nixpkgs> {{ config = {{}}; overlays = []; }};
let
  addShebang = {add_shebang};
  interpreterPath = "${{{attribute_path}}}/{bin_path}";
  shebangLine = interpreter: writers.makeScriptWriter {{ inherit interpreter; }} "shebang" "";
in
runCommand "bazel-nixpkgs-python-toolchain"
  {{ executable = false;
    # Pointless to do this on a remote machine.
    preferLocalBuild = true;
    allowSubstitutes = false;
  }}
  ''
    n=$out/BUILD.bazel
    mkdir -p "$(dirname "$n")/bin"
    ln -s ${{interpreterPath}} $out/bin/python

    cat >>$n <<EOF
    py_runtime(
        name = "runtime",
        interpreter_path = "${{interpreterPath}}",
        python_version = "{version}",
        ${{lib.optionalString addShebang ''
          stub_shebang = "$(cat ${{shebangLine interpreterPath}})",
        ''}}
        visibility = ["//visibility:public"],
    )
    EOF
  ''
""".format(
        add_shebang = "true" if add_shebang else "false",
        attribute_path = attribute_path,
        bin_path = bin_path,
        version = version,
    )

def nixpkgs_python_configure(
        name = "nixpkgs_python_toolchain",
        python2_attribute_path = None,
        python2_bin_path = "bin/python",
        python3_attribute_path = "python3",
        python3_bin_path = "bin/python",
        repository = None,
        repositories = {},
        nix_file_deps = None,
        nixopts = [],
        fail_not_supported = True,
        quiet = False,
        exec_constraints = None,
        target_constraints = None):
    """Define and register a Python toolchain provided by nixpkgs.

    Creates `nixpkgs_package`s for Python 2 or 3 `py_runtime` instances and a
    corresponding `py_runtime_pair` and `toolchain`. The toolchain is
    automatically registered and uses the constraint:

    ```
    "@io_tweag_rules_nixpkgs//nixpkgs/constraints:support_nix"
    ```

    Args:
      name: The name-prefix for the created external repositories.
      python2_attribute_path: The nixpkgs attribute path for python2.
      python2_bin_path: The path to the interpreter within the package.
      python3_attribute_path: The nixpkgs attribute path for python3.
      python3_bin_path: The path to the interpreter within the package.
      repository: See [`nixpkgs_package`](#nixpkgs_package-repository).
      repositories: See [`nixpkgs_package`](#nixpkgs_package-repositories).
      nix_file_deps: See [`nixpkgs_package`](#nixpkgs_package-nix_file_deps).
      nixopts: See [`nixpkgs_package`](#nixpkgs_package-nixopts).
      fail_not_supported: See [`nixpkgs_package`](#nixpkgs_package-fail_not_supported).
      quiet: See [`nixpkgs_package`](#nixpkgs_package-quiet).
      exec_constraints: Constraints for the execution platform.
      target_constraints: Constraints for the target platform.
    """
    python2_specified = python2_attribute_path and python2_bin_path
    python3_specified = python3_attribute_path and python3_bin_path
    if not python2_specified and not python3_specified:
        fail("At least one of python2 or python3 has to be specified.")
    kwargs = dict(
        repository = repository,
        repositories = repositories,
        nix_file_deps = nix_file_deps,
        nixopts = nixopts,
        fail_not_supported = fail_not_supported,
        quiet = quiet,
    )
    python2_repo = None
    if python2_attribute_path:
        python2_repo = "@%s_python2//" % name
        nixpkgs_package(
            name = name + "_python2",
            nix_file_content = _python_nix_file_content(
                attribute_path = python2_attribute_path,
                bin_path = python2_bin_path,
                version = "PY2",
            ),
            **kwargs
        )
    python3_repo = None
    if python3_attribute_path:
        python3_repo = "@%s_python3//" % name
        nixpkgs_package(
            name = name + "_python3",
            nix_file_content = _python_nix_file_content(
                attribute_path = python3_attribute_path,
                bin_path = python3_bin_path,
                version = "PY3",
            ),
            **kwargs
        )
    _nixpkgs_python_toolchain(
        name = name,
        python2_repo = python2_repo,
        python3_repo = python3_repo,
        exec_constraints = exec_constraints,
        target_constraints = target_constraints,
    )
    native.register_toolchains("@%s//:toolchain" % name)
