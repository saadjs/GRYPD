#!/usr/bin/env python3
import copy
import os
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.dirname(__file__))

import assemble

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


if __name__ == "__main__":
    unittest.main()
