#!/usr/bin/env python3
"""
Build the published copy: index.html -> docs/index.html (what GitHub Pages
serves). The commit hook runs this for you whenever index.html is staged.

The SEED block is kept empty in the source; personal data lives in your Stride
account, never in the repo. On a machine with .leakwords, the build also
refuses to write a file containing any of those strings.

    python3 build.py
"""
import re, sys, pathlib

HERE = pathlib.Path(__file__).parent
SRC  = HERE / "index.html"
OUT  = HERE / "docs" / "index.html"

SEED_RE = re.compile(r"/\* SEED:START.*?/\* SEED:END \*/", re.S)
BLANK   = "/* SEED:START — empty in the published copy. */\nconst SEED = {};\n/* SEED:END */"

# Strings that must not survive into the published copy. The list lives in
# .leakwords, which is gitignored — the list is itself the sensitive data.
# Fails closed.
def load_leakwords():
    p = HERE / ".leakwords"
    if not p.exists():
        return []   # only Neil's machine has the list; the source holds no personal data
    words = [l.strip() for l in p.read_text().splitlines() if l.strip() and not l.startswith("#")]
    return words

def main():
    src = SRC.read_text()
    blocks = SEED_RE.findall(src)
    if len(blocks) > 1:
        sys.exit(f"build: expected at most one SEED:START … SEED:END block, found {len(blocks)}")
    out = SEED_RE.sub(lambda _: BLANK, src)   # a no-op unless an old seed block is pasted back in

    hits = sorted({w for w in load_leakwords() if w in out})
    if hits:
        sys.exit(f"build: REFUSING to write — personal data still present: {', '.join(hits)}")

    # and it still has to be a working app
    for marker in ("function analyzeFit(", "function renderToday(", "const SUPABASE", "syncInit(fromLink)", "function checkIntervals("):
        if marker not in out:
            sys.exit(f"build: output is missing `{marker}` — something was over-stripped")

    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(out)
    print(f"source : {SRC.name}  {len(src):,} bytes")
    print(f"wrote  : docs/{OUT.name}  {len(out):,} bytes")
    print("checked: nothing from .leakwords in the published copy" if (HERE / ".leakwords").exists() else "checked: no .leakwords on this machine — leak check skipped")

if __name__ == "__main__":
    main()
