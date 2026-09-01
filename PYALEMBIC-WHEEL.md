# PyAlembic wheel build

This fork packages the PyAlembic bindings as `alembic3d`, avoiding the import
name used by SQLAlchemy Alembic. GitHub Actions builds CPython 3.9-3.14 wheels
for Linux x86_64, Windows x86_64, and macOS ARM64. Linux wheels target
`manylinux_2_28`, including Rocky Linux 9.

## Build

1. Open **Actions** in this fork and enable workflows if prompted.
2. Select **Wheels**.
3. Select **Run workflow**.
4. Download the artifact matching the required OS and Python version.

## Install and read an archive

```bash
python3.9 -m venv .venv-alembic3d
source .venv-alembic3d/bin/activate
python -m pip install /path/to/alembic3d-1.8.12.1-*.whl
python examples/read_alembic.py /path/to/archive.abc
```

Large `.abc` production files do not need to be uploaded to GitHub. The
workflow validates the wheel against a small archive already present in the
upstream test suite.
