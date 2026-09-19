import unittest

from pokoin_public_card import rewrite_public_card


class RewritePublicCardTests(unittest.TestCase):
    def test_rewrites_leftover_prefix_and_drops_ct_id(self):
        card = rewrite_public_card({
            "card_id": 668126,
            "ct_id": 334063,
            "name": "Levincia",
            "set_name": "Destined Rivals",
            "imageUrl": "/card-images/334063_levincia.jpg",
            "tileImageUrl": "/card-images/334063_levincia_homepage.webp",
        })
        self.assertEqual(card["id"], "668126")
        self.assertNotIn("ct_id", card)
        self.assertEqual(card["imageUrl"], "/card-images/668126_levincia.jpg")
        self.assertEqual(card["tileImageUrl"], "/card-images/668126_levincia_homepage.webp")
        self.assertEqual(card["set"], "Destined Rivals")

    def test_rewrites_stray_prefix_to_public_id(self):
        card = rewrite_public_card({
            "id": "713760",
            "ct_id": 356880,
            "image_url": "/card-images/89220_wondrous-patch.jpg",
        })
        self.assertEqual(card["image_url"], "/card-images/713760_wondrous-patch.jpg")
