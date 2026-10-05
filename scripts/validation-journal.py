#!/usr/bin/env python3
"""Manual, local acceptance journal; never reads battery, credentials or device data."""
import argparse
from collections import Counter
from contextlib import contextmanager
from datetime import datetime, timezone
import fcntl
import json
import os
from pathlib import Path
import re
import tempfile

CATALOG = Path(__file__).resolve().parents[1] / "docs/validation/cases.json"
RESULTS = ("passed", "failed", "blocked", "not_run")
BASES = ("simulation", "physical", "system", "release")
ENV_FIELDS = {
    "sessionID", "deviceID", "model", "chip", "macOSVersion", "macOSBuild",
    "firmware", "appVersion", "daemonVersion", "commit", "adapter", "connection",
    "externalDisplay", "lid",
}


def bounded(value, name, limit=2000):
    if not isinstance(value, str) or not value.strip() or len(value) > limit:
        raise ValueError(f"{name}: nonempty text, maximum {limit} characters required")
    return value


def timestamp(value):
    bounded(value, "testedAt", 40)
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValueError("testedAt: ISO 8601 timestamp required") from exc
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise ValueError("testedAt: timezone required")
    return parsed


def catalog():
    data = json.loads(CATALOG.read_text(encoding="utf-8"))
    return {case["id"]: case for case in data["cases"]}


def validate(data):
    if set(data) != {"schemaVersion", "environment", "records"} or data["schemaVersion"] != 1:
        raise ValueError("Unsupported journal schema")
    env = data["environment"]
    if not isinstance(env, dict) or set(env) != ENV_FIELDS:
        raise ValueError("Environment fields do not match the template")
    for key, value in env.items():
        bounded(value, key, 160)
    for key in ("sessionID", "deviceID"):
        if not re.fullmatch(r"[A-Za-z0-9._-]{1,80}", env[key]):
            raise ValueError(f"{key}: use a pseudonymous identifier")
    if env["commit"] != "unknown" and not re.fullmatch(r"[0-9a-f]{40}", env["commit"]):
        raise ValueError("commit: full lowercase SHA or unknown required")
    records = data["records"]
    if not isinstance(records, list) or len(records) > 10000:
        raise ValueError("records: list with at most 10000 entries required")
    known = catalog()
    previous_time = None
    for record in records:
        if not isinstance(record, dict) or set(record) != {
            "caseID", "basis", "result", "testedAt", "steps", "observed", "evidence"
        }:
            raise ValueError("Invalid record fields")
        if record["caseID"] not in known or record["basis"] not in BASES or record["result"] not in RESULTS:
            raise ValueError("Unknown case, basis or result")
        moment = timestamp(record["testedAt"])
        if previous_time is not None and moment < previous_time:
            raise ValueError("Records must be in chronological order; use a new session after a clock correction")
        previous_time = moment
        bounded(record["steps"], "steps")
        bounded(record["observed"], "observed")
        evidence = record["evidence"]
        if not isinstance(evidence, list) or len(evidence) > 20:
            raise ValueError("evidence: list with at most 20 references required")
        for item in evidence:
            bounded(item, "evidence reference", 500)
        if record["result"] in ("passed", "failed"):
            if not evidence:
                raise ValueError("Executed tests need evidence references")
            if record["basis"] not in ("simulation", known[record["caseID"]]["basis"]):
                raise ValueError("Evidence basis does not match this test case")
            if record["basis"] != "simulation" and any(
                env[key] == "unknown" for key in
                ("model", "macOSVersion", "macOSBuild", "appVersion", "daemonVersion", "commit")
            ):
                raise ValueError("Executed acceptance tests need model, OS/build, app, daemon and commit")
    return data


def read(path):
    return validate(json.loads(Path(path).read_text(encoding="utf-8")))


def write_atomic(path, data):
    validate(data)
    path = Path(path)
    descriptor, temporary = tempfile.mkstemp(prefix=".journal-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            json.dump(data, output, indent=2, ensure_ascii=False)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


@contextmanager
def journal_lock(path):
    lock = Path(str(path) + ".lock")
    descriptor = os.open(lock, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield
    finally:
        os.close(descriptor)


def summary(data):
    validate(data)
    env = data["environment"]
    known = catalog()
    latest = {}
    for record in data["records"]:
        latest[(record["caseID"], record["basis"])] = record
    rows = [
        "# B-Guard Abnahmebericht", "",
        f"Session: {env['sessionID']} · Gerät: {env['deviceID']}",
        f"App/Dienst: {env['appVersion']} / {env['daemonVersion']} · Commit: {env['commit']}", "",
        "Gilt nur für die dokumentierte Umgebung. Keine automatische Hardwarefreigabe.",
        "Simulationen ersetzen keine physische oder systemweite Abnahme.", "",
        "| Fall | Bereich | Letztes Ergebnis | Zeitpunkt |",
        "| --- | --- | --- | --- |",
    ]
    counts = Counter()
    for case in known.values():
        record = latest.get((case["id"], case["basis"]))
        result = record["result"] if record else "not_run"
        counts[result] += 1
        rows.append(f"| {case['id']} · {case['title']} | {case['basis']} | {result} | {record['testedAt'] if record else '—'} |")
    rows.extend(["", "Abnahmestand: " + ", ".join(f"{name}={counts[name]}" for name in RESULTS) + "."])
    simulations = [item for item in data["records"] if item["basis"] == "simulation"]
    rows.append(f"Separat erfasste Simulationen: {len(simulations)}.")
    failures = [item for item in data["records"] if item["result"] == "failed"]
    rows.extend(["", f"Fehlversuche im gesamten Verlauf: {len(failures)} (auch nach bestandenem Wiederholungstest)."])
    for item in failures:
        rows.append(f"- {item['caseID']} / {item['basis']} / {item['testedAt']}")
    rows.extend(["", "Beobachtungen, Schritte und Belegreferenzen stehen im unveränderten JSON-Journal.",
                 "Ein passed-Eintrag ist eine manuelle Angabe; das Werkzeug prüft keine Beleginhalte.", ""])
    return "\n".join(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    init = commands.add_parser("init")
    init.add_argument("journal", type=Path)
    init.add_argument("--environment", required=True, type=Path)
    record = commands.add_parser("record")
    record.add_argument("journal", type=Path)
    record.add_argument("--case", dest="case_id", required=True, choices=tuple(catalog()))
    record.add_argument("--basis", choices=BASES, required=True)
    record.add_argument("--result", choices=RESULTS, required=True)
    record.add_argument("--steps", required=True)
    record.add_argument("--observed", required=True)
    record.add_argument("--evidence", action="append", default=[])
    record.add_argument("--tested-at", default=None)
    report = commands.add_parser("summary")
    report.add_argument("journal", type=Path)
    check = commands.add_parser("check")
    check.add_argument("journal", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "init":
            data = validate({"schemaVersion": 1, "environment": json.loads(
                args.environment.read_text(encoding="utf-8")), "records": []})
            with journal_lock(args.journal):
                if args.journal.exists():
                    raise ValueError("Journal exists; use a new session filename")
                write_atomic(args.journal, data)
            print("Empty journal created; no tests have been executed.")
        elif args.command == "record":
            with journal_lock(args.journal):
                data = read(args.journal)
                data["records"].append({
                    "caseID": args.case_id, "basis": args.basis, "result": args.result,
                    "testedAt": args.tested_at or datetime.now(timezone.utc).isoformat(timespec="seconds"),
                    "steps": args.steps, "observed": args.observed, "evidence": args.evidence,
                })
                write_atomic(args.journal, data)
            print("Manual record saved; hardware capabilities unchanged.")
        elif args.command == "summary":
            print(summary(read(args.journal)), end="")
        else:
            read(args.journal)
            print("Journal schema valid; evidence contents not verified.")
    except (ValueError, OSError, KeyError, TypeError) as exc:
        parser.exit(1, f"Journal error: {exc}\n")


if __name__ == "__main__":
    main()
