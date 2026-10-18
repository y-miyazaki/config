#!/usr/bin/env python3
"""Print the loop input topology table and gate it against the design decisions.

Usage: python3 -I scripts/self/ci/loop_input_topology.py <repo_root>

For every workflow_call input of ci-loop-caller.yaml and ci-loop-caller-entity.yaml,
print one Markdown row: the decision-table annotation (pre-rename name, level where the
value takes effect, disposition), whether the value reaches the detect action from each
reusable, the declared default, how many on-loop-* callers set it, every downstream
layer input it flows into (`*` when an expression transforms it), the env vars it
becomes, and the action scripts that read those env vars.

The parser is indentation based (no YAML library); it reads only the shapes the loop
workflows and composite actions use.

Exit status:
  0  every input is annotated and the level-dependent inputs reach both detect actions
  1  an input has no decision-table entry, an entry names no input, or a
     level-dependent input does not reach detect from one of the reusables
  2  usage error

Design: docs/superpowers/specs/2026-10-17-loop-delivery-plan-design.md (Appendix A, section 6)
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

EXPR_RE = re.compile(r"\$\{\{(.*?)\}\}")
INPUT_REF_RE = re.compile(r"inputs\.([a-z0-9_]+)")
LOCAL_PATH_RE = re.compile(r"(\.github/(?:actions|workflows)/[^@\s]+)")

REUSABLES = {
    ".github/workflows/ci-loop-caller.yaml": "branch",
    ".github/workflows/ci-loop-caller-entity.yaml": "entity",
}
AGENT = ".github/workflows/ci-loop-agent.yaml"
SHORT = {
    ".github/workflows/ci-loop-caller.yaml": "caller",
    ".github/workflows/ci-loop-caller-entity.yaml": "entity",
    AGENT: "agent",
}
DETECT_RE = re.compile(r"^loop-(?:entity-)?detect::")

# Section 6: inputs validated by level at detect time, plus the two decision inputs.
# Each must reach detect from both reusables.
DETECT_REQUIRED = (
    "agent_edit_allowlist",
    "agent_edit_denylist",
    "agent_edit_target",
    "agent_unchanged_verdict",
    "delivery",
    "level",
)

# Decision table keyed by the current (post-rename) caller input name:
#   (pre-rename name or "—", level where the value takes effect, disposition)
#   level: "全" = all levels, "L2+" = consumed only by agent-l2 / finalize-l2
DECISIONS: dict[str, tuple[str, str, str]] = {
    "agent_branch_prefix": ("branch_prefix", "L2+", "改名"),
    "agent_checker_effort": ("—", "L2+", "変更なし"),
    "agent_checker_instructions": ("—", "L2+", "変更なし"),
    "agent_checker_max_turns": ("—", "L2+", "変更なし"),
    "agent_checker_model": ("—", "L2+", "変更なし"),
    "agent_checker_path_pattern": ("infer_files_pattern", "L2+", "改名"),
    "agent_checker_skill_name": ("—", "L2+", "変更なし。caller の既定値と同じ行を削除"),
    "agent_cli_version": ("cli_version", "全", "改名"),
    "agent_commit_message": ("commit_message", "L2+", "改名"),
    "agent_edit_allowlist": ("allowlist", "L2+", "改名。第6節で検証"),
    "agent_edit_denylist": ("denylist", "L2+", "改名。第6節で検証"),
    "agent_edit_target": ("write_target", "L2+", "改名。第6節で検証"),
    "agent_engine": ("engine", "全", "改名"),
    "agent_loop_max_attempts": ("—", "L2+", "変更なし"),
    "agent_maker_effort": ("—", "全", "変更なし"),
    "agent_maker_instructions": ("—", "全", "変更なし"),
    "agent_maker_max_turns": ("—", "全", "変更なし"),
    "agent_maker_model": ("—", "全", "変更なし"),
    "agent_maker_skill_name": ("—", "全", "変更なし"),
    "agent_tool_allowlist": ("agent_allowed_tools", "全", "改名"),
    "agent_unchanged_verdict": ("no_changes_verdict", "L2+", "改名。第6節で検証"),
    "budget_file": ("—", "全", "変更なし"),
    "budget_max_runs_per_day": ("—", "全", "変更なし"),
    "budget_max_tokens_per_day": ("—", "全", "変更なし"),
    "delivery": ("—", "全", "値を変更(第1節)。既定値を削除"),
    "detect_branch_match": ("branch_match", "全", "改名。第7-3節"),
    "detect_branch_match_mode": ("branch_match_mode", "全", "改名"),
    "detect_env_json": ("detect_domain_env_json", "全", "改名"),
    "detect_hook_script": ("dispatch_hook_script", "全", "改名"),
    "detect_max_targets": ("max_targets_per_schedule", "全", "改名"),
    "detect_pr_bot_allowlist": ("pr_include_bots", "全", "改名"),
    "detect_pr_denylist": ("pr_exclude", "全", "改名"),
    "detect_pr_enabled": ("pr_enabled", "全", "改名"),
    "detect_pr_number": ("scoped_pr_number", "全", "改名"),
    "detect_priority": ("priority", "全", "改名"),
    "detect_script": ("—", "全", "変更なし"),
    "environment": ("—", "全", "変更なし。caller の既定値と同じ行を削除"),
    "finalize_commit_paths": ("additional_commit_paths", "L2+", "改名"),
    "finalize_outcome_override": ("outcome_override", "L2+", "改名"),
    "finalize_script": ("finalize_hook_script", "L2+", "改名(投稿の配信 第1節)"),
    "level": ("—", "全", "既定値を削除"),
    "loop_name": ("—", "全", "変更なし"),
    "pr_body": ("—", "L2+", "変更なし"),
    "pr_draft": ("—", "L2+", "変更なし"),
    "pr_labels": ("labels", "L2+", "改名"),
    "pr_title": ("—", "L2+", "変更なし"),
    "run_log_file": ("—", "全", "変更なし"),
    "state_branch": ("branch_state", "全", "改名。第7-3節"),
    "state_file": ("—", "全", "変更なし"),
    "trigger_comment_ack": ("ack_trigger_comment", "全", "改名"),
}

KEY_RE = re.compile(r"\s*([A-Za-z0-9_\-]+):\s?(.*)$")
BLOCK_SCALARS = ("|", ">", "|-", ">-")


def indent(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def is_skippable(line: str) -> bool:
    return not line.strip() or line.lstrip().startswith("#")


def block_after(lines: list[str], i: int):
    """Yield (index, key, value) for the mapping directly under lines[i]."""
    base = indent(lines[i])
    child = None
    j = i + 1
    while j < len(lines):
        line = lines[j]
        if is_skippable(line):
            j += 1
            continue
        ind = indent(line)
        if ind <= base:
            break
        if child is None:
            child = ind
        if ind == child:
            m = KEY_RE.match(line)
            if m:
                value = m.group(2)
                if value in BLOCK_SCALARS:
                    k = j + 1
                    parts = []
                    while k < len(lines) and (not lines[k].strip() or indent(lines[k]) > child):
                        parts.append(lines[k].strip())
                        k += 1
                    value = " ".join(p for p in parts if p)
                yield j, m.group(1), value
        j += 1


def uses_with(lines: list[str]):
    """Yield (uses, key, value) for each `uses:` that has a sibling `with:` map."""
    for i, line in enumerate(lines):
        m = re.match(r"(\s*)(- )?uses:\s*(\S+)", line)
        if not m:
            continue
        ind = len(m.group(1)) + (2 if m.group(2) else 0)
        j = i + 1
        while j < len(lines):
            nxt = lines[j]
            if nxt.strip() and (indent(nxt) < ind or (indent(nxt) == ind - 2 and nxt.lstrip().startswith("- "))):
                break
            if indent(nxt) == ind and re.match(r"\s*with:\s*$", nxt):
                for _, key, value in block_after(lines, j):
                    yield m.group(3), key, value
                break
            j += 1


def declared_inputs(lines: list[str]):
    """Yield (name, default, required) for the first `inputs:` map in the file."""
    for i, line in enumerate(lines):
        if not re.match(r"\s*inputs:\s*$", line):
            continue
        for ln, key, _ in block_after(lines, i):
            default = required = ""
            j = ln + 1
            while j < len(lines) and (not lines[j].strip() or indent(lines[j]) > indent(lines[ln])):
                m = re.match(r"\s*default:\s*(.*)$", lines[j])
                if m:
                    default = m.group(1)
                m = re.match(r"\s*required:\s*(.*)$", lines[j])
                if m:
                    required = m.group(1)
                j += 1
            yield key, default, required
        return


def env_from_inputs(lines: list[str]):
    """Yield (ENV, input) for `ENV: ... ${{ inputs.x }} ...` lines."""
    for line in lines:
        m = re.match(r"\s*([A-Z][A-Z0-9_]*):\s*(.*)$", line)
        if not m:
            continue
        for expr in EXPR_RE.findall(m.group(2)):
            for name in INPUT_REF_RE.findall(expr):
                yield m.group(1), name


def target_of(uses: str) -> str | None:
    """Map a `uses:` value to a repo-relative definition path, or None when not local."""
    m = LOCAL_PATH_RE.search(uses)
    if not m:
        return None
    path = m.group(1)
    if path.startswith(".github/actions/") and not path.endswith("action.yml"):
        path = path.rstrip("/") + "/action.yml"
    return path


def short(path: str) -> str:
    if path in SHORT:
        return SHORT[path]
    m = re.match(r"\.github/actions/([^/]+)/action\.yml$", path)
    return m.group(1) if m else path


class Topology:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.cache: dict[str, list[str]] = {}
        actions = sorted(str(p.relative_to(root)) for p in root.glob(".github/actions/loop-*/action.yml"))
        self.files = [*REUSABLES, AGENT, *actions]
        self.edges: dict[tuple[str, str], list[tuple[str, str, bool]]] = {}
        self.envs: dict[tuple[str, str], list[str]] = {}
        self.readers_cache: dict[tuple[str, str], list[str]] = {}
        for src in self.files:
            lines = self.lines(src)
            for uses, key, value in uses_with(lines):
                dst = target_of(uses)
                if dst is None:
                    continue
                for expr in EXPR_RE.findall(value):
                    for name in set(INPUT_REF_RE.findall(expr)):
                        plain = value.strip() == "${{ inputs." + name + " }}"
                        self.edges.setdefault((src, name), []).append((dst, key, plain))
            for env, name in env_from_inputs(lines):
                self.envs.setdefault((src, name), []).append(env)

    def lines(self, rel: str) -> list[str]:
        if rel not in self.cache:
            path = self.root / rel
            self.cache[rel] = path.read_text(encoding="utf-8").splitlines() if path.is_file() else []
        return self.cache[rel]

    def readers(self, env: str, src: str) -> list[str]:
        key = (env, src)
        if key in self.readers_cache:
            return self.readers_cache[key]
        dirs = [self.root / ".github/actions/lib/loop"]
        m = re.match(r"(\.github/actions/[^/]+)/action\.yml$", src)
        if m:
            dirs.insert(0, self.root / m.group(1))
        pattern = re.compile(r"\$\{?" + re.escape(env) + r"\b")
        found = set()
        for base in dirs:
            for dirpath, _, filenames in os.walk(base):
                for filename in filenames:
                    if not filename.endswith(".sh"):
                        continue
                    path = Path(dirpath) / filename
                    if pattern.search(path.read_text(encoding="utf-8", errors="replace")):
                        found.add(str(path.relative_to(self.root)).replace(".github/actions/", ""))
        self.readers_cache[key] = sorted(found)
        return self.readers_cache[key]

    def walk(self, node: tuple[str, str], seen: set, hops: list, envs: set, reads: set) -> None:
        src, _ = node
        for env in self.envs.get(node, []):
            envs.add(f"{short(src)}:{env}")
            reads.update(self.readers(env, src))
        for dst, key, plain in sorted(self.edges.get(node, [])):
            hops.append(f"{short(dst)}::{key}" + ("" if plain else "*"))
            nxt = (dst, key)
            if nxt not in seen:
                self.walk(nxt, seen | {nxt}, hops, envs, reads)


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: loop_input_topology.py <repo_root>", file=sys.stderr)
        return 2
    root = Path(argv[1])
    topo = Topology(root)

    declared: dict[str, dict[str, str]] = {}
    for path, kind in REUSABLES.items():
        lines = topo.lines(path)
        if not lines:
            print(f"error: missing {path}", file=sys.stderr)
            return 1
        for name, default, required in declared_inputs(lines):
            if required == "true":
                cell = "必須"
            else:
                cell = default if default not in ("", '""') else '""'
            declared.setdefault(name, {})[kind] = cell

    usage: dict[str, int] = {}
    for caller in sorted(root.glob(".github/workflows/on-loop-*.yaml")):
        lines = caller.read_text(encoding="utf-8").splitlines()
        for uses, key, _ in uses_with(lines):
            if "ci-loop-caller" in uses:
                usage[key] = usage.get(key, 0) + 1

    errors: list[str] = []
    rows: list[str] = []
    cell = lambda xs: "<br>".join(f"`{x}`" for x in xs) or "—"  # noqa: E731
    for name in sorted(declared):
        hops: list[str] = []
        envs: set[str] = set()
        reads: set[str] = set()
        reach: dict[str, str] = {}
        for path, kind in REUSABLES.items():
            if kind not in declared[name]:
                reach[kind] = "—"
                continue
            mine: list[str] = []
            topo.walk((path, name), {(path, name)}, mine, envs, reads)
            hops += mine
            reach[kind] = "はい" if any(DETECT_RE.match(h) for h in mine) else "いいえ"
            if name in DETECT_REQUIRED and reach[kind] != "はい":
                errors.append(f"{name} does not reach detect from {Path(path).name}")
        if name not in DECISIONS:
            errors.append(f"no decision-table entry: {name}")
            old, effect, disposition = "?", "?", "?"
        else:
            old, effect, disposition = DECISIONS[name]
        oldc = "—" if old == "—" else f"`{old}`"
        rows.append(
            f"| `{name}` | {oldc} | {effect} | {disposition} | {reach['branch']} | {reach['entity']} "
            f"| {declared[name].get('branch', '—')} | {declared[name].get('entity', '—')} | {usage.get(name, 0)} "
            f"| {cell(sorted(set(hops)))} | {cell(sorted(envs))} | {cell(sorted(reads))} |"
        )
    for name in sorted(set(DECISIONS) - set(declared)):
        errors.append(f"decision-table entry names no caller input: {name}")
    for name in DETECT_REQUIRED:
        if name not in declared:
            errors.append(f"{name} is not a caller input")

    print(
        "| caller の入力 | 旧い名前 | 効く `level` | 処置 | detect に届く(branch) | detect に届く(entity) "
        "| branch | entity | 設定する caller 数 | 流れる先(層::入力。`*` は式で加工) | 環境変数 | 読むスクリプト |"
    )
    print("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    print("\n".join(rows))
    for err in errors:
        print(f"error: {err}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
