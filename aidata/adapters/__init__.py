"""aidata adapters package.

Each adapter module exposes:
    collect() -> int      # L1: fetch new data, redact, append to raw/, update watermark
    normalize() -> int    # L2: read raw/, clean into clean/<source>.db

The registry below maps source name -> module. cli.py drives them.
"""
