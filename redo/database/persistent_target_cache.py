"""
Persistent target database cache.

After each build, the ephemeral redo_target.db is copied to a persistent
location so that 'redo what' can read it instantly without rebuilding.
"""
import os
import os.path
import shutil


def _get_project_build_dir():
    """Return the project-level build/redo directory, or None."""
    # Walk up from cwd looking for default.do to find the project root
    d = os.getcwd()
    while d != "/":
        if os.path.isfile(os.path.join(d, "default.do")):
            return os.path.join(d, "build", "redo")
        d = os.path.dirname(d)
    return None


def get_persistent_db_path():
    """Return the path to the persistent target DB, or None."""
    build_dir = _get_project_build_dir()
    if build_dir is None:
        return None
    return os.path.join(build_dir, "redo_target.db")


def save_persistent_db(session_db_path):
    """
    Copy the session's redo_target.db to the persistent location.
    Called during build cleanup, before the session dir is destroyed.
    """
    if not os.path.isfile(session_db_path):
        return

    persistent_path = get_persistent_db_path()
    if persistent_path is None:
        return

    try:
        os.makedirs(os.path.dirname(persistent_path), exist_ok=True)
        # Atomic copy: write to temp file then rename
        tmp_path = persistent_path + ".tmp"
        shutil.copy2(session_db_path, tmp_path)
        os.replace(tmp_path, persistent_path)
    except Exception:
        # Don't let cache save failures break builds
        pass
