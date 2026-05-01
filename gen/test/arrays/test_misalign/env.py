from environments import test, modify_build_path  # noqa: F401
import os

this_dir = os.path.dirname(os.path.realpath(__file__))
modify_build_path.add_to_build_path(
    [
        this_dir,
        os.path.realpath(os.path.join(this_dir, "..")),
        os.path.realpath(
            os.path.join(this_dir, ".." + os.sep + ".." + os.sep + "records")
        ),
        # Pull in Packed_F64x3 from src/types/packed_arrays so we can
        # exercise the 64-bit byte-aligned-primitive runtime path.
        os.path.realpath(
            os.path.join(
                this_dir,
                ".." + os.sep + ".." + os.sep + ".."
                + os.sep + "src" + os.sep + "types" + os.sep + "packed_arrays",
            )
        ),
    ]
)
