"""Attribution parsing for the Photo Credits screen.

The photographs are CC-BY-SA and the licence requires the source to be shown
wherever the image is. The credit is stored as one string per product in two
different shapes, and if parsing it silently fails the screen renders an
empty list — an attribution that is missing without anything looking broken.
"""
import pytest

from main import _parse_credit


class TestOpenFoodFacts:
    CREDIT = "Open Food Facts (8901719100956), CC-BY-SA"

    def test_source_and_licence(self):
        parsed = _parse_credit(self.CREDIT)
        assert parsed["source"] == "Open Food Facts"
        assert parsed["licence"] == "CC-BY-SA"

    def test_links_to_the_product_record(self):
        assert _parse_credit(self.CREDIT)["url"].endswith("/product/8901719100956")

    def test_a_missing_barcode_still_credits_the_source(self):
        parsed = _parse_credit("Open Food Facts (), CC-BY-SA")
        assert parsed["source"] == "Open Food Facts"
        assert parsed["url"] == "https://world.openfoodfacts.org"


class TestOpenverse:
    """A different shape: the photographer is named and the bracketed part is
    the licence, not a barcode."""

    def test_creator_and_licence(self):
        parsed = _parse_credit("Openverse / Jane Doe (cc-by)")
        assert parsed["source"] == "Openverse"
        assert parsed["creator"] == "Jane Doe"
        assert parsed["licence"] == "cc-by"

    def test_a_name_with_initials(self):
        assert _parse_credit("Openverse / A. B. Smith (cc-by-sa)")["creator"] == "A. B. Smith"

    def test_an_unknown_photographer(self):
        assert _parse_credit("Openverse / unknown (cc0)")["licence"] == "cc0"


class TestDegradesGracefully:
    """Whatever arrives, the screen must render something rather than throw —
    a crash here means no credit is displayed at all."""

    @pytest.mark.parametrize("credit", ["", None, "Some Photographer", "?????", "()"])
    def test_never_raises(self, credit):
        parsed = _parse_credit(credit)
        assert set(parsed) == {"source", "creator", "licence", "home", "url"}

    def test_a_bare_name_is_still_a_source(self):
        assert _parse_credit("Some Photographer")["source"] == "Some Photographer"
