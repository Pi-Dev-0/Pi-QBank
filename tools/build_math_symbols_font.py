#!/usr/bin/env python3
"""Rebuild assets/fonts/MathSymbols.ttf from DejaVu Sans.

The PDF generator needs a font for glyphs that SutonnyMJ (Bijoy-ANSI) and the
PDF base-14 fonts do not have: geometry, Greek, arrows, sub/superscripts.

It was originally hand-picked one codepoint at a time, which is how U+2220
(ANGLE) and U+22A5 (UP TACK / perpendicular) came to be missing — the app
rendered a log line per occurrence and silently dropped the glyph. So the
subset is now whole Unicode *blocks*: anything DejaVu Sans covers in a block we
care about gets in, and nothing has to be remembered.

Usage:
    python3 tools/build_math_symbols_font.py \
        --source /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf \
        --output assets/fonts/MathSymbols.ttf

DejaVu fonts are under the Bitstream Vera / DejaVu permissive licence, which is
what allowed the original subset to be redistributed here.
"""

import argparse
import sys

from fontTools import subset
from fontTools.ttLib import TTFont

# Blocks a high-school question paper can plausibly need. Latin and Greek are
# included so a stray non-Bangla letter never falls back to nothing.
BLOCKS = [
    (0x0020, 0x007E, "Basic Latin"),
    (0x00A0, 0x00FF, "Latin-1 Supplement"),
    (0x0100, 0x017F, "Latin Extended-A"),
    (0x0192, 0x0192, "Latin Extended-B (fractions)"),
    (0x02B0, 0x02FF, "Spacing Modifier Letters"),
    (0x0370, 0x03FF, "Greek and Coptic"),
    (0x1D00, 0x1D7F, "Phonetic Extensions"),
    (0x1D80, 0x1DBF, "Phonetic Extensions Supplement"),
    (0x2000, 0x206F, "General Punctuation"),
    (0x2070, 0x209F, "Superscripts and Subscripts"),
    (0x20A0, 0x20CF, "Currency Symbols"),
    (0x20D0, 0x20FF, "Combining Diacriticals for Symbols"),
    (0x2100, 0x214F, "Letterlike Symbols"),
    (0x2150, 0x218F, "Number Forms"),
    (0x2190, 0x21FF, "Arrows"),
    (0x2200, 0x22FF, "Mathematical Operators"),
    (0x2300, 0x23FF, "Miscellaneous Technical"),
    (0x25A0, 0x25FF, "Geometric Shapes"),
    (0x2600, 0x26FF, "Miscellaneous Symbols"),
    (0x2700, 0x27BF, "Dingbats"),
    (0x27C0, 0x27EF, "Miscellaneous Math Symbols-A"),
    (0x27F0, 0x27FF, "Supplemental Arrows-A"),
    (0x2900, 0x297F, "Supplemental Arrows-B"),
    (0x2A00, 0x2AFF, "Supplemental Mathematical Operators"),
]

# Characters the question bank is known to use. Checked explicitly so a future
# rebuild that silently loses one fails here instead of in the app's log.
MUST_HAVE = "∩∪∈∉∅≠≤≥×÷√∑−±∝∞∠⊥⊢∠∡≡≈…→⇒⌐∆∏∂°²³½αβγπμθω"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--source",
        default="/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    )
    ap.add_argument("--output", default="assets/fonts/MathSymbols.ttf")
    args = ap.parse_args()

    source = TTFont(args.source)
    available = set()
    for table in source["cmap"].tables:
        available |= set(table.cmap.keys())

    wanted = set()
    for start, end, _name in BLOCKS:
        wanted |= {cp for cp in range(start, end + 1) if cp in available}

    # U+0020 alone is not enough for a usable space; keep the codepoints that
    # DejaVu reports as a composite of existing glyphs.
    options = subset.Options()
    options.layout_features = ["*"]
    options.name_IDs = ["*"]
    options.notdef_outline = True
    options.recalc_bounds = True
    options.drop_tables = []
    options.hinting = False
    options.desubroutinize = True

    subsetter = subset.Subsetter(options=options)
    subsetter.populate(unicodes=wanted)
    # `subset` rewrites the font in place and returns nothing.
    subsetter.subset(source)
    source.save(args.output)

    built = TTFont(args.output)
    built_cmap = set()
    for table in built["cmap"].tables:
        built_cmap |= set(table.cmap.keys())

    missing = [c for c in MUST_HAVE if ord(c) not in built_cmap]
    if missing:
        print("MISSING from the rebuilt font: %s" % " ".join(missing))
        print("These are absent from DejaVu itself; decide on a substitute.")
        return 1

    print(
        "%s: %d codepoints (source had %d in the selected blocks)"
        % (args.output, len(built_cmap), len(wanted))
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())