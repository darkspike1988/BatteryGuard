import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "validation-journal.py"
spec = importlib.util.spec_from_file_location("validation_journal", SCRIPT)
journal = importlib.util.module_from_spec(spec)
spec.loader.exec_module(journal)


class JournalTests(unittest.TestCase):
    def setUp(self):
        self.data = {
            "schemaVersion": 1,
            "environment": {key: "unknown" for key in journal.ENV_FIELDS},
            "records": [],
        }
        self.data["environment"].update(
            sessionID="test-session", deviceID="mac01", model="test-model",
            macOSVersion="14.0", macOSBuild="test-build", appVersion="0.3.7",
            daemonVersion="0.3.7", commit="a" * 40,
        )

    def record(self, case="H01", basis="physical", result="passed", at="2026-10-05T12:00:00Z"):
        return {"caseID": case, "basis": basis, "result": result, "testedAt": at,
                "steps": "Observe documented test", "observed": "Test observation",
                "evidence": ["fixtures/reviewed-example.txt"]}

    def test_empty_journal_has_no_passes(self):
        report = journal.summary(self.data)
        self.assertIn("passed=0", report)
        self.assertIn("not_run=25", report)

    def test_simulation_does_not_count_as_hardware_acceptance(self):
        self.data["records"] = [self.record(basis="simulation")]
        report = journal.summary(self.data)
        self.assertIn("passed=0", report)
        self.assertIn("not_run=25", report)
        self.assertIn("Simulationen: 1", report)

    def test_retest_retains_failed_history(self):
        self.data["records"] = [
            self.record(result="failed"),
            self.record(at="2026-10-05T12:01:00Z"),
        ]
        report = journal.summary(self.data)
        self.assertIn("passed=1", report)
        self.assertIn("Fehlversuche im gesamten Verlauf: 1", report)
        self.assertEqual(len(self.data["records"]), 2)

    def test_rejects_missing_evidence_wrong_basis_and_unknown_case(self):
        for edits in ({"evidence": []}, {"basis": "system"}, {"caseID": "H99"}):
            with self.subTest(edits=edits):
                data = copy.deepcopy(self.data)
                item = self.record()
                item.update(edits)
                data["records"] = [item]
                with self.assertRaises(ValueError):
                    journal.validate(data)

    def test_unknown_environment_can_be_blocked_but_not_passed(self):
        self.data["environment"]["commit"] = "unknown"
        self.data["records"] = [self.record(result="blocked")]
        journal.validate(self.data)
        self.data["records"][0]["result"] = "passed"
        with self.assertRaises(ValueError):
            journal.validate(self.data)

    def test_rejects_naive_time_and_backwards_records(self):
        self.data["records"] = [self.record(at="2026-10-05T12:00:00")]
        with self.assertRaises(ValueError):
            journal.validate(self.data)
        self.data["records"] = [
            self.record(at="2026-10-05T12:01:00Z"),
            self.record(at="2026-10-05T12:00:00Z"),
        ]
        with self.assertRaises(ValueError):
            journal.validate(self.data)

    def test_cli_init_append_and_failed_append_preserves_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            environment = root / "environment.json"
            environment.write_text(json.dumps(self.data["environment"]))
            target = root / "journal.json"

            def run(*args):
                return subprocess.run([sys.executable, str(SCRIPT), *map(str, args)],
                                      capture_output=True, text=True)

            self.assertEqual(run("init", target, "--environment", environment).returncode, 0)
            initial = target.read_bytes()
            self.assertNotEqual(run("init", target, "--environment", environment).returncode, 0)
            self.assertEqual(target.read_bytes(), initial)
            result = run("record", target, "--case", "S01", "--basis", "system",
                         "--result", "blocked", "--steps", "Search", "--observed", "No test Mac")
            self.assertEqual(result.returncode, 0, result.stderr)
            before = target.read_bytes()
            invalid = run("record", target, "--case", "H01", "--basis", "physical",
                          "--result", "passed", "--steps", "Observe", "--observed", "No evidence")
            self.assertNotEqual(invalid.returncode, 0)
            self.assertEqual(target.read_bytes(), before)
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)
            self.assertEqual(run("check", target).returncode, 0)
            self.assertIn("blocked=1", run("summary", target).stdout)

    def test_catalog_ids_unique_and_expected_behavior_present(self):
        data = json.loads(journal.CATALOG.read_text())
        self.assertEqual(len(data["cases"]), len(journal.catalog()))
        self.assertEqual(set(case["basis"] for case in data["cases"]), {"physical", "system", "release"})
        self.assertTrue(all(case["expected"] for case in data["cases"]))


if __name__ == "__main__":
    unittest.main()
