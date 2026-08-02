"""The rename rules that were applied to 1,137 products.

Renaming touches what customers search for, so the rules have to be narrow:
spacing and unit spelling only, never a word. The multipack cases matter most
— "3X75G" means three packs of 75g, and splitting that changes the meaning of
the product rather than its punctuation.
"""
import re
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

from normalize_product_names import normalize  # noqa: E402


class TestSizeIsSeparatedFromTheWord:
    @pytest.mark.parametrize("before,after", [
        ("Aachi Curry Leaf Paste200g", "Aachi Curry Leaf Paste 200g"),
        ("Everyday Milk Bread450G", "Everyday Milk Bread 450g"),
        ("Farmley Chilli Cashews36g", "Farmley Chilli Cashews 36g"),
        ("3 Roses Top Star100 G", "3 Roses Top Star 100g"),
    ])
    def test_splits(self, before, after):
        assert normalize(before) == after


class TestUnitSpelling:
    @pytest.mark.parametrize("before,after", [
        ("Lion Jam 500 G", "Lion Jam 500g"),
        ("Surf Xl Easy 1Kg", "Surf Xl Easy 1kg"),
        ("Dds Raw Rice 1 Kg", "Dds Raw Rice 1kg"),
        ("Coke 2 Lt", "Coke 2L"),
        ("Water 1 L", "Water 1L"),
        ("Slice 20rs", "Slice 20Rs"),
    ])
    def test_canonical_form(self, before, after):
        assert normalize(before) == after

    def test_already_correct_names_are_untouched(self):
        for name in ("Setwet Deo Cool Avatar 150ml", "Act Ii Pop Tan Tadka",
                     "All Out Liq 60 Nights", "Brit Milk Bikis-15"):
            assert normalize(name) == name, f"{name!r} was changed when it did not need to be"


class TestMultipacksAreLeftAlone:
    """"3X75G" is three packs of 75g. Inserting a space turns a multipack into
    something else, and no customer benefit is worth that."""

    @pytest.mark.parametrize("name", [
        "Medimix 3X75G",
        "Godrej No.1 Kes Milk Cr4x50g",
    ])
    def test_untouched(self, name):
        assert normalize(name) == name


class TestNoWordIsEverChanged:
    """The safety property the whole rename rests on.

    Sizes are excluded from the comparison, because respelling a unit is the
    point — "2 Lt" becoming "2L" loses a letter by design. Everything that is
    not a pack size must survive untouched, or a customer's saved search stops
    matching the product they bought last week.
    """

    @staticmethod
    def _words_outside_the_size(s: str) -> str:
        without_sizes = re.sub(r"\d+(?:\.\d+)?\s*[a-zA-Z]{0,5}", " ", s.lower())
        return "".join(c for c in without_sizes if c.isalpha())

    @pytest.mark.parametrize("name", [
        "Aachi Curry Leaf Paste200g", "Lion Jam 500 G", "Coke 2 Lt",
        "3 Roses Natural100 G (S)", "Hershey`s Cho Syrup623g",
        "Ponds Sun Scr Spf55pa++100g", "7Up Nimbooz10rs",
    ])
    def test_letters_outside_the_size_survive(self, name):
        assert self._words_outside_the_size(normalize(name)) == \
               self._words_outside_the_size(name), (
            f"normalising {name!r} changed a word, not just the pack size"
        )

    @pytest.mark.parametrize("name", [
        "Aachi Curry Leaf Paste200g", "Lion Jam 500 G", "Medimix 3X75G",
    ])
    def test_digits_survive_unchanged(self, name):
        digits = lambda s: "".join(c for c in s if c.isdigit())
        assert digits(normalize(name)) == digits(name), (
            f"normalising {name!r} changed a number — the pack size moved"
        )


class TestIsStable:
    def test_running_it_twice_changes_nothing_further(self):
        for name in ("Aachi Curry Leaf Paste200g", "Lion Jam 500 G", "Coke 2 Lt"):
            once = normalize(name)
            assert normalize(once) == once, "the rules are not idempotent"

    @pytest.mark.parametrize("name", ["", "   ", "A"])
    def test_degenerate_input(self, name):
        normalize(name)
