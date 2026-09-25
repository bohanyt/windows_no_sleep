"""Fail-closed checks for promoting an exact main CI artifact to stable.

The script does not compile, download, or publish. The workflow supplies
checkout metadata, Actions JSON, and a staging directory.
"""

import argparse
import hashlib
import json
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

TAG_RE = re.compile(r"^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
SUM_RE = re.compile(r"^([0-9a-fA-F]{64})  WindowsNoSleep\.exe$")
ATTR_RE = {
    "AssemblyVersion": re.compile(r'\[assembly:\s*AssemblyVersion\("([^"]+)"\)\]'),
    "AssemblyFileVersion": re.compile(r'\[assembly:\s*AssemblyFileVersion\("([^"]+)"\)\]'),
}
EXPECTED_FILES = {
    "WindowsNoSleep.exe",
    "WindowsNoSleep.exe.config",
    "README.txt",
    "SHA256SUMS.txt",
    "BUILD_SHA.txt",
}


def fail(message):
    print(f"STABLE PROMOTION FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def version_from_tag(tag):
    if not TAG_RE.fullmatch(tag or ""):
        fail("Stable tag must be vX.Y.Z.")
    return tag[1:] + ".0"


def verify_source(assembly_text, manifest_text, version):
    for name, pattern in ATTR_RE.items():
        found = pattern.findall(assembly_text)
        if found != [version]:
            fail(f"{name} does not match {version}.")
    try:
        root = ET.fromstring(manifest_text)
    except ET.ParseError as exc:
        fail(f"Manifest XML is malformed: {exc}")
    identities = [el for el in root.iter() if el.tag.endswith("assemblyIdentity")]
    if len(identities) != 1:
        fail("Manifest must contain one assemblyIdentity.")
    identity = identities[0]
    name = identity.attrib.get("name", "")
    if identity.attrib.get("version") != version or name != "WindowsNoSleep" or "NativePilot" in name:
        fail("Manifest stable identity is unresolved or inconsistent.")


def load_json_lines(path):
    items = []
    text = Path(path).read_text(encoding="utf-8")
    for line_number, line in enumerate(text.splitlines(), 1):
        if not line.strip():
            continue
        try:
            items.append(json.loads(line))
        except json.JSONDecodeError as exc:
            fail(f"Malformed JSON on line {line_number}: {exc}")
    return items


def select_run(runs, sha):
    if not SHA_RE.fullmatch(sha or ""):
        fail("Tag SHA is malformed.")
    matches = []
    for run in runs:
        if not isinstance(run, dict):
            fail("Workflow run record is malformed.")
        name = run.get("name")
        if (
            run.get("head_sha") == sha
            and run.get("head_branch") == "main"
            and run.get("event") == "push"
            and run.get("status") == "completed"
            and run.get("conclusion") == "success"
            and (name is None or name == "native-v1")
            and isinstance(run.get("id"), int)
        ):
            matches.append(run)
    if len(matches) != 1:
        fail(f"Expected exactly one successful main push run for {sha}; found {len(matches)}.")
    return matches[0]


def select_artifact(artifacts):
    matches = []
    for artifact in artifacts:
        if not isinstance(artifact, dict):
            fail("Artifact record is malformed.")
        if artifact.get("name") != "WindowsNoSleep-native-pilot":
            continue
        if artifact.get("expired") is True:
            fail("Exact main artifact WindowsNoSleep-native-pilot is expired.")
        if artifact.get("expired") is not False or not isinstance(artifact.get("id"), int):
            fail("Exact main artifact record is malformed.")
        matches.append(artifact)
    if len(matches) != 1:
        fail(f"Expected exactly one WindowsNoSleep-native-pilot artifact; found {len(matches)}.")
    return matches[0]


def read_exe_versions(path):
    command = (
        "$v = [Diagnostics.FileVersionInfo]::GetVersionInfo($env:WNS_EXE); "
        "Write-Output $v.FileVersion; Write-Output $v.ProductVersion"
    )
    completed = subprocess.run(
        ["powershell", "-NoProfile", "-NonInteractive", "-Command", command],
        capture_output=True,
        text=True,
        check=False,
        env={**dict(**{k: v for k, v in __import__("os").environ.items()}), "WNS_EXE": str(path)},
    )
    if completed.returncode != 0:
        fail(f"Unable to read EXE version: {completed.stderr.strip()}")
    lines = [line.strip() for line in completed.stdout.splitlines() if line.strip()]
    if len(lines) != 2:
        fail("EXE version output is malformed.")
    return lines[0], lines[1]


def verify_package(directory, sha, version, versions=None):
    root = Path(directory)
    if not root.is_dir():
        fail("Staging directory is missing.")
    found = {path.name for path in root.iterdir() if path.is_file()}
    nested = [path for path in root.iterdir() if path.is_dir()]
    if nested or found != EXPECTED_FILES:
        fail("Staged package files are missing or unexpected.")
    build_sha = (root / "BUILD_SHA.txt").read_text(encoding="ascii").splitlines()
    if build_sha != [sha]:
        fail("BUILD_SHA.txt does not equal the tag commit.")
    sums = (root / "SHA256SUMS.txt").read_text(encoding="ascii").splitlines()
    if len(sums) != 1:
        fail("SHA256SUMS.txt must contain one line.")
    match = SUM_RE.fullmatch(sums[0])
    if not match:
        fail("SHA256SUMS.txt is malformed.")
    exe = root / "WindowsNoSleep.exe"
    actual = hashlib.sha256(exe.read_bytes()).hexdigest()
    if actual.lower() != match.group(1).lower():
        fail("Staged EXE SHA-256 does not match SHA256SUMS.txt.")
    file_version, product_version = versions if versions is not None else read_exe_versions(exe)
    if file_version != version or product_version != version:
        fail("EXE FileVersion/ProductVersion does not match the tag.")
    return actual


def self_test():
    version = version_from_tag("v1.0.0")
    assembly = '[assembly: AssemblyVersion("1.0.0.0")]\n[assembly: AssemblyFileVersion("1.0.0.0")]\n'
    manifest = '<assembly><assemblyIdentity version="1.0.0.0" name="WindowsNoSleep" /></assembly>'
    verify_source(assembly, manifest, version)
    sha = "a" * 40
    run = select_run(
        [{"id": 7, "name": "native-v1", "head_sha": sha, "head_branch": "main", "event": "push", "status": "completed", "conclusion": "success"}],
        sha,
    )
    if run["id"] != 7:
        fail("Unique run was not selected.")
    artifact = select_artifact([{"id": 9, "name": "WindowsNoSleep-native-pilot", "expired": False}])
    if artifact["id"] != 9:
        fail("Unique artifact was not selected.")
    import tempfile

    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        payload = b"exact-bytes"
        (root / "WindowsNoSleep.exe").write_bytes(payload)
        (root / "WindowsNoSleep.exe.config").write_text("<configuration />", encoding="ascii")
        (root / "README.txt").write_text("readme\n", encoding="ascii")
        digest = hashlib.sha256(payload).hexdigest().upper()
        (root / "SHA256SUMS.txt").write_text(f"{digest}  WindowsNoSleep.exe\n", encoding="ascii")
        (root / "BUILD_SHA.txt").write_text(sha + "\n", encoding="ascii")
        actual = verify_package(root, sha, version, versions=("1.0.0.0", "1.0.0.0"))
        if actual.lower() != digest.lower():
            fail("Package hash mismatch in fixture.")
    failures = [
        lambda: version_from_tag("v1.0"),
        lambda: verify_source(assembly.replace("1.0.0.0", "0.4.7.0", 1), manifest, version),
        lambda: verify_source(assembly, manifest.replace("WindowsNoSleep", "WindowsNoSleep.NativePilot"), version),
        lambda: select_run([], sha),
        lambda: select_run(
            [
                {"id": 1, "name": "native-v1", "head_sha": sha, "head_branch": "main", "event": "push", "status": "completed", "conclusion": "success"},
                {"id": 2, "name": "native-v1", "head_sha": sha, "head_branch": "main", "event": "push", "status": "completed", "conclusion": "success"},
            ],
            sha,
        ),
        lambda: select_artifact([{"id": 3, "name": "WindowsNoSleep-native-pilot", "expired": True}]),
    ]
    for check in failures:
        try:
            check()
        except SystemExit as exc:
            if exc.code == 1:
                continue
            raise
        fail("A fail-closed fixture unexpectedly passed.")
    print("PROMOTE_EXACT_MAIN_ARTIFACT_SELF_TEST_PASS")


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    source = sub.add_parser("verify-source")
    source.add_argument("--tag", required=True)
    source.add_argument("--assembly", required=True)
    source.add_argument("--manifest", required=True)
    select = sub.add_parser("select-run")
    select.add_argument("--sha", required=True)
    select.add_argument("--runs", required=True)
    select.add_argument("--out", required=True)
    choose = sub.add_parser("select-artifact")
    choose.add_argument("--artifacts", required=True)
    choose.add_argument("--out", required=True)
    package = sub.add_parser("verify-package")
    package.add_argument("--dir", required=True)
    package.add_argument("--sha", required=True)
    package.add_argument("--version", required=True)
    package.add_argument("--out", required=True)
    sub.add_parser("self-test")
    args = parser.parse_args()
    if args.command == "self-test":
        self_test()
        return
    if args.command == "verify-source":
        verify_source(Path(args.assembly).read_text(encoding="utf-8"), Path(args.manifest).read_text(encoding="utf-8"), version_from_tag(args.tag))
        print("SOURCE_IDENTITY_PASS")
        return
    if args.command == "select-run":
        run = select_run(load_json_lines(args.runs), args.sha)
        Path(args.out).write_text(str(run["id"]) + "\n", encoding="ascii")
        print(f"SELECTED_MAIN_RUN {run['id']}")
        return
    if args.command == "select-artifact":
        artifact = select_artifact(load_json_lines(args.artifacts))
        Path(args.out).write_text(str(artifact["id"]) + "\n", encoding="ascii")
        print(f"SELECTED_ARTIFACT {artifact['id']}")
        return
    digest = verify_package(args.dir, args.sha, args.version)
    Path(args.out).write_text(digest.upper() + "\n", encoding="ascii")
    print(f"PACKAGE_IDENTITY_PASS {digest.upper()}")


if __name__ == "__main__":
    main()
