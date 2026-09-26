"""The words on the built page: claims, links, and the design process leaking in.

`verify.py` checks how a page looks against the spec; this checks what it
says. It reads the built HTML rather than the source, because the reader sees
the rendered text and a React island's copy only exists as text once it is
rendered.

Three things are counted:

    claims        every percentage, "3+", year range, multiplier or counted
                  noun ("12 projects") on the page must appear in the claims
                  file with a source, so a number invented to fill a stat tile
                  is caught instead of shipped
    links         every relative link must resolve to a file in the build;
                  with network checks on, every absolute URL and every URL
                  shown in text (a copyable curl command) must answer below 400
    process leak  the spec's own seeds and file name must not appear in the
                  copy; they are the designer's notes, not the product

Imported by verify.py. Python standard library only.

reethink, by ree_es97 (https://reetech.web.id)
MIT licensed. https://github.com/masbrokemanaaja/reethink
"""

import html.parser
import json
import os
import re
import urllib.error
import urllib.request

# A number that asserts something about the person or the product.
CLAIM = re.compile(
    r"\b\d{1,3}(?:[.,]\d+)?\s?%"
    r"|\b\d+\s?\+(?=[\s\w]|$)"
    r"|\b(?:19|20)\d{2}\s?[-\u2013\u2014]\s?(?:(?:19|20)\d{2}|sekarang|kini|now|present|today)\b"
    r"|\b\d+(?:\.\d+)?x\b"
    r"|\b\d[\d.,]*\s+(?:years?|tahun|projects?|proyek|clients?|klien|customers?|pelanggan"
    r"|users?|pengguna|companies|perusahaan|countries|negara|downloads?|stars?|bintang)\b",
    re.I)
URL_IN_TEXT = re.compile(r"https?://[^\s\"'<>)\]]+")
USER_FACING_ATTRS = ("alt", "title", "aria-label", "placeholder")
SKIP_TAGS = {"script", "style", "noscript", "template"}


class _Page(html.parser.HTMLParser):
    """Visible text blocks, links and meta description of one HTML file."""

    # Structural tags end a block; inline ones (span, a, strong, code) do not,
    # so "3+ <span>years</span>" stays one phrase.
    BLOCK = {"p", "li", "h1", "h2", "h3", "h4", "h5", "h6", "div", "section",
             "article", "aside", "nav", "main", "header", "footer", "td", "th", "dd",
             "dt", "figcaption", "blockquote", "pre", "button", "label", "br"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.blocks, self.links, self._buf, self._skip = [], [], [], 0

    def _flush(self):
        text = " ".join("".join(self._buf).split())
        if text:
            self.blocks.append(text)
        self._buf = []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag in SKIP_TAGS:
            self._skip += 1
        if tag in self.BLOCK:
            self._flush()
        rel = (a.get("rel") or "").lower()
        fetched = tag in ("a", "img", "script", "source", "iframe") or (
            tag == "link" and any(r in rel for r in ("stylesheet", "icon", "preload")))
        for key in ("href", "src"):
            if fetched and a.get(key):
                self.links.append(a[key])
        for key in USER_FACING_ATTRS:
            if a.get(key):
                self.blocks.append(" ".join(a[key].split()))
        if tag == "meta" and (a.get("name") or "").lower() == "description" and a.get("content"):
            self.blocks.append(" ".join(a["content"].split()))

    def handle_endtag(self, tag):
        if tag in SKIP_TAGS and self._skip:
            self._skip -= 1
        if tag in self.BLOCK:
            self._flush()

    def handle_data(self, data):
        if not self._skip:
            self._buf.append(data)

    def close(self):
        super().close()
        self._flush()


def read_site(site):
    """[(path, page)] for every .html file under the build directory."""
    pages = []
    for base, dirs, names in os.walk(site):
        dirs[:] = sorted(d for d in dirs if d not in {"node_modules", ".git"})
        for name in sorted(names):
            if name.lower().endswith((".html", ".htm")):
                path = os.path.join(base, name)
                page = _Page()
                with open(path, encoding="utf-8", errors="replace") as fh:
                    page.feed(fh.read())
                page.close()
                pages.append((path, page))
    return pages


def load_claims(path):
    """Claims as [(normalised text, source)]; ValueError on a malformed file."""
    if not path:
        return []
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    entries = data.get("claims", data) if isinstance(data, dict) else data
    claims = []
    for i, entry in enumerate(entries):
        text = " ".join(str(entry.get("text", "")).split()).lower()
        source = str(entry.get("source", "")).strip()
        if not text:
            raise ValueError(f"claim {i + 1} has no text")
        claims.append((text, source))
    return claims


def check_claims(pages, claims):
    """Numbers on the page that no sourced claim covers, and claims with no source."""
    hits = []
    for text, source in claims:
        if not source:
            hits.append(("claims file", 0, f"no source given for: {text}"))
    sourced = [t for t, s in claims if s]
    for path, page in pages:
        for block in page.blocks:
            low = block.lower()
            spans = []
            for t in sourced:
                start = low.find(t)
                while start != -1:
                    spans.append((start, start + len(t)))
                    start = low.find(t, start + 1)
            for m in CLAIM.finditer(block):
                if not any(a <= m.start() and m.end() <= b for a, b in spans):
                    hits.append((path, 0, f"{m.group(0).strip()}  in: {block[:80]}"))
    return hits


def _local_target(site, page_path, href):
    target = href.split("#", 1)[0].split("?", 1)[0]
    if not target:
        return None
    if target.startswith("/"):
        path = os.path.join(site, target.lstrip("/"))
    else:
        path = os.path.join(os.path.dirname(page_path), target)
    candidates = [path, os.path.join(path, "index.html"), path.rstrip("/") + ".html"]
    return any(os.path.isfile(c) for c in candidates)


def _fetch(url, timeout):
    headers = {"User-Agent": "reethink-verify/1 (+https://github.com/masbrokemanaaja/reethink)"}
    for method in ("HEAD", "GET"):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, method=method, headers=headers),
                                        timeout=timeout) as resp:
                return resp.status
        except urllib.error.HTTPError as e:
            if method == "HEAD" and e.code in (403, 405, 501):
                continue
            return e.code
        except (urllib.error.URLError, OSError, ValueError) as e:
            return f"unreachable ({getattr(e, 'reason', e)})"
    return "unreachable"


# Answers that prove a link is dead. Anything else at 400 or above (401, 403,
# 429, and LinkedIn's 999 for anything that is not a browser) only proves the
# site refused a script, so it is reported as unverified rather than broken.
DEAD = {404, 410}


def check_links(site, pages, network, timeout=10):
    """(broken, unverified, external count): relative links always, absolute ones with `network`."""
    hits, unverified, external = [], [], {}
    for path, page in pages:
        for href in page.links:
            if href.startswith(("mailto:", "tel:", "data:", "javascript:", "#")):
                continue
            if re.match(r"https?://", href):
                external.setdefault(href, path)
            elif not href.startswith("//") and _local_target(site, path, href) is False:
                hits.append((path, 0, f"missing in the build: {href}"))
        for block in page.blocks:
            for url in URL_IN_TEXT.findall(block):
                external.setdefault(url.rstrip(".,;:"), path)
    if network:
        for url, path in sorted(external.items()):
            status = _fetch(url, timeout)
            if not isinstance(status, int) or status in DEAD or 500 <= status < 600:
                hits.append((path, 0, f"{status}: {url}"))
            elif status >= 400:
                unverified.append((path, 0, f"{status}: {url}"))
    return hits, unverified, len(external)


def check_process_leak(pages, spec):
    """The spec's own seeds and file name showing up in the copy."""
    # A seed is caught inside a label such as "DIR-934454", but not inside a
    # longer number that merely contains the same digits.
    patterns = [(str(spec[k]["seed"]), r"(?<!\d)" + str(spec[k]["seed"]) + r"(?!\d)")
                for k in ("direction", "palette")]
    patterns.append(("design-direction", r"design-direction"))
    hits = []
    for path, page in pages:
        for block in page.blocks:
            for token, pattern in patterns:
                if re.search(pattern, block, re.I):
                    hits.append((path, 0, f"{token}  in: {block[:80]}"))
    return hits
