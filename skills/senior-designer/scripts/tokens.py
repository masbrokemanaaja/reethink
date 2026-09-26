#!/usr/bin/env python3
"""Turn a chosen direction and palette into a spec file and the tokens it implies.

A direction that lives only in the conversation gets translated into code by
hand, and the hand writes its habits: the fonts the project already had, the
framework's default colors, a glow on the button. So the choice is written
down as a file, and the tokens are generated from that file rather than
retyped. `verify.py` then reads the same file back and checks the code
against it.

    python3 tokens.py spec --direction 822532 --palette 914858 --mode dark \\
        --brand "#22d3ee" --scheme triadic --out design-direction.json
    python3 tokens.py emit design-direction.json                 Tailwind v4 @theme
    python3 tokens.py emit design-direction.json --format css    plain :root variables

The Tailwind block opens with `--color-*: initial` and `--font-*: initial`,
which removes the framework's default palette and font stacks from the build:
checked against Tailwind 4.3.3, `text-cyan-400`, `bg-zinc-900` and `bg-white`
stop generating any CSS, while `bg-transparent` and `text-current` keep
working. A default color can then not slip back in without somebody noticing.

Brand fonts replace the rolled pair only when the user has said they are the
brand's (`--brand-fonts "Display,Text"`). Fonts that merely exist in the code
are not brand fonts.

Python standard library only.

reethink, by ree_es97 (https://reetech.web.id)
MIT licensed. https://github.com/masbrokemanaaja/reethink
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import direction  # noqa: E402
import palette  # noqa: E402

# Finite radii each shape allows, in px. A circle (a status dot, an avatar, a
# pill) is 9999px or 50% and is always allowed, because it is a shape rather
# than a corner.
SHAPES = {
    "square": {"allowed": [[0, 0]], "container": "0", "control": "0"},
    "small-radius": {"allowed": [[0, 0], [2, 4]], "container": "4px", "control": "4px"},
    "pill-and-square": {"allowed": [[0, 0]], "container": "0", "control": "9999px"},
    "soft-containers": {"allowed": [[0, 0], [6, 8], [16, 24]], "container": "20px", "control": "8px"},
    "notched": {"allowed": [[0, 0]], "container": "0", "control": "0"},
}

GENERIC = {
    "display": "system-ui, sans-serif",
    "text": "system-ui, sans-serif",
    "mono": "ui-monospace, SFMono-Regular, Menlo, monospace",
}


def build_spec(args):
    d = direction.build(args.direction, args.surface)
    p = palette.build(args.palette, args.mode, args.hue, args.brand, args.scheme)
    if p is None:
        raise ValueError(f"palette seed {args.palette} does not meet its targets in {args.mode} mode")
    if args.brand_fonts:
        names = [n.strip() for n in args.brand_fonts.split(",") if n.strip()]
        if not 1 <= len(names) <= 2:
            raise ValueError("--brand-fonts takes one or two family names: \"Display,Text\"")
        fonts = {"display": names[0], "text": names[-1], "source": "brand"}
    else:
        fonts = {**d["fonts"], "source": "rolled"}
    mono = fonts["display"] if d["axes"]["type"] == "mono-accent" and fonts["source"] == "rolled" else None
    fonts["mono"] = mono
    shape = SHAPES[d["axes"]["shape"]]
    reproduce = ["python3", "tokens.py", "spec", "--direction", str(args.direction),
                 "--surface", args.surface, "--palette", str(args.palette), "--mode", args.mode]
    for flag, value in (("--brand", args.brand), ("--scheme", args.scheme),
                        ("--hue", args.hue), ("--brand-fonts", args.brand_fonts)):
        if value is not None:
            reproduce += [flag, str(value)]
    return {
        "generator": "reethink senior-designer",
        "reproduce": reproduce,
        "direction": d,
        "palette": p,
        "fonts": fonts,
        "radius": {"allowed_px": shape["allowed"], "container": shape["container"],
                   "control": shape["control"]},
    }


def font_stack(name, kind):
    return f'"{name}", {GENERIC[kind]}' if name else GENERIC[kind]


def google_fonts_url(fonts):
    families = []
    for name in (fonts["display"], fonts["text"]):
        if name and name not in families:
            families.append(name)
    # No weights are requested: asking for one a family does not have makes
    # the whole request fail, so the weights are added by hand after checking
    # what each family ships.
    query = "&".join("family=" + f.replace(" ", "+") for f in families)
    return f"https://fonts.googleapis.com/css2?{query}&display=swap"


def emit(spec, fmt):
    f, roles = spec["fonts"], spec["palette"]["roles"]
    d, p = spec["direction"], spec["palette"]
    head = [
        f"/* reethink senior-designer: direction {d['seed']} ({d['surface']}), "
        f"palette {p['seed']} ({p['mode']}). */",
        f"/* Fonts: {google_fonts_url(f)} */",
        "/* Add the weights each family actually ships before loading it. */",
    ]
    # A monospace display face falls back to a monospace stack, not a sans.
    display_kind = "mono" if f["mono"] and f["mono"] == f["display"] else "display"
    fonts = [
        ("display", font_stack(f["display"], display_kind)),
        ("sans", font_stack(f["text"], "text")),
        ("mono", font_stack(f["mono"], "mono")),
    ]
    radius = [("container", spec["radius"]["container"]), ("control", spec["radius"]["control"])]
    if fmt == "tailwind":
        body = ["@theme {", "  --color-*: initial;", "  --font-*: initial;"]
        body += [f"  --color-{role}: {hx};" for role, hx in roles.items()]
        body += [f"  --font-{name}: {stack};" for name, stack in fonts]
        body += [f"  --radius-{name}: {value};" for name, value in radius]
        body.append("}")
    else:
        body = [":root {"]
        body += [f"  --{role}: {hx};" for role, hx in roles.items()]
        body += [f"  --font-{name}: {stack};" for name, stack in fonts]
        body += [f"  --radius-{name}: {value};" for name, value in radius]
        body.append("}")
    return "\n".join(head + body)


def cmd_spec(args):
    spec = build_spec(args)
    text = json.dumps(spec, indent=2) + "\n"
    if args.out:
        with open(args.out, "w", encoding="utf-8") as fh:
            fh.write(text)
        print(f"wrote {args.out}: direction {spec['direction']['seed']}, "
              f"palette {spec['palette']['seed']}, fonts {spec['fonts']['display']} / "
              f"{spec['fonts']['text']} ({spec['fonts']['source']})")
    else:
        sys.stdout.write(text)
    return 0


def cmd_emit(args):
    with open(args.spec, encoding="utf-8") as fh:
        spec = json.load(fh)
    print(emit(spec, args.format))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description="A spec file and tokens from a direction and a palette.")
    sub = ap.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("spec", help="write the chosen direction and palette down")
    s.add_argument("--direction", type=int, required=True, help="direction seed")
    s.add_argument("--surface", choices=sorted(direction.SURFACE_RULES), default="web")
    s.add_argument("--palette", type=int, required=True, help="palette seed")
    s.add_argument("--mode", choices=("light", "dark"), default="light")
    s.add_argument("--hue", type=float)
    s.add_argument("--brand", help="the brand color the palette was built around")
    s.add_argument("--scheme", choices=sorted(palette.SCHEMES))
    s.add_argument("--brand-fonts", help="\"Display,Text\", only when the user named them as the brand's")
    s.add_argument("--out", help="file to write; stdout when omitted")
    s.set_defaults(fn=cmd_spec)

    s = sub.add_parser("emit", help="the tokens a spec implies")
    s.add_argument("spec")
    s.add_argument("--format", choices=("tailwind", "css"), default="tailwind")
    s.set_defaults(fn=cmd_emit)

    args = ap.parse_args(argv)
    try:
        return args.fn(args)
    except (ValueError, OSError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
