# PyAlembic wheel build

This fork includes a manually triggered GitHub Actions workflow that builds an
Alembic 1.8.12 wheel for CPython 3.9 on x86_64 Linux. The repaired
`manylinux_2_28` wheel supports distributions with glibc 2.28 or newer,
including Rocky Linux 9.

## Build

1. Open **Actions** in this fork and enable workflows if prompted.
2. Select **Build PyAlembic wheel**.
3. Select **Run workflow**.
4. Download the `pyalembic-1.8.12-cp39-manylinux-x86_64` artifact.

## Install and read an archive

Use a dedicated virtual environment because PyAlembic and SQLAlchemy Alembic
both use the top-level import name `alembic`.

```bash
python3.9 -m venv .venv-pyalembic
source .venv-pyalembic/bin/activate
python -m pip install /path/to/pyalembic_aswf-1.8.12-*.whl
python examples/read_alembic.py /path/to/archive.abc
```

Large `.abc` production files do not need to be uploaded to GitHub. The
workflow validates the wheel against a small archive already present in the
upstream test suite.
