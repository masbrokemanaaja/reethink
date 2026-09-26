#!/usr/bin/env python3
"""Roll a design direction, so the first design is not the average one.

Asked for a landing page, a model reaches for the statistical middle of every
landing page it has seen: centered hero, gradient, three icon cards. That is
not a taste problem, it is what sampling the most likely answer produces. The
fix is to make the expressive choices somewhere other than the model's first
instinct, while leaving the functional ones to the brief and to the craft.

So this rolls only the expressive axes, ten of them, each option a
recognised technique rather than a random value. Pairs that fight each other
are excluded by rule, with the reason written beside the rule. What the craft
decides outright, the spacing scale, the type scale and the motion, is derived
from what was rolled rather than rolled itself.

    python3 direction.py roll                   three directions to choose from
    python3 direction.py roll --surface mobile  the same, for an app screen
    python3 direction.py roll --avoid 48213     unlike a direction already used
    python3 direction.py show 48213             that direction again, exactly
    python3 direction.py count                  how many valid directions exist
    python3 direction.py axes                   every option and every rule

Python standard library only.

reethink, by ree_es97 (https://reetech.web.id)
MIT licensed. https://github.com/masbrokemanaaja/reethink
"""

import argparse
import itertools
import json
import random
import sys

# --- the expressive axes -----------------------------------------------------
# Each option is one sentence that can be acted on. Function (information
# architecture, navigation, platform conventions, accessibility) is never an
# axis: it comes from the brief.
AXES = {
    "composition": {
        "swiss-grid": "Strict 12-column grid, flush-left and ragged-right, every heading hanging on the body's left edge. Mobile: a 4-column grid, the same left edge on every screen.",
        "editorial": "A reading column of 60 to 70 characters with a wide margin for notes, captions and small figures. Mobile: margin notes become inline asides under the paragraph they annotate.",
        "asymmetric-split": "Two unequal regions, about 5:7 or 1:2; the larger holds the single most important thing. Mobile: stacked, the dominant region first and taller.",
        "poster": "Each section is one statement at poster scale, one element per viewport height. Mobile: one element per screen.",
        "index": "The content is a list or table first: rows, columns, counts and filters are the layout. Mobile: rows become tappable list items with the key value right-aligned.",
        "bands": "Full-bleed horizontal bands that alternate background and density, each with its own inner grid. Mobile: the bands keep their color changes, inner grids drop to one column.",
        "layered-collage": "Image, type and shape overlap on a grid broken on purpose in two or three places only. Mobile: one overlap per screen, never over body text.",
        "narrative-column": "One column read top to bottom as a story, broken by full-width images or figures. Mobile: native, nothing to adapt.",
    },
    "type": {
        "superfamily": "One superfamily; contrast comes from weight and width only.",
        "serif-display": "A serif for display, a grotesque sans for text.",
        "editorial-inverse": "A grotesque for display, a serif for running text.",
        "mono-accent": "Monospace for labels, numbers and metadata, a humanist sans for text.",
        "condensed-display": "A condensed sans for display, a neutral sans for text.",
        "slab-display": "A slab serif for display, a neutral sans for text.",
        "single-face": "One family at two weights at most; hierarchy by size alone.",
    },
    "color": {
        "accent-sparse": "Neutral surfaces and one saturated accent covering under 5% of any screen.",
        "duotone": "Two strong colors do all the work; neutrals only for paper and ink.",
        "tinted-neutrals": "Every gray tinted toward the base hue; saturated color appears only for state: focus, selection, error.",
        "color-field": "One saturated color is the background of the key surfaces, with content set on it in paper and ink.",
        "paper-and-ink": "Off-white paper and near-black ink, with color used like a printer's second ink.",
        "dark-luminous": "Dark surfaces by default and one luminous accent; surfaces get lighter as they rise.",
    },
    "shape": {
        "square": "0 radius everywhere, 1px hairline borders.",
        "small-radius": "One radius only, 2 to 4px, on every component.",
        "pill-and-square": "Pills for controls (buttons, chips, inputs), square containers.",
        "soft-containers": "A large radius (16 to 24px) on containers only; controls at 6 to 8px.",
        "notched": "Chamfered or notched corners on one component family, square everywhere else.",
    },
    "depth": {
        "rules": "Flat; separation by 1px rules and alignment only.",
        "blocks": "Flat; separation by fields of tone or color.",
        "hard-offset": "A hard offset shadow, such as 4px 4px 0 in ink, on interactive elements only.",
        "ambient": "One soft shadow level, used only for layers that float: menus, dialogs, toasts.",
        "stacked-paper": "Surfaces as stacked sheets with a visible 1 to 2px edge.",
    },
    "hierarchy": {
        "scale": "Extreme size contrast: display type at 5 to 8 times the body size.",
        "weight": "Similar sizes, contrast from weight, such as 400 against 800.",
        "color": "The accent marks what matters most on each screen, and nothing else uses it.",
        "isolation": "The key element is isolated by empty space, at least twice the usual gap around it.",
        "numbering": "Numbered sections and indexed labels (01, 02, A, B) lead the eye.",
        "framing": "Rules, boxes and brackets frame the important parts.",
    },
    "density": {
        "airy": "One idea per viewport; outer margins at least 12% of the width on desktop.",
        "balanced": "Standard density; the gap between groups is twice the gap inside a group.",
        "dense": "Information-dense like a tool; whitespace only groups things, it never decorates.",
        "contrast": "Dense blocks set against large empty areas on the same screen.",
    },
    "imagery": {
        "type-only": "No photography or illustration; type, diagrams and data carry the page.",
        "duotone-photo": "Photography mapped to two palette colors.",
        "documentary": "Full-bleed, unretouched documentary photography of real people, places or product.",
        "line-illustration": "Line illustration at one stroke weight, in the ink color.",
        "product-crops": "Tight, straight-on crops of the real product or interface; no device mockups.",
        "geometric": "Abstract shapes built from the logo's own construction.",
        "texture": "Grain, halftone or paper scans as the image layer.",
    },
    "icons": {
        "none": "No icons; text labels only.",
        "outline": "Outline icons from one set, 24px grid, 1.5px stroke.",
        "solid": "Solid geometric glyphs from one set, 20 or 24px grid.",
        "duotone": "Two-tone icons in the palette's ink and accent.",
        "custom": "A small custom set of 6 to 12 icons drawn from the logo's geometry.",
        "glyphs": "Typographic symbols from the text face itself: arrows, plus, multiply.",
    },
    "signature": {
        "big-numerals": "Oversized numerals (prices, steps, figures) used as graphic elements.",
        "ticker": "One ticker line of short phrases, static or slowly moving.",
        "annotations": "Hand-drawn marks on top of the layout: circles, underlines, arrows.",
        "stamp": "A stamp, seal or badge motif repeated as a brand mark.",
        "grid-visible": "Visible grid lines, crop marks or registration marks.",
        "highlighter": "A flat highlighter swatch behind key words.",
        "vertical-type": "Vertical text running along one edge.",
        "cutout-type": "Type used as a mask over imagery.",
    },
}

# Combinations that fight each other. Each rule is a set of (axis, option)
# pairs that may not all hold at once, and the reason is shown by `axes`.
RULES = (
    ((("composition", "index"), ("density", "airy")),
     "an index is dense by nature"),
    ((("composition", "poster"), ("density", "dense")),
     "a poster holds one thing"),
    ((("composition", "layered-collage"), ("imagery", "type-only")),
     "a collage needs layers to overlap, and type alone turns it into noise"),
    ((("composition", "layered-collage"), ("signature", "grid-visible")),
     "a visible grid contradicts a grid broken on purpose"),
    ((("color", "color-field"), ("imagery", "documentary")),
     "full-bleed photography fights a saturated field"),
    ((("color", "tinted-neutrals"), ("hierarchy", "color")),
     "tinted neutrals keep color for state, so it cannot also mark hierarchy"),
    ((("color", "dark-luminous"), ("depth", "hard-offset")),
     "an ink-colored offset shadow disappears on a dark surface"),
    ((("type", "single-face"), ("hierarchy", "weight")),
     "one face at two weights at most leaves size as the only lever"),
    ((("imagery", "type-only"), ("signature", "cutout-type")),
     "cutout type needs an image to cut out"),
)

# Platform conventions that override an option. iOS tab bars and Android
# navigation bars both pair a glyph with each destination.
SURFACE_RULES = {
    "web": (),
    "mobile": (
        ((("icons", "none"),),
         "iOS tab bars and Android navigation bars pair a glyph with each destination"),
    ),
}

# --- type pools ----------------------------------------------------------------
# Every family here was checked against the Google Fonts CSS API on
# 2026-09-24 and is served from the library itself. The overused defaults
# below are never picked; a brand that already uses one keeps it.
OVERUSED = (
    "Inter", "Roboto", "Poppins", "Montserrat", "Open Sans", "Lato",
    "Space Grotesk", "Playfair Display", "Oswald", "Bebas Neue", "Raleway",
)

FONTS = {
    "superfamily": (
        ("Archivo", "Sofia Sans", "Barlow", "Encode Sans", "IBM Plex Sans"),
        None,
    ),
    "serif-display": (
        ("Fraunces", "Instrument Serif", "Young Serif", "Gloock", "DM Serif Display",
         "Libre Caslon Display", "Bodoni Moda", "Newsreader"),
        ("Hanken Grotesk", "Schibsted Grotesk", "Familjen Grotesk", "Instrument Sans",
         "Public Sans", "Work Sans"),
    ),
    "editorial-inverse": (
        ("Bricolage Grotesque", "Familjen Grotesk", "Schibsted Grotesk", "Archivo",
         "Unbounded", "Syne"),
        ("Source Serif 4", "Literata", "Newsreader", "Spectral", "Crimson Pro",
         "EB Garamond", "Lora"),
    ),
    "mono-accent": (
        ("JetBrains Mono", "IBM Plex Mono", "DM Mono", "Martian Mono", "Fragment Mono",
         "Space Mono"),
        ("Source Sans 3", "Fira Sans", "Alegreya Sans", "Cabin", "Red Hat Text"),
    ),
    "condensed-display": (
        ("Big Shoulders Display", "Antonio", "Barlow Condensed",
         "Sofia Sans Extra Condensed", "Saira Extra Condensed", "Fjalla One"),
        ("Hanken Grotesk", "Public Sans", "Karla", "Albert Sans", "Epilogue"),
    ),
    "slab-display": (
        ("Zilla Slab", "Bitter", "Aleo", "Arvo", "Josefin Slab", "Podkova"),
        ("Karla", "Public Sans", "Work Sans", "IBM Plex Sans"),
    ),
    "single-face": (
        ("Instrument Sans", "Onest", "Geist", "Schibsted Grotesk", "Newsreader",
         "Literata"),
        None,
    ),
}

MIN_DISTANCE = 6
SEED_RANGE = (1, 1_000_000)


# --- rules and counting --------------------------------------------------------
def constraints(surface):
    return [set(pairs) for pairs, _ in RULES + SURFACE_RULES[surface]]


def broken_rule(direction, surface):
    """The reason for the first rule `direction` breaks, or None."""
    for pairs, reason in RULES + SURFACE_RULES[surface]:
        if all(direction[axis] == option for axis, option in pairs):
            return reason
    return None


def count_valid(surface, axes=None):
    """Exact number of directions that break no rule, by inclusion-exclusion.

    Enumerating all of them would take tens of millions of steps; counting the
    combinations that break a chosen set of rules is a single product, so the
    exact figure comes from a few hundred subsets instead.
    """
    axes = AXES if axes is None else axes
    rules = constraints(surface)
    total = 0
    for k in range(len(rules) + 1):
        for subset in itertools.combinations(rules, k):
            fixed = {}
            consistent = True
            for pairs in subset:
                for axis, option in pairs:
                    if fixed.setdefault(axis, option) != option or option not in axes[axis]:
                        consistent = False
            if not consistent:
                continue
            n = 1
            for axis, options in axes.items():
                n *= 1 if axis in fixed else len(options)
            total += (-1) ** k * n
    return total


def font_pairs(strategy):
    display, text = FONTS[strategy]
    return len(display) * (len(text) if text else 1)


def count_with_fonts(surface):
    """Valid directions times the font pairs each type strategy offers."""
    return sum(
        count_valid(surface, dict(AXES, type={strategy: AXES["type"][strategy]}))
        * font_pairs(strategy)
        for strategy in AXES["type"])


# --- one direction ---------------------------------------------------------------
def distance(a, b):
    return sum(a["axes"][axis] != b["axes"][axis] for axis in AXES)


def pick_fonts(rng, strategy):
    display, text = FONTS[strategy]
    first = rng.choice(display)
    if text is None:
        return {"display": first, "text": first}
    second = rng.choice([f for f in text if f != first])
    return {"display": first, "text": second}


def derive(axes, surface):
    """What the craft decides from what was rolled."""
    density, hierarchy = axes["density"], axes["hierarchy"]
    spacing = {
        "airy": "8px base, doubling: 8 16 32 64 128; sections at least 128px apart on desktop, 64px on mobile",
        "balanced": "8px base: 4 8 12 16 24 32 48 64 96; the gap between groups at least twice the gap inside one",
        "dense": "4px base: 4 8 12 16 20 24 32; rows 32 to 40px on desktop, touch rows still 44pt on iOS and 48dp on Android",
        "contrast": "4px steps inside blocks (4 8 12 16), 96px or more between blocks",
    }[density]
    if hierarchy == "scale":
        desktop = {"airy": 1.618, "dense": 1.333}.get(density, 1.5)
    elif hierarchy == "weight" or density == "dense":
        desktop = 1.2
    elif density in ("airy", "contrast"):
        desktop = 1.333
    else:
        desktop = 1.25
    mobile = min(desktop, 1.25 if hierarchy == "scale" else 1.2)
    body = ("17pt on iOS, 16sp on Android, following each platform's text styles"
            if surface == "mobile" else "16px, 14px only for dense tables and secondary UI")
    if axes["depth"] in ("rules", "hard-offset") or axes["shape"] == "square":
        motion = "mechanical: 100 to 150ms, linear or stepped, no overshoot"
    elif axes["depth"] == "ambient" or axes["shape"] in ("soft-containers", "pill-and-square"):
        motion = "functional: 150 to 250ms, ease-out on enter, a faster ease-in on exit"
    else:
        motion = "quiet: 150 to 200ms, opacity and position only, nothing that bounces"
    return {
        "spacing": spacing,
        "type scale": f"{desktop} on desktop, {mobile} on mobile; body {body}",
        "motion": motion + "; under prefers-reduced-motion, an opacity change or nothing",
    }


def build(seed, surface):
    """The direction a seed stands for: the same seed always gives the same one."""
    rng = random.Random(f"{surface}:{seed}")
    while True:
        axes = {axis: rng.choice(sorted(options)) for axis, options in AXES.items()}
        if broken_rule(axes, surface) is None:
            break
    return {
        "seed": seed,
        "surface": surface,
        "axes": axes,
        "fonts": pick_fonts(rng, axes["type"]),
        "derived": derive(axes, surface),
    }


def roll(count, surface, master=None, avoid=()):
    """`count` directions, each at least MIN_DISTANCE axes from the others."""
    pick = random.Random(master) if master is not None else random.SystemRandom()
    taken = [build(seed, surface) for seed in avoid]
    found = []
    for _ in range(10_000):
        if len(found) == count:
            break
        d = build(pick.randrange(*SEED_RANGE), surface)
        if all(distance(d, other) >= MIN_DISTANCE for other in taken + found):
            found.append(d)
    return found


# --- output -----------------------------------------------------------------------
def render(d, index=None, total=None):
    head = f"direction {index} of {total}" if index else "direction"
    lines = [f"{head}   seed {d['seed']}   surface {d['surface']}"]
    for axis, option in d["axes"].items():
        lines.append(f"  {axis:<12} {option:<18} {AXES[axis][option]}")
        if axis == "type":
            f = d["fonts"]
            pair = f["display"] if f["display"] == f["text"] else f"{f['display']} for display, {f['text']} for text"
            lines.append(f"  {'':<12} {'':<18} {pair} (Google Fonts)")
    lines.append("  derived")
    for key, value in d["derived"].items():
        lines.append(f"    {key:<11} {value}")
    return "\n".join(lines)


def cmd_roll(args):
    found = roll(args.count, args.surface, args.seed, args.avoid)
    if len(found) < args.count:
        print(f"found {len(found)} of {args.count} directions far enough apart; "
              "avoid fewer seeds", file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps(found, indent=2))
    else:
        print("\n\n".join(render(d, i + 1, len(found)) for i, d in enumerate(found)))
    return 0


def cmd_show(args):
    d = build(args.seed, args.surface)
    print(json.dumps(d, indent=2) if args.json else render(d))
    return 0


def cmd_count(args):
    rows = {s: {"directions": count_valid(s), "with font pairs": count_with_fonts(s)}
            for s in SURFACE_RULES}
    if args.json:
        print(json.dumps(rows, indent=2))
    else:
        for s, r in rows.items():
            print(f"{s:<7} {r['directions']:>14,} directions   "
                  f"{r['with font pairs']:>16,} with font pairs")
    return 0


def cmd_axes(args):
    if args.json:
        print(json.dumps({"axes": AXES,
                          "rules": [{"never together": [list(p) for p in pairs], "because": why}
                                    for pairs, why in RULES],
                          "surface rules": {s: [{"never": [list(p) for p in pairs], "because": why}
                                                for pairs, why in r]
                                            for s, r in SURFACE_RULES.items()},
                          "overused fonts": OVERUSED}, indent=2))
        return 0
    for axis, options in AXES.items():
        print(axis)
        for option, meaning in options.items():
            print(f"  {option:<18} {meaning}")
    print("never together")
    for pairs, why in RULES:
        print("  " + " + ".join(f"{a}={o}" for a, o in pairs) + f": {why}")
    for surface, rules in SURFACE_RULES.items():
        for pairs, why in rules:
            print(f"  on {surface}, " + " + ".join(f"{a}={o}" for a, o in pairs) + f": {why}")
    print("never picked: " + ", ".join(OVERUSED))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description="Roll a design direction that is not the default one.")
    sub = ap.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("roll", help="several directions, far apart from each other")
    s.add_argument("--count", type=int, default=3)
    s.add_argument("--surface", choices=sorted(SURFACE_RULES), default="web")
    s.add_argument("--seed", type=int, help="repeatable run")
    s.add_argument("--avoid", type=int, action="append", default=[],
                   help="seed of a direction already used; repeatable")
    s.add_argument("--json", action="store_true")
    s.set_defaults(fn=cmd_roll)

    s = sub.add_parser("show", help="one direction again, by its seed")
    s.add_argument("seed", type=int)
    s.add_argument("--surface", choices=sorted(SURFACE_RULES), default="web")
    s.add_argument("--json", action="store_true")
    s.set_defaults(fn=cmd_show)

    s = sub.add_parser("count", help="how many valid directions exist")
    s.add_argument("--json", action="store_true")
    s.set_defaults(fn=cmd_count)

    s = sub.add_parser("axes", help="every option and every rule")
    s.add_argument("--json", action="store_true")
    s.set_defaults(fn=cmd_axes)

    args = ap.parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
