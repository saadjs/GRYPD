#!/usr/bin/env python3
import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.dirname(__file__))

import validate_outputs


class ValidateOutputsTests(unittest.TestCase):
    def write_json(self, path, obj):
        with open(path, "w") as f:
            json.dump(obj, f)

    def test_malformed_manifest_reports_errors_without_traceback(self):
        with tempfile.TemporaryDirectory() as tmp:
            dist_dir = os.path.join(tmp, "dist")
            app_dir = os.path.join(tmp, "app")
            os.makedirs(dist_dir)
            os.makedirs(app_dir)

            manifest = {"taxonomy": None, "disciplines": [None]}
            self.write_json(os.path.join(dist_dir, "manifest.json"), manifest)
            self.write_json(os.path.join(app_dir, "manifest.json"), manifest)
            self.write_json(os.path.join(app_dir, "taxonomy.json"), {})
            self.write_json(os.path.join(app_dir, "strength.json"), [])

            output = io.StringIO()
            with (
                patch.object(validate_outputs, "DIST_DIR", dist_dir),
                patch.object(validate_outputs, "APP_RESOURCES_DIR", app_dir),
                contextlib.redirect_stdout(output),
                self.assertRaises(SystemExit) as raised,
            ):
                validate_outputs.main()

        self.assertEqual(raised.exception.code, 1)
        text = output.getvalue()
        self.assertIn("JSON CONTRACT: FAIL", text)
        self.assertIn("manifest.taxonomy must be object", text)
        self.assertNotIn("Traceback", text)


if __name__ == "__main__":
    unittest.main()
