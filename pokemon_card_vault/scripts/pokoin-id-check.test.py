#!/usr/bin/env python3
import unittest

from pokoin_id_check import canonical_image_stem, classify_row, leftover_image_id, parse_token, pick_row, slugify_name


class ParseTokenTests(unittest.TestCase):
    def test_public_id(self):
        self.assertEqual(parse_token("668126")["asked"], "668126")
        self.assertEqual(parse_token("668126")["kind_hint"], "id")

    def test_object_key(self):
        parsed = parse_token("/card-images/334063_levincia_homepage.webp")
        self.assertEqual(parsed["asked"], "334063")
        self.assertEqual(parsed["slug"], "levincia")

    def test_cdn_url(self):
        parsed = parse_token("https://cdn.pokoin.com/110481_espurr-58-122-breakpoint.jpg")
        self.assertEqual(parsed["asked"], "110481")
        self.assertTrue(parsed["slug"].startswith("espurr"))


class ClassifyTests(unittest.TestCase):
    ROW = {
        "card_id": 668126,
        "ct_id": 334063,
        "name": "Levincia",
        "set_name": "Destined Rivals",
        "card_number": "244/182",
    }

    def test_public_id_ok(self):
        result = classify_row(668126, self.ROW, "levincia")
        self.assertEqual(result["kind"], "public")
        self.assertTrue(result["valid_public"])
        self.assertTrue(result["matches_card"])
        self.assertEqual(result["use"], 668126)

    def test_leftover_blueprint_is_not_public(self):
        result = classify_row(334063, self.ROW, "levincia")
        self.assertEqual(result["kind"], "leftover_blueprint")
        self.assertFalse(result["valid_public"])
        self.assertTrue(result["matches_card"])
        self.assertEqual(result["use"], 668126)

    def test_unknown(self):
        result = classify_row(1, None)
        self.assertEqual(result["kind"], "unknown")
        self.assertFalse(result["valid_public"])

    def test_slugify(self):
        self.assertEqual(slugify_name("Mega Lucario ex"), "mega-lucario-ex")


class ImageKeyTests(unittest.TestCase):
    NET = {
        "card_id": 245292,
        "ct_id": 122646,
        "name": "Net Ball",
        "set_name": "Lost Thunder",
        "card_number": "187/214",
    }

    def test_leftover_image_id_is_public_over_two(self):
        self.assertEqual(leftover_image_id(245292), 122646)
        self.assertEqual(leftover_image_id(245292, 122646), 122646)

    def test_canonical_stem_uses_leftover_not_public_id(self):
        self.assertEqual(
            canonical_image_stem("/card-images/245292_net-ball.jpg", 245292, 122646),
            "/card-images/122646_net-ball.jpg",
        )

    def test_public_id_image_key_is_not_ok(self):
        result = classify_row(245292, self.NET, "net-ball", kind_hint="object_key")
        self.assertEqual(result["kind"], "public")
        self.assertFalse(result["image_key_ok"])
        self.assertFalse(result["matches_card"])
        self.assertIn("leftover ct_id is 122646", result["reason"])

    def test_leftover_image_key_is_ok(self):
        result = classify_row(122646, self.NET, "net-ball", kind_hint="object_key")
        self.assertEqual(result["kind"], "leftover_blueprint")
        self.assertTrue(result["image_key_ok"])
        self.assertTrue(result["matches_card"])

    def test_pick_row_prefers_slug_over_leftover_ct_id_collision(self):
        cyndaquil = {
            "card_id": 490584,
            "ct_id": 245292,
            "name": "Cyndaquil",
        }
        net = {
            "card_id": 245292,
            "ct_id": 122646,
            "name": "Net Ball",
        }
        rows = [cyndaquil, net]
        self.assertEqual(
            pick_row(rows, 245292, "net-ball", "object_key")["name"],
            "Net Ball",
        )
        self.assertEqual(
            pick_row(rows, 245292, "cyndaquil", "object_key")["name"],
            "Cyndaquil",
        )
        self.assertEqual(pick_row(rows, 245292, "", "id")["name"], "Net Ball")


if __name__ == "__main__":
    unittest.main()
