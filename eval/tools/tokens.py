"""Token usage per eval case and per agent, from Claude Code session transcripts.

Usage:
  python eval/tools/tokens.py --ticket 20261113-eval-d4 [--split 2026-11-13T23:28:11]
         [--orchestrator <session file stem>] [--exclude <session id>] [--projects DIR]

Finds every main transcript that mentions the ticket ID, adds its helper (subagent)
transcripts, and sums the API usage of each assistant message once. The main session is
reported as "main" (the agent the session was started as, usually the architect); helpers
by their agent type. --split divides the totals into "design" (before) and "build" (after),
by message timestamp (UTC, ISO). Prints a Markdown table to paste into a run file.

Columns: calls, output tokens, fresh input (uncached input + cache writes), cache reads,
and total (all four input/output kinds). Cache reads are cheap but show context size.
"""
import argparse, glob, json, os, re, sys
from collections import defaultdict


def default_projects():
    home = os.path.expanduser("~")
    return os.path.join(home, ".claude", "projects")


def find_main(projects, ticket):
    hits = []
    for f in glob.glob(os.path.join(projects, "*", "*.jsonl")):
        with open(f, encoding="utf-8", errors="ignore") as h:
            for line in h:
                if ticket in line:
                    hits.append(f)
                    break
    return hits


def find_main_in(f, ticket):
    with open(f, encoding="utf-8", errors="ignore") as h:
        return any(ticket in line for line in h)


def tickets_in(f):
    """Distinct ticket folders a transcript works on (d365fo-work/<id>/)."""
    ids = set()
    with open(f, encoding="utf-8", errors="ignore") as h:
        for line in h:
            ids.update(re.findall(r"d365fo-work[\\/]+([0-9A-Za-z][\w.-]*?)[\\/]", line))
    return ids


def agent_type(jsonl):
    meta = jsonl[: -len(".jsonl")] + ".meta.json"
    try:
        with open(meta, encoding="utf-8") as h:
            return json.load(h).get("agentType") or "helper"
    except OSError:
        return "helper"


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--ticket", required=True)
    p.add_argument("--split", help="UTC ISO timestamp: design before, build after")
    p.add_argument("--projects", default=default_projects())
    p.add_argument("--orchestrator", action="append", default=[],
                   help="session id (file stem) that ran several cases: skip its own messages, "
                        "count only its helpers whose transcript names the ticket")
    p.add_argument("--exclude", action="append", default=[],
                   help="session id (file stem, or its first 8 characters) to leave out, e.g. a "
                        "workbench session that only mentions the ticket while scoring it")
    a = p.parse_args()

    mains = [m for m in find_main(a.projects, a.ticket)
             if not any(os.path.basename(m).startswith(x) for x in a.exclude)]
    if not mains:
        sys.exit(f"No transcript mentions {a.ticket}")

    rows = defaultdict(lambda: [0, 0, 0, 0, 0])  # calls, output, fresh, cache_read, total
    models = set()
    for m in mains:
        sid = m[:-6]
        helpers = glob.glob(os.path.join(sid, "subagents", "*.jsonl"))
        if os.path.basename(sid) in a.orchestrator:
            files = []
            for f in helpers:
                if not find_main_in(f, a.ticket):
                    continue
                who, n = agent_type(f), len(tickets_in(f))
                # One helper that worked on several tickets (e.g. one reviewer for a whole
                # batch) is shown once, marked shared, and left out of this ticket's total.
                files.append((f, f"{who} (shared, {n} tickets)" if n > 1 else who))
        else:
            files = [(m, "main")] + [(f, agent_type(f)) for f in helpers]
        for f, who in files:
            seen = set()
            with open(f, encoding="utf-8", errors="ignore") as h:
                for line in h:
                    try:
                        d = json.loads(line)
                    except ValueError:
                        continue
                    if d.get("type") != "assistant":
                        continue
                    msg = d.get("message", {})
                    u, mid = msg.get("usage"), msg.get("id")
                    if not u or mid in seen:
                        continue
                    seen.add(mid)
                    if msg.get("model", "").startswith("claude"):
                        models.add(msg["model"])
                    phase = ""
                    if a.split:
                        phase = "design" if d.get("timestamp", "") < a.split else "build"
                    i = u.get("input_tokens", 0)
                    cw = u.get("cache_creation_input_tokens", 0)
                    cr = u.get("cache_read_input_tokens", 0)
                    o = u.get("output_tokens", 0)
                    r = rows[(phase, who)]
                    for k, v in enumerate((1, o, i + cw, cr, i + cw + cr + o)):
                        r[k] += v

    print(f"Ticket `{a.ticket}` - transcripts: {', '.join(os.path.basename(m)[:8] for m in mains)}"
          f" - model: {', '.join(sorted(models)) or 'unknown'}\n")
    head = "| Phase | Agent | Calls | Output | Fresh input | Cache reads | Total |"
    print(head)
    print("|---|---|---:|---:|---:|---:|---:|")
    total = [0] * 5
    shared = False
    for (phase, who), r in sorted(rows.items(), key=lambda kv: (kv[0][0] != "design", kv[0])):
        if "(shared," in who:
            shared = True
        else:
            total = [x + y for x, y in zip(total, r)]
        print(f"| {phase or '-'} | {who} | {r[0]} | {r[1]:,} | {r[2]:,} | {r[3]:,} | {r[4]:,} |")
    print(f"| **all** | | {total[0]} | {total[1]:,} | {total[2]:,} | {total[3]:,} | {total[4]:,} |")
    if shared:
        print("\nRows marked *shared* served several tickets in one run; they are not in this "
              "ticket's total. Count them once for the batch.")


if __name__ == "__main__":
    main()
