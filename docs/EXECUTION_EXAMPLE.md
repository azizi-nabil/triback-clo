# TriBack-Clo: Step-by-Step Execution Example

This document traces the complete execution of TriBack-Clo on a small database to illustrate the algorithm's key mechanisms: BackScan pruning, forward-closed detection, and envelope-based verification.

---

## Algorithm Overview

TriBack-Clo uses a **three-gate architecture** to efficiently mine closed sequential patterns:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        TriBack-Clo DFS Node Processing                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Gate 1: BackScan Pruning and Gating (DFS-level)                           │
  ┌─────────────────────────────────────────────────────────────────┐    │
  │ 1. Temporal: Item in [startIdx, currentIdx) for ALL?            │    │
  │    If YES → PRUNE entire subtree immediately                    │    │
  │                                                                 │    │
  │ 2. Local-gap: Item < maxItem in tail itemset for ALL?           │    │
  │    If YES → GATE (skip output), continue search                 │    │
  │                                                                 │    │
  │ 3. Internal: Item in a previous itemset for ALL?                │    │
  │    If YES → GATE (skip output), continue search                 │    │
  └─────────────────────────────────────────────────────────────────┘    │
│                              ↓ NO                                       │
│  Gate 2: Forward-Closed Check                                           │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │ Does any extension have same support as current pattern?       │    │
│  │ If YES → NOT forward-closed → skip envelope, continue DFS      │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                              ↓ NO (forward-closed)                      │
│  Gate 3: Envelope Verification                                          │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │ Check all possible same-support superpatterns:                 │    │
│  │ • Backward S-prepend: [0, last(E₀))                            │    │
│  │ • Backward I-augment: items in first element's matching sets   │    │
│  │ • Middle S-insert: (last(Eₖ)+1, first(Eₖ₊₁)) for each gap      │    │
│  │ • Middle I-augment: items in each element's matching sets      │    │
│  │ If ALL pass → OUTPUT as closed pattern                         │    │
│  │ If FAIL → do NOT output, but continue DFS into children        │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

> **Important**: Only Gate 1 (BackScan) causes subtree pruning. Gate 3 (Envelope) failure just skips output — the algorithm continues to children.

---

## Database

| SID | Sequence | SPMF Format | Positions (0-indexed) |
|-----|----------|-------------|----------------------|
| S1 | ⟨(d)(a)(ab)(bc)⟩ | `4 -1 1 -1 1 2 -1 2 3 -1 -2` | 0:{d}, 1:{a}, 2:{a,b}, 3:{b,c} |
| S2 | ⟨(d)(a)(ab)(bc)⟩ | `4 -1 1 -1 1 2 -1 2 3 -1 -2` | 0:{d}, 1:{a}, 2:{a,b}, 3:{b,c} |
| S3 | ⟨(a)(ab)⟩ | `1 -1 1 2 -1 -2` | 0:{a}, 1:{a,b} |
| S4 | ⟨(a)⟩ | `1 -1 -2` | 0:{a} |

**Item mapping**: a=1, b=2, c=3, d=4  
**Item order**: a < b < c < d  
**Minimum support**: 2

---

## Key Data Structures

### PointerStore 4-Tuple Format

| Field | Description |
|-------|-------------|
| `startIdx` | Start of semi-maximum period (= parent_currentIdx + 1 for S-ext, unchanged for I-ext) |
| `currentIdx` | Position where current (last) pattern element was matched |
| `lastItem` | The item used for the last extension (for canonical I-extension ordering) |

**Note**: Extension type is implicit in the update rules and the branch being processed.

### Extension Rules

| Extension Type | startIdx | currentIdx | lastItem |
|---------------|----------|------------|----------|
| **S-extension** | parent_currentIdx + 1 | position of new item | new item |
| **I-extension** | unchanged from parent | unchanged from parent | new item |

---

## Full DFS Tree

The tree below shows **all nodes TriBack-Clo actually visits**. Nodes under a Gate 1 prune are absent because the algorithm returns immediately.

```
Root (∅)
│
├─[S-ext a]→ ⟨(a)⟩ sup=4                          ★ OUTPUT (closed)
│   │
│   ├─[S-ext a]→ ⟨(a)(a)⟩ sup=3                   ↪ NOT forward-closed
│   │   │                                          (I-ext b keeps sup=3)
│   │   ├─[I-ext b]→ ⟨(a)(ab)⟩ sup=3              ★ OUTPUT (closed)
│   │   │   │
│   │   │   ├─[S-ext b]→ ⟨(a)(ab)(b)⟩ sup=2       ↪ NOT forward-closed
│   │   │   │   │                                  (I-ext c keeps sup=2)
│   │   │   │   └─[I-ext c]→ ⟨(a)(ab)(bc)⟩ sup=2  🚫 Envelope fail (S-prepend {d})
│   │   │   │
│   │   │   └─[S-ext c]→ ⟨(a)(ab)(c)⟩ sup=2       ✂ Gate 1 PRUNE (local-gap {b})
│   │   │
│   │   ├─[S-ext b]→ ⟨(a)(a)(b)⟩ sup=2            ↪ NOT forward-closed
│   │   │   │                                      (I-ext c keeps sup=2)
│   │   │   └─[I-ext c]→ ⟨(a)(a)(bc)⟩ sup=2       🚫 Envelope fail (S-prepend {d})
│   │   │
│   │   └─[S-ext c]→ ⟨(a)(a)(c)⟩ sup=2            ✂ Gate 1 PRUNE (local-gap {b})
│   │
│   ├─[S-ext b]→ ⟨(a)(b)⟩ sup=3                   ✂ Gate 1 PRUNE (local-gap {a})
│   ├─[S-ext c]→ ⟨(a)(c)⟩ sup=2                   ✂ Gate 1 PRUNE (local-gap {b})
│   │
│   └─[I-ext b]→ ⟨(ab)⟩ sup=3                     🚫 Envelope fail (S-prepend {a})
│       │
│       ├─[S-ext b]→ ⟨(ab)(b)⟩ sup=2              ↪ NOT forward-closed
│       │   │                                      (I-ext c keeps sup=2)
│       │   └─[I-ext c]→ ⟨(ab)(bc)⟩ sup=2         🚫 Envelope fail (S-prepend {d})
│       │
│       └─[S-ext c]→ ⟨(ab)(c)⟩ sup=2              ✂ Gate 1 PRUNE (local-gap {b})
│
├─[S-ext b]→ ⟨(b)⟩ sup=3                          ✂ Gate 1 PRUNE (local-gap {a})
├─[S-ext c]→ ⟨(c)⟩ sup=2                          ✂ Gate 1 PRUNE (local-gap {b})
│
└─[S-ext d]→ ⟨(d)⟩ sup=2                          ↪ NOT forward-closed
    │                                               (S-ext a keeps sup=2)
    ├─[S-ext a]→ ⟨(d)(a)⟩ sup=2                   ↪ NOT forward-closed
    │   │                                           (S-ext a keeps sup=2)
    │   ├─[S-ext a]→ ⟨(d)(a)(a)⟩ sup=2            ↪ NOT forward-closed
    │   │   │                                       (I-ext b keeps sup=2)
    │   │   ├─[I-ext b]→ ⟨(d)(a)(ab)⟩ sup=2       ↪ NOT forward-closed
    │   │   │   │                                   (S-ext b keeps sup=2)
    │   │   │   ├─[S-ext b]→ ⟨(d)(a)(ab)(b)⟩ sup=2 ↪ NOT forward-closed
    │   │   │   │   │                                (I-ext c keeps sup=2)
    │   │   │   │   └─[I-ext c]→ ⟨(d)(a)(ab)(bc)⟩ sup=2 ★ OUTPUT (closed)
    │   │   │   │
    │   │   │   └─[S-ext c]→ ⟨(d)(a)(ab)(c)⟩ sup=2 ✂ Gate 1 PRUNE (local-gap {b})
    │   │   │
    │   │   ├─[S-ext b]→ ⟨(d)(a)(a)(b)⟩ sup=2     ↪ NOT forward-closed
    │   │   │   │                                   (I-ext c keeps sup=2)
    │   │   │   └─[I-ext c]→ ⟨(d)(a)(a)(bc)⟩ sup=2 🚫 Envelope fail (Middle I-augment: 3rd elem {a}→{ab})
    │   │   │
    │   │   └─[S-ext c]→ ⟨(d)(a)(a)(c)⟩ sup=2     ✂ Gate 1 PRUNE (local-gap {b})
    │   │
    │   ├─[S-ext b]→ ⟨(d)(a)(b)⟩ sup=2            ✂ Gate 1 PRUNE (local-gap {a})
    │   │
    │   └─[S-ext c]→ ⟨(d)(a)(c)⟩ sup=2            ✂ Gate 1 PRUNE (local-gap {b})
    │
    ├─[S-ext b]→ ⟨(d)(b)⟩ sup=2                   ✂ Gate 1 PRUNE (local-gap {a})
    │
    └─[S-ext c]→ ⟨(d)(c)⟩ sup=2                   ✂ Gate 1 PRUNE (local-gap {b})
```

### Legend

| Symbol | Meaning |
|--------|---------|
| ★ OUTPUT | Passes Gate 1, Gate 2 (forward-closed), and Gate 3 (envelope) |
| ✂ Gate 1 PRUNE | BackScan witness found → subtree cut immediately |
| ↪ NOT forward-closed | Has same-support forward extension → envelope skipped |
| 🚫 Envelope fail | Forward-closed, but exact verification finds same-support superpattern |

### Why Local-Gap Witness Works

When S-extending to match item `x` at an itemset containing items < x:
- If those smaller items appear in ALL supporting sequences' matched itemsets
- Then they form a **local-gap witness** (same-support I-augment exists)

**Examples**:
- ⟨(b)⟩ matches at {a,b} → item {a} < b exists in all SIDs → **witness {a}**
- ⟨(a)(ab)(b)⟩ matches 'b' at {b,c} → no items < b in {b,c} → **no witness** → passes Gate 1


---

## DFS Execution Trace

### Node A1: P = ⟨(a)⟩, support = 4

**How we got here**: S-extension from root by item 'a'. First occurrence of 'a' found at:
- S1: position 1, S2: position 1, S3: position 0, S4: position 0

**PointerStore**:
```
SID  startIdx  currentIdx  lastItem
S1:    0          1          a         0      ← For first element, startIdx = 0 by definition
S2:    0          1          a         0
S3:    0          0          a         0
S4:    0          0          a         0
```

**Gate 1: BackScan Check**

*Temporal witness* — check items in `[startIdx, currentIdx)`:
- S1: [0,1) = position 0 = {d}
- S2: [0,1) = position 0 = {d}
- S3: [0,0) = ∅ (empty range)
- S4: [0,0) = ∅

**Intersection**: {d} ∩ {d} ∩ ∅ ∩ ∅ = **∅**

*Intra-itemset witness* — item < lastItem in the same matched itemset:
- Items < a in current itemset? No items < a exist.

**Result**: No witness → continue (no subtree pruning)

**Gate 2: Forward-Closed Check**

Enumerate extensions from each SID's suffix after currentIdx:
- S1: positions 2,3 → {a,b,c}
- S2: positions 2,3 → {a,b,c}
- S3: position 1 → {a,b}
- S4: no positions → ∅

Extension supports: a→3, b→3, c→2

**Parent support = 4, no extension has support 4** → Forward-closed = YES

**Gate 3: Envelope Verification**

Compute envelopes for element E₀ = {a}:
```
SID   first(a)  last(a)
S1:      1         2       ← last 'a' is at position 2 (in {a,b})
S2:      1         2
S3:      0         1       ← last 'a' is at position 1 (in {a,b})
S4:      0         0       ← only one 'a' at position 0
```

*Backward S-prepend* — window `[0, last(E₀))`:
- S1: [0,2) = positions 0,1 = {d} ∪ {a} = {a,d}
- S2: [0,2) = positions 0,1 = {a,d}
- S3: [0,1) = position 0 = {a}
- S4: [0,0) = ∅
- Intersection = {a,d} ∩ {a,d} ∩ {a} ∩ ∅ = **∅** (S4 blocks)


*Backward I-augment* — extra items in itemsets matching {a} within [first, last] window:
- S1: {a,b} at pos 2 is in window [1,2] → extras = {b}
- S2: {a,b} at pos 2 is in window [1,2] → extras = {b}
- S3: {a,b} at pos 1 is in window [0,1] → extras = {b}
- S4: only {a} at pos 0 → extras = ∅
- Intersection = {b} ∩ {b} ∩ {b} ∩ ∅ = **∅** (S4 blocks)

**All checks pass** → **OUTPUT: ⟨(a)⟩ #SUP: 4** ✅

---

### Node A2: P = ⟨(a)(a)⟩, support = 3

**How we got here**: S-extension from ⟨(a)⟩ by item 'a'. Next 'a' after parent's currentIdx:
- S1: currentIdx was 1, next 'a' at position 2 (in itemset {a,b})
- S2: same
- S3: currentIdx was 0, next 'a' at position 1 (in itemset {a,b})
- S4: drops (no 'a' after position 0)

**PointerStore**:
```
SID  startIdx  currentIdx  lastItem
S1:    2          2          a         0      ← startIdx = parent_currentIdx + 1 = 1+1 = 2
S2:    2          2          a         0
S3:    1          1          a         0      ← startIdx = 0+1 = 1
```

**Gate 1: BackScan Check**

*Temporal witness* — `[startIdx, currentIdx)`:
- S1: [2,2) = ∅
- S2: [2,2) = ∅
- S3: [1,1) = ∅

**All empty** → No witness → continue

**Gate 2: Forward-Closed Check**

I-extension by 'b' (b > a in current itemset {a,b}):
- S1,S2,S3 all have 'b' at currentIdx → support = 3 = parent support

**Has same-support extension** → Forward-closed = NO → skip envelope

**Not output** (absorbed by ⟨(a)(ab)⟩)

---

### Node A3: P = ⟨(a)(ab)⟩, support = 3

**How we got here**: I-extension from ⟨(a)(a)⟩ by item 'b'.

**PointerStore** (I-extension preserves startIdx and currentIdx):
```
SID  startIdx  currentIdx  lastItem
S1:    2          2          b         1      ← I-ext: unchanged startIdx/currentIdx
S2:    2          2          b         1
S3:    1          1          b         1
```

**Gate 1: BackScan Check**

*Temporal witness* — `[startIdx, currentIdx)`:
- S1: [2,2) = ∅
- S2: [2,2) = ∅
- S3: [1,1) = ∅

**All empty** → No witness

*Intra-itemset check*: No item $x < b$ ($x \neq a$) in matched itemsets.

**Result**: No witness → continue

**Gate 2: Forward-Closed Check**

S-extensions after currentIdx:
- S1: position 3 = {b,c} → candidates b, c
- S2: position 3 = {b,c} → candidates b, c
- S3: no positions after 1 → ∅

Extension supports: b→2, c→2

**Parent support = 3, no extension has support 3** → Forward-closed = YES

**Gate 3: Envelope Verification**

Envelopes:
```
       E₀={a}           E₁={ab}
SID   first  last      first  last
S1:     1     1          2      2
S2:     1     1          2      2
S3:     0     0          1      1
```

*Backward S-prepend* — `[0, last(E₀))`:
- S1: [0,1) = {d}
- S2: [0,1) = {d}
- S3: [0,0) = ∅
- Intersection = ∅ → **No witness**

*Gap S-insert* — `(last(E₀)+1, first(E₁))`:
- S1: (1+1, 2) = [2,2) = ∅
- S2: (1+1, 2) = [2,2) = ∅
- S3: (0+1, 1) = [1,1) = ∅
- Intersection = ∅ → **No witness**

*I-augment checks*: All matching itemsets exactly match pattern elements

**All checks pass** → **OUTPUT: ⟨(a)(ab)⟩ #SUP: 3** ✅

---

### Node A4: P = ⟨(a)(ab)(b)⟩, support = 2

**How we got here**: S-extension from ⟨(a)(ab)⟩ by item 'b'.

**PointerStore**:
```
SID  startIdx  currentIdx  lastItem
S1:    3          3          b         0      ← startIdx = parent_currentIdx + 1 = 2+1 = 3
S2:    3          3          b         0
```
(S3 drops — no positions after 1)

**Gate 1: BackScan Check**

*Temporal witness* — `[startIdx, currentIdx)`:
- S1: [3,3) = ∅
- S2: [3,3) = ∅

**Empty** → No witness → continue

**Gate 2: Forward-Closed Check**

I-extension by 'c' (c > b in current itemset {b,c}):
- S1,S2 both have 'c' at position 3 → support = 2 = parent support

**Has same-support extension** → Forward-closed = NO → skip envelope

**Not output** (absorbed by ⟨(a)(ab)(bc)⟩)

---

### Node A5: P = ⟨(a)(ab)(bc)⟩, support = 2

**How we got here**: I-extension from ⟨(a)(ab)(b)⟩ by item 'c'.

**PointerStore** (I-extension preserves startIdx/currentIdx):
```
SID  startIdx  currentIdx  lastItem
S1:    3          3          c         1
S2:    3          3          c         1
```

**Gate 1: BackScan Check**

*Temporal witness* — `[startIdx, currentIdx)`:
- S1: [3,3) = ∅
- S2: [3,3) = ∅

**Empty** → No witness

*Intra-itemset check*: No item $x < c$ ($x \neq a, b$) in matched itemsets.

**Result**: No witness → continue

**Gate 2: Forward-Closed Check**

No positions after currentIdx=3 (end of sequences) → no extensions

**No extensions** → Forward-closed = YES

**Gate 3: Envelope Verification**

Envelopes:
```
       E₀={a}    E₁={ab}    E₂={bc}
SID   first/last first/last first/last
S1:    1/1        2/2        3/3
S2:    1/1        2/2        3/3
```

*Backward S-prepend* — `[0, last(E₀))`:
- S1: [0,1) = position 0 = {d}
- S2: [0,1) = position 0 = {d}
- **Intersection = {d}** → **WITNESS FOUND!**

Item 'd' can be S-prepended: ⟨(d)(a)(ab)(bc)⟩ has same support.

**Envelope check fails** → **NOT OUTPUT** 🚫

> **Note**: Per TriBack-Clo's DFS, we do NOT prune the subtree here — we just skip output and continue to children. However, there are no children (end of sequence), so DFS backtracks.

---

### Node D1: P = ⟨(d)⟩, support = 2

**PointerStore**:
```
SID  startIdx  currentIdx  lastItem
S1:    0          0          d         0
S2:    0          0          d         0
```

**Gate 1: BackScan Check**

*Temporal witness* — `[0,0)` = ∅ → No witness

**Gate 2: Forward-Closed Check**

S-extension by 'a' at position 1: support = 2 = parent support

**Has same-support extension** → Forward-closed = NO

**Not output** (absorbed by ⟨(d)(a)⟩)

---

### Nodes D2-D4: ⟨(d)(a)⟩ → ⟨(d)(a)(a)⟩ → ⟨(d)(a)(ab)⟩

All have same-support extensions → NOT forward-closed → not output

---

### Node D5: P = ⟨(d)(a)(ab)(b)⟩, support = 2

**Gate 2**: I-extension by 'c' has support = 2 = parent → NOT forward-closed

**Not output**

---

### Node D6: P = ⟨(d)(a)(ab)(bc)⟩, support = 2

**How we got here**: I-extension from ⟨(d)(a)(ab)(b)⟩ by item 'c'.

**PointerStore**:
```
SID  startIdx  currentIdx  lastItem
S1:    3          3          c         1
S2:    3          3          c         1
```

**Gate 1: BackScan Check**

*Temporal witness* — `[3,3)` = ∅ → No witness

**Gate 2: Forward-Closed Check**

No positions after 3 → no extensions → Forward-closed = YES

**Gate 3: Envelope Verification**

Envelopes:
```
       E₀={d}    E₁={a}    E₂={ab}    E₃={bc}
SID   first/last first/last first/last first/last
S1:    0/0        1/1        2/2        3/3
S2:    0/0        1/1        2/2        3/3
```

*Backward S-prepend* — `[0, last(E₀))`:
- S1: [0,0) = ∅
- S2: [0,0) = ∅
- Intersection = ∅ → **No witness**

*All gap S-inserts*:
- Gap 0-1: [1,1) = ∅
- Gap 1-2: [2,2) = ∅
- Gap 2-3: [3,3) = ∅
- All empty → **No witness**

*I-augment checks*: All matching itemsets exactly match pattern elements → **No witness**

**All checks pass** → **OUTPUT: ⟨(d)(a)(ab)(bc)⟩ #SUP: 2** ✅

---

## Summary

| Pattern | Support | Gate 1 | Gate 2 | Gate 3 | Output |
|---------|---------|--------|--------|--------|--------|
| ⟨(a)⟩ | 4 | pass | ✅ forward-closed | ✅ pass | ✅ **OUTPUT** |
| ⟨(a)(a)⟩ | 3 | pass | ❌ not forward-closed | skip | ❌ |
| ⟨(a)(ab)⟩ | 3 | pass | ✅ forward-closed | ✅ pass | ✅ **OUTPUT** |
| ⟨(a)(ab)(b)⟩ | 2 | pass | ❌ not forward-closed | skip | ❌ |
| ⟨(a)(ab)(bc)⟩ | 2 | pass | ✅ forward-closed | ❌ {d} witness | 🚫 |
| ⟨(d)⟩ | 2 | pass | ❌ not forward-closed | skip | ❌ |
| ... | ... | ... | ... | ... | ... |
| ⟨(d)(a)(ab)(bc)⟩ | 2 | pass | ✅ forward-closed | ✅ pass | ✅ **OUTPUT** |

**Final closed patterns**: ⟨(a)⟩ sup=4, ⟨(a)(ab)⟩ sup=3, ⟨(d)(a)(ab)(bc)⟩ sup=2

---

## Key Algorithmic Points

### 1. Extension Rules for startIdx

```
S-extension:  startIdx = parent_currentIdx + 1
I-extension:  startIdx = parent_startIdx (unchanged)
```

This ensures the semi-maximum period `[startIdx, currentIdx)` correctly captures the gap between the (k-1)th and kth pattern elements.

### 2. Local-Gap Check

This generalization covers both singleton and multi-item tails. Unlike single-item BackScan which only checks $x < \min(P_k)$, TriBack-Clo checks all $x \in E_{match(k)}$ such that $x < \max(P_k)$ and $x \notin P_k$.

### 3. Gate 3 Failure Does NOT Prune Subtree

When envelope verification fails:
- The pattern is **not output** (it has a same-support superpattern)
- DFS **continues to children** as normal

Only Gate 1 (BackScan witness) causes immediate subtree pruning, because a BackScan witness implies ALL descendants also have the same backward extension.

### 4. Why ⟨(a)(ab)(bc)⟩ Fails but ⟨(d)(a)(ab)(bc)⟩ Passes

- **⟨(a)(ab)(bc)⟩**: Envelope finds {d} as a backward S-prepend witness. Both S1 and S2 have {d} at position 0, before the first element {a}. So ⟨(d)(a)(ab)(bc)⟩ is a same-support superpattern.

- **⟨(d)(a)(ab)(bc)⟩**: The first element is now {d} at position 0. The backward S-prepend window `[0, last(d))` = `[0,0)` is empty — nothing can be prepended before position 0.

---

## Execution Statistics

Running TriBack-Clo on this example dataset produces:

```
 -cp triback-clo-java/triback-clo.jar:experiments/spmf.jar ca.pfv.spmf.algorithms.sequentialpatterns.tribackclo.MainTestTriBackClo experiments/datasets/execution_example_test.txt /tmp/triback-output.txt 2

ItemsetSequenceDatabase Statistics:
  Sequences: 4
  Total itemsets: 11
  Total items: 16
  Avg itemsets/seq: 2.8
  Avg items/itemset: 1.5
  Max itemset size: 2
  Max sequence length: 4
  Max item ID: 4

[TriBackCloMiner] Mining: 0.007 seconds
[TriBackCloMiner] Nodes visited: 28
[TriBackCloMiner] Subtrees pruned: 12
[TriBackCloMiner] Closed patterns found: 3

Sample patterns:
  4 -> 1 -> (1,2) -> (2,3)  [sup=2]   ← ⟨(d)(a)(ab)(bc)⟩
  1                         [sup=4]   ← ⟨(a)⟩
  1 -> (1,2)                [sup=3]   ← ⟨(a)(ab)⟩
```

### Summary Statistics

| Metric | Value | Notes |
|--------|-------|-------|
| **Database** | | |
| Sequences | 4 | S1, S2, S3, S4 |
| Total itemsets | 11 | Sum of sequence lengths |
| Distinct items | 4 | a, b, c, d |
| **Mining** | | |
| Minimum support | 2 (50%) | Absolute count |
| Mining time | 0.007s | Excludes I/O |
| **DFS Traversal** | | |
| Nodes visited | 28 | All nodes entered in DFS |
| Gate 1 prunes | 12 | Subtrees cut by BackScan |
| Forward-closed nodes | ~7 | Reached Gate 2, passed to Gate 3 |
| Envelope verifications | ~7 | Performed on ALL forward-closed nodes |
| **Output** | | |
| Closed patterns | 3 | ★ passed all 3 gates |
| Non-closed (envelope fail) | ~4 | 🚫 passed Gate 2, failed Gate 3 |

### Efficiency Analysis

| Optimization | Impact |
|--------------|--------|
| **Gate 1 pruning** | 12 subtrees cut → saves ~30+ potential node visits |
| **Gate 2 skip** | ~9 non-forward-closed nodes skip envelope verification |
| **Overall** | 21/28 nodes skipped envelope (12 Gate 1 prunes + ~9 not forward-closed) |

The three-gate architecture ensures expensive envelope verification runs only on forward-closed nodes.
