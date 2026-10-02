#!/usr/bin/env python3
"""
Build the publishable copy.

index.html holds your real data in its SEED block (profile, weigh-ins, the
first runs from your notes). docs/index.html is the same app with that block
emptied, so the published page carries nothing personal. It refuses to write
a file that still has your data in it.

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
        sys.exit("build: REFUSING — .leakwords is missing, so nothing can be checked.")
    words = [l.strip() for l in p.read_text().splitlines() if l.strip() and not l.startswith("#")]
    if not words:
        sys.exit("build: REFUSING — .leakwords is empty.")
    return words

def main():
    src = SRC.read_text()
    blocks = SEED_RE.findall(src)
    if len(blocks) != 1:
        sys.exit(f"build: expected one SEED:START … SEED:END block, found {len(blocks)}")
    out = SEED_RE.sub(lambda _: BLANK, src)

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
    print(f"wrote  : docs/{OUT.name}  {len(out):,} bytes  ({len(src) - len(out):,} bytes of seed data removed)")
    print("checked: nothing from .leakwords in the published copy")

if __name__ == "__main__":
    main()
