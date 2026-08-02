"""Search behaviour that customers depend on.

The catalogue is written in a shop's shorthand — "Brit Milk Bikis", "Col Zig
Zag" — and customers type the brand in full. Roughly 200 products returned
nothing before the synonym map, and "3roses" found nothing because of a
space. Both are asserted here.
"""
import pytest

from search_utils import BRAND_SYNONYMS, build_query, normalize, tokenize


class TestNormalisation:
    @pytest.mark.parametrize("written,typed", [
        ("3 Roses", "3roses"),
        ("Milk Bikis", "milkbikis"),
        ("Close Up", "closeup"),
        ("Hide & Seek", "hideseek"),
        ("Dds Raw Rice 1kg", "ddsrawrice1kg"),
    ])
    def test_spacing_and_case_do_not_matter(self, written, typed):
        assert normalize(written) == normalize(typed), (
            f"a customer typing {typed!r} would not find {written!r}"
        )

    def test_punctuation_is_dropped(self):
        assert normalize("Hershey's Cho-Syrup") == normalize("hersheys cho syrup")

    def test_empty_input_is_handled(self):
        assert normalize("") == ""
        assert normalize(None) == ""


class TestBrandSynonyms:
    """The catalogue abbreviates; customers do not."""

    def test_every_alias_maps_to_a_longer_name(self):
        for full, aliases in BRAND_SYNONYMS.items():
            for alias in aliases:
                assert len(alias) < len(full), f"{alias} is not shorter than {full}"
                assert full.startswith(alias), (
                    f"{alias} is not a prefix of {full} — the map is for abbreviations"
                )

    @pytest.mark.parametrize("typed", ["britannia", "colgate", "himalaya", "gillette"])
    def test_full_brand_names_are_expanded(self, typed):
        query = str(build_query(typed))
        assert BRAND_SYNONYMS[typed][0] in query, (
            f"searching {typed!r} does not look for the catalogue's abbreviation"
        )


class TestTokenising:
    def test_splits_on_spaces(self):
        assert tokenize("milk bikis") == ["milk", "bikis"]

    def test_ignores_extra_whitespace(self):
        assert tokenize("  milk   bikis  ") == ["milk", "bikis"]

    def test_a_query_is_built_for_every_token(self):
        query = str(build_query("brit milk"))
        assert "brit" in query and "milk" in query


class TestQueryShape:
    def test_blank_search_does_not_match_everything(self):
        """An empty query returning the whole catalogue would look like a
        working search while telling the customer nothing."""
        query = build_query("")
        assert query != {}, "an empty search builds a match-everything query"
