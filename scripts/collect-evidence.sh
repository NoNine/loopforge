#!/usr/bin/env bash

set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=common.sh
. "$script_dir/common.sh"

usage() {
  cat <<'EOF'
Usage: scripts/collect-evidence.sh [options]

Aggregate role-local and verifier evidence into a final package.

Options:
  --input <path>     Input evidence root or file; may be repeated.
  --output <path>    Output package directory.
  --mode <label>     Optional expected mode label used in summaries.
  -h, --help         Show this help text.

Defaults:
  Inputs are discovered from the current packageable evidence locations when present:
    generated/simulation/docker
  Output defaults to:
    simulation/evidence/package
EOF
}

help_requested=0
output_dir=""
mode_label=""
declare -a input_paths=()

sanitize_path_list() {
  local path
  for path in "$@"; do
    [ -e "$path" ] || continue
    input_paths+=("$path")
  done
}

discover_default_inputs() {
  local candidate
  for candidate in \
    "$repo_root/generated/simulation/docker"
  do
    [ -e "$candidate" ] && input_paths+=("$candidate")
  done
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --input)
        [ "$#" -ge 2 ] || die "--input requires a value"
        input_paths+=("$2")
        shift 2
        ;;
      --input=*)
        input_paths+=("${1#--input=}")
        shift
        ;;
      --output)
        [ "$#" -ge 2 ] || die "--output requires a value"
        output_dir="$2"
        shift 2
        ;;
      --output=*)
        output_dir="${1#--output=}"
        shift
        ;;
      --mode)
        [ "$#" -ge 2 ] || die "--mode requires a value"
        mode_label="$2"
        shift 2
        ;;
      --mode=*)
        mode_label="${1#--mode=}"
        shift
        ;;
      -h|--help)
        help_requested=1
        shift
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

parse_args "$@"
if [ "$help_requested" -eq 1 ]; then
  usage
  exit 0
fi

repo_root="$(cd "$script_dir/.." && pwd)"
version_baseline="Gerrit 3.13.6 / Jenkins 2.555.3 / Plugin Manager 2.15.0 / Java 21 / Ubuntu 24.04 noble"
collector_version="collect-evidence.sh $(git -C "$repo_root" rev-parse --short=12 HEAD 2>/dev/null || printf 'unknown')"
timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [ "${#input_paths[@]}" -eq 0 ]; then
  discover_default_inputs
fi

output_dir="${output_dir:-$repo_root/simulation/evidence/package}"
mkdir -p "$output_dir"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/collect-evidence.XXXXXX")"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

manifest_json="$tmpdir/manifest.json"
summary_json="$tmpdir/summary.json"
summary_text="$tmpdir/summary.txt"
records_json="$tmpdir/records.json"
package_log="$output_dir/collect-evidence.log"

python3 - "$repo_root" "$timestamp" "$version_baseline" "$collector_version" "$mode_label" "$manifest_json" "$summary_json" "$summary_text" "$records_json" "$package_log" "${input_paths[@]}" <<'PY'
import json, os, re, sys, pathlib, hashlib

repo_root = pathlib.Path(sys.argv[1])
timestamp = sys.argv[2]
version_baseline = sys.argv[3]
collector_version = sys.argv[4]
mode_label = sys.argv[5]
manifest_json = pathlib.Path(sys.argv[6])
summary_json = pathlib.Path(sys.argv[7])
summary_text = pathlib.Path(sys.argv[8])
records_json = pathlib.Path(sys.argv[9])
package_log = pathlib.Path(sys.argv[10])
inputs = [pathlib.Path(p) for p in sys.argv[11:]]

allowed_statuses = {"pass", "fail", "blocked", "unsupported", "not-applicable"}
secret_patterns = [
    re.compile(r"(?i)-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"(?i)-----BEGIN PRIVATE KEY-----"),
]
redacted_markers = {
    "redacted",
    "secrets-not-recorded",
    "secrets-redacted",
    "secrets-redacted; private keys, passwords, tokens, and ldap bind secrets must not appear in summaries.",
}
secret_key_names = {
    "token",
    "password",
    "private_key",
    "secret_key",
    "credential",
    "bind_secret",
    "secret",
    "passphrase",
}
secret_value_markers = re.compile(r"(?is)\b(?:token|password|private[_-]?key|credential|bind[_-]?secret|secret|passphrase)\b\s*[:=]\s*(.+)")
required = [
    "verification_mode",
    "timestamp",
    "role_or_environment",
    "checkpoint_name",
    "command_name",
    "status",
    "bounded_log_references",
    "redaction_status",
]

def fail(msg):
    raise SystemExit(f"ERROR: {msg}")

def is_secret_value(value):
    if not isinstance(value, str):
        return False
    normalized = value.strip()
    lowered = normalized.lower()
    if lowered in redacted_markers or lowered.startswith("secrets-redacted") or lowered.startswith("secrets-not-recorded"):
        return False
    for pat in secret_patterns:
        if pat.search(value):
            return True
    match = secret_value_markers.search(normalized)
    if match and rhs_looks_like_secret_payload(match.group(1)):
        return True
    return False

def rhs_looks_like_secret_payload(rhs):
    candidate = rhs.strip().strip("\"'")
    lowered = candidate.lower()
    if not candidate:
        return False
    if lowered in redacted_markers or lowered.startswith("secrets-redacted") or lowered.startswith("secrets-not-recorded"):
        return False
    if any(pat.search(candidate) for pat in secret_patterns):
        return True
    if re.search(r"(?i)\b(redacted|not recorded|vault|documented in vault)\b", candidate):
        return False
    if "/" in candidate or candidate.startswith("."):
        return False
    if len(candidate.split()) >= 3:
        return False
    if re.fullmatch(r"[A-Za-z0-9+/=_-]{6,}", candidate):
        return True
    if len(candidate) <= 48 and re.search(r"[A-Za-z]", candidate) and re.search(r"[0-9]", candidate):
        return True
    if len(candidate) <= 24 and " " not in candidate:
        return True
    return False

def split_key_name(name):
    value = str(name).strip()
    value = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", value)
    value = re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1_\2", value)
    value = re.sub(r"[^A-Za-z0-9]+", "_", value)
    value = value.lower().strip("_")
    return [part for part in value.split("_") if part]

def is_secret_key_path(key_path):
    if not key_path:
        return False
    parts = split_key_name(key_path[-1])
    if not parts:
        return False
    terminal = parts[-1]
    if terminal in secret_key_names:
        return True
    if terminal == "key" and len(parts) >= 2 and parts[-2] in {
        "api",
        "access",
        "client",
        "private",
        "secret",
        "token",
        "password",
        "credential",
        "passphrase",
        "bind",
    }:
        return True
    return False

def walk_values(value, key_path=()):
    if isinstance(value, dict):
        for key, child in value.items():
            if key == "redaction_status":
                continue
            yield from walk_values(child, key_path + (str(key),))
    elif isinstance(value, list):
        for child in value:
            yield from walk_values(child, key_path)
    else:
        yield key_path, value

def normalize_list(value):
    if value is None:
        return []
    if isinstance(value, list):
        return [str(v) for v in value]
    if isinstance(value, str):
        parts = [p.strip() for p in value.split(";") if p.strip()]
        if len(parts) > 1:
            return parts
        parts = [p.strip() for p in value.split(",") if p.strip()]
        if len(parts) > 1:
            return parts
        return [value] if value else []
    return [str(value)]

def manifest_entry(path):
    if path.is_file():
        stat = path.stat()
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        return {
            "path": str(path),
            "type": "file",
            "sha256": digest,
            "bytes": stat.st_size,
        }
    if path.is_dir():
        children = sorted(p for p in path.rglob("*") if p.is_file())
        digest = hashlib.sha256()
        total = 0
        for child in children:
            rel = child.relative_to(path)
            digest.update(str(rel).encode())
            digest.update(b"\0")
            data = child.read_bytes()
            digest.update(hashlib.sha256(data).digest())
            total += len(data)
        return {
            "path": str(path),
            "type": "directory",
            "sha256": digest.hexdigest(),
            "files": len(children),
            "bytes": total,
        }
    return {
        "path": str(path),
        "type": "missing",
        "sha256": "not-applicable",
    }

def load_record(path):
    try:
        data = json.loads(path.read_text())
    except Exception as exc:
        fail(f"malformed JSON in {path}: {exc}")
    if not isinstance(data, dict):
        fail(f"record must be a JSON object: {path}")
    for key in required:
        if key not in data or data[key] in ("", None):
            fail(f"missing required field {key} in {path}")
    if data["status"] not in allowed_statuses:
        fail(f"invalid status {data['status']} in {path}")
    source_version = data.get("package_version")
    source_helper = data.get("helper_command_version")
    data.setdefault("package_version", "legacy-inferred" if source_version in (None, "") else source_version)
    data.setdefault("helper_command_version", "legacy-inferred" if source_helper in (None, "") else source_helper)
    data["source_metadata"] = {
        "package_version": "legacy-inferred" if source_version in (None, "") else "present",
        "helper_command_version": "legacy-inferred" if source_helper in (None, "") else "present",
    }
    for key_path, value in walk_values(data):
        key_string = " / ".join(key_path).lower()
        if "redaction_status" in key_string:
            continue
        value_str = str(value)
        if not value_str:
            continue
        if is_secret_key_path(key_path):
            if value_str.strip().lower() in redacted_markers or value_str.strip().lower().startswith("secrets-redacted") or value_str.strip().lower().startswith("secrets-not-recorded"):
                continue
            fail(f"secret-looking key/value found in {path}: {'/'.join(key_path)}")
        if is_secret_value(value_str):
            fail(f"secret-looking value found in {path}")
    return data

records = []
for item in inputs:
    if not item.exists():
        continue
    if item.is_file() and item.suffix == ".json":
        records.append(load_record(item))
        continue
    if item.is_dir():
        for json_file in sorted(item.rglob("*.json")):
            records.append(load_record(json_file))
        continue
    fail(f"unsupported input path: {item}")

if not records:
    fail("no evidence records found")

status_counts = {status: 0 for status in sorted(allowed_statuses)}
mode_counts = {}
role_counts = {}
checkpoint_counts = {}
package_manifests = []
bounded_logs = []
status_by_record = []

for record in records:
    status = record["status"]
    status_counts[status] += 1
    mode = str(record.get("verification_mode", ""))
    role = str(record.get("role_or_environment", ""))
    checkpoint = str(record.get("checkpoint_name", ""))
    mode_counts[mode] = mode_counts.get(mode, 0) + 1
    role_counts[role] = role_counts.get(role, 0) + 1
    checkpoint_counts[checkpoint] = checkpoint_counts.get(checkpoint, 0) + 1
    status_by_record.append({
        "timestamp": record.get("timestamp"),
        "verification_mode": mode,
        "package_version": record.get("package_version"),
        "helper_command_version": record.get("helper_command_version"),
        "role_or_environment": role,
        "checkpoint_name": checkpoint,
        "command_name": record.get("command_name"),
        "status": status,
        "source_metadata": record.get("source_metadata"),
        "hostnames": normalize_list(record.get("hostnames") or record.get("hostname")),
        "endpoints": normalize_list(record.get("service_endpoints") or record.get("endpoint") or record.get("endpoints")),
        "observed_checks": record.get("observed_checks"),
        "bounded_log_references": record.get("bounded_log_references"),
        "redaction_status": record.get("redaction_status"),
        "artifact_manifest_references": record.get("artifact_manifest_references", "not-applicable"),
        "checksum_references": record.get("checksum_references", "not-applicable"),
        "checksum_verification_result": record.get("checksum_verification_result", "not-applicable"),
    })
    for key in ("artifact_manifest_references", "checksum_references", "bounded_log_references"):
        value = record.get(key)
        if value and value != "not-applicable":
            package_manifests.append({
                "record": str(record.get("role_or_environment", "unknown")),
                "field": key,
                "value": value,
            })
    logs = normalize_list(record.get("bounded_log_references"))
    for log in logs:
        if log:
            bounded_logs.append(log)

summary = {
    "package_timestamp": timestamp,
    "collector_version": collector_version,
    "version_baseline": version_baseline,
    "package_version": "v1-evidence-package",
    "mode_label": mode_label or "mixed",
    "helper_command_version": collector_version,
    "metadata_policy": "legacy-evidence-enriched",
    "record_count": len(records),
    "status_counts": status_counts,
    "verification_mode_counts": mode_counts,
    "role_counts": role_counts,
    "checkpoint_counts": checkpoint_counts,
    "records": status_by_record,
    "manifests": package_manifests,
    "bounded_log_references": sorted(set(bounded_logs)),
}

manifest = {
    "package_timestamp": timestamp,
    "inputs": [str(p) for p in inputs],
    "record_count": len(records),
    "records_sha256": hashlib.sha256("\n".join(json.dumps(r, sort_keys=True) for r in records).encode()).hexdigest(),
    "status_counts": status_counts,
}

summary_json.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
records_json.write_text(json.dumps(records, indent=2, sort_keys=True) + "\n")
manifest_json.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")

lines = [
    f"Package timestamp: {timestamp}",
    f"Collector version: {collector_version}",
    f"Version baseline: {version_baseline}",
    f"Mode label: {mode_label or 'mixed'}",
    f"Records: {len(records)}",
    "Status counts:",
]
for status in sorted(status_counts):
    lines.append(f"  {status}: {status_counts[status]}")
lines.append("Roles:")
for role, count in sorted(role_counts.items()):
    lines.append(f"  {role}: {count}")
lines.append("Checkpoints:")
for checkpoint, count in sorted(checkpoint_counts.items()):
    lines.append(f"  {checkpoint}: {count}")
lines.append("Bounded logs:")
for log in sorted(set(bounded_logs)):
    lines.append(f"  {log}")
lines.append("Redaction: secrets-redacted; private keys, passwords, tokens, and LDAP bind secrets must not appear in summaries.")
summary_text.write_text("\n".join(lines) + "\n")

with package_log.open("w") as fh:
    fh.write("status=pass command=collect-evidence aggregate=complete\n")
    fh.write(f"records={len(records)} output={summary_json}\n")
PY

mkdir -p "$output_dir"
cp "$summary_json" "$output_dir/summary.json"
cp "$summary_text" "$output_dir/summary.txt"
cp "$records_json" "$output_dir/records.json"
cp "$manifest_json" "$output_dir/manifest.json"

record_count="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$output_dir/records.json")"
printf 'status=pass command=collect-evidence package=%s records=%s\n' "$output_dir" "$record_count"
