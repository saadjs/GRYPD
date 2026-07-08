#!/usr/bin/env python3
import copy
import os
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.dirname(__file__))

import assemble
import common

KN = {
    "trainer": "Trainer",
    "duration": "Duration",
    "body_focus": "Body Focus",
    "ep": "Ep",
    "link": "Link",
    "description": "Description",
    "format": "Format",
    "detailed_moves": "Detailed Moves",
    "muscle_groups": "Muscle Groups",
    "equipment": "Equipment",
    "dumbbells": "Dumbbells",
    "moves": "Types of Moves",
    "date": "Date",
}


def row(row_id, link=None):
    return {
        "_id": row_id,
        "trainer": "Sam",
        "duration": "20",
        "body_focus": "Total Body",
        "ep": 7,
        "link": link,
        "description": "SeaTable description",
        "format": None,
        "detailed_moves": None,
        "muscle_groups": ["Shoulders"],
        "equipment": ["Dumbbells"],
        "dumbbells": ["2 Medium"],
        "moves": ["Squat"],
        "date": "2026-01-01",
    }


def catalog_record(workout_id):
    return {
        "id": workout_id,
        "discipline": "strength",
        "title": "Strength with Sam",
        "trainer": "sam",
        "durationMinutes": 20,
        "episode": 7,
        "appleUrl": f"https://fitness.apple.com/us/workout/strength-with-sam/{workout_id}",
        "description": "Apple description",
        "releaseDate": "2026-01-01",
        "facets": {
            "bodyFocus": "total-body",
            "muscleGroups": ["shoulders"],
            "equipment": ["dumbbells"],
            "dumbbells": ["2-medium"],
        },
        "moves": ["squat"],
    }


class BuildCompleteCatalogTests(unittest.TestCase):
    def build_with_rows(self, rows, catalog):
        table = {"rows": copy.deepcopy(rows)}
        with patch.object(assemble, "load_table", return_value=(table, KN, {})):
            return assemble.build_complete_catalog(copy.deepcopy(catalog))

    def test_duplicate_linked_rows_are_all_aliased_to_canonical_record(self):
        workout_id = "1234567890"
        link = f"https://fitness.apple.com/us/workout/strength-with-sam/{workout_id}"

        complete, fallback_count = self.build_with_rows(
            [row("a", link), row("b", link)],
            [catalog_record(workout_id)],
        )

        self.assertEqual(fallback_count, 0)
        self.assertEqual(len(complete), 1)
        self.assertEqual(complete[0]["id"], workout_id)
        self.assertEqual(complete[0]["aliases"], ["seatable-a", "seatable-b"])

    def test_duplicate_linked_rows_without_canonical_record_share_one_fallback(self):
        workout_id = "1234567890"
        link = f"https://fitness.apple.com/us/workout/strength-with-sam/{workout_id}"

        complete, fallback_count = self.build_with_rows(
            [row("a", link), row("b", link)],
            [],
        )

        self.assertEqual(fallback_count, 1)
        self.assertEqual(len(complete), 1)
        self.assertEqual(complete[0]["id"], "seatable-a")
        self.assertEqual(complete[0]["appleUrl"], link)
        self.assertEqual(complete[0]["aliases"], ["seatable-b"])

    def test_incomplete_rows_are_not_published_as_fallbacks(self):
        incomplete = row("draft")
        incomplete["trainer"] = None
        incomplete["duration"] = None
        incomplete["body_focus"] = None
        incomplete["muscle_groups"] = None
        incomplete["moves"] = None

        complete, fallback_count = self.build_with_rows([incomplete], [])

        self.assertEqual(fallback_count, 0)
        self.assertEqual(complete, [])


class DumbbellLoadTests(unittest.TestCase):
    def load(self, slugs, workout_id="x"):
        # Silence the "empty" warning print during expected-empty cases.
        with patch("builtins.print"):
            return common.dumbbell_load(slugs, workout_id=workout_id)

    def test_plain_tiers(self):
        self.assertEqual(self.load(["2-heavy"]), ["heavy"])
        self.assertEqual(self.load(["1-medium"]), ["medium"])
        self.assertEqual(self.load(["2-light"]), ["light"])
        self.assertEqual(self.load(["bodyweight"]), ["bodyweight"])

    def test_quantity_prefix_is_ignored(self):
        self.assertEqual(self.load(["1-heavy"]), self.load(["2-heavy"]))

    def test_compounds_fold_to_the_heavier_bucket(self):
        self.assertEqual(self.load(["2-medium-heavy"]), ["heavy"])
        self.assertEqual(self.load(["1-medium-heavy"]), ["heavy"])
        self.assertEqual(self.load(["2-light-medium"]), ["medium"])

    def test_named_slugs(self):
        self.assertEqual(self.load(["1-challenging"]), ["medium"])
        self.assertEqual(self.load(["2-you-can-curl-and-press"]), ["medium"])
        self.assertEqual(self.load(["2-you-can-lift-to-the-side"]), ["medium"])

    def test_multiple_slugs_union_in_canonical_order(self):
        self.assertEqual(self.load(["2-heavy", "2-light"]), ["light", "heavy"])

    def test_option_b_guard_drops_bodyweight_when_weights_present(self):
        self.assertEqual(self.load(["2-heavy", "bodyweight"]), ["heavy"])

    def test_unknown_slug_resolves_empty_and_warns(self):
        with patch("builtins.print") as printed:
            self.assertEqual(common.dumbbell_load(["mystery"], workout_id="w1"), [])
        printed.assert_called_once()
        self.assertIn("w1", printed.call_args[0][0])

    def test_bare_optional_without_override_warns_empty(self):
        self.assertEqual(self.load(["optional"], workout_id="unmapped"), [])

    def test_future_super_heavy_parses_via_substring(self):
        self.assertEqual(self.load(["2-super-heavy"]), ["heavy"])

    def test_optional_id_overrides(self):
        self.assertEqual(self.load(["optional"], "1577854883"), ["heavy"])
        self.assertEqual(self.load(["optional"], "1536717998"), ["heavy"])
        self.assertEqual(self.load(["optional"], "1554611034"), ["medium", "heavy"])
        self.assertEqual(self.load(["optional"], "1569935664"), ["light", "medium"])
        self.assertEqual(self.load(["optional"], "1591386110"), ["heavy"])


if __name__ == "__main__":
    unittest.main()
