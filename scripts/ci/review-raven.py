#!/usr/bin/env python3
"""Route review invocation through the review-only Codex home.

Keep CODEX_HOME, model, tools and review policy separate from daily Codex.
Never load daily auth files, print credential values, edit configuration or retry.
"""
import os
from pathlib import Path
import sys
import tomllib


def build_command(config_path, binary, arguments, environment=None):
    try:
        config = tomllib.loads(Path(config_path).read_text(encoding="utf-8"))
    except (OSError, UnicodeError, tomllib.TOMLDecodeError):
        raise ValueError("Cannot read review Codex provider configuration") from None
    provider = config.get("model_provider")
    if not isinstance(provider, str) or not provider.strip():
        raise ValueError("Review Codex configuration must explicitly select a model_provider")
    return [binary, "exec", *arguments]


def main():
    if len(sys.argv) < 2:
        print("[codex-review] expected Codex binary and exec arguments", file=sys.stderr)
        return 1
    codex_home = os.environ.get("CODEX_HOME")
    if not codex_home or not str(codex_home).strip():
        print("[codex-review] Raven setup failed: Missing or empty CODEX_HOME environment variable", file=sys.stderr)
        return 1
    config = Path(codex_home) / "config.toml"
    try:
        command = build_command(config, sys.argv[1], sys.argv[2:], os.environ)
        os.execvp(command[0], command)
    except (ValueError, OSError) as error:
        # Never print an OSError filename/argv or a TOML parser's source excerpt.
        detail = str(error) if isinstance(error, ValueError) else "Cannot start Codex executable"
        print(f"[codex-review] Raven setup failed: {detail}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
