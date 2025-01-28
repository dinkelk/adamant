import os
from environments import modify_build_path

this_dir = os.path.dirname(os.path.realpath(__file__))
# Overwrite the normal build path mechanism and just use
# this directory as the build path. This prevents any
# name conflicts we might get from using the regular
# ".all_path".
os.environ["EXTRA_BUILD_PATH"] = ([this_dir,
    os.path.join(this_dir, ".." + os.sep + "example_architecture"),
    os.path.join(
        this_dir, ".." + os.sep + "example_architecture" + os.sep + "example_component"
    )])
