import os
from environments import modify_build_path

# Add the example directory and the example architecture directory to the
# build path, for the prototype package and the packed record model it uses.
this_dir = os.path.dirname(os.path.realpath(__file__))
modify_build_path.add_to_build_path([this_dir + os.sep + "..", this_dir + os.sep + ".." + os.sep + ".."])
