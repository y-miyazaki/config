#!/usr/bin/env python3
"""Link repository paths and commit SHAs in loop message text.

Agents write the paths and SHAs they cite as plain text or code spans, which GitHub
does not make clickable. This reads the text on stdin and writes it with the linkable
tokens turned into markdown links. Only tokens that name something known are linked,
so example paths and unknown tokens stay as written.

Usage:
  linkify.py --ref REF --tracked          link every file tracked at REF (git ls-tree),
                                          in code spans and plain text; a bare file name
                                          is linked when exactly one tracked file has it
  linkify.py --ref REF                    link the files in CHANGED_FILES_JSON and the
                                          commits in DETECT_RESULT_JSON, in code spans only

Environment:
  GITHUB_REPOSITORY    owner/repo (required; without it the text is printed unchanged)
  GITHUB_SERVER_URL    GitHub host (default https://github.com)
  CHANGED_FILES_JSON   JSON string array of changed paths (without --tracked)
  DETECT_RESULT_JSON   JSON whose 40-hex SHAs may be linked (without --tracked)

Design rules:
  - Existing markdown links, bare URLs, HTML comments, and fenced code blocks are left alone
  - A code span is linked only when it holds exactly one known path or SHA
  - A `#L12` / `#L12-L20` or `:12` / `:12-20` suffix becomes a line anchor
  - A bare 7-40 hex token is linked only when it prefixes a known commit SHA
  - Any error leaves the original text untouched (the caller prints it as is)
"""

import argparse
import json
import os
import re
import subprocess
import sys
from urllib.parse import quote

BASE = ""
REF = ""
PATHS = set()
SHAS = []
PLAIN = False
BARE = False

NAMES = {}

EXT = r"(?:sh|bats|ya?ml|md|json|toml|py|go|tf|tfvars|js|ts|bash)"
SUFFIX = re.compile(r"(?:#L(\d+)(?:-L(\d+))?|:(\d+)(?:-(\d+))?)$")
SKIP = re.compile(r"(\[[^\]\n]*\]\([^)\n]*\))|(https?://[^\s<>)]+)|(<!--.*?-->)")
CODE = re.compile(r"`([^`\n]+)`")
LEAD = r"(?<![\w/.:@#=\[-])"
PLAIN_PATH = re.compile(
    LEAD + r"(?:\./)?[A-Za-z0-9_.@+-]+(?:/[A-Za-z0-9_.@+-]+)*(?:#L\d+(?:-L\d+)?)?(?![\w/(-])"
)
BARE_NAME = re.compile(LEAD + r"[\w.-]+\." + EXT + r"(?:#L\d+(?:-L\d+)?)?(?![\w/(-])")
BARE_SHA = re.compile(r"(?<![\w/#=.-])([0-9a-f]{7,40})(?![\w/-])")


def resolve_path(token):
    """Return (path, anchor) when token names a known path, else None."""
    anchor = ""
    core = token
    m = SUFFIX.search(token)
    if m:
        core = token[: m.start()]
        start = m.group(1) or m.group(3)
        end = m.group(2) or m.group(4)
        anchor = "#L%s" % start + ("-L%s" % end if end else "")
    core = core[2:] if core.startswith("./") else core
    if core in PATHS:
        return core, anchor
    if BARE and "/" not in core and re.fullmatch(r"[\w.-]+\." + EXT, core) and len(NAMES.get(core, [])) == 1:
        return NAMES[core][0], anchor
    return None


def link_sha(token):
    if re.fullmatch(r"[0-9a-f]{7,40}", token):
        for sha in SHAS:
            if sha.startswith(token):
                return "[%s](%s/commit/%s)" % (token, BASE, sha)
    return None


def link_path(token):
    hit = resolve_path(token)
    if hit is None:
        return None
    path, anchor = hit
    return "[%s](%s/blob/%s/%s%s)" % (token, BASE, REF, quote(path, safe="/"), anchor)


def outside_links(text, fn):
    """Apply fn to the parts of text that are not already links, URLs, or comments."""
    out = []
    pos = 0
    for m in SKIP.finditer(text):
        out.append(fn(text[pos : m.start()]))
        out.append(m.group(0))
        pos = m.end()
    out.append(fn(text[pos:]))
    return "".join(out)


def sha_pass(seg):
    if not SHAS:
        return seg
    return BARE_SHA.sub(lambda m: link_sha(m.group(1)) or m.group(0), seg)


def trim_trailing(token):
    trail = ""
    while token and token[-1] in ".,;:)":
        trail = token[-1] + trail
        token = token[:-1]
    return token, trail


def path_pass(seg):
    if not PLAIN:
        return seg

    def link(m):
        token, trail = trim_trailing(m.group(0))
        link_text = link_path(token)
        return (link_text + trail) if link_text else m.group(0)

    if "/" in seg:
        seg = PLAIN_PATH.sub(link, seg)
    if BARE and "." in seg:
        seg = BARE_NAME.sub(link, seg)
    return seg


def plain_text(seg):
    return outside_links(outside_links(seg, sha_pass), path_pass)


def code_span(match):
    inner = match.group(1)
    return link_path(inner) or link_sha(inner) or match.group(0)


def convert_segment(seg):
    out = []
    pos = 0
    for m in CODE.finditer(seg):
        out.append(plain_text(seg[pos : m.start()]))
        out.append(code_span(m))
        pos = m.end()
    out.append(plain_text(seg[pos:]))
    return "".join(out)


def convert_line(line):
    return outside_links(line, convert_segment)


def load_tracked(ref):
    out = subprocess.run(
        ["git", "ls-tree", "-r", "--name-only", ref], capture_output=True, text=True, check=True
    ).stdout
    return {p for p in out.split("\n") if p}


def load_changed():
    try:
        paths = json.loads(os.environ.get("CHANGED_FILES_JSON") or "[]")
    except ValueError:
        paths = []
    return {p for p in paths if isinstance(p, str)}


def configure(args):
    global BASE, REF, PATHS, SHAS, PLAIN, BARE
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    if not repo or not args.ref:
        return False
    BASE = "%s/%s" % (os.environ.get("GITHUB_SERVER_URL") or "https://github.com", repo)
    BASE = BASE.rstrip("/")
    REF = args.ref
    if args.tracked:
        PATHS = load_tracked(REF)
        PLAIN = BARE = True
    else:
        PATHS = load_changed()
        SHAS = sorted(set(re.findall(r"\b[0-9a-f]{40}\b", os.environ.get("DETECT_RESULT_JSON") or "")))
    for p in PATHS:
        NAMES.setdefault(p.rsplit("/", 1)[-1], []).append(p)
    return bool(PATHS or SHAS)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--ref", default="")
    parser.add_argument("--tracked", action="store_true")
    args = parser.parse_args()
    text = sys.stdin.read()
    try:
        ready = configure(args)
    except (OSError, subprocess.CalledProcessError):
        ready = False
    if not ready:
        sys.stdout.write(text)
        return
    lines = []
    fenced = False
    for line in text.split("\n"):
        if line.lstrip().startswith("```"):
            fenced = not fenced
            lines.append(line)
        elif fenced:
            lines.append(line)
        else:
            lines.append(convert_line(line))
    sys.stdout.write("\n".join(lines))


if __name__ == "__main__":
    main()
