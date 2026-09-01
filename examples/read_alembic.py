#!/usr/bin/env python3
"""Print the object hierarchy of an Alembic geometry-cache archive."""

import argparse
from pathlib import Path

from alembic3d.Abc import IArchive


def print_tree(obj, depth=0):
    print(f"{'  ' * depth}{obj.getName()}")
    for index in range(obj.getNumChildren()):
        print_tree(obj.getChild(index), depth + 1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path, help="Path to an Alembic .abc file")
    args = parser.parse_args()

    archive_path = args.archive.expanduser().resolve()
    if not archive_path.is_file():
        parser.error(f"file not found: {archive_path}")

    archive = IArchive(str(archive_path))
    print(f"Archive: {archive.getName()}")
    print_tree(archive.getTop())


if __name__ == "__main__":
    main()
