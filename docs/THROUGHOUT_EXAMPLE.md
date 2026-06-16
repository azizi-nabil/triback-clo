# TriBack-Clo: PointerStore Creation Trace Example

## Loading and Initialization Pipeline

TriBack-Clo uses a multi-step initialization before mining begins:

| Step | What it does | I/O |
| --- | --- | --- |
| **Scan 1** (partial) | Sample first 1000 lines to detect singleton vs multi-item itemsets | File read (partial) |
| **Scan 2** (full) | Parse entire file → `ItemsetSequenceDatabase` in memory | File read (full) |
| **In-memory** | Create root `PointerStore` from DB (one tuple per sequence) | None |
| **DFS Mining** | Extend PointerStores during pattern enumeration | None |

### Why two scans?

The first partial scan detects the dataset format to choose the most memory-efficient storage:

| Dataset Type | Example | Storage Format |
| --- | --- | --- |
| **Singleton** | Kosarak | `Array[Array[Int]]` (flat) — avoids millions of 1-element arrays |
| **Multi-item** | Retail | `Array[Array[Array[Int]]]` (nested) — preserves itemset structure |

---

## The 4-Tuple PointerStore Format

A **PointerStore** is a **single unified data structure** that stores all tuples for a given pattern in one flat array. Each pattern in the DFS tree has its own PointerStore containing **one tuple per supporting sequence** (a sequence that contains the pattern).

**Internal representation:**

```scala
// One flat array with stride 4 (memory-efficient, cache-friendly)
positions: Array[Int] = [sid1, start1, curr1, last1, sid2, start2, curr2, ...]
```

### Tuple Fields

```
(sid, startIdx, currentIdx, lastItem)
  │       │          │          │
  │       │          │          └─ Last item used for extension (for canonical ordering)
  │       │          └─ Position where pattern's last element matched
  │       └─ Start of semi-maximum period (for BackScan pruning)
  └─ Sequence ID this tuple refers to
```

### Semi-Maximum Period

The **semi-maximum period** is the gap between where the previous pattern element matched and where the current element matched: `[startIdx, currentIdx)`.

**Visual example:**

```
Sequence:    {d}  {a}  {a,b}  {b,c}
Position:     0    1     2      3
```

Pattern ⟨(a)(bc)⟩ matched:
  - Element {a} at position 1
  - Element {bc} at position 3
  
```
Tuple: (sid, startIdx=2, currentIdx=3, lastItem=c)
```

**Semi-maximum period** = [2, 3) = contains {a,b} at position 2

### BackScan Witnesses: Pruning vs Gating

**BackScan** is a pruning technique from the BIDE algorithm that checks if a pattern can have a **same-support backward extension**.

TriBack-Clo uses **three independent witness families** with different effects:

| Witness Type  | What it checks                                                                  | Action                     |
| ------------- | ------------------------------------------------------------------------------- | -------------------------- |
| **Temporal**  | Items in semi-max period `[startIdx, currentIdx)`                               | ✂ **Prune entire subtree** |
| **Local-gap** | Items in tail itemset `E[currentIdx]`: $x < \max(P_k)$ AND $x \notin P_k$       | 🚫 **Gate node only**      |
| **Internal**  | Items in previous element's matched itemset `E[startIdx-1]`: $x \notin P_{k-1}$ | 🚫 **Gate node only**      |

> **Note:** Internal witnesses only apply to patterns of length $\geq 2$ (where `prevElement` exists).

**Why the difference?** The "match-jump" phenomenon: Under canonical I-extension ordering, a descendant can use a different occurrence of the tail event that doesn't contain the intra-itemset witness. So we can only skip output for the current pattern, not prune all descendants.

### Representative Projection Semantics

TriBack-Clo keeps **exactly one representative 4-tuple per supporting sequence** (the earliest end match).

- **Representative-only:** temporal windows for BackScan (`[startIdx, currentIdx)`) and S-extension enumeration (search strictly after `currentIdx`).
- **Existential tail scan (I-extensions):** for each supporting sequence `s`, count a canonical I-extension candidate `x` if there exists an event $E_j$ with $j \geq \text{currentIdx}(s)$ such that $P_k \subseteq E_j$ and $x \in E_j$ (implementation uses $lastItem(s) ∈ E_j$ as a fast pre-filter, then verifies the full subset condition before counting). The child’s $currentIdx$ is the earliest such $j$ found during the scan.

### Temporal BackScan (Subtree Pruning)

For a pattern P, temporal BackScan checks if there's an item that appears in the semi-maximum period `[startIdx, currentIdx)` of **ALL** supporting sequences.

Pattern ⟨(c)⟩ in our example:
  SID1: ⟨{a,b}, {c}⟩  →  Semi-max period [0,1) = pos 0 = {a,b}
  SID2: ⟨{a}, {b,c}⟩  →  Semi-max period [0,1) = pos 0 = {a}
  
  Intersection = {a} ← This item appears before 'c' in BOTH sequences!

**What a temporal witness means:**

If we find a temporal witness item (like 'a' above):
- **⟨(a)(c)⟩** has the same support as **⟨(c)⟩**
- Therefore ⟨(c)⟩ is **not closed** (it has a same-support superpattern)
- Moreover, **all descendants** of ⟨(c)⟩ will also have the same witness
- So we can **prune the entire subtree** (temporal witnesses are safe for subtree pruning)

### Intra-Itemset BackScan (Node Gating)

For Local-gap witnesses (items $x < \max(P_k)$ in tail itemset `E[currentIdx]`) and Internal witnesses (items $x \notin P_{k-1}$ in previous element's matched itemset `E[startIdx-1]`):

**What an intra-itemset witness means:**

- The current pattern P is definitely **not closed**
- But we **cannot prune descendants** due to match-jump
- So we **skip output/verification** for P, but still explore its children

> **Implementation note:** In `detectNotClosedFast()`, the code also re-checks Temporal witnesses as a defensive measure, even though `detectBackScanPrune()` already checked them for subtree pruning. This is harmless (short-circuits immediately if found) and allows `detectNotClosedFast()` to be used standalone if needed.

### BIDE+ Failure Case (Why Generalized Gating Matters)

The simplest known failure of BIDE+ on itemset-sequences occurs on a minimal **2-sequence database with just 5 items**:

**Database:**
```
S₁: ⟨{1,2,3}, {4}, {5}⟩
S₂: ⟨{1,2,3}, {4,5}⟩
```

**Why it fails:**
*   Pattern `⟨{1,2}, {5}⟩` has support 2 but is **not closed** (absorbed by `⟨{1,2,3}, {5}⟩` with same support)
*   Item **3** co-occurs with {1,2} in **both** sequences at position 0 → it's an **Internal witness**
*   BIDE+ misses it because implementations use $x < \min(P_i)$. Since $3 > 1$, the internal backward scan skips it.
*   This check is inherited from singleton sequences and is **unsound** for multi-item itemsets.

**Results:**
*   **TriBack-Clo**: 2 closed patterns (`⟨{1,2,3}, {4}⟩` and `⟨{1,2,3}, {5}⟩`)
*   **BIDE+**: 4 patterns (**2 false positives**: `⟨{1,2}, {5}⟩` and `⟨{1}, {5}⟩`)


**Test files:**
Create `test_minimal_5items.txt`:
```bash
echo "1 2 3 -1 4 -1 5 -1 -2" > test_minimal_5items.txt
echo "1 2 3 -1 4 5 -1 -2" >> test_minimal_5items.txt
```

Run comparison:
```bash
# TriBack-Clo
java -cp triback-clo-java/triback-clo.jar:experiments/spmf.jar ca.pfv.spmf.algorithms.sequentialpatterns.tribackclo.MainTestTriBackClo test_minimal_5items.txt /tmp/triback-output.txt 2

# BIDE+ (SPMF)
java -jar experiments/spmf.jar run BIDE+ test_minimal_5items.txt bide_out.txt 100%
```

**Verification Results:**
*   **TriBack-Clo**: 2 closed patterns
*   **BIDE+**: 4 patterns (**2 false positives**)


### Verified BIDE+ Failure on Multi-Item Dataset

**Dataset: `test_phase1.txt`** (10 sequences, 3 itemsets each, 2-3 items per itemset)

```
1 2 3 -1 4 5 -1 6 7 8 -1 -2
1 2 3 -1 4 5 6 -1 7 8 -1 -2
1 2 -1 3 4 5 -1 6 7 -1 -2
1 3 -1 2 4 -1 5 6 7 -1 -2
2 3 -1 4 5 -1 6 8 -1 -2
1 2 -1 3 5 -1 4 6 7 -1 -2
2 3 -1 4 6 -1 5 7 8 -1 -2
1 3 -1 2 5 -1 4 6 8 -1 -2
1 2 3 -1 4 6 -1 5 7 -1 -2
2 3 -1 4 5 6 -1 7 8 -1 -2
```

**Benchmark Results (minsup=2, 20%):**

| Algorithm | Closed Patterns | Status |
| --- | --- | --- |
| **TriBack-Clo** | **84** | ✅ Correct |
| **ClaSP** | **84** | ✅ Correct |
| **CloFast** | **84** | ✅ Correct |
| **CloSpan** | **84** | ✅ Correct |
| **BIDE+** | **95** | ❌ outputs 12 non-closed + misses 1 closed |

**Python Verification:**
```bash
python3 check_correctness.py test_phase1.txt /tmp/triback_phase1_out.txt 2 /tmp/bide_phase1_out.txt
# TriBack-Clo: 84, BIDE+: 95, BIDE+ Non-Closed Patterns: 12
# SUCCESS: TriBack-Clo results are perfect!
```

**Conclusion:** BIDE+'s backward-I checking ($x < \min(P_k)$) is insufficient for multi-item itemsets. All candidate-based algorithms (ClaSP, CloFast, CloSpan) agree with TriBack-Clo.


**Why BackScan is powerful:**

| Without BackScan | With BackScan |
| --- | --- |
| Explore ⟨(c)⟩, ⟨(c)(...)⟩, etc. | Detect temporal witness immediately |
| Find they're all non-closed later | Skip entire subtree |
| Wasted computation | **Massive speedup** |

---

## Why TriBack-Clo does not apply I-closure jumping

TriBack-Clo intentionally **does not** “jump” over I-extension nodes.

- Under the paper’s **existential tail** semantics for I-extension counting, different supporting sequences may realize same-support I-items using **different tail occurrences**.
- Merging same-support I-items into one “jumped” node (and skipping intermediate I/S branches) can therefore be unsound.

This is why the implementation always enumerates frequent I-children normally and relies on **forward-closed gating** to skip output for non-closed nodes while still exploring descendants (see also `tmp_ijump_counterexample.txt`).

## Concrete Example

This small example is meant to illustrate, end-to-end:

- How the 4-tuple `(sid, startIdx, currentIdx, lastItem)` is updated for **S-extensions** vs **I-extensions**
- The **forward-closed gate** (skipping output for a node that has a same-support forward extension)
- A **temporal BackScan prune** (skipping an entire subtree safely)

Database:

| SID | Sequence | Positions |
| --- | --- | --- |
| 1 | ⟨{a,b}, {c}⟩ | 0:{a,b}, 1:{c} |
| 2 | ⟨{a}, {b,c}⟩ | 0:{a}, 1:{b,c} |
| 3 | ⟨{b}, {d}⟩ | 0:{b}, 1:{d} |

min_sup = 2

### Runnable SPMF version (same DB)

Use a simple mapping `a=1, b=2, c=3, d=4`:

```text
1 2 -1 3 -1 -2
1 -1 2 3 -1 -2
2 -1 4 -1 -2
```

Run TriBack-Clo:

```bash
cat > /tmp/throughout_example_db.txt <<'EOF'
1 2 -1 3 -1 -2
1 -1 2 3 -1 -2
2 -1 4 -1 -2
EOF

java -cp triback-clo-java/triback-clo.jar:experiments/spmf.jar ca.pfv.spmf.algorithms.sequentialpatterns.tribackclo.MainTestTriBackClo \
  --input /tmp/throughout_example_db.txt --minsup 2 --output /tmp/throughout_example_out.txt
```

Expected output (2 closed patterns):

```text
1 -1 3 -1 #SUP: 2   (⟨(a)(c)⟩)
2 -1 #SUP: 3        (⟨(b)⟩)
```

### Frequent 1-patterns

| Item | SID1 | SID2 | SID3 | Support |
| --- | --- | --- | --- | --- |
| a | ✓ | ✓ | ✗ | 2 ✓ |
| b | ✓ | ✓ | ✓ | 3 ✓ |
| c | ✓ | ✓ | ✗ | 2 ✓ |
| d | ✗ | ✗ | ✓ | 1 ✗ |

### Root PointerStore (before mining)

| SID | startIdx | currentIdx | lastItem |
| --- | --- | --- | --- |
| 1 | 0 | -1 | 0 |
| 2 | 0 | -1 | 0 |
| 3 | 0 | -1 | 0 |

This represents "before the first element" — the starting point for DFS.

---

## Complete DFS Trace (Step-by-Step)

### How the DFS Tree is Constructed

TriBack-Clo builds a **depth-first search tree** where each node represents a pattern. The tree is constructed using two types of extensions:

**1. S-extension (Sequence extension):** Append a new itemset containing item $x$
$$
P ⊕S x = ⟨P₁, P₂, ..., Pₖ, {x}⟩
$$
- Requires: $x$ must appear at some position **strictly after** `currentIdx` in the sequence
- Example: $⟨(a)⟩ ⊕S c = ⟨(a)(c)⟩$

**2. I-extension (Itemset extension):** Add item `x` to the last itemset
$$
P ⊕I x = ⟨P₁, P₂, ..., Pₖ ∪ {x}⟩
$$
- Requires: $x > lastItem$ (canonical ordering to avoid duplicates)
- Counted **existentially** (implementation): for each supporting sequence $s, x$ is counted if there exists an event position $j \geq \text{currentIdx}(s)$` such that `$P_k \subseteq E_j^{(s)}$` and `$x \in E_j^{(s)}$`
- Example: $⟨(a)⟩ ⊕I b = ⟨(ab)⟩$ (only if there exists some tail occurrence at/after the match of `{a}` that contains both `a` and `b`)

**Tree construction algorithm (simplified, see Step 2 for full details):**
```
DFS(pattern P, PointerStore):
    0. If support < minsup: RETURN
    
    1. PRUNE CHECK: If temporal BackScan finds witness → PRUNE subtree, RETURN
    
    2. ENUMERATE extensions (S-ext and I-ext)
       Track hasSameSupportForward
    
    3. OUTPUT DECISION:
       If forward-closed AND no Local/Internal witness AND exact-closed:
         → OUTPUT pattern
    
    4. RECURSE into children:
       For each frequent S-extension: DFS(P ⊕S x, childStore)
       For each frequent I-extension: DFS(P ⊕I x, childStore)
```

**Key point:** S-extensions and I-extensions have different support because they impose different structural constraints on where `x` must appear.

### How TriBack-Clo Calculates Support (Implementation)

TriBack-Clo uses **stamp-based counting** in `enumerateExtensions()` to efficiently count support:

```scala
// For each supporting sequence of the parent pattern:
for each tuple (sid, startIdx, currentIdx, lastItem) in PointerStore:
    
    // S-extension candidates: items appearing AFTER currentIdx
    for isIdx = currentIdx + 1 to seq.length:
        for item in seq(isIdx):
            if sExtSeen(item) != stamp:  // First occurrence in this SID
                sExtSeen(item) = stamp
                sExtSupport(item) += 1   // Increment support count
    
    // I-extension candidates (existential tail scan): items > lastItem co-occurring with the tail itemset
    for pos = currentIdx to seq.length:
        ev = seq(pos)
        if ev contains lastItem AND ev containsAll(tailItemset):
            for item in ev where item > lastItem:
                if iExtSeen(item) != stamp:
                    iExtSeen(item) = stamp
                    iExtSupport(item) += 1
```

**After scanning all SIDs:**
- `sExtSupport[x]` = number of sequences where `x` appears after `currentIdx`
- `iExtSupport[x]` = number of sequences where `x > lastItem` co-occurs with the tail itemset in some event $j \geq \text{currentIdx}$`

**The stamp trick:** Using a unique `stamp` per SID avoids double-counting when an item appears multiple times in the same sequence. We only count the **first occurrence** per SID.

### How TriBack-Clo Distinguishes S-extension vs I-extension

The distinction is based on **where the extension item is found** relative to `currentIdx`:

```scala
// I-extension: existential scan over tail occurrences at/after currentIdx
for pos = currentIdx to seq.length:
    val ev = seq(pos)
    if contains(lastItem) && containsAll(tailItemset):
        for item in ev:
            if item > lastItem:
                → This is an I-extension candidate

// S-extension: items in ANY itemset AFTER currentIdx
for isIdx = currentIdx + 1 to seq.length:
    for item in seq(isIdx):
        → This is an S-extension candidate
```

| Extension | Where to look | Condition | Tuple update |
| --- | --- | --- | --- |
| **I-ext** | events `seq(pos)` for `pos >= currentIdx` where `tailItemset ⊆ seq(pos)` | `item > lastItem` | `startIdx` unchanged |
| **S-ext** | `seq(isIdx)` for `isIdx > currentIdx` | any item | `startIdx = currentIdx + 1` |

**Key insight:** The same item `x` can be both an S-extension and I-extension candidate if it appears in multiple positions. TriBack-Clo tracks them **separately** using `sExtSupport` and `iExtSupport` arrays.

### DFS Tree Overview


```
Root (∅)
├── [S-ext a] → ⟨(a)⟩ sup=2        → Skip output (same-supp forward ext: c)
│   ├── [S-ext b] → ⟨(a)(b)⟩ sup=1 ✗ below minsup
│   ├── [S-ext c] → ⟨(a)(c)⟩ sup=2 → Output (closed) (LEAF)
│   └── [I-ext b] → ⟨(ab)⟩ sup=1   ✗ below minsup
├── [S-ext b] → ⟨(b)⟩ sup=3        → Check closure (LEAF)
│   ├── [S-ext c] → ⟨(b)(c)⟩ sup=1 ✗ below minsup
│   ├── [S-ext d] → ⟨(b)(d)⟩ sup=1 ✗ below minsup
│   └── [I-ext c] → ⟨(bc)⟩ sup=1   ✗ below minsup
├── [S-ext c] → ⟨(c)⟩ sup=2        ✂ PRUNE (BackScan witness {a})
└── [S-ext d] → ⟨(d)⟩ sup=1        ✗ below minsup
```



> **Why ⟨(a)(b)⟩ has sup=1 (infrequent)?**
> 
> An **S-extension** ⟨(a)(b)⟩ requires 'b' to appear in a **later itemset** than 'a':
> - **SID1**: 'a' at pos 0 ({a,b}), but 'b' is also at pos 0 (same itemset) → ❌
> - **SID2**: 'a' at pos 0 ({a}), 'b' at pos 1 ({b,c}) → ✅
> 
> Only SID2 supports ⟨(a)(b)⟩, so support = 1 < minsup.
> 
> Compare with **I-extension** ⟨(ab)⟩: requires 'a' and 'b' in the **same itemset**.
> Only SID1's {a,b} qualifies, so support = 1 < minsup.

> **Why no ⟨(ac)⟩ at all?**
> 
> An **I-extension** ⟨(ac)⟩ requires an event at/after the tail match that contains **both** 'a' and 'c' (existential tail scan):
> - **SID1**: {a,b} then {c} → no event contains {a,c} → **NO**
> - **SID2**: {a} then {b,c} → no event contains {a,c} → **NO**
> 
> Support = 0, so ⟨(ac)⟩ is **never enumerated** (not even shown as infrequent).



---


### Step 1: Initialize Root

**Pattern:** ∅ (empty)

**Algorithm:**
```
1. CREATE ROOT PointerStore:
   For each sequence s in database:
     Add tuple (sid=s, startIdx=0, currentIdx=-1, lastItem=0)

2. ENUMERATE frequent 1-patterns:
   For each item x in vocabulary:
     Count sequences where x appears
     If support(x) >= minsup: add to frequent items
```

**PointerStore:**

| SID | startIdx | currentIdx | lastItem |
| --- | --- | --- | --- |
| 1 | 0 | -1 | 0 |
| 2 | 0 | -1 | 0 |
| 3 | 0 | -1 | 0 |

**Extensions found:**

| Item | SID1 pos | SID2 pos | SID3 pos | Support |
| --- | --- | --- | --- | --- |
| a | 0 | 0 | — | 2 ✓ |
| b | 0 | 1 | 0 | 3 ✓ |
| c | 1 | 1 | — | 2 ✓ |
| d | — | — | 1 | 1 ✗ |

**Next:** DFS into ⟨(a)⟩, ⟨(b)⟩, ⟨(c)⟩

---

### Step 2: Process ⟨(a)⟩

**Pattern:** ⟨(a)⟩ (support 2: SID1, SID2)

**Algorithm (matches code execution order):**
1. **BUILD PointerStore** for $P = \langle (a) \rangle$:
   - For each supporting sequence s:
     - Find first position pos where 'a' occurs
     - Add tuple `(sid=s, startIdx=0, currentIdx=pos, lastItem=a)`

2. **PRUNE CHECK - Temporal BackScan** (immediate):
   - Temporal witness: $\bigcap_s T(s)$ where $T(s) =$ items in $[\text{startIdx}, \text{currentIdx})$
   - If non-empty → **PRUNE** entire subtree and RETURN

3. **ENUMERATE Extensions:**
   - **3a. S-extensions:** items appearing strictly AFTER currentIdx
   - **3b. I-extensions:** items $> \text{lastItem}$ co-occurring with the tail in some event $j \geq \text{currentIdx}$ (existential tail scan)
   - Track: `hasSameSupportForward = true` if any extension has same support as P

4. **FORWARD-CLOSED CHECK:**
   - If `hasSameSupportForward` → P is **NOT** forward-closed → skip output (but continue DFS into children)

5. **GATE CHECK - Local/Internal BackScan** (deferred, only if forward-closed):
   - **5a. Local-gap witness:** $\bigcap_s L(s)$ where $L(s) = \{x \in E[\text{currentIdx}] : x < \max(P_k) \land x \notin P_k\}$
     - If non-empty → **GATE** (skip output, continue DFS)
   - **5b. Internal witness** (only if length $\geq 2$): $\bigcap_s \text{Int}_{k-1}(s)$ where $\text{Int}_{k-1}(s) = E[\text{startIdx}-1] \setminus P_{k-1}$
     - If non-empty → **GATE** (skip output, continue DFS)

6. **EXACT VERIFICATION** (lazy, only if all gates passed):
   - Run `EnvelopeClosedExact` → OUTPUT if closed

7. **RECURSE into children** (S-extensions first, then I-extensions)

**Why this order?** The code defers Local/Internal gating until after enumeration because:
- If forward-closed check fails (step 4), we skip output anyway → no need to run Local/Internal checks
- This saves computation when the forward-closed gate already rejects the node

**PointerStore:**

| SID | startIdx | currentIdx | lastItem |
| --- | -------- | ---------- | -------- |
| 1   | 0        | 0          | a        |
| 2   | 0        | 0          | a        |

**Step 2 - Temporal BackScan Check:**
```
Semi-max period [startIdx, currentIdx):
  SID1: [0, 0) = ∅
  SID2: [0, 0) = ∅
Intersection = ∅ → NO WITNESS → CONTINUE
```

**Step 3 - Enumerate Extensions:**

*S-extensions (items after currentIdx):*

| Item | SID1 pos | SID2 pos | Support |
| ---- | -------- | -------- | ------- |
| c    | 1        | 1        | 2 ✓     |
| b    | —        | 1        | 1 ✗     |

*I-extensions (items > 'a' co-occurring with the tail):*

| Item | SID1 ({a,b}) | SID2 ({a}) | Support |
| ---- | ------------ | ---------- | ------- |
| b    | ✓            | ✗          | 1 ✗     |

**Step 4 - Forward-closed?** NO — same-support forward extension exists:
- `c` is an S-extension with `supp(⟨(a)(c)⟩)=2`, equal to `supp(⟨(a)⟩)=2`

**Step 5 - Local/Internal Gating:** SKIPPED (forward-closed check already failed)

**Effect:** TriBack-Clo skips output (and skips envelope verification) for ⟨(a)⟩, but still explores its children.

**Next:** DFS into ⟨(a)(c)⟩

---

### Step 3: Process ⟨(a)(c)⟩

**Pattern:** ⟨(a)(c)⟩ (support 2: SID1, SID2)

**Algorithm Note:**
```
S-extension from ⟨(a)⟩:
  For each supporting sequence s:
    Find first position pos > parent.currentIdx where 'c' occurs
    New tuple: (sid, startIdx=parent.currentIdx+1, currentIdx=pos, lastItem=c)
```

**PointerStore:**

| SID | startIdx | currentIdx | lastItem |
| --- | --- | --- | --- |
| 1 | 1 | 1 | c |
| 2 | 1 | 1 | c |

*Note: startIdx = parent.currentIdx + 1 = 0 + 1 = 1*

**Step 2 - Temporal BackScan Check:**
```
Semi-max period [startIdx, currentIdx):
  SID1: [1, 1) = ∅
  SID2: [1, 1) = ∅
Intersection = ∅ → NO WITNESS → CONTINUE
```

**Step 3 - Enumerate Extensions:**
- S-extensions: No positions after 1 in either sequence
- I-extensions: No items > 'c' co-occurring with the tail at/after position 1

**No extensions → LEAF**

**Step 4/5/6 - Forward-closed, Gating, Verification:**
- Forward-closed? Yes (no extensions)
- Local/Internal gating: No witnesses (singleton tail, length-2)
- Exact verification: Run EnvelopeClosedExact (see trace below)

**EnvelopeClosedExact Trace for ⟨(a)(c)⟩:**

First, compute envelopes for each SID:

| SID | Sequence | first[0] (a) | first[1] (c) | last[0] (a) | last[1] (c) |
| --- | --- | --- | --- | --- | --- |
| 1 | ⟨{a,b}, {c}⟩ | 0 | 1 | 0 | 1 |
| 2 | ⟨{a}, {b,c}⟩ | 0 | 1 | 0 | 1 |

Then run the 4 closure checks:

| Check | Window/Position | SID1 candidates | SID2 candidates | Intersection | Result |
| --- | --- | --- | --- | --- | --- |
| **S-prepend** | `[0, last[0])` = `[0, 0)` | ∅ | ∅ | ∅ | PASS ✓ |
| **I-prepend** | E[0] \ {a} | {b} | ∅ | ∅ | PASS ✓ |
| **S-insert (gap 0→1)** | `[first[0]+1, last[1])` = `[1, 1)` | ∅ | ∅ | ∅ | PASS ✓ |
| **I-insert (P₂={c})** | E[1] \ {c} | ∅ | {b} | ∅ | PASS ✓ |

All 4 checks pass → **⟨(a)(c)⟩ is CLOSED** → **OUTPUT**

**Next:** Backtrack to ⟨(a)⟩, then to Root, then DFS into ⟨(b)⟩

---

### Step 4: Process ⟨(b)⟩

**Pattern:** ⟨(b)⟩ (support 3: SID1, SID2, SID3)

**Algorithm Note:**
```
Length-1 pattern:
  For each sequence s where 'b' appears:
    Find first position pos where 'b' occurs
    New tuple: (sid, startIdx=0, currentIdx=pos, lastItem=b)
```

**PointerStore:**

| SID | startIdx | currentIdx | lastItem |
| --- | --- | --- | --- |
| 1 | 0 | 0 | b |
| 2 | 0 | 1 | b |
| 3 | 0 | 0 | b |

*Note: Different currentIdx! SID1 matches 'b' at 0 (in {a,b}), SID2 at 1 (in {b,c}), SID3 at 0 (in {b})*

**Step 2 - Temporal BackScan Check:**
```
Semi-max period [startIdx, currentIdx):
  SID1: [0, 0) = ∅
  SID2: [0, 1) = pos 0 = {a}
  SID3: [0, 0) = ∅
Intersection = ∅ (SID1 and SID3 have nothing) → NO WITNESS → CONTINUE
```

**Step 3 - Enumerate Extensions:**

*S-extensions:*

| Item | SID1 (after 0) | SID2 (after 1) | SID3 (after 0) | Support |
| --- | --- | --- | --- | --- |
| c | pos 1 ✓ | — | — | 1 ✗ |
| d | — | — | pos 1 ✓ | 1 ✗ |

*I-extensions (items > 'b' co-occurring with the tail):*

| Item | SID1 (> b in {a,b}) | SID2 (> b in {b,c}) | SID3 (> b in {b}) | Support |
| --- | --- | --- | --- | --- |
| c | — | ✓ | — | 1 ✗ |

**No frequent extensions → LEAF**

**Step 4/5/6 - Forward-closed, Gating, Verification:**
- Forward-closed? Yes (no frequent extensions)
- Local/Internal gating: No witness (intersection empty)
- Exact verification: Run EnvelopeClosedExact → OUTPUT if closed

**Next:** Backtrack to Root, then DFS into ⟨(c)⟩

---

### Step 5: Process ⟨(c)⟩ — **PRUNING EXAMPLE**

**Pattern:** ⟨(c)⟩ (support 2: SID1, SID2)

**Algorithm Note:**
```
Length-1 pattern:
  Find first position where 'c' occurs in each sequence
  SID1: pos 1, SID2: pos 1
```

**PointerStore:**

| SID | startIdx | currentIdx | lastItem |
| --- | --- | --- | --- |
| 1 | 0 | 1 | c |
| 2 | 0 | 1 | c |

**Step 2 - Temporal BackScan Check:**
```
Algorithm: detectBackScanPrune()
  For each SID, collect items in [startIdx, currentIdx):
    SID1: [0, 1) = pos 0 = {a, b}
    SID2: [0, 1) = pos 0 = {a}
  Intersect across all SIDs:
    Intersection = {a} ≠ ∅ → TEMPORAL WITNESS FOUND!
```

**Decision: ✂️ PRUNE ENTIRE SUBTREE**

**Why?** Item 'a' appears before 'c' in ALL supporting sequences.
- S-inserting {a} gives ⟨(a)(c)⟩ with support 2 = support(⟨(c)⟩)
- Therefore ⟨(c)⟩ is NOT closed
- By Proposition 5, NO descendant of ⟨(c)⟩ can be closed either

**Action:**
- Do NOT enumerate extensions
- Do NOT run closure verification
- Skip entire subtree immediately

**Next:** Backtrack to Root → DFS complete

---

### Step 6: Mining Complete

**DFS Summary:**

| Step | Pattern | PointerStore | Support | BackScan | Result |
| --- | --- | --- | --- | --- | --- |
| 2 | ⟨(a)⟩ | SID1:(0,0,a), SID2:(0,0,a) | 2 | pass | forward-gated (same-supp S-ext: c) |
| 3 | ⟨(a)(c)⟩ | SID1:(1,1,c), SID2:(1,1,c) | 2 | pass | ✅ output (closed) |
| 4 | ⟨(b)⟩ | SID1:(0,0,b), SID2:(0,1,b), SID3:(0,0,b) | 3 | pass | ✅ output (closed) |
| 5 | ⟨(c)⟩ | SID1:(0,1,c), SID2:(0,1,c) | 2 | **{a}** | ✂ prune subtree |

**Closed patterns output:** ⟨(a)(c)⟩, ⟨(b)⟩

---

## Supplementary Examples: Local-gap and Internal Gating

The main example above only demonstrates **Temporal pruning** (Step 5: ⟨(c)⟩) and **forward-closed gating** (Step 2: ⟨(a)⟩). This section provides concrete traces for the other two witness types that only **gate** the current node (skip output) without pruning descendants.

### Example A: Local-gap Witness Gating

**Database:**

| SID | Sequence |
| --- | --- |
| 1 | ⟨{a,b}, {c,d}⟩ |
| 2 | ⟨{a,b}, {c,d}⟩ |

**Pattern:** ⟨(b)(d)⟩ (support 2)

**PointerStore:**

| SID | startIdx | currentIdx | lastItem |
| --- | --- | --- | --- |
| 1 | 1 | 1 | d |
| 2 | 1 | 1 | d |

**Step-by-step trace:**

```
1. BUILD PointerStore: ⟨(b)(d)⟩
   - SID1: 'b' at pos 0, 'd' at pos 1 → (sid=1, startIdx=1, currentIdx=1, lastItem=d)
   - SID2: 'b' at pos 0, 'd' at pos 1 → (sid=2, startIdx=1, currentIdx=1, lastItem=d)

2. PRUNE CHECK - Temporal BackScan:
   Semi-max period [startIdx, currentIdx) = [1, 1) = ∅
   → NO TEMPORAL WITNESS → CONTINUE

3. ENUMERATE Extensions:
   - S-extensions: No positions after 1 → none
   - I-extensions: No items > 'd' in {c,d} → none
   → LEAF (no extensions)

4. FORWARD-CLOSED CHECK:
   No extensions exist → hasSameSuppForward = false → FORWARD-CLOSED ✓

5. GATE CHECK - Local-gap Witness:
   Check E[currentIdx=1] = {c,d} for items x where x < max(P_k)=d AND x ∉ P_k={d}
   
   SID1: E[1] = {c,d} → c < d AND c ∉ {d} → L(1) = {c}
   SID2: E[1] = {c,d} → c < d AND c ∉ {d} → L(2) = {c}
   
   Intersection: L(1) ∩ L(2) = {c} ≠ ∅ → LOCAL-GAP WITNESS FOUND!

6. DECISION: 🚫 GATE (skip output, continue DFS)
```

**Why?** Item 'c' can be I-inserted into the tail itemset {d} to form ⟨(b)(c,d)⟩, which has the same support. Therefore ⟨(b)(d)⟩ is NOT closed. However, its descendants might still be closed (due to match-jump), so we continue DFS but skip output.

> **Note:** Local-gap witnesses only apply to patterns where the tail itemset has items with smaller canonical order available in the matched event.

---

### Example B: Internal Witness Gating

**Database:**

| SID | Sequence |
| --- | --- |
| 1 | ⟨{a,x}, {b}⟩ |
| 2 | ⟨{a,x}, {b}⟩ |

**Pattern:** ⟨(a)(b)⟩ (support 2)

**PointerStore:**

| SID | startIdx | currentIdx | lastItem |
| --- | --- | --- | --- |
| 1 | 1 | 1 | b |
| 2 | 1 | 1 | b |

**Step-by-step trace:**

```
1. BUILD PointerStore: ⟨(a)(b)⟩
   - SID1: 'a' at pos 0, 'b' at pos 1 → (sid=1, startIdx=1, currentIdx=1, lastItem=b)
   - SID2: 'a' at pos 0, 'b' at pos 1 → (sid=2, startIdx=1, currentIdx=1, lastItem=b)

2. PRUNE CHECK - Temporal BackScan:
   Semi-max period [startIdx, currentIdx) = [1, 1) = ∅
   → NO TEMPORAL WITNESS → CONTINUE

3. ENUMERATE Extensions:
   - S-extensions: No positions after 1 → none
   - I-extensions: No items > 'b' in singleton {b} → none
   → LEAF (no extensions)

4. FORWARD-CLOSED CHECK:
   No extensions exist → FORWARD-CLOSED ✓

5. GATE CHECK - Local-gap Witness:
   Tail itemset P_k = {b} is a singleton, so max(P_k) = b.
   E[currentIdx=1] = {b} → no item x < b exists → L(s) = ∅
   → NO LOCAL-GAP WITNESS

6. GATE CHECK - Internal Witness:
   Check E[startIdx-1] = E[0] for items x ∉ $P_{k-1}$ = {a}
   
   SID1: E[0] = {a,x} → x ∉ {a} → Int(1) = {x}
   SID2: E[0] = {a,x} → x ∉ {a} → Int(2) = {x}
   
   Intersection: Int(1) ∩ Int(2) = {x} ≠ ∅ → INTERNAL WITNESS FOUND!

7. DECISION: 🚫 GATE (skip output, continue DFS)
```

**Why?** Item 'x' can be I-inserted into the previous element {a} to form ⟨(a,x)(b)⟩, which has the same support. Therefore ⟨(a)(b)⟩ is NOT closed.

> **Note:** Internal witnesses only apply to patterns of length $\geq 2$. The code checks `prevElement != null` before running this test.

---

### Summary: When Each Witness Type Applies

| Witness Type | Condition | Position Checked | Action |
| --- | --- | --- | --- |
| **Temporal** | Always (length $\geq 1$) | `[startIdx, currentIdx)` | ✂ Prune subtree |
| **Local-gap** | Multi-item tail | `E[currentIdx]` | 🚫 Gate node only |
| **Internal** | Length ≥ 2 | `E[startIdx-1]` | 🚫 Gate node only |

**Code order in `detectNotClosedFast()`:**
1. Temporal witness (redundant with prune check, but defensive)
2. Local-gap witness (if `lastElement.length > 0`)
3. Internal witness (if `prevElement != null`, i.e., length $\geq 2$)

---

## Envelope-Based Exact Closure Verification

After a pattern passes all fast gates (forward-closed, no BackScan witness), TriBack-Clo performs **exact verification** using **envelope-based window checking**. This is the final, sound closure check that ensures no same-support superpattern exists.

### What are Envelopes?

For each supporting sequence, TriBack-Clo computes **first** and **last** embedding positions:

| Envelope | Definition | Purpose |
| --- | --- | --- |
| **First embedding** | `first[i]` = earliest position where pattern element `P_i` can match | Defines left boundary of forcing windows |
| **Last embedding** | `last[i]` = latest position where pattern element `P_i` can match | Defines right boundary of forcing windows |

**Example:**

```
Sequence S: ⟨{a}, {b}, {a}, {c}, {b}⟩
Pattern P:  ⟨(a), (b)⟩

First embedding: a@0, b@1  →  first = [0, 1]
Last embedding:  a@2, b@4  →  last  = [2, 4]
```

### The Four Closure Checks

A pattern P is **closed** if and only if there is NO item `x` that can be:

| Check | Superpattern | Window per SID | Condition |
| --- | --- | --- | --- |
| **1. S-prepend** | `⟨{x}, P₁, P₂, ...⟩` | `[0, last[0])` | Any item before rightmost match of P₁ |
| **2. I-prepend** | `⟨{P₁ ∪ x}, P₂, ...⟩` | `[first[0], last[0]]` positions where P₁ matches | Item in same itemset as P₁, not already in P₁ |
| **3. S-insert (gap g)** | `⟨..., Pₘ, {x}, Pₘ₊₁, ...⟩` | `[first[g]+1, last[g+1])` | Item in gap between elements g and g+1 |
| **4. I-insert (element i)** | `⟨..., Pᵢ ∪ {x}, ...⟩` | `[first[i], last[i]]` positions where Pᵢ matches | Item in same itemset as Pᵢ, not already in Pᵢ |

If **any** of these checks finds a common item across ALL supporting sequences, the pattern is **not closed**.

### Why Envelopes Enable Efficient Checking

Without envelopes, we'd need to enumerate all possible embeddings for each sequence. With envelopes:

- **First/Last positions define the "forcing window"** — the range of positions where a witness item MUST appear
- **Stamp-based intersection** — efficiently finds common items across all SIDs without allocations

### S-prepend Check (Backward Extension)

```
Pattern P = ⟨(a)(c)⟩

SID1: ⟨{d}, {a,b}, {c}⟩  →  last[0] = 1 (rightmost 'a' at pos 1)
      Window [0, 1) = pos 0 = {d}

SID2: ⟨{a}, {b,c}⟩      →  last[0] = 0 (rightmost 'a' at pos 0)
      Window [0, 0) = ∅

Intersection = ∅ → NO S-prepend witness → PASS
```

> **Key insight:** We use `last[0]` (not `first[0]`) because we need to check if ANY embedding can be extended. The rightmost match of P₁ gives the widest possible prepend window.

### S-insert Check (Middle Gap Extension)

For a pattern `P = ⟨P₁, P₂, ..., Pₖ⟩`, check each gap between consecutive elements:

```
Pattern P = ⟨(a)(b)(c)⟩, checking gap between element 0 and 1

SID1: ⟨{a}, {x}, {b}, {c}⟩
      first[0] = 0, last[1] = 2
      Wide window: [first[0]+1, last[1]) = [1, 2) = pos 1 = {x}

SID2: ⟨{a}, {b}, {y}, {c}⟩
      first[0] = 0, last[1] = 1
      Wide window: [1, 1) = ∅

Intersection = ∅ → NO S-insert witness for gap 0 → PASS
```

> **Note:** TriBack-Clo uses the **wide window** `[first[g]+1, last[g+1])` which correctly handles repeated items and multiple embeddings.

### I-prepend and I-insert Checks

For multi-item datasets, TriBack-Clo also checks if an item can be **merged into** an existing itemset:

```
Pattern P = ⟨(a,b)(c)⟩, checking I-insert into element 0

The window is [first[0], last[0]] — all positions where {a,b} matches.
For each such position, collect items that are:
  - In the matched itemset
  - NOT already in {a,b}

If any such item appears in ALL SIDs → NOT closed
```

### Code Flow

```scala
// In ClosureCheckerFast.isClosedUsingEnvelopes():

// 1. S-prepend: check [0, last[0])
if (hasCommonItemInRange(..., fromFn = 0, toFn = last[0])) return false

// 2. I-prepend: check positions where P₁ matches
if (hasCommonItemIPrepend(...)) return false

// 3. S-insert for each gap g
for (g <- 0 until k-1) {
  if (hasCommonItemInRange(..., 
      fromFn = first[g] + 1, 
      toFn = last[g+1])) return false
}

// 4. I-insert for each element i
for (i <- 0 until k) {
  if (hasCommonItemIInsert(...)) return false
}

return true  // Pattern is CLOSED
```

### When Does Exact Verification Reject a Pattern?

A pattern can pass all fast gates but fail exact verification when:

1. **S-prepend witness exists** — An item appears before P₁ in all SIDs, but wasn't caught by BackScan (rare edge case)
2. **I-prepend/I-insert witness exists** — A same-support I-merge exists that BackScan didn't detect
3. **Middle S-insert witness exists** — An item can be inserted between elements that BackScan missed

**In practice:** The fast gates (forward-closed + BackScan) catch 95%+ of non-closed patterns. Exact verification is the final safety net.

### Singleton Dataset Optimization

For singleton datasets (like Kosarak where each itemset has exactly one item):

- **I-prepend and I-insert checks are skipped** (impossible with single-item itemsets)
- **Only S-prepend and S-insert checks are performed**
- **Fast path for length-1 patterns:** Only S-prepend matters, no gaps to check

---

## PointerStore base structures (current implementation)

- For **singleton** datasets (Kosarak-style): the loader builds a flattened `Array[Array[Int]]` (`singletonSeqs`) and the miner scans plain integer arrays.
- For **multi-item** datasets: TriBack-Clo performs **on-the-fly suffix scans** in `ItemsetPointerStore.enumerateExtensions()` and materializes child PointerStores via `MinerContext`’s touched-item lists (`sLists` / `iLists`).

(Conceptually, a positional inverted index could speed up some scans, but the current code keeps the representation simple and cache-friendly.)

---

## Summary

| Concept | Description |
| --- | --- |
| **Supporting sequence** | A sequence that contains the current pattern |
| **Tuple count** | One tuple per supporting sequence |
| **startIdx** | Position after previous element match (semi-max period start) |
| **currentIdx** | Position where last element matched |
| **lastItem** | Last item added to tail element (for canonical I-extension ordering) |
| **Semi-maximum period** | Gap `[startIdx, currentIdx)` checked for BackScan witnesses |
| **startIdx rule (S-ext)** | `parent.currentIdx + 1` |
| **startIdx rule (I-ext)** | `parent.startIdx` (unchanged) |
| **First embedding** | Earliest positions `first[i]` where each pattern element matches |
| **Last embedding** | Latest positions `last[i]` where each pattern element matches |
| **Forcing window** | Range `[from, to)` where witness items must appear in ALL SIDs |
| **S-prepend check** | Check `[0, last[0])` for backward S-extension witness |
| **I-prepend check** | Check itemsets at `[first[0], last[0]]` for backward I-merge witness |
| **S-insert check** | Check gaps `[first[g]+1, last[g+1])` for middle S-insert witness |
| **I-insert check** | Check itemsets at `[first[i], last[i]]` for middle I-merge witness |

