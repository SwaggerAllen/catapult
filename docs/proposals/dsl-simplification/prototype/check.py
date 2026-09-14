#!/usr/bin/env python3
"""Prototype checks: derive each tier's effective context from the
edges, run the traversability rule for each flow/type pairing, and
measure both files against the acceptance number. Read-only; prints."""
import re, sys, yaml

chain = yaml.safe_load(open("chain.yaml"))
wf = yaml.safe_load(open("workflow.yaml"))
tiers, edges = chain["tiers"], chain["edges"]

def parent_of(t):
    m = re.match(r"(?:per|child_of)\((\w+)\)", str(tiers[t].get("scope", "")))
    return m.group(1) if m else None

# ---- effective context ------------------------------------------------
def derived(t):
    out = {}
    p = parent_of(t)
    if p:
        out["parent"] = f"self.parent.handle  ({p})"
    for ename, e in edges.items():
        for inst in e["instances"]:
            proj = inst.get("context", e.get("context"))
            if proj in (None, "none"):
                continue
            src, var = inst["source"], inst.get("as", ename)
            if src == t:
                walk = f"self.{ename} -> {inst['target']}.{proj}"
            elif p and src == p:
                walk = f"self.parent.{ename} -> {inst['target']}.{proj}"
            else:
                continue
            if var in out:
                print(f"  LOAD ERROR: {t}: two derived reads named {var!r}; the instance needs `as:`")
            out[var] = walk
    return out

gen = [t for t, v in tiers.items() if "phase" in v]
n_derived = n_explicit = 0
print("== effective context (derived, then explicit) ==")
for t in gen:
    d, x = derived(t), tiers[t].get("context", {})
    n_derived += len(d); n_explicit += len(x)
    if t in ("comparch", "subcomparch", "screen_collarch"):
        print(f"-- {t}")
        for k, v in d.items(): print(f"   {k:20} {v}   [derived]")
        for k, v in x.items(): print(f"   {k:20} {v}   [explicit]")
print(f"generating tiers {len(gen)}: derived reads {n_derived}, explicit reads {n_explicit}")

# ---- traversability -----------------------------------------------------
def positions(type_name):
    flat, order = [], {}
    for e in wf["types"][type_name]["statuses"]:
        flat += e if isinstance(e, list) else [e]
    for i, e in enumerate(flat):
        if "status" in e:
            order[e.get("name") or e["status"]] = i
    return order

def reads(t):
    """(structural, global): structural reads walk from self or the
    parent inside this traversal; global reads (`all.<tier>`) read the
    project's approved state as of dispatch and are ordered only as a
    note, since a flow's plan tier reads the graph it is about to
    regenerate (in-flight-tickets.md, ORC-247 review 5)."""
    structural, global_ = set(), set()
    for w in list(tiers[t].get("context", {}).values()):
        m = re.match(r"all\.(\w+)\.", w)
        if m: global_.add(m.group(1)); continue
        for m in re.finditer(r"-> (\w+)\.", w): structural.add(m.group(1))
    for v in derived(t).values():
        m = re.search(r"-> (\w+)\.", v)
        if m: structural.add(m.group(1))
    p = parent_of(t)
    if p: structural.add(p)
    return structural, global_

def generating_ancestor(node):
    """A join target's position is its minting tier's; a supplied tier has none."""
    seen = set()
    while node and node not in seen and "phase" not in tiers.get(node, {}):
        seen.add(node)
        node = next((i["source"] for e in edges.values() for i in e["instances"]
                     if e["type"] == "fanout" and i["target"] == node), None)
    return node if node in tiers and "phase" in tiers[node] else None

print("\n== traversability ==")
problems, notes = 0, []
for fname, flow in chain["flows"].items():
    tname = flow["ticket"]["type"]
    order = positions(tname)
    active = set(gen) - {x for f in chain["flows"].values() for x in f.get("delta", {}).get("tiers", [])} \
             | set(flow.get("delta", {}).get("tiers", []))
    for t in sorted(active):
        ph = tiers[t]["phase"]
        if ph not in order:
            print(f"  {fname}/{tname}: {t} names phase {ph!r}, not in type"); problems += 1; continue
        structural, global_ = reads(t)
        for r in structural:
            ga = generating_ancestor(r)
            if ga and ga in active and order[tiers[ga]["phase"]] > order[ph]:
                print(f"  {fname}/{tname}: {t}@{ph} reads {r} (position {tiers[ga]['phase']}, later)"); problems += 1
        for r in global_:
            ga = generating_ancestor(r)
            if ga and ga in active and order[tiers[ga]["phase"]] > order[ph]:
                notes.append(f"{fname}/{tname}: {t}@{ph} reads all.{r}, regenerated later at {tiers[ga]['phase']}")
    unfilled = [p for p, i in order.items() if p not in {tiers[t]["phase"] for t in active}
                and p not in ("critique", "checks", "reconcile", "merge", "deploy", "terminal")]
    print(f"  {fname} -> {tname}: {len(active)} tiers, positions unfilled: {unfilled or 'none'} (warning only)")
print(f"traversability problems: {problems}")
for n in notes: print("  note:", n)

# ---- measurement ------------------------------------------------------
print("\n== measurement ==")
for f, limit in (("chain.yaml", 800), ("workflow.yaml", 240)):
    lines = open(f).read().splitlines()
    comments = sum(1 for l in lines if l.strip().startswith("#"))
    print(f"  {f}: {len(lines)} lines (limit {limit}), {comments} comment lines ({100*comments//len(lines)}%)")
