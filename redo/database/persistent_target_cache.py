"""
Persistent target database cache.

After each build, the ephemeral redo_target.db is copied to a persistent
location in /tmp so that 'redo what' can read it instantly without
rebuilding. The cache is keyed by project root path.

Can also be invoked directly to build the full target DB:
    python3 -m database.persistent_target_cache
"""
import hashlib
import os
import os.path
import shutil


def _get_project_key():
    """Return a stable key identifying the current project environment.

    Uses ADAMANT_CONFIGURATION_YAML env var (unique per project) so the
    same cache is found regardless of which subdirectory you're in.
    Falls back to walking up from cwd to find default.do.
    """
    config_yaml = os.environ.get("ADAMANT_CONFIGURATION_YAML")
    if config_yaml:
        # Include TARGET in the key so different cross-compile targets
        # (e.g. Linux vs Pico) get separate caches.
        target = os.environ.get("TARGET", "")
        return config_yaml + ":" + target
    # Fallback: walk up from cwd
    d = os.getcwd()
    while True:
        if os.path.isfile(os.path.join(d, "default.do")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            return None
        d = parent


def _get_cache_dir(project_key):
    """Return /tmp/redo-<uid>/ cache directory for the given project."""
    path_hash = hashlib.md5(project_key.encode()).hexdigest()[:12]
    return os.path.join("/tmp", "redo-{uid}".format(uid=os.getuid()), path_hash)


def get_persistent_db_path():
    """Return the path to the persistent target DB, or None."""
    project_key = _get_project_key()
    if project_key is None:
        return None
    cache_dir = _get_cache_dir(project_key)
    return os.path.join(cache_dir, "redo_target.db")


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


def build_full_target_cache():
    """
    Build the full project target database and save it to the persistent
    cache. This does a complete setup (loading all source/models) so it
    takes ~4s, but only needs to run once (e.g. from env/activate).
    """
    import database.setup
    from database.redo_target_database import redo_target_database

    project_key = _get_project_key()
    if project_key is None:
        return

    # Derive project root from config yaml path or use the key itself
    config_yaml = os.environ.get("ADAMANT_CONFIGURATION_YAML")
    if config_yaml:
        # Config yaml is typically at <project_root>/config/foo.yaml
        project_root = os.path.dirname(os.path.dirname(config_yaml))
    else:
        project_root = project_key

    # Run full setup from project root to populate the ephemeral target DB
    redo_1 = os.path.join(project_root, "_cache_warmup")
    redo_2 = os.path.join(project_root, "_cache_warmup.tmp")
    redo_3 = os.path.join(project_root, "_cache_warmup.base")

    did_setup = database.setup.setup(redo_1, redo_2, redo_3)
    if did_setup:
        # The setup populated the session target DB — save it
        from database._setup import _get_session_dir
        session_dir = _get_session_dir()
        session_db = os.path.join(session_dir, "db", "redo_target.db")
        save_persistent_db(session_db)
        # Clean up
        database.setup.cleanup(redo_1, redo_2, redo_3)


if __name__ == "__main__":
    build_full_target_cache()
