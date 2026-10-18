import os
from environments import modify_build_path

# Add the example architecture directory to the build path, since it holds
# the packed record model that this example uses.
this_dir = os.path.dirname(os.path.realpath(__file__))
modify_build_path.add_to_build_path(this_dir + os.sep + "..")
