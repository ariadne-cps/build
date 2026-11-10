# Ariadne Build

Shared **CMake build infrastructure** for the [Ariadne repository structure](https://github.com/ariadne-cps/ariadne/blob/main/doc/structure.md).
Use this repository as a pinned Git submodule; it provides reusable build
functions and targets, not a C++ runtime library.

## Modules and functions

| Module | Functions or macros | Purpose |
| --- | --- | --- |
| `ProjectOptions.cmake` | `setup_project`, `enable_project_options`, `check_project_compiler`, `configure_library_kind`, `report_python_configuration_once` | C++20 compiler options, warnings, shared/static library choices, common project targets and sanitizers. |
| `InitializeSccache.cmake` | Optional compiler-cache preflight | Checks the sccache daemon before compilation, with direct compiler fallback if startup fails. |
| `sccache.toml` | `server_startup_timeout_ms` | Configures sccache daemon startup timeout for GitHub Actions. |
| `DependencyChecks.cmake` | `ensure_submodule_initialized`, `ariadne_add_submodule`, `get_gitlink_commit`, `require_same_dependency_commit` | Resolve submodule paths and validate pinned dependency consistency along different repository chains. |
| `TestingSupport.cmake` | `ariadne_setup_testing` | Select root Testing only for standalone tests; verify its Build Gitlink. |
| `BenchmarkingSupport.cmake` | `ariadne_setup_benchmarking` | Select root Benchmarking; verify its Build and Logging pins; Benchmarking registers the aggregate `benchmarks` target and the root `benchmarks/` directory. |
| `ModuleSupport.cmake` | `ariadne_setup_module` | Derive functional C++ dependencies and configure the module's targets. |
| `DependencySnapshot.cmake` | Internal snapshot cache | Reuse exact-chain Gitlink verifications when the relevant pins are unchanged. |
| `ProjectLibrarySupport.cmake` | `setup_project_library` | Build the standalone library target from object targets and module dependencies. |
| `InstallBundleSupport.cmake` | `ariadne_register_public_headers`, `ariadne_install_dependency_bundle` | Register and install public header bundles, including reachable project dependencies. |
| `CoverageSupport.cmake` | `enable_project_coverage`, `setup_project_coverage`, `setup_project_tests`, `setup_standalone_project` | Standalone test/benchmark setup and code coverage, using GCC/lcov or LLVM tools. |
| `PythonBindingSupport.cmake` | `ariadne_add_python_module`, `ariadne_finalize_python_module` | Configure and finalize Python binding modules. |
| `UninstallSupport.cmake` | `setup_project_uninstall` | Create a project uninstall target. |
| `UseDoxygen.cmake` | `ariadne_setup_documentation` | Define `doc`, `doxygen`, `doc-html`, `doc-markdown`, and optionally `doc-pdf`. |

The `GCCCodeCoverage.cmake` and `LLVMCodeCoverage.cmake` modules provide
compiler-specific coverage implementations; `Uninstall.cmake.in` is the
template used for uninstalling a project.

`ss/bui` is the canonical checkout path for the `build` submodule.
Shared infrastructure targets also include `check-format` and `impose-format`.

## C++ formatting

`check-format` verifies formatting without modifying files; `impose-format` applies
the shared style in-place. After configuring the project with CMake:

```sh
cmake --build <build-directory> --target check-format
cmake --build <build-directory> --target impose-format
```

These standalone-project targets check only the caller's Git-tracked `.cpp` and
`.hpp` files under `include/`, `src/`, and `python/bindings/`. The `.hpp` rule
also covers `.tpl.hpp` and `.inc.hpp`, and includes top-level umbrella headers.
Nested submodules and untracked files are not modified. The style is read from
the caller's pinned `ss/bui/.clang-format`. Install clang-format **18** before
running either target; by default it looks for `clang-format-18` or an unversioned
`clang-format` that reports version 18. To use a nonstandard executable path, set
`ARIADNE_CLANG_FORMAT_EXECUTABLE` when configuring with CMake.

## Auxiliary dependency isolation

Only direct functional submodules are linked by `ariadne_setup_module(NAME)`.
Build, Testing, Benchmarking and PythonCommon are excluded from production
link interfaces. `ariadne_setup_testing()` and
`ariadne_setup_benchmarking()` select auxiliary submodules only in the root
project and validate their Build pins; the latter also validates its Logging
pin against the active Logging module. A nested module must never initialize
its own auxiliary checkout. Tests and benchmark executables link their own
auxiliary support explicitly.

## Pinned submodules during incremental builds

`setup_project()` registers the current project's Git index as a CMake
configuration dependency (including when the project is itself a nested
submodule or Git linked worktree). After a superproject `git pull` or
checkout changes pinned gitlinks, an ordinary
`cmake --build <build-dir> --target benchmarks` causes CMake/Ninja or
Make to reconfigure first. During reconfiguration,
`ariadne_add_submodule()` aligns declared dependencies with the
**recorded gitlink commits**, never remote branch tips. This also applies
to ordinary library and test targets.

When a submodule checkout is already on the correct commit, it is left
unchanged. When the checkout differs from the pinned commit, a dirty
worktree (including untracked files) causes a clear configure error
instead of a silent checkout. Submodules not yet initialized can be
initialized normally. Nested submodule dependencies are checked at their
respective CMake project configuration levels. The repository must have a
Git checkout; source archives without `.git` work as before.

This does **not** run `git pull`, automatically advance pinned commits,
or reconfigure for uncommitted gitlink changes without an index update.
As before, the initial `ss/bui` bootstrap in a project's root
`CMakeLists.txt` runs before Build's CMake helpers are available.
For emergency manual recovery, use
`git submodule update --init --recursive`, reviewing local modifications
first. A fresh CMake configure remains required after switching build
generators or changing configuration options.

## CMake use

Projects include `cmake/ProjectOptions.cmake` via their pinned
`ss/bui` gitlink and call `setup_project()`. Submodule directories use short
checkout codes such as `ss/mac` for `macro`, while CMake dependency checks use
full logical repository names. `ariadne_add_submodule(macro)` resolves the
checkout directory from `.gitmodules` and adds the dependency. Both the
original long paths and short paths are supported during migration.

To use the in-house Testing framework, register it only for standalone
test builds:

```cmake
setup_standalone_project(
  TARGET ariadne-utility
  TEST_DIRECTORY tests
  TEST_TARGET tests
  SOURCES "${PROJECT_SOURCE_DIR}/include" "${PROJECT_SOURCE_DIR}/src"
)
```

When the project declares a `testing` Git submodule, standalone test
configuration initializes its pinned gitlink automatically and exposes
the existing `ariadne-testing` static target. If a Testing target already
exists, it is reused. Projects without a Testing submodule continue
using their own CTest tests, without fetching Testing. Benchmarking is independent:
when the root declares `benchmarking` as a Git submodule, the standalone setup
loads it independently of Testing. The `benchmarking` repository creates the
`benchmarks` aggregate and registers the root project\x27s `benchmarks/`
subdirectory if present. Build no longer creates that target or registers
benchmarks itself; consumers that stay pinned to older Build commits are
unaffected. Individual tests can simply link it:

```cmake
target_link_libraries(test_example PRIVATE ariadne-utility utility ariadne-testing)
```

No duplicate library assembled from `TESTING_SRC` is necessary. Testing
never becomes an `INTERFACE` dependency of the production target and is
**never installed**. No `USE_ARIADNE_TESTING` flag is required: the submodule declaration is
sufficient. Projects embedding a library do not configure its standalone
tests.

For standalone API documentation, after the project targets have been set up:

```cmake
include("${PROJECT_SOURCE_DIR}/ss/bui/cmake/UseDoxygen.cmake")
ariadne_setup_documentation(
  INPUT "${PROJECT_SOURCE_DIR}/include" "${PROJECT_SOURCE_DIR}/src"
)
```

Documentation input paths are supplied by the caller; this repository owns
the Doxygen configuration template and XML-to-Markdown conversion machinery.

```sh
npm install --global moxygen@2.1.19
cmake -S . -B build-docs -DDOXYFILE_LATEX=OFF
cmake --build build-docs --target doc-markdown
```

Doxygen and Python 3 are required for `doc-markdown`; Moxygen 2.1.19 requires
Node.js. Doxygen produces HTML and XML under `build-docs/docs/`, and the
converter produces Markdown under `build-docs/docs/markdown/`. The generated
Markdown excludes private and protected nested compounds from the public
reference while keeping the original Doxygen output unchanged.

The `doc-pdf` target additionally requires a working TeX installation and
`make`. Documentation targets are defined only for standalone projects.

## Optional sccache in GitHub Actions

The compiler cache is optional. After initializing the pinned `ss/bui`
submodule, CI workflows can set `SCCACHE_CONF` to
`$GITHUB_WORKSPACE/ss/bui/cmake/sccache.toml`, run
`cmake -P ss/bui/cmake/InitializeSccache.cmake`, and pass the exported
`SCCACHE_LAUNCHER` value to both C and C++ `CMAKE_*_COMPILER_LAUNCHER`
CMake options. The preflight attempts `sccache --zero-stats` up to three
times to verify daemon connectivity. On failure, it exports an empty
launcher and CMake compiles directly.

For resilient workflows, mark the `mozilla-actions/sccache-action`
setup step `continue-on-error: true` and set
`SCCACHE_IGNORE_SERVER_IO_ERROR=1` so sccache falls back to the local
compiler if the server becomes unreachable during compilation. The
compiler and test exit codes remain authoritative; only cache failures
are tolerated.
