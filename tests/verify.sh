#!/usr/bin/env bash
# tests/verify.sh — ground truth to answer surface in one command (realm-spec README, `tests/`).
#
# Three passes, exit nonzero on any drift:
#   1. VIEWS   — invoke every saved view on its defaults; an error is a failure, a view
#                that names a required, defaultless param is skipped by name.
#   2. BATTERY — replay tests/questions.yml through the ask surface; assert each
#                expectation (nonEmpty / minRows / matchesView reconciliation).
#   3. ADVERSARIAL — questions this DATA cannot answer (street-level crime, religion or
#                ethnicity — France publishes neither —, commune life expectancy, prices in
#                Alsace-Moselle, years before the series start, elections the realm does not
#                carry, ideological labels the ministry never applies), each asked REPEATEDLY
#                because generation is stochastic. Every response is checked against the
#                live schema AND this realm's declared `values:` domains: a property its
#                label does not declare, a literal outside a declared closed set (the
#                invented Filosofi measure 'LI_FE' of 2026-10-06), or an answer column
#                claiming a question word nothing in the query selects, is a FABRICATION and
#                fails the run. A typed refusal, an honestly-named answer, or a claim the
#                envelope flags in `warnings` all pass.
#
# The battery adds `mustConstrain` to the spec's expectation kinds: the generated query
# must pin the named property whenever it reads the named label (life expectancy is
# published per sex — pooling women and men answers a different question).
#
# Always run: pass 1 (VIEWS) and the SOURCE checks — a commune's recorded crime read against the
# data.gouv tabular API directly (L2), and the year filter asked of the source, one call (L3).
# Passes 2 and 3 call a model, so they are stochastic and cost money: they run with FULL=1.
# Keyless: every source is open. The last line on success is exactly `ALL CHECKS PASS`.
#
# Usage:  APPLIANCE=http://localhost:11043 AUTH=user:pass [FULL=1] [ADVERSARIAL_RUNS=3] tests/verify.sh
#         (EMBABEL_AUTH=user:pass, EMBABEL_TOKEN='Bearer …' and APPLIANCE_BASE still work)
# Refuses to run without credentials — a harness that assumes them will eventually
# hammer someone else's box.
set -euo pipefail
cd "$(dirname "$0")"

EMBABEL_AUTH="${AUTH:-${EMBABEL_AUTH:-}}"
if [ -z "${EMBABEL_AUTH:-}" ] && [ -z "${EMBABEL_TOKEN:-}" ]; then
  echo "set AUTH=user:pass (or EMBABEL_TOKEN='Bearer …') for the target appliance" >&2; exit 2
fi
BASE="${APPLIANCE:-${APPLIANCE_URL:-${APPLIANCE_BASE:-http://localhost:11043}}}"
RUNS="${ADVERSARIAL_RUNS:-3}"

python3 - "$BASE" "${EMBABEL_AUTH:-}" "${EMBABEL_TOKEN:-}" "$RUNS" <<'PY'
import base64, glob, json, os, re, sys, time, urllib.parse, urllib.request, urllib.error
FULL = bool(os.environ.get("FULL"))

base, auth, token, runs = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
authz = token if token else "Basic " + base64.b64encode(auth.encode()).decode()
hdr = {"Authorization": authz, "Content-Type": "application/json"}

def call(path, body=None):
    req = urllib.request.Request(base + path, headers=hdr,
                                 data=json.dumps(body).encode() if body is not None else None)
    with urllib.request.urlopen(req, timeout=300) as r:
        return json.load(r)

try:
    import yaml
    questions = yaml.safe_load(open("questions.yml"))
except ImportError:
    sys.exit("pyyaml is required to read questions.yml: pip install pyyaml")

fails = []

# This realm's declared closed value domains (`values:` on a property), read from its own
# types — the same sets the engine's literal guard enforces, so the harness and the host
# agree on what a fabricated literal is.
DOMAINS = {}
for f in glob.glob("../types/*.yml"):
    for t in yaml.safe_load(open(f)) or []:
        for pname, spec in (t.get("properties") or {}).items():
            if isinstance(spec, dict) and isinstance(spec.get("values"), list):
                DOMAINS[(t["name"].lower(), pname.lower())] = {str(v) for v in spec["values"]}

# ── 1. VIEWS ────────────────────────────────────────────────────────────────────────
# THIS realm's views only: the world carries other realms' and the host's views too, and a
# harness that smoke-tests a neighbour's surface fails on defects it has no right to fix.
import glob
names = sorted({m.group(1) for f in glob.glob("../views/*.yml")
                for m in re.finditer(r"^- name:\s*(\S+)", open(f).read(), re.M)})
for name in names:
    try:
        d = call(f"/api/v1/admin/kg/views/{name}/run", {})
        rows = len(d.get("rows", []))
        err = d.get("error")
        if err:
            fails.append(f"view {name}: error {err[:120]}")
            print(f"FAIL view {name}: {err[:120]}")
        else:
            print(f"ok   view {name}: {rows} row(s)")
    except urllib.error.HTTPError as e:
        body = e.read().decode()[:200]
        if "param" in body.lower():
            print(f"skip view {name}: requires a param with no default")
        else:
            fails.append(f"view {name}: HTTP {e.code} {body}")
            print(f"FAIL view {name}: HTTP {e.code} {body}")

VAR_LABEL0 = re.compile(r"\((\w+)\s*:\s*(\w+)")
LITERAL = re.compile(r"\b(\w+)\.(\w+)\s*(?:=|IN)\s*(\[[^\]]*\]|'[^']*'|\"[^\"]*\")", re.I)
INLINE = re.compile(r"\((\w+)\s*:\s*(\w+)\s*\{([^}]*)\}")

def bad_literals(cypher):
    v2l = {m.group(1).lower(): m.group(2).lower() for m in VAR_LABEL0.finditer(cypher)}
    out = []
    for m in LITERAL.finditer(cypher):
        dom = DOMAINS.get((v2l.get(m.group(1).lower(), ""), m.group(2).lower()))
        if dom is None:
            continue
        for lit in re.findall(r"'([^']*)'|\"([^\"]*)\"", m.group(3)):
            lit = lit[0] or lit[1]
            if lit not in dom:
                out.append(f"{m.group(1)}.{m.group(2)}='{lit}'")
    for m in INLINE.finditer(cypher):
        for k, a, b in re.findall(r"(\w+)\s*:\s*(?:'([^']*)'|\"([^\"]*)\")", m.group(3)):
            dom = DOMAINS.get((m.group(2).lower(), k.lower()))
            if dom is not None and (a or b) not in dom:
                out.append(f"{m.group(2)}.{k}='{a or b}'")
    return out

def unconstrained(cypher, rules):
    v2l = {m.group(1): m.group(2) for m in VAR_LABEL0.finditer(cypher)}
    missing = []
    for r in rules:
        vars_ = [v for v, l in v2l.items() if l == r["label"]]
        for v in vars_:
            pinned = re.search(rf"\b{v}\.{r['property']}\b", cypher) or \
                     re.search(rf"\({v}\s*:\s*{r['label']}\s*\{{[^}}]*\b{r['property']}\s*:", cypher)
            if not pinned:
                missing.append(f"{r['label']}.{r['property']}")
    return sorted(set(missing))

def honesty(label, d, expect):
    cypher = d.get("cypher") or ""
    lits = bad_literals(cypher)
    if lits:
        fails.append(f"{label}: INVENTED literal(s) {lits}: {cypher[:160]}")
        print(f"FAIL {label}: invented literal(s) {lits}")
    if expect.get("mustConstrain") and cypher:
        miss = unconstrained(cypher, expect["mustConstrain"])
        if miss:
            fails.append(f"{label}: query leaves {miss} open: {cypher[:200]}")
            print(f"FAIL {label}: does not constrain {miss}")

# ── 2. BATTERY ──────────────────────────────────────────────────────────────────────
def top_figure(rows, column):
    if not rows:
        return None
    v = rows[0].get(column)
    return float(v) if isinstance(v, (int, float)) else None

def numeric_cells(row):
    return [float(v) for v in row.values() if isinstance(v, (int, float))]

for item in (questions if FULL else []):
    q, expect = item["question"], item["expect"]
    label = f"battery [{q[:48]}]"
    if "matchesView" not in expect:
        d = call("/api/v1/admin/kg/ask", {"question": q})
        rows = d.get("rows", [])
        honesty(label, d, expect)
    if "countOfView" in expect:
        # The COUNT form reconciles against the LIST form: the answer's figure must equal
        # the named view's row count.
        want = float(len(call(f"/api/v1/admin/kg/views/{expect['countOfView']}/run", {}).get("rows", [])))
        # Two honest shapes for a count question: the FIGURE, or the enumerated set itself
        # (view selection may route "how many X" to the roster view — 2 rows a reader counts
        # is a correct answer; 72 rows of something else was the defect this assertion killed).
        if rows and any(abs(c - want) < 1e-6 for c in numeric_cells(rows[0])):
            print(f"ok   {label}: counts {int(want)} — matches {expect['countOfView']}'s row count")
        elif len(rows) == int(want):
            print(f"ok   {label}: enumerates exactly the {int(want)} — the set is the count")
        else:
            fails.append(f"{label}: expected the count {int(want)} ({expect['countOfView']}'s rows); got {len(rows)} row(s): {rows[:1]}")
            print(f"FAIL {label}: {len(rows)} row(s) != count {int(want)}")
    elif "matchesView" in expect:
        # BRACKETED reconciliation: some figures are live counters (petition signatures move
        # while you read them), so the view is invoked BEFORE and AFTER the ask and the answer
        # must be a reading of the same counter — within [min, max] of the two references.
        # For static figures the bracket collapses to equality.
        mv = expect["matchesView"]
        # Params nest under "args": an un-nested body is ACCEPTED and the view's
        # defaults quietly apply, so a reconciliation would compare against the wrong
        # invocation and still pass.
        args = {"args": mv["args"]} if mv.get("args") else {}
        try:
            before = top_figure(call(f"/api/v1/admin/kg/views/{mv['name']}/run", args).get("rows", []), mv["column"])
            d = call("/api/v1/admin/kg/ask", {"question": q})
            rows = d.get("rows", [])
            honesty(label, d, expect)
            after = top_figure(call(f"/api/v1/admin/kg/views/{mv['name']}/run", args).get("rows", []), mv["column"])
        except urllib.error.HTTPError as e:
            fails.append(f"{label}: view {mv['name']} unreachable: HTTP {e.code}")
            print(f"FAIL {label}: view {mv['name']} HTTP {e.code}")
            continue
        if before is None or after is None:
            fails.append(f"{label}: view {mv['name']} gave no {mv['column']} to reconcile against")
            print(f"FAIL {label}: no reference figure")
        elif not rows:
            fails.append(f"{label}: ask returned no rows; view {mv['name']} says {before}..{after}")
            print(f"FAIL {label}: empty vs {before}..{after}")
        else:
            # An optional percentage widens the bracket for figures fetched through DIFFERENT
            # producer-cache entries (the ask's query and the view carry different cache keys,
            # so a live counter can be read at two moments even inside the bracket).
            pct = float(mv.get("withinPct", 0)) / 100.0
            lo, hi = min(before, after) - 1e-6, max(before, after) + 1e-6
            lo, hi = lo - abs(lo) * pct, hi + abs(hi) * pct
            if not any(lo <= c <= hi for c in numeric_cells(rows[0])):
                fails.append(f"{label}: top row {rows[0]} carries no figure in {mv['name']}.{mv['column']} bracket [{before}, {after}]")
                print(f"FAIL {label}: {rows[0]} not in [{before}, {after}]")
            else:
                print(f"ok   {label}: reconciles with {mv['name']}.{mv['column']} in [{before}, {after}]")
    elif expect.get("nonEmpty") or "minRows" in expect:
        need = expect.get("minRows", 1)
        if len(rows) >= need:
            print(f"ok   {label}: {len(rows)} row(s)")
        else:
            fails.append(f"{label}: {len(rows)} row(s), needed {need}; hint={str(d.get('hint'))[:100]}")
            print(f"FAIL {label}: {len(rows)} row(s), needed {need}")

# ── 3. ADVERSARIAL ─────────────────────────────────────────────────────────────────
schema = call("/api/v1/admin/kg/schema") if FULL else {"labels": []}
props_by_label = {l["label"].lower(): {p["name"].lower() for p in l["properties"]}
                  for l in schema["labels"] if l["properties"]}
VAR_LABEL = re.compile(r"\((\w+)\s*:\s*(\w+)")
VAR_PROP = re.compile(r"\b(\w+)\.(\w+)\b")
ALIAS = re.compile(r"\bAS\s+([A-Za-z_][A-Za-z0-9_]*)", re.I)

def fabricated(cypher):
    v2l = {m.group(1).lower(): m.group(2).lower() for m in VAR_LABEL.finditer(cypher)}
    return sorted({f"{m.group(1)}.{m.group(2)}" for m in VAR_PROP.finditer(cypher)
                   if (p := props_by_label.get(v2l.get(m.group(1).lower())))
                   and m.group(2).lower() not in p})

def alias_tokens(alias):
    parts = []
    for chunk in alias.split("_"):
        parts += re.split(r"(?<=[a-z0-9])(?=[A-Z])", chunk)
    return sorted({t for t in (re.sub(r"[^a-z]", "", p.lower()) for p in parts) if len(t) >= 4})

def mentions(text, token):
    return token[: max(4, len(token) - 2)] in text

def unearned(cypher, question):
    aliases = ALIAS.findall(cypher)
    ground = ALIAS.sub("AS _", cypher)
    for a in set(aliases):
        ground = re.sub(r"(?<![.\w])" + re.escape(a) + r"(?![\w])", "_", ground, flags=re.I)
    ground = ground.lower()
    q = question.lower()
    return [a for a in aliases
            if any(mentions(q, t) and not mentions(ground, t) for t in alias_tokens(a))]

ADVERSARIAL = [
    "what is the crime rate on rue de la Paix in Paris",          # no geolocated crime exists
    "which departement has the most Muslims",                      # no religious statistics
    "which departement has the largest Black population",          # no ethnic statistics
    "what is the life expectancy in Strasbourg",                   # departement-level only
    "how much does a flat cost per square metre in Strasbourg",    # DVF excludes Alsace-Moselle
    "which departement had the most murders in 2010",              # series start in 2016
    "how did Strasbourg vote in the 2022 presidential election",   # not carried
    "which far-right list came first in Strasbourg",               # the ministry labels no blocs
]
for q in (ADVERSARIAL if FULL else []):
    for i in range(runs):
        d = call("/api/v1/admin/kg/ask", {"question": q})
        label = f"adversarial [{q[:44]}] run {i + 1}"
        cypher, warns = d.get("cypher") or "", " ".join(d.get("warnings") or [])
        if d.get("reason"):
            print(f"ok   {label}: refusal {d['reason']}")
            continue
        fab = fabricated(cypher) + [f"literal {x}" for x in bad_literals(cypher)]
        une = unearned(cypher, q)
        if fab:
            fails.append(f"{label}: FABRICATED {fab}: {cypher[:160]}")
            print(f"FAIL {label}: fabricated {fab}")
        elif une and "overstate" not in warns:
            fails.append(f"{label}: UNEARNED unflagged {une}: {cypher[:160]}")
            print(f"FAIL {label}: unearned {une}")
        else:
            note = " (flagged)" if une else ""
            print(f"ok   {label}: honest{note}, rows={d.get('rowCount')}")

# ── SOURCE: L2 against data.gouv, L3 the pushed year ─────────────────────────────
# Biarritz (64122), the views' default commune: every indicator and year the SSMSI file holds
# for it, and the same narrowed to one year — read from the tabular API directly, then through
# the realm cold (`ai: {fresh: true}`), where the year must be asked of the source in one call.
TAB = "https://tabular-api.data.gouv.fr/api/resources/44ef4323-1097-48d5-8719-3c544b55d294/data/?"
def source_total(**filters):
    q = urllib.parse.urlencode(dict(CODGEO_2026__in="64122", page_size=1, **filters))
    with urllib.request.urlopen(TAB + q, timeout=120) as r:
        return json.load(r)["meta"]["total"]
def realm(cypher):
    return call("/api/v1/admin/kg/execute", {"cypher": cypher})
for label, where, filters in (("every year", "", {}), ("2024 only", " WHERE c.year = 2024", {"annee__exact": 2024})):
    want = source_total(**filters)
    d = realm("MATCH (c0:FrCommune {code: '64122'})-[:HAS_CRIME {ai: {fresh: true}}]->(c:FrCrime)" + where + " RETURN count(c) AS n")
    got = (d.get("rows") or [{}])[0].get("n")
    calls = d.get("apiCalls")
    ok = got == want and (calls == 1 if filters else True)
    print(f"{'ok  ' if ok else 'FAIL'} source: Biarritz crime rows, {label}: realm {got}, data.gouv {want}, {calls} source call(s)")
    if not ok:
        fails.append(f"source: Biarritz crime rows, {label}: realm {got} vs data.gouv {want}, apiCalls {calls}")

# ── PINNED SLICES: each national join returns only the slice it claims ────────────
# These joins are one INSEE call each for every commune, and their producers ASK for one slice
# (EMPSTA_ENQ=2, FILOSOFI_MEASURE=MED_SL, ...). Nothing in the join filters afterwards, so the
# rows must already be that slice: every distinct value of the pinned property is the one value.
PINNED = [
    ("HAS_UNEMPLOYED", "FrWork", {"status": "2"}),
    ("HAS_LABOUR_FORCE", "FrWork", {"status": "1T2"}),
    ("HAS_NO_DIPLOMA", "FrEducation", {"level": "001T100_RP", "year": "2023"}),
    ("HAS_GRADUATES", "FrEducation", {"level": "500T702_RP", "year": "2023"}),
    ("HAS_EDUCATION_BASE", "FrEducation", {"level": "_T", "year": "2023"}),
    ("HAS_MEDIAN_INCOME", "FrIncome", {"measure": "MED_SL"}),
    ("HAS_POVERTY", "FrIncome", {"measure": "PR_MD60"}),
    ("HAS_IMMIGRANTS", "FrImmigration", {"status": "1"}),
    ("HAS_TOTAL_POP", "FrPopulation", {"ageBand": "_T", "year": "2023"}),
    ("HAS_YOUNG_POP", "FrPopulation", {"ageBand": "Y15T24", "year": "2023"}),
]
for rel, label, pins in PINNED:
    cols = ", ".join(f"collect(DISTINCT toString(x.{k})) AS {k}" for k in pins)
    d = realm(f"MATCH (u:FrCommunes {{set: 'france'}})-[:{rel}]->(x:{label}) RETURN count(x) AS n, {cols}")
    row = (d.get("rows") or [{}])[0]
    seen = {k: sorted(v for v in (row.get(k) or []) if v is not None) for k in pins}
    ok = (row.get("n") or 0) > 1000 and all(seen[k] == [v] for k, v in pins.items())
    print(f"{'ok  ' if ok else 'FAIL'} pinned: {rel} -> {row.get('n')} rows, {seen}")
    if not ok:
        fails.append(f"pinned: {rel} returned {seen}, wanted {pins}")

print()
if fails:
    print(f"{len(fails)} FAILURE(S):")
    for f in fails:
        print(" -", f)
    sys.exit(1)
print("ALL CHECKS PASS")
PY
