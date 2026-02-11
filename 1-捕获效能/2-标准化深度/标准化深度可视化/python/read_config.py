#!/usr/bin/env python3
"""Read a single key from config.json (stdout only)."""

from __future__ import annotations

import argparse
import json
from typing import Any


def run(*, config_path: str, key: str, default: str | None = None) -> str:
    with open(config_path, "r", encoding="utf-8") as handle:
        config = json.load(handle)
    value: Any = config.get(key, default)
    if isinstance(value, bool):
        return str(value).lower()
    return "" if value is None else str(value)


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Read a key from conf/config.json")
    parser.add_argument("--config", required=True, help="Path to config.json")
    parser.add_argument("--key", required=True, help="Key to read")
    parser.add_argument("--default", default=None, help="Default value if key missing")
    return parser


def main() -> None:
    parser = _build_parser()
    args = parser.parse_args()
    print(run(config_path=args.config, key=args.key, default=args.default))


if __name__ == "__main__":
    main()
