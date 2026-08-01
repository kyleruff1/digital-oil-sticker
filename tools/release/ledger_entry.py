#!/usr/bin/env python3
"""Render one release-ledger row from a /version response.

Kept as a file rather than inlined in the workflow: a heredoc inside a YAML
block scalar loses its column-0 terminator once YAML dedents the block, which
fails at deploy time — the worst moment to discover a quoting bug.
"""
import json
import os
import sys


def main() -> int:
    path = sys.argv[1] if len(sys.argv) > 1 else "-"
    raw = sys.stdin.read() if path == "-" else open(path, encoding="utf-8").read()

    try:
        identity = json.loads(raw)
    except json.JSONDecodeError:
        # A machine that cannot report its identity still gets a ledger entry —
        # one that says so. A missing row would read as "no deploy happened".
        identity = {}

    rows = [
        ("Deployed at (UTC)", os.environ.get("DEPLOY_AT") or "see workflow run timestamp"),
        ("Deployed by", os.environ.get("ACTOR", "unknown")),
        ("Reason", os.environ.get("REASON", "")),
        ("Commit", identity.get("git_sha", "unknown")),
        ("Built at", identity.get("built_at", "unknown")),
        ("App version", identity.get("app_version", "unknown")),
        ("Catalog data_version", identity.get("catalog_data_version", "unknown")),
        ("Catalog schema_version", identity.get("catalog_schema_version", "unknown")),
        ("Catalog payload sha256", identity.get("catalog_payload_sha256", "unknown")),
        ("LocalStore schema_version", identity.get("local_store_schema_version", "unknown")),
        ("Fly release", identity.get("fly_release_version") or "unknown"),
        ("Fly image", identity.get("fly_image_ref") or "unknown"),
        ("Fly region", identity.get("fly_region") or "unknown"),
        ("Rollback target", os.environ.get("PREVIOUS", "unknown")),
    ]

    print("| Field | Value |")
    print("| --- | --- |")
    for key, value in rows:
        print(f"| {key} | `{value}` |")

    if identity.get("git_sha", "unknown") == "unknown":
        print()
        print(
            "> This machine could not report its commit. That means it was built "
            "without the `GIT_SHA` build arg — see the deploy runbook."
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
