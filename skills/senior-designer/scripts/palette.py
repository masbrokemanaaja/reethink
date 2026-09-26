#!/usr/bin/env python3
"""Color palettes whose contrast is measured, not promised.

A palette suggestion is only worth making if it can carry text. Every palette
this prints has been checked against WCAG 2.2 contrast before it is shown, and
the ratios are printed beside it, so the reader can see which pairs may carry
body text and which may only carry large text, icons and borders.

    python3 palette.py suggest                     three palettes, light mode
    python3 palette.py suggest --mode dark         three for a dark interface
    python3 palette.py suggest --hue 30            around a hue the brand owns
    python3 palette.py suggest --brand "#C8553D"   keep one brand color as is
    python3 palette.py show 48213                  the palette with that seed again
    python3 palette.py audit "#1B1B1B" "#F4EFE6" "#C8553D"
                                                   which pairs of a user's colors can carry text
    python3 palette.py contrast "#767676" "#FFFFFF"

Colors are built in OKLCH, the perceptual space from Bjorn Ottosson's Oklab,
so a lightness step looks like the same step at every hue. The contrast ratio
is WCAG's own formula and is floored, never rounded up: 4.499 is shown as
4.49, because 4.499 fails 4.5.

Python standard library only.

reethink, by ree_es97 (https://reetech.web.id)
MIT licensed. https://github.com/masbrokemanaaja/reethink
"""

import argparse
import json
import math
import random
import re
import sys

# --- WCAG 2.2 thresholds -----------------------------------------------------
BODY = 4.5      # 1.4.3, normal text
UI = 3.0        # 1.4.3 large text, and 1.4.11 components and graphics
INK_TARGET = 7.0  # 1.4.6 (AAA) for the main text color, as headroom

# --- hue policy ----------------------------------------------------------------
# The indigo to violet band is where the default AI palette lives: the
# purple-to-blue gradient and the stock indigo button. A random suggestion
# never lands there; a brand that owns the hue asks for it with --hue or
# --brand, and then gets it.
SLOP_HUES = (268.0, 312.0)
MIN_HUE_GAP = 60.0

HUE_NAMES = (
    (12.0, "rose"), (45.0, "red"), (68.0, "clay"), (90.0, "amber"),
    (112.0, "yellow"), (132.0, "olive"), (165.0, "green"), (205.0, "teal"),
    (240.0, "azure"), (268.0, "blue"), (290.0, "indigo"), (312.0, "violet"),
    (340.0, "magenta"), (360.0, "rose"),
)

# Where the second accent sits relative to the base hue. Monochrome has none.
SCHEMES = {
    "monochrome": None,
    "analogous": 35.0,
    "complementary": 180.0,
    "split-complementary": 150.0,
    "triadic": 120.0,
}

# The paper's temperature: a fixed hue for warm and cool, the base hue for
# tinted, and no chroma at all for neutral.
TEMPERATURES = ("warm", "cool", "tinted", "neutral")
WARM_HUE = 75.0
COOL_HUE = 250.0


# --- sRGB and Oklab ------------------------------------------------------------
def parse_hex(text):
    """'#abc', 'abc', '#aabbcc' -> (r, g, b) in 0..1. Raises ValueError."""
    h = text.strip().lstrip("#")
    if re.fullmatch(r"[0-9a-fA-F]{3}", h):
        h = "".join(c * 2 for c in h)
    if not re.fullmatch(r"[0-9a-fA-F]{6}", h):
        raise ValueError(f"not a hex color: {text!r}")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def to_hex(rgb):
    return "#" + "".join(f"{round(min(1.0, max(0.0, c)) * 255):02X}" for c in rgb)


def to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def from_linear(c):
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def linear_to_oklab(r, g, b):
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l, m, s = (math.copysign(abs(v) ** (1 / 3), v) for v in (l, m, s))
    return (
        0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
        1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
        0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
    )


def oklab_to_linear(L, a, b):
    l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
    return (
        4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
    )


def hex_to_oklch(text):
    L, a, b = linear_to_oklab(*(to_linear(c) for c in parse_hex(text)))
    return L, math.hypot(a, b), math.degrees(math.atan2(b, a)) % 360


def _in_gamut(rgb, eps=1e-6):
    return all(-eps <= c <= 1 + eps for c in rgb)


def oklch_to_hex(L, C, h):
    """OKLCH -> hex, lowering chroma until the color exists in sRGB.

    Lightness and hue are what a palette is built on, so they are kept and
    chroma gives way, found by bisection. Clipping each channel instead would
    shift the hue, which is the one thing a palette cannot afford.
    """
    def linear(c):
        rad = math.radians(h)
        return oklab_to_linear(L, c * math.cos(rad), c * math.sin(rad))

    rgb = linear(C)
    if not _in_gamut(rgb):
        lo, hi = 0.0, C
        for _ in range(30):
            mid = (lo + hi) / 2
            if _in_gamut(linear(mid)):
                lo = mid
            else:
                hi = mid
        rgb = linear(lo)
    return to_hex(from_linear(min(1.0, max(0.0, c))) for c in rgb)


# --- WCAG contrast ---------------------------------------------------------------
def luminance(text):
    r, g, b = (to_linear(c) for c in parse_hex(text))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = sorted((luminance(a), luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def floor2(x):
    """Two decimals, never rounded up across a threshold."""
    return math.floor(x * 100 + 1e-9) / 100


def verdict(ratio):
    if ratio >= BODY:
        return "body text"
    if ratio >= UI:
        return "large text, icons and borders only"
    return "decoration only"


# --- building one palette ---------------------------------------------------------
def hue_name(h):
    for limit, name in HUE_NAMES:
        if h % 360 < limit:
            return name
    return HUE_NAMES[-1][1]


def hue_gap(a, b):
    d = abs(a - b) % 360
    return min(d, 360 - d)


def in_slop_zone(h):
    return SLOP_HUES[0] <= h % 360 <= SLOP_HUES[1]


def solve_lightness(C, h, against, target, start, direction):
    """Walk lightness from `start` in `direction` until contrast >= target.

    Returns the hex of the first color that clears the target, or None when
    the walk runs out of lightness first.
    """
    L = start
    while 0.02 <= L <= 0.99:
        hx = oklch_to_hex(L, C, h)
        if contrast(hx, against) >= target:
            return hx
        L += 0.005 * direction
    return None


def closest_to(C, h, against, target, dark_side):
    """The color nearest the paper that still reaches `target` against it."""
    direction = -1 if dark_side else 1
    L0 = hex_to_oklch(against)[0]
    return solve_lightness(C, h, against, target, L0, direction)


def build(seed, mode="light", hue=None, brand=None, scheme=None):
    """One palette from one seed, or None if this seed cannot meet the checks.

    Every generated role is solved for its contrast target rather than
    guessed, and a brand color, when given, is used exactly as supplied:
    its ratios are reported, never quietly corrected.
    """
    rng = random.Random(seed)
    light = mode == "light"
    brand_hex = to_hex(parse_hex(brand)) if brand else None
    if brand_hex:
        base = hex_to_oklch(brand_hex)[2]
    elif hue is not None:
        base = hue % 360
    else:
        base = rng.uniform(0, 360)
        while in_slop_zone(base):
            base = rng.uniform(0, 360)
    scheme = scheme or rng.choice(sorted(SCHEMES))
    temperature = rng.choice(TEMPERATURES)

    paper_h = {"warm": WARM_HUE, "cool": COOL_HUE}.get(temperature, base)
    paper_c = 0.0 if temperature == "neutral" else rng.uniform(0.006, 0.018)
    paper_l = rng.uniform(0.965, 0.985) if light else rng.uniform(0.17, 0.22)
    paper = oklch_to_hex(paper_l, paper_c, paper_h)
    surface = oklch_to_hex(paper_l + (-0.03 if light else 0.05), paper_c, paper_h)

    ink_c = rng.uniform(0.012, 0.03) if light else rng.uniform(0.006, 0.014)
    ink_l = rng.uniform(0.2, 0.27) if light else rng.uniform(0.93, 0.96)
    ink = oklch_to_hex(ink_l, ink_c, base)

    # Text roles sit on the dark side of a light paper and the light side of
    # a dark one; each is the color nearest the paper that still passes.
    muted = closest_to(ink_c, base, paper, BODY + 0.1, light)
    rule = closest_to(paper_c, paper_h, paper, 1.35, light)
    control = closest_to(paper_c or 0.01, paper_h, paper, UI + 0.05, light)

    accent_c = rng.uniform(0.12, 0.2)
    if brand_hex:
        accent = brand_hex
    else:
        start = rng.uniform(0.5, 0.64) if light else rng.uniform(0.7, 0.8)
        accent = solve_lightness(accent_c, base, paper, UI + 0.1, start, -1 if light else 1)
    if accent is None:
        return None
    on_accent = max((paper, ink), key=lambda c: contrast(c, accent))
    accent_text = closest_to(accent_c, base, paper, BODY + 0.1, light)

    roles = {
        "paper": paper, "surface": surface, "ink": ink, "muted": muted,
        "rule": rule, "control-border": control, "accent": accent,
        "on-accent": on_accent, "accent-text": accent_text,
    }
    offset = SCHEMES[scheme]
    if offset is not None:
        h2 = (base + offset) % 360
        roles["accent-2"] = solve_lightness(
            accent_c, h2, paper, UI + 0.1,
            rng.uniform(0.55, 0.7) if light else rng.uniform(0.7, 0.82),
            -1 if light else 1)
    if any(v is None for v in roles.values()):
        return None

    checks = [
        ("ink on paper", "ink", "paper", INK_TARGET),
        ("ink on surface", "ink", "surface", BODY),
        ("muted on paper", "muted", "paper", BODY),
        ("accent-text on paper", "accent-text", "paper", BODY),
        ("on-accent on accent", "on-accent", "accent", BODY),
        ("accent against paper", "accent", "paper", UI),
        ("control-border against paper", "control-border", "paper", UI),
    ]
    if "accent-2" in roles:
        checks.append(("accent-2 against paper", "accent-2", "paper", UI))
    measured = []
    for label, fg, bg, need in checks:
        ratio = contrast(roles[fg], roles[bg])
        measured.append({"pair": label, "ratio": floor2(ratio), "needs": need,
                         "passes": ratio >= need})
    # A generated role that misses its target means this seed is unusable.
    # Only the brand color is allowed to fail, and then it says so.
    brand_pairs = {"on-accent on accent", "accent against paper"} if brand_hex else set()
    if any(not m["passes"] and m["pair"] not in brand_pairs for m in measured):
        return None

    return {
        "seed": seed,
        "mode": mode,
        "scheme": scheme,
        "base": f"{hue_name(base)} ({base:.0f})",
        "paper temperature": temperature,
        "brand": brand_hex,
        "roles": roles,
        "measured": measured,
    }


def suggest(count, mode, master=None, hue=None, brand=None):
    """`count` palettes that differ in hue, scheme or both."""
    pick = random.Random(master) if master is not None else random.SystemRandom()
    fixed_hue = hue is not None or brand is not None
    schemes = sorted(SCHEMES)
    pick.shuffle(schemes)
    found, tries = [], 0
    while len(found) < count and tries < 2000:
        tries += 1
        seed = pick.randrange(1, 1_000_000)
        scheme = schemes[len(found) % len(schemes)] if fixed_hue else None
        p = build(seed, mode, hue, brand, scheme)
        if p is None:
            continue
        base = float(p["base"].split("(")[1].rstrip(")"))
        if not fixed_hue and any(
                hue_gap(base, float(q["base"].split("(")[1].rstrip(")"))) < MIN_HUE_GAP
                for q in found):
            continue
        found.append(p)
    return found


# --- output ---------------------------------------------------------------------
def render(p, index=None, total=None):
    head = f"palette {index} of {total}" if index else "palette"
    lines = [f"{head}   seed {p['seed']}   {p['mode']}, {p['scheme']}, "
             f"{p['base']} base, {p['paper temperature']} paper"]
    if p["brand"]:
        lines.append(f"  brand color {p['brand']} is used exactly as given")
    for role, hx in p["roles"].items():
        L, C, h = hex_to_oklch(hx)
        lines.append(f"  {role:<15} {hx}   oklch({L:.3f} {C:.3f} {h:.0f})")
    lines.append("  measured (WCAG 2.2)")
    for m in p["measured"]:
        mark = "ok  " if m["passes"] else "FAIL"
        lines.append(f"    {mark} {m['pair']:<29} {m['ratio']:>5.2f}  needs {m['needs']}")
    failing = [m["pair"] for m in p["measured"] if not m["passes"]]
    if failing:
        lines.append("  the brand color misses a target: keep it for large fills and "
                     "logos, and use accent-text for text, links and thin outlines")
    return "\n".join(lines)


def cmd_suggest(args):
    found = suggest(args.count, args.mode, args.seed, args.hue, args.brand)
    if not found:
        print("no palette met the contrast targets; try another --hue or --mode",
              file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps(found, indent=2))
    else:
        print("\n\n".join(render(p, i + 1, len(found)) for i, p in enumerate(found)))
    return 0


def cmd_show(args):
    p = build(args.seed, args.mode, args.hue, args.brand, args.scheme)
    if p is None:
        print(f"seed {args.seed} does not meet the targets in {args.mode} mode",
              file=sys.stderr)
        return 1
    print(json.dumps(p, indent=2) if args.json else render(p))
    return 0


def cmd_audit(args):
    colors = [to_hex(parse_hex(c)) for c in args.colors]
    rows = []
    for i, a in enumerate(colors):
        for b in colors[i + 1:]:
            ratio = contrast(a, b)
            rows.append({"pair": [a, b], "ratio": floor2(ratio), "use": verdict(ratio)})
    rows.sort(key=lambda r: -r["ratio"])
    if args.json:
        print(json.dumps(rows, indent=2))
    else:
        for r in rows:
            print(f"  {r['pair'][0]} / {r['pair'][1]}   {r['ratio']:>5.2f}   {r['use']}")
    return 0


def cmd_contrast(args):
    ratio = contrast(args.fg, args.bg)
    print(f"{floor2(ratio):.2f}  {verdict(ratio)}")
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description="Palettes with measured WCAG contrast.")
    sub = ap.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("suggest", help="several palettes, each checked")
    s.add_argument("--count", type=int, default=3)
    s.add_argument("--mode", choices=("light", "dark"), default="light")
    s.add_argument("--seed", type=int, help="repeatable run")
    s.add_argument("--hue", type=float, help="base hue in degrees, OKLCH")
    s.add_argument("--brand", help="a brand color to keep exactly")
    s.add_argument("--json", action="store_true")
    s.set_defaults(fn=cmd_suggest)

    s = sub.add_parser("show", help="one palette again, by its seed")
    s.add_argument("seed", type=int)
    s.add_argument("--mode", choices=("light", "dark"), default="light")
    s.add_argument("--hue", type=float)
    s.add_argument("--brand")
    s.add_argument("--scheme", choices=sorted(SCHEMES),
                   help="needed only for a palette built with --hue or --brand")
    s.add_argument("--json", action="store_true")
    s.set_defaults(fn=cmd_show)

    s = sub.add_parser("audit", help="every pair of the given colors")
    s.add_argument("colors", nargs="+")
    s.add_argument("--json", action="store_true")
    s.set_defaults(fn=cmd_audit)

    s = sub.add_parser("contrast", help="one pair")
    s.add_argument("fg")
    s.add_argument("bg")
    s.set_defaults(fn=cmd_contrast)

    args = ap.parse_args(argv)
    try:
        return args.fn(args)
    except ValueError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
