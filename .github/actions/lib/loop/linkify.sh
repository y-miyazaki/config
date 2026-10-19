#!/bin/bash
#######################################
# Description:
#   Link repository file paths in a loop message before it is posted. Agents write
#   the paths they cite as plain text or code spans, which GitHub does not make
#   clickable. This turns a path into a blob link only when the file exists at the
#   ref, so example paths and unknown tokens stay as written.
#
# Usage:
#   source linkify.sh
#   text="$(linkify_repo_text "${text}" "${ref}")"
#
# Design Rules:
#   - A path is linked only when it is tracked at the ref (git ls-tree); a bare file
#     name (no directory) is linked only when exactly one tracked file has that name
#   - Existing markdown links, bare URLs, HTML comments, fenced code blocks, and
#     code spans that hold anything but a single path are left alone
#   - A `#L12` / `#L12-L20` or `:12` / `:12-20` suffix becomes a line anchor
#   - A no-op when the repository, the ref, or the tracked file list is unavailable
#   - The function never fails; on any error the original text is printed
#
# Output:
#   None (library file, sourced by other scripts)
#######################################

#######################################
# linkify_repo_text: Link tracked repository paths in message text
#
# Globals:
#   GITHUB_REPOSITORY - owner/repo
#   GITHUB_SERVER_URL - GitHub host (default https://github.com)
#
# Arguments:
#   $1 - Message text
#   $2 - Full commit SHA (or ref) to read paths from and to link at
#
# Outputs:
#   Text with tracked paths replaced by markdown links, on stdout
#
# Returns:
#   0 always
#
# Usage:
#   text="$(linkify_repo_text "${text}" "$(git rev-parse HEAD)")"
#
#######################################
function linkify_repo_text {
    local text="${1:-}"
    local ref="${2:-}"
    local files

    if [[ -z ${text} || -z ${ref} || -z ${GITHUB_REPOSITORY:-} ]] \
        || ! files="$(git ls-tree -r --name-only "${ref}" 2> /dev/null)" || [[ -z ${files} ]]; then
        printf '%s' "${text}"
        return 0
    fi

    # shellcheck disable=SC2016 # the Python source is intentionally single-quoted
    BASE="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}" REF="${ref}" FILES="${files}" \
        python3 -I -c '
import os
import re
import sys
from urllib.parse import quote

text = sys.stdin.read()
base = os.environ["BASE"].rstrip("/")
ref = os.environ["REF"]
paths = set(os.environ["FILES"].split("\n"))
names = {}
for p in paths:
    names.setdefault(p.rsplit("/", 1)[-1], []).append(p)

NAME_EXT = re.compile(r"[\w.-]+\.(?:sh|bats|ya?ml|md|json|toml|py|go|tf|tfvars|js|ts|bash)")
SUFFIX = re.compile(r"(?:#L(\d+)(?:-L(\d+))?|:(\d+)(?:-(\d+))?)$")


def resolve(token):
    """Return (path, anchor) for a token naming a tracked file, else None."""
    anchor = ""
    m = SUFFIX.search(token)
    core = token
    if m:
        core = token[: m.start()]
        start = m.group(1) or m.group(3)
        end = m.group(2) or m.group(4)
        anchor = "#L%s" % start + ("-L%s" % end if end else "")
    core = core[2:] if core.startswith("./") else core
    if core in paths:
        return core, anchor
    if "/" not in core and NAME_EXT.fullmatch(core) and len(names.get(core, [])) == 1:
        return names[core][0], anchor
    return None


def make_link(token, label):
    hit = resolve(token)
    if hit is None:
        return None
    path, anchor = hit
    return "[%s](%s/blob/%s/%s%s)" % (label, base, ref, quote(path, safe="/"), anchor)


def link_code(match):
    inner = match.group(1)
    return make_link(inner, "`%s`" % inner) or match.group(0)


def link_plain(match):
    token = match.group(0)
    trail = ""
    while token and token[-1] in ".,;:)":
        trail = token[-1] + trail
        token = token[:-1]
    link = make_link(token, token)
    return (link + trail) if link else match.group(0)


# Priority order: existing link, URL, HTML comment, code span (handled apart).
skip = re.compile(r"(\[[^\]\n]*\]\([^)\n]*\))|(https?://[^\s<>)]+)|(<!--.*?-->)")
code = re.compile(r"`([^`\n]+)`")
plain = re.compile(
    r"(?<![\w/.:@#=\[-])(?:\./)?[A-Za-z0-9_.@+-]+(?:/[A-Za-z0-9_.@+-]+)*"
    r"(?:#L\d+(?:-L\d+)?)?(?![\w/(-])"
)
bare = re.compile(r"(?<![\w/.:@#=\[-])[\w.-]+\.(?:sh|bats|ya?ml|md|json|toml|py|go|tf|tfvars|js|ts|bash)(?![\w/(-])")


def convert_segment(seg):
    # Code spans first, so their content is not re-linked as plain text.
    out = []
    pos = 0
    for m in code.finditer(seg):
        out.append(plain_pass(seg[pos : m.start()]))
        out.append(link_code(m))
        pos = m.end()
    out.append(plain_pass(seg[pos:]))
    return "".join(out)


def plain_pass(seg):
    if "/" in seg:
        seg = plain.sub(link_plain, seg)
    return bare.sub(lambda m: link_plain(m), seg) if "." in seg else seg


def convert_line(line):
    out = []
    pos = 0
    for m in skip.finditer(line):
        out.append(convert_segment(line[pos : m.start()]))
        out.append(m.group(0))
        pos = m.end()
    out.append(convert_segment(line[pos:]))
    return "".join(out)


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
' <<< "${text}" 2> /dev/null || printf '%s' "${text}"
}
