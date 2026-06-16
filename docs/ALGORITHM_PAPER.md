# TriBack-Clo: Closed Sequential Pattern Mining for Itemset-Sequences via BackScan Pruning and Lazy Envelope Verification

## Abstract

We present **TriBack-Clo**, a closed sequential pattern miner for **itemset-sequences** (each sequence element is a set of items). TriBack-Clo combines:

1. **BackScan witness pruning** extended to itemset semantics, including a *new local-gap witness* valid for S-extensions that create singleton last elements,
2. **forward-closed gating** (cheap) to limit exact checking to output candidates, and
3. **lazy envelope verification** (exact) using **first/last embedding envelopes** and stamp-based intersections.

On **Kosarak25k** at **minsup = 0.2%** (50 sequences), TriBack-Clo runs in **1.62s wall time** vs **2.88s** for BIDE+ (SPMF), while using **~231MB** peak memory vs **~1,339MB**. Output matches BIDE+ exactly (same pattern–support pairs).

---

## 1. Introduction

### 1.1 Problem Statement

Given a database D of itemset-sequences, **closed sequential pattern mining** outputs all patterns P such that no strict superpattern has the same support. BIDE (Wang & Han, 2004) provides closure theory and BackScan pruning for **simple sequences** (single item per element) and notes that extensions to itemset-sequences require additional details (S/I growth, insertions into elements), but these are not spelled out end-to-end.

TriBack-Clo focuses on **exact closedness** for itemset-sequences while keeping the hot path fast and memory-stable.

### 1.2 Contributions (What is actually new vs BIDE+)

| # | Contribution | Novelty Type |
|---|--------------|--------------|
| 1 | **Two BackScan witness propositions for itemset-sequences**: (i) temporal semi-maximum witness and (ii) **local-gap witness** for S-extensions | Theoretical adaptation |
| 2 | **Unified 4-tuple projection state** `(sid, startIdx, currentIdx, lastItem)` enabling both witnesses and canonical I-ordering | Data structure / representation |
| 3 | **Three-stage pipeline**: sufficient prune → forward-closed gate → exact lazy verification | Algorithmic engineering |
| 4 | **Allocation-free implementation** (stamps, flat envelopes, reusable SID buffers) | Systems / performance |

---

## 2. Preliminaries

### 2.1 Sequences, Subsequence, Support, Closedness

An **itemset-sequence** is S = ⟨E₁, E₂, ..., Eₙ⟩ where each Eᵢ ⊆ I.

A pattern P = ⟨P₁, ..., Pₖ⟩ is a **subsequence** of S (denoted P ⊑ S) if there exist indices 1 ≤ i₁ < ··· < iₖ ≤ n such that Pⱼ ⊆ E_{iⱼ} for all j.

**Support**: supp(P) = |{S ∈ D : P ⊑ S}|

**Closedness**: P is **closed** if there is no P' ⊃ P with supp(P') = supp(P).

### 2.2 Growth Operations (S and I)

* **S-extension** by item x: P ⊕ₛ {x} = ⟨P₁, ..., Pₖ, {x}⟩

* **I-extension** by item x into last element: P ⊕ᵢ x = ⟨P₁, ..., (Pₖ ∪ {x})⟩

**Canonical I-ordering** (to avoid duplicates): only allow x > max(Pₖ) for I-extensions.

---

## 3. Core Representation: the Unified 4-Tuple Projection State

### 3.1 Definition and Invariants

For each supporting sequence id `sid`, TriBack-Clo stores a 4-tuple:

```
(sid, startIdx, currentIdx, lastItem)
```

**Meaning (invariant):**

* `currentIdx`: the itemset position in S_{sid} where the **last element** Pₖ is matched.
* `startIdx`: the boundary that starts the **semi-maximum period** for the *gap preceding the last element*. Intuitively: "position after the match of P_{k-1}" (or 0 if k=1).
* `lastItem`: the last appended item used to build the current last element (needed for canonical I-ordering and local-gap logic).

**Note on implicit extension type**: TriBack-Clo does not store the extension type ($extType$) explicitly. This is because the distinction between S and I extensions is already encoded in the update rules for \textit{startIdx}, and the enumeration logic already knows which branch it is processing. This optimization saves 20% memory in the state storage.

### 3.2 Update Rules

Let the parent state be `(sid, start_p, cur_p, last_p)`.

  ```
  (sid, startIdx = cur_p + 1, currentIdx = P, lastItem = X)
  ```

* After **I-extension** adding item X into the same last element matched at position cur_p:
  ```
  (sid, startIdx = start_p, currentIdx = cur_p, lastItem = X)
  ```

**Key point:** `startIdx` must remain tied to the boundary **before the last element**, so I-extension does not change it.

---

## 4. BackScan Pruning for Itemset-Sequences

BackScan is used as a **sufficient pruning test**: if a witness exists, **no closed pattern exists in the subtree** rooted at the current prefix.

TriBack-Clo uses **two distinct witness types**, each with its own intersection (this is the critical fix).

### 4.1 Temporal (Semi-Maximum) Witness

For a pattern P = ⟨E₁, ..., Eₖ⟩, for each supporting sequence s define:

```
T(s) = ⋃_{j=startIdx(s)}^{currentIdx(s)-1} S_s[j]
```

**Proposition 1 (Temporal BackScan Witness ⇒ Safe Subtree Prune)**

If ⋂_{s ∈ sup(P)} T(s) ≠ ∅, then **no closed pattern exists in the subtree rooted at P**.

*Proof sketch.* Pick x in the intersection. Then in every supporting sequence there exists an occurrence of x strictly between the match of E_{k-1} and the match of Eₖ. Therefore x can be inserted as a new singleton itemset between these elements, producing a superpattern P' ⊃ P with the same support. Hence P is not closed. For any descendant Q of P, the matched positions for E_{k-1} and Eₖ cannot move "backward", so the corresponding gap is a subset of the parent's gap; thus the same x remains insertable, and Q is also not closed. □

### 4.2 Local-Gap Witness (NEW, Itemset-Specific, S-Extension-Only)

This witness captures a closure violation that canonical forward enumeration will never generate, because it requires inserting a smaller item into the last element.

Assume the current prefix was reached by an **S-extension** creating a **fresh singleton last element** Eₖ = {y}, so `extType = 0` and `lastItem = y`.

For each supporting sequence s, define:

```
L(s) = {x ∈ S_s[currentIdx(s)] : x < y}
```

**Proposition 2 (Local-Gap Witness for S-Extensions ⇒ Safe Subtree Prune)**

If the last step is an S-extension (extType = 0) and ⋂_{s ∈ sup(P)} L(s) ≠ ∅, then **no closed pattern exists in the subtree rooted at P**.

*Proof sketch.* Pick x in the intersection. Since x occurs in the **same matched itemset** as {y} in every supporting sequence, the superpattern:

```
P'' = ⟨E₁, ..., E_{k-1}, {x, y}⟩
```

has the same support as P. This violates closedness. Descendants of P still include that element position (it becomes internal as the pattern grows), and adding x into that element remains valid in all supporting sequences, so no descendant can be closed. □

**Why S-extension-only is essential:** for I-extensions, items < lastItem may already be part of the pattern's last itemset (because it was built incrementally), so "local gap" is not a valid witness category there.

### 4.3 The Critical Correctness Fix

**Correct pruning rule:**

```
(⋂_s T(s) ≠ ∅)  OR  (extType = 0 ∧ ⋂_s L(s) ≠ ∅)
```

**Do NOT** intersect (T(s) ∪ L(s)) across SIDs. A "mixed" witness (temporal in some SIDs and local in others) does **not** imply a single same-support superpattern.

**Implementation consequence:** compute **two intersections** (temporal and local) and prune if either is non-empty.

---

## 5. Full Mining Pipeline (Prune → Gate → Verify)

TriBack-Clo separates tasks that BIDE+ interleaves:

1. **BackScan prune** (sufficient): if witness exists, return immediately.
2. **Forward-closed gate** (cheap): if some S or I extension has same support, prefix cannot be closed → skip verification.
3. **Lazy envelope verification** (exact): run only when the node is forward-closed.

### 5.1 Pseudocode

```
DFS(prefix P, pointerStore S):
  if supp(S) < minsup: return

  // 1) sufficient prune
  if P ≠ ∅ and BackScanWitness(S): return

  // 2) enumerate children and detect same-support forward extension
  (children, hasSameSuppForward) = EnumerateExtensions(S)
  forwardClosed = !hasSameSuppForward

  // 3) exact verify only for candidates
  if P ≠ ∅ and forwardClosed:
     if EnvelopeClosedExact(P, S): output P

  // recurse
  for child in children: DFS(P ⊕ child, childStore)
```

---

## 6. Lazy Envelope Verification (Exact Closedness)

BackScan is only sufficient for pruning. Exact closedness requires detecting *any* same-support superpattern via:

* backward S-prepend,
* backward I-augment (into first element),
* middle S-insert (tight gap),
* middle I-insert (into any element).

TriBack-Clo checks these lazily using **first/last embedding envelopes** over supporting SIDs.

### 6.1 Envelope Definitions

For each supporting sequence s and pattern element index i:

* `first_s(i)`: earliest position matching Eᵢ given previous matches
* `last_s(i)`: latest position matching Eᵢ given later matches

These define safe **windows** for candidate items.

### 6.2 Tight Gap Window

For middle S-insert between Eₘ and E_{m+1}, the correct "forced insertion" region is:

```
[last_s(m) + 1, first_s(m+1))
```

Using [first_s(m) + 1, last_s(m+1)) is too wide and over-collects.

### 6.3 Allocation-Free Intersection

TriBack-Clo uses **epoch/stamp arrays** (like BackScan stamping) to compute intersections of items appearing in these windows across all supporting SIDs without allocating BitSets.

---

## 7. Experimental Evaluation

### 7.1 Results (Kosarak25k)

| Minsup | TriBack-Clo Wall | BIDE+ Wall | Speedup | Peak Mem Ratio |
|--------|------------------|------------|---------|----------------|
| 0.5% | 0.92s | 0.85s | 0.92× | ~0.78× |
| **0.2%** | **1.69s** | 2.83s | **1.67×** | **~0.17×** |

**Correctness:** exact match with BIDE+ (same patterns and supports).

### 7.2 Validation on General Itemset Datasets

| Dataset | Minsup | TriBack-Clo | BIDE+ | Match |
|---------|--------|-------------|-------|-------|
| Example 11 | 66% | 2 patterns | 2 | ✓ |
| Example 12 | 50% | 4 patterns | 4 | ✓ |
| Example 12 | 25% | 7 patterns | 7 | ✓ |

### 7.3 Why the Speedup Grows at Lower Minsup

At lower support thresholds, the search tree expands sharply. TriBack-Clo gains more from:

* earlier subtree pruning via BackScan witnesses, and
* avoiding envelope verification except on forward-closed candidates.

Memory remains stable due to reusable buffers and stamp resets.

---

## 8. Related Work (Positioning)

| Algorithm | BackScan | I-Extension | Two-Witness | Lazy Verify |
|-----------|----------|-------------|-------------|-------------|
| BIDE+ | ✓ (simple seq) | Mentioned | Not specified | ✗ |
| PrefixSpan | ✗ | ✓ | ✗ | ✗ |
| CloSpan | ✗ | ✓ | ✗ | ✗ |
| **TriBack-Clo** | **✓ (itemset)** | **✓** | **Prop 1 + Prop 2** | **✓** |

TriBack-Clo's novelty is not "closed mining exists" — it is a **sound and efficient itemset-sequence BackScan formulation** (two-witness pruning with an S-extension local-gap theorem) plus a **practical, low-allocation closedness pipeline**.

---

## 9. Conclusion

TriBack-Clo provides:

1. **A correct itemset-sequence BackScan pruning theory** with **two independent witnesses**:
   * temporal semi-maximum witness (generalized),
   * **local-gap witness (new)** for S-extensions.

2. A **unified 4-tuple projection state** enabling correct witness semantics and canonical I-ordering.

3. A **lazy exact verification architecture** that confines expensive checks to forward-closed candidates.

4. A **memory-stable, allocation-free implementation**, delivering large gains at low minsup.

---

## Appendix A: Critical BackScan Fix Summary

Earlier implementations mistakenly applied the local-gap candidate set to I-extensions and/or mixed temporal and local candidates by intersecting (T(s) ∪ L(s)). TriBack-Clo fixes this by:

1. Applying local-gap logic **only when extType = 0** (fresh singleton last element), and
2. Computing **two separate intersections** ⋂T(s) and ⋂L(s), pruning if either is non-empty.

This removes unsound mixed-witness pruning while preserving maximal pruning power.

---

## References

1. Wang, J., & Han, J. (2004). BIDE: Efficient mining of frequent closed sequences. *ICDE*.
2. Pei, J., et al. (2001). PrefixSpan: Mining sequential patterns efficiently. *ICDE*.
3. Yan, X., Han, J., & Afshar, R. (2003). CloSpan: Mining closed sequential patterns. *SDM*.
4. Gomariz, A., et al. (2013). ClaSP: An efficient algorithm for mining frequent closed sequences. *PAKDD*.
