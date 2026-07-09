import os
import tempfile

# `registrar.app` now builds a module-level `app` via `_build_app_from_env()`
# (Task 10), which requires TG_BOT_TOKEN at import time and writes under
# REGISTRAR_DATA_ROOT (default /app/registrar-data, not writable outside the
# container). Set harmless placeholders before any test module imports
# `registrar.app`, so the existing test suite (which builds its own app via
# `create_app(...)` directly) is unaffected by that module-level wiring.
os.environ.setdefault("TG_BOT_TOKEN", "test-placeholder-token")
os.environ.setdefault("REGISTRAR_DATA_ROOT", tempfile.mkdtemp(prefix="registrar-test-data-"))
