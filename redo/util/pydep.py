import os
import sys
from util import redo
from database.py_source_database import py_source_database
from base_classes.build_rule_base import build_rule_base
from util import shell


# Return dependencies for a given python source file.
# Two lists are returned to the user. The first list is
# the modules found whose source files actually exist on
# the system. The second list includes modules
# that were found in the source file, but could not be
# found on the file system.
def pydep(source_file, path=[]):
    # monkey-patch broken modulefinder._find_module
    # (https://github.com/python/cpython/issues/84530)
    # in Python 3.8-3.10
    #
    # Found: https://github.com/thebjorn/pydeps/commit/17a09ac344cad06cc9a1e9129c08ffee02cb4b60
    import modulefinder
    if hasattr(modulefinder, '_find_module'):
        from imp import find_module
        modulefinder._find_module = find_module

    # If a path is not provided than just use the python
    # path variable:
    if not path:
        path = os.environ["PYTHONPATH"].split(":")

    # Run the module finder script on the given
    # python source file.
    finder = modulefinder.ModuleFinder(path=path)
    finder.run_script(source_file)

    # Collect and return the results:
    existing_deps = finder.modules
    nonexistant_deps = finder.badmodules
    return existing_deps, nonexistant_deps


# Recursively build any missing python module dependencies for
# a given source file.
def _build_pydeps(source_file, path=[]):
    built_deps = []
    deps_not_in_path = []

    def _inner_build_pydeps(source_file):
        # Find the python dependencies:
        existing_deps, nonexistant_deps = pydep(source_file, path)

        # For the nonexistent dependencies, see if we have a rule
        # to build those:
        if nonexistant_deps:
            deps_to_build = []
            with py_source_database() as db:
                deps_to_build = db.try_get_sources(nonexistant_deps)

            deps_not_in_path.extend(deps_to_build)

            # Don't rebuild anything we have already built:
            deps_to_build = [d for d in deps_to_build if d not in built_deps]

            # Build the deps:
            if deps_to_build:
                redo.redo_ifchange(deps_to_build)
                built_deps.extend(deps_to_build)

                # Run py deps on each of the build source files:
                for dep in deps_to_build:
                    _inner_build_pydeps(dep)

    _inner_build_pydeps(source_file)
    return list(set(deps_not_in_path))


# Class which helps us build the dependencies of a python file using
# the build system.
class _build_python_no_update(build_rule_base):
    def _build(self, redo_1, redo_2, redo_3):
        # Build any dependencies:
        return _build_pydeps(redo_1)


# Class which helps us build the dependencies of a python file using
# the build system.
class _build_python(build_rule_base):
    def _build(self, redo_1, redo_2, redo_3):
        # Build any dependencies:
        deps_not_in_path = _build_pydeps(redo_1)

        # Figure out what we need to add to the path:
        paths_to_add = list(set([os.path.dirname(d) for d in deps_not_in_path]))

        # Add the paths to the path:
        sys.path.extend(paths_to_add)

        return deps_not_in_path


# Class which helps us run a python file using the build system.
# This has the major benefit of building all python dependencies that
# are autogenerated prior to running the actual python file to be executed.
class _run_python(build_rule_base):
    def _build(self, redo_1, redo_2, redo_3):
        # Build any dependencies:
        deps_not_in_path = _build_pydeps(redo_1)

        # Figure out what we need to add to the path:
        paths_to_add = list(set([os.path.dirname(d) for d in deps_not_in_path]))

        # Run the python script:
        shell.run_command(
            "PYTHONPATH=$PYTHONPATH:" + ":".join(paths_to_add) + " python " + redo_1
        )


def build_py_deps(source_file=None, update_path=True):
    # If the source file is none, then use the source file of this function caller:
    if not source_file:
        import inspect

        frame = inspect.stack()[1]
        module = inspect.getmodule(frame[0])
        source_file = module.__file__
    if update_path:
        rule = _build_python()
    else:
        rule = _build_python_no_update()
    deps = rule.build(
        redo_1=source_file,
        redo_2=os.path.splitext(source_file)[0],
        redo_3=source_file + ".out",
    )

    # Reset the database, so that this function can be run again, if warrented.
    import database.setup

    database.setup.reset()

    return deps


def run_py(source_file):
    rule = _run_python()
    rule.build(
        redo_1=source_file,
        redo_2=os.path.splitext(source_file)[0],
        redo_3=source_file + ".out",
    )

    # Reset the database, so that this function can be run again, if warrented.
    import database.setup

    database.setup.reset()


# This can also be run from the command line:
if __name__ == "__main__":
    args = sys.argv[-2:]
    if len(args) != 2 or args[-1].endswith("pydep.py"):
        print("usage:\n  pydep.py /path/to/python_file.py")
    source_file = args[-1]

    existing_deps, nonexistant_deps = pydep(source_file)
    print("Finding dependencies for: " + source_file)
    print("")
    print("Existing dependencies: ")
    for dep in existing_deps:
        print(dep)
    print("")
    print("Nonexistent dependencies: ")
    for dep in nonexistant_deps:
        print(dep)
    print("")
    print("Building nonexistent dependencies: ")
    build_py_deps(source_file)
