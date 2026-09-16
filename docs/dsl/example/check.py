#!/usr/bin/env python3
"""Prototype checks for the flipped binding: the workflow names the
tiers, the chain names nothing in the workflow. Derives each tier's
effective context from the edges, resolves which type serves each
flow, checks that the type's positions cover the flow's tiers (exactly
once, bar a cascade_visit tier), runs the traversability rule over the
resulting order, and
measures both files against the acceptance number. Read-only; prints.
"""
import re, sys, yaml

chain = yaml.safe_load(open("chain.yaml"))
wf = yaml.safe_load(open("workflow.yaml"))
tiers, edges = chain["tiers"], chain["edges"]
errors = []


def fail(msg):
    errors.append(msg)
    print(f"  LOAD ERROR: {msg}")


def parent_of(t):
    m = re.match(r"(?:per|child_of)\((\w+)\)", str(tiers[t].get("scope", "")))
    return m.group(1) if m else None


def kind(t):
    """live: a tier is supplied, a join target, or generating."""
    v = tiers[t] or {}
    if v.get("generator") == "supplied":
        return "supplied"
    if v.get("draft") == "none":
        return "join"
    return "generating"


gen = [t for t in tiers if kind(t) == "generating"]

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
                fail(f"{t}: two derived reads named {var!r}; the instance needs `as:`")
            out[var] = walk
    return out


n_derived = n_explicit = 0
print("== effective context (derived, then explicit) ==")
for t in gen:
    d, x = derived(t), (tiers[t] or {}).get("context", {})
    n_derived += len(d)
    n_explicit += len(x)
    if t in ("comparch", "subcomparch", "screen_collarch"):
        print(f"-- {t}")
        for k, v in d.items():
            print(f"   {k:20} {v}   [derived]")
        for k, v in x.items():
            print(f"   {k:20} {v}   [explicit]")
print(f"generating tiers {len(gen)}: derived reads {n_derived}, explicit reads {n_explicit}")

# ---- the workflow's half of the binding --------------------------------
def layout(type_name):
    """(position order, tier -> position index) for one type."""
    flat = []
    for e in wf["types"][type_name]["statuses"]:
        flat += e if isinstance(e, list) else [e]
    order, tier_at = {}, {}
    for i, e in enumerate(flat):
        if "status" not in e:
            continue
        order.setdefault(e.get("name") or e["status"], i)
        for t in e.get("tiers", []):
            if t not in tiers:
                fail(f"{type_name}: position {e.get('name')!r} names {t!r}, not a tier")
            elif kind(t) != "generating":
                fail(f"{type_name}: position {e.get('name')!r} names {t!r}, a {kind(t)} tier")
            if t in tier_at:
                # chain.md #40: a cascade_visit tier rests at each plan
                # position; every other tier sits at exactly one.
                if str((tiers.get(t) or {}).get("scope")) != "cascade_visit":
                    fail(f"{type_name}: {t!r} is listed at two positions")
                continue  # ordering uses the earliest; per-position
                          # drainage is the flow engine's (chain.md #40)
            tier_at[t] = i
    return order, tier_at


def has_delta(flow):
    d = flow.get("delta") or {}
    return bool(d.get("tiers") or d.get("edges"))


def serving_type(fname, flow):
    """A type naming this flow outright beats one matching by predicate."""
    named = [n for n, t in wf["types"].items() if isinstance(t.get("serves"), list) and fname in t["serves"]]
    if len(named) > 1:
        fail(f"flow {fname!r} is claimed outright by {named}")
    if named:
        return named[0]
    want = "has_delta" if has_delta(flow) else "no_delta"
    match = [n for n, t in wf["types"].items() if t.get("serves") == want]
    if len(match) != 1:
        fail(f"flow {fname!r} ({want}) is served by {match or 'no type'}")
    return match[0] if len(match) == 1 else None


# ---- traversability -----------------------------------------------------
def reads(t):
    """(structural, global): structural reads walk from self or the
    parent inside this traversal; global reads (`all.<tier>`) read the
    project's approved state as of dispatch and are ordered only as a
    note, since a flow's plan tier reads the graph it is about to
    regenerate (ORC-247, review 5)."""
    structural, global_ = set(), set()
    for w in list((tiers[t] or {}).get("context", {}).values()):
        m = re.match(r"all\.(\w+)\.", w)
        if m:
            global_.add(m.group(1))
            continue
        for m in re.finditer(r"-> (\w+)\.", w):
            structural.add(m.group(1))
    for v in derived(t).values():
        m = re.search(r"-> (\w+)\.", v)
        if m:
            structural.add(m.group(1))
    p = parent_of(t)
    if p:
        structural.add(p)
    return structural, global_


def generating_ancestor(node):
    """A join target's position is its minting tier's; a supplied tier has none."""
    seen = set()
    while node in tiers and node not in seen and kind(node) != "generating":
        seen.add(node)
        node = next((i["source"] for e in edges.values() for i in e["instances"]
                     if e["type"] == "fanout" and i["target"] == node), None)
    return node if node in tiers and kind(node) == "generating" else None


# ---- depth, computed from the tiers a position lists (workflow.md #28)
_per = {}
for _t, _v in tiers.items():
    _m = re.match(r"per\((\w+)\)", str((_v or {}).get("scope", "")))
    if _m:
        _per.setdefault(_m.group(1), []).append(_t)
spawning = {(i["source"], i["target"])
            for e in edges.values() if e.get("type") == "fanout"
            for i in e["instances"]
            if any(kind(k) == "generating" for k in _per.get(i["target"], []))}
scope_parent = {}
for t, v in tiers.items():
    m = re.match(r"(?:per|child_of)\((\w+)\)", str((v or {}).get("scope", "")))
    if m:
        scope_parent[t] = m.group(1)


def depth(t, seen=()):
    """chain.md #42: a level is a fan-out whose target something generates from."""
    if t in seen or t not in scope_parent:
        return 0
    p = scope_parent[t]
    return depth(p, seen + (t,)) + (1 if (p, t) in spawning else 0)


print("\n== depth ==")
print(f"  ticket-spawning fan-outs: {len(spawning)} of "
      f"{sum(len(e['instances']) for e in edges.values() if e.get('type') == 'fanout')}"
      f"  -> {sorted(t for _, t in spawning)}")

print("\n== the binding ==")
all_delta = {x for f in chain["flows"].values() for x in (f.get("delta") or {}).get("tiers", [])}
layouts = {n: layout(n) for n in wf["types"] if any(
    "tiers" in s for e in wf["types"][n]["statuses"] for s in (e if isinstance(e, list) else [e]))}
for n, (order, tier_at) in layouts.items():
    print(f"  type {n}: {len(order)} positions, {len(tier_at)} tiers listed")
    flat = []
    for e in wf["types"][n]["statuses"]:
        flat += e if isinstance(e, list) else [e]
    for e in flat:
        if "tiers" not in e:
            continue
        cascade = [t for t in e["tiers"]
                   if str((tiers.get(t) or {}).get("scope")) == "cascade_visit"]
        own = {depth(t) for t in e["tiers"] if t not in cascade}
        # workflow.md #28: a position runs from depth 0 to its deepest tier —
        # shallower tickets stand there to receive what merges from below.
        ds = list(range(0, max(own) + 1)) if own else []
        shown = f"{ds}  (own work at {sorted(own)})" if own else "follows the position it precedes"
        print(f"     {e.get('name'):22} depths {shown}")

print("\n== traversability ==")
notes = []
for fname, flow in chain["flows"].items():
    tname = serving_type(fname, flow)
    if not tname:
        continue
    order, tier_at = layouts[tname]
    active = (set(gen) - all_delta) | set((flow.get("delta") or {}).get("tiers", []))
    for t in sorted(active):
        if t not in tier_at:
            fail(f"{fname} -> {tname}: {t!r} runs in this flow and no position lists it")
            continue
        structural, global_ = reads(t)
        for r in structural:
            ga = generating_ancestor(r)
            if ga and ga in active and ga in tier_at and tier_at[ga] > tier_at[t]:
                fail(f"{fname} -> {tname}: {t} reads {r}, generated at a later position")
        for r in global_:
            ga = generating_ancestor(r)
            if ga and ga in active and ga in tier_at and tier_at[ga] > tier_at[t]:
                notes.append(f"{fname} -> {tname}: {t} reads all.{r}, regenerated later")
    unfilled = [p for p, i in order.items()
                if i in {tier_at[t] for t in tier_at} and not (
                    {t for t, j in tier_at.items() if j == i} & active)]
    print(f"  {fname} -> {tname}: {len(active)} tiers, positions unfilled: {unfilled or 'none'} (warning only)")
print(f"load errors: {len(errors)}")
for n in notes:
    print("  note:", n)

# ---- measurement ------------------------------------------------------
print("\n== measurement ==")
for f, limit in (("chain.yaml", 800), ("workflow.yaml", 240)):
    lines = open(f).read().splitlines()
    comments = sum(1 for l in lines if l.strip().startswith("#"))
    print(f"  {f}: {len(lines)} lines (limit {limit}), {comments} comment lines ({100*comments//len(lines)}%)")
sys.exit(1 if errors else 0)
