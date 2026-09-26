#!/usr/bin/env python3
"""Check the code against the direction it claims to follow.

A model that has announced a direction will still write its habits when it
gets to the code: the fonts that were already there, the framework's default
colors, a neon glow on the call to action. Reading its own work back, the
same model does not see the difference. This does, because it counts.

    python3 verify.py design-direction.json src
    python3 verify.py design-direction.json src/styles src/components --json

Point it at source, not at a build: a build also carries the framework's own
stylesheet, which is not a choice anybody made on this page.

Against the source, eight checks fail the run and one only warns:

    fonts            every font stack starts with the spec's display, text or
                     mono family, or with a generic system stack
    overused fonts   none of the defaults the direction never picks, unless
                     the spec records them as the brand's own
    palette          every color literal is a palette role, or black or white
                     used as a translucent scrim
    default colors   no framework default color utility, such as text-cyan-400
    glow             no colored shadow with a blur of 4px or more
    gradient text    no background-clip: text
    glass            no backdrop blur
    radius           every finite corner radius is one the rolled shape allows
    hotlinks         (warning) images and styles loaded from another domain

Against the built site (--site dist), three more fail and one warns, all in
content.py: numbers on the page with no sourced claim (--claims), broken
links (absolute URLs too with --links), the spec's own seeds in the copy, and
(warning) design vocabulary such as WCAG in the copy. Without --site those
checks cannot run, and that is reported as a failure rather than a pass.

    python3 verify.py design-direction.json src --site dist \
        --claims design-claims.json --links

Exit status is 1 when any check fails, so an agent cannot report the work as
done without the numbers saying so.

Python standard library only.

reethink, by ree_es97 (https://reetech.web.id)
MIT licensed. https://github.com/masbrokemanaaja/reethink
"""

import argparse
import colorsys
import json
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import content  # noqa: E402
import direction  # noqa: E402
import palette  # noqa: E402

SOURCE_EXT = {".css", ".scss", ".sass", ".less", ".html", ".htm", ".astro", ".tsx",
              ".jsx", ".ts", ".js", ".mjs", ".vue", ".svelte", ".mdx"}
SKIP_DIRS = {"node_modules", ".git", "dist", "build", ".astro", ".next", ".nuxt",
             ".svelte-kit", ".output", "coverage", "vendor", "__pycache__"}
GENERIC_FAMILIES = {
    "serif", "sans-serif", "monospace", "cursive", "fantasy", "system-ui",
    "ui-serif", "ui-sans-serif", "ui-monospace", "ui-rounded", "emoji", "math",
    "fangsong", "-apple-system", "blinkmacsystemfont", "segoe ui", "sfmono-regular",
    "menlo", "monaco", "consolas", "courier new", "inherit", "initial", "unset",
}
PALETTE_TOLERANCE = 0.02   # Oklab distance still counted as the same color
GLOW_MIN_BLUR = 4.0        # px
GLOW_MIN_CHROMA = 0.04     # OKLCH chroma above which a shadow is colored
SHOW = 5

TAILWIND_HUES = ("slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|green|"
                 "emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose|"
                 "mauve|olive|mist|taupe")
TAILWIND_PROPS = ("bg|text|border(?:-[trblxyse])?|ring(?:-offset)?|outline|shadow|"
                  "inset-shadow|drop-shadow|divide|decoration|accent|caret|fill|stroke|"
                  "from|via|to|placeholder")
DEFAULT_COLOR = re.compile(
    r"(?<![\w-])(?:[a-z0-9-]+:)*(?:%s)-(?:(?:%s)-(?:50|[1-9]00|950)|white|black)(?:/\d+)?(?![\w-])"
    % (TAILWIND_PROPS, TAILWIND_HUES))
RADIUS_CLASS = re.compile(
    r"(?<![\w-])(?:[a-z0-9-]+:)*rounded(?:-(?:[trblse]|tl|tr|bl|br|ss|se|es|ee))?"
    r"(?:-(none|xs|sm|md|lg|xl|2xl|3xl|4xl|full|\[[^\]\s]+\]))?(?![\w-])")
RADIUS_SCALE = {None: 4, "none": 0, "xs": 2, "sm": 4, "md": 6, "lg": 8, "xl": 12,
                "2xl": 16, "3xl": 24, "4xl": 32, "full": None}

HEX = re.compile(r"(?<![\w&])#([0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{4}|[0-9a-fA-F]{3})(?![\w-])")
FUNC = re.compile(r"\b(rgba?|hsla?|oklch)\(\s*([^()]*?)\s*\)", re.I)


# --- reading color literals ------------------------------------------------------
def _num(token, scale=1.0):
    token = token.strip()
    if token.endswith("%"):
        return float(token[:-1]) / 100 * scale
    return float(token)


def parse_color(kind, body):
    """(hex, alpha) for one functional color, or None when it is not literal."""
    if "var(" in body or "calc(" in body:
        return None
    parts = [p for p in re.split(r"[\s,/_]+", body) if p]
    try:
        if kind.startswith("rgb") and len(parts) >= 3:
            rgb = [_num(p, 255) / 255 for p in parts[:3]]
            alpha = _num(parts[3]) if len(parts) > 3 else 1.0
            return palette.to_hex(rgb), alpha
        if kind.startswith("hsl") and len(parts) >= 3:
            h = float(parts[0].rstrip("deg")) / 360
            s, l = _num(parts[1], 1), _num(parts[2], 1)
            alpha = _num(parts[3]) if len(parts) > 3 else 1.0
            r, g, b = colorsys.hls_to_rgb(h % 1, min(1, l), min(1, s))
            return palette.to_hex((r, g, b)), alpha
        if kind == "oklch" and len(parts) >= 3:
            L = _num(parts[0], 1)
            C = _num(parts[1], 0.4)
            h = float(parts[2].rstrip("deg")) if parts[2] != "none" else 0.0
            alpha = _num(parts[3]) if len(parts) > 3 else 1.0
            return palette.oklch_to_hex(L, C, h), alpha
    except ValueError:
        return None
    return None


def colors_in(line):
    """Every literal color in a line of source: (hex, alpha, text)."""
    found = []
    for m in HEX.finditer(line):
        before = line[max(0, m.start() - 6):m.start()]
        if "href=" in before or "url(" in before:
            continue
        h = m.group(1)
        if len(h) in (3, 4):
            h = "".join(c * 2 for c in h)
        alpha = int(h[6:8], 16) / 255 if len(h) == 8 else 1.0
        found.append(("#" + h[:6].upper(), alpha, m.group(0)))
    for m in FUNC.finditer(line):
        parsed = parse_color(m.group(1).lower(), m.group(2))
        if parsed:
            found.append((parsed[0], parsed[1], m.group(0)))
    return found


def oklab(hx):
    return palette.linear_to_oklab(*(palette.to_linear(c) for c in palette.parse_hex(hx)))


def distance(a, b):
    return math.dist(oklab(a), oklab(b))


def chroma(hx):
    return palette.hex_to_oklch(hx)[1]


# --- the checks --------------------------------------------------------------------
def first_family(stack):
    first = stack.split(",")[0].strip().strip("'\"").strip()
    return first


def font_declarations(line):
    """Font family names a line declares or loads: (name, text)."""
    out = []
    for m in re.finditer(r"font-family\s*:\s*([^;}\n]+)", line):
        out.append((first_family(m.group(1)), m.group(0)))
    for m in re.finditer(r"--font-(?!weight|size|feature|variation|stretch)[\w-]*\s*:\s*([^;}\n]+)", line):
        out.append((first_family(m.group(1)), m.group(0)))
    for m in re.finditer(r"fonts\.googleapis\.com/css2?\?([^\"'\s>)]+)", line):
        for fam in re.findall(r"family=([^&:\"']+)", m.group(1)):
            out.append((fam.replace("+", " "), "family=" + fam))
    for m in re.finditer(r"(?<![\w-])font-\[([^\]]+)\]", line):
        out.append((first_family(m.group(1).replace("_", " ")), m.group(0)))
    return out


def check_fonts(files, spec):
    allowed = {f.lower() for f in (spec["fonts"]["display"], spec["fonts"]["text"],
                                   spec["fonts"]["mono"]) if f}
    brand = spec["fonts"]["source"] == "brand"
    overused = {f.lower() for f in direction.OVERUSED}
    off, stale = [], []
    for path, number, line in files:
        for name, text in font_declarations(line):
            key = name.lower()
            if not key or key.startswith(("var(", "--theme", "theme(")) or key in GENERIC_FAMILIES:
                continue
            if key not in allowed:
                off.append((path, number, text))
            if key in overused and not (brand and key in allowed):
                stale.append((path, number, text))
    return off, stale


def check_palette(files, spec):
    roles = list(spec["palette"]["roles"].values())
    off = []
    for path, number, line in files:
        for hx, alpha, text in colors_in(line):
            if hx in ("#000000", "#FFFFFF") and alpha < 1:
                continue
            if min(distance(hx, r) for r in roles) > PALETTE_TOLERANCE:
                off.append((path, number, text))
    return off


def check_pattern(files, pattern):
    hits = []
    for path, number, line in files:
        for m in pattern.finditer(line):
            hits.append((path, number, m.group(0)))
    return hits


SHADOW_DECL = re.compile(r"(?:box-shadow|text-shadow)\s*:\s*([^;}\n]+)|drop-shadow\(([^()]*(?:\([^()]*\)[^()]*)*)\)"
                         r"|(?<![\w-])(?:[a-z0-9-]+:)*(?:shadow|drop-shadow|text-shadow)-\[([^\]]+)\]")


def glow_layers(value):
    """Shadow layers in a value that are colored and blurred."""
    glows = []
    for layer in re.split(r",(?![^(]*\))", value.replace("_", " ")):
        lengths = re.findall(r"(-?\d*\.?\d+)(px|rem|em)?(?![\w%])", re.sub(FUNC, " ", re.sub(HEX, " ", layer)))
        px = [float(n) * (16 if unit in ("rem", "em") else 1) for n, unit in lengths]
        blur = px[2] if len(px) >= 3 else 0.0
        colors = colors_in(layer)
        if blur >= GLOW_MIN_BLUR and any(chroma(hx) >= GLOW_MIN_CHROMA for hx, _, _ in colors):
            glows.append(layer.strip())
    return glows


def check_glow(files):
    hits = []
    for path, number, line in files:
        for m in SHADOW_DECL.finditer(line):
            value = next(g for g in m.groups() if g is not None)
            if glow_layers(value):
                hits.append((path, number, m.group(0)))
    return hits


def check_radius(files, spec):
    allowed = spec["radius"]["allowed_px"]
    ok = lambda px: px is None or px >= 9999 or any(lo <= px <= hi for lo, hi in allowed)
    hits = []
    for path, number, line in files:
        for m in re.finditer(r"border-(?:[a-z-]+-)?radius\s*:\s*([^;}\n]+)", line):
            for n, unit in re.findall(r"(\d*\.?\d+)(px|rem|%)?", m.group(1)):
                if unit == "%" or "var(" in m.group(1):
                    continue
                px = float(n) * (16 if unit == "rem" else 1)
                if not ok(px):
                    hits.append((path, number, m.group(0)))
                    break
        for m in RADIUS_CLASS.finditer(line):
            size = m.group(1)
            if size and size.startswith("["):
                inner = size[1:-1]
                nm = re.fullmatch(r"(\d*\.?\d+)(px|rem)", inner)
                if not nm:
                    continue
                px = float(nm.group(1)) * (16 if nm.group(2) == "rem" else 1)
            elif size in RADIUS_SCALE:
                px = RADIUS_SCALE[size]
            else:
                continue
            if not ok(px):
                hits.append((path, number, m.group(0)))
    return hits


HOTLINK = re.compile(r"""(?:url\(\s*['"]?|(?:src|href)\s*=\s*['"])(https?://(?!fonts\.(?:googleapis|gstatic)\.com)[^'")\s]+)""")
HOTLINK_ASSET = re.compile(r"\.(?:png|jpe?g|gif|webp|avif|svg|css)(?:[?#][^'\")\s]*)?$|/noise|/texture", re.I)


def check_hotlinks(files):
    hits = []
    for path, number, line in files:
        for m in HOTLINK.finditer(line):
            if HOTLINK_ASSET.search(m.group(1)):
                hits.append((path, number, m.group(1)))
    return hits


# --- running ---------------------------------------------------------------------------
def source_lines(paths):
    for root in paths:
        if os.path.isfile(root):
            candidates = [root]
        else:
            candidates = []
            for base, dirs, names in os.walk(root):
                dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
                candidates += [os.path.join(base, n) for n in sorted(names)]
        for path in candidates:
            if os.path.splitext(path)[1].lower() not in SOURCE_EXT:
                continue
            try:
                with open(path, encoding="utf-8") as fh:
                    for number, line in enumerate(fh, 1):
                        yield path, number, line
            except (OSError, UnicodeDecodeError):
                continue


def content_results(spec, site, claims_path, network):
    """The checks that read the built page's words, or one failure saying why not."""
    if not site:
        return [("claims", "fail", [("--site", 0, "not checked: pass --site <build dir>")],
                 "numbers on the page without a sourced claim")]
    pages = content.read_site(site)
    if not pages:
        return [("claims", "fail", [(site, 0, "no .html files found: build first")],
                 "numbers on the page without a sourced claim")]
    claims = content.load_claims(claims_path)
    links, unverified, external = content.check_links(site, pages, network)
    where = f"{external} external checked" if network else f"{external} external not checked, add --links"
    words = [(p, 0, f"{m.group(0)}  in: {b[:80]}") for p, page in pages for b in page.blocks
             for m in re.finditer(r"\bWCAG\b", b)]
    return [
        ("claims", "fail", content.check_claims(pages, claims), "numbers on the page without a sourced claim"),
        ("links", "fail", links, f"broken links ({where})"),
        ("links refused", "warn", unverified, "sites that refused a script; open these by hand"),
        ("process leak", "fail", content.check_process_leak(pages, spec), "the spec's seeds or file name in the copy"),
        ("process words", "warn", words, "design vocabulary in the copy"),
    ]


def run(spec, paths, site=None, claims=None, network=False):
    files = list(source_lines(paths))
    fonts, stale = check_fonts(files, spec)
    f = spec["fonts"]
    wanted = " / ".join(dict.fromkeys(x for x in (f["display"], f["text"], f["mono"]) if x))
    results = [
        ("fonts", "fail", fonts, f"font stacks that do not start with {wanted}"),
        ("overused fonts", "fail", stale, "defaults the direction never picks"),
        ("palette", "fail", check_palette(files, spec), "color literals outside the palette"),
        ("default colors", "fail", check_pattern(files, DEFAULT_COLOR), "framework default color utilities"),
        ("glow", "fail", check_glow(files), "colored, blurred shadows"),
        ("gradient text", "fail", check_pattern(files, re.compile(
            r"(?:-webkit-)?background-clip\s*:\s*text|(?<![\w-])(?:[a-z0-9-]+:)*bg-clip-text(?![\w-])")),
         "gradient-filled text"),
        ("glass", "fail", check_pattern(files, re.compile(
            r"backdrop-filter\s*:\s*[^;]*blur|(?<![\w-])(?:[a-z0-9-]+:)*backdrop-blur(?:-[\w\[\]./]+)?(?![\w-])")),
         "backdrop blur"),
        ("radius", "fail", check_radius(files, spec),
         f"corner radii the {spec['direction']['axes']['shape']} shape does not allow"),
        ("hotlinks", "warn", check_hotlinks(files), "images or styles from another domain"),
    ] + content_results(spec, site, claims, network)
    return len({p for p, _, _ in files}), results


def render(spec_path, spec, scanned, results):
    d, p = spec["direction"], spec["palette"]
    lines = [f"verify {spec_path}: direction {d['seed']}, palette {p['seed']}, "
             f"{scanned} source files"]
    failed = 0
    for name, level, hits, what in results:
        if not hits:
            mark = "ok  "
        elif level == "warn":
            mark = "warn"
        else:
            mark = "FAIL"
            failed += 1
        lines.append(f"  {mark} {name:<15} {len(hits):>4}  {what}")
        for path, number, text in hits[:SHOW]:
            where = f"{path}:{number}" if number else path
            lines.append(f"         {where}  {text.strip()[:110]}")
        if len(hits) > SHOW:
            lines.append(f"         and {len(hits) - SHOW} more")
    checks = sum(1 for _, level, _, _ in results if level == "fail")
    lines.append(f"result: {checks - failed} of {checks} checks pass")
    return "\n".join(lines), failed


def main(argv=None):
    ap = argparse.ArgumentParser(description="Check source code against a senior-designer spec.")
    ap.add_argument("spec", help="the design-direction.json written by tokens.py")
    ap.add_argument("paths", nargs="+", help="source files or directories")
    ap.add_argument("--site", help="the built site (dist/), whose rendered words are checked")
    ap.add_argument("--claims", help="design-claims.json: every number on the page and its source")
    ap.add_argument("--links", action="store_true", help="also request every absolute URL (network)")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    try:
        with open(args.spec, encoding="utf-8") as fh:
            spec = json.load(fh)
    except (OSError, ValueError) as e:
        print(f"error: cannot read {args.spec}: {e}", file=sys.stderr)
        return 2
    try:
        scanned, results = run(spec, args.paths, args.site, args.claims, args.links)
    except (OSError, ValueError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 2
    text, failed = render(args.spec, spec, scanned, results)
    if args.json:
        print(json.dumps({
            "scanned": scanned,
            "checks": [{"name": n, "level": lv, "count": len(h), "what": w,
                        "hits": [{"file": p, "line": ln, "text": t.strip()} for p, ln, t in h]}
                       for n, lv, h, w in results],
            "failed": failed,
        }, indent=2))
    else:
        print(text)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
