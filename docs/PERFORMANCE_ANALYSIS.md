# TriBack-Clo V2.0 Performance Analysis

## Executive Summary

TriBack-Clo V2.0 with BIDE-style BackScan pruning achieves **183x speedup** at minsup=25, becoming **3x faster than BIDE+**.

---

## Performance Results (Kosarak25k, 25,000 sequences)

| minsup | Patterns | V1.0 | V2.0 | BIDE+ | V2.0 vs BIDE+ |
|--------|----------|------|------|-------|---------------|
| 75 | 3,972 | 0.95s | **0.64s** | 1.22s | **1.9x faster** |
| 50 | 9,005 | 1.96s | **1.2s** | ~2s | **1.7x faster** |
| 25 | 42,671 | 795s | **4.35s** | 13.6s | **3.1x faster** |

---

## V2.0 Breakthrough: BackScan Pruning

### Before vs After at minsup=25

| Metric | V1.0 (No Pruning) | V2.0 (BackScan) | Reduction |
|--------|-------------------|-----------------|-----------|
| **Runtime** | 795s | **4.35s** | 183x |
| **DFS nodes** | 28,341,065 | **264,773** | 107x |
| **Item updates** | 23.7 billion | **95 million** | 249x |
| **Pruned subtrees** | 0 | **58,257** | - |

### Why Pruning Works

At minsup=25, without pruning:
- 28M DFS nodes to explore
- Each node scans suffixes, counting items
- Total work: O(nodes × support × seqLen)

With BackScan pruning:
- 58,257 subtrees pruned early
- Only 264K nodes actually enumerated
- Most dead-end branches avoided

---

## Key Innovation: Correct Semi-Maximum Periods

### The Problem with Naive Backward Check

Our V1.0 backward check computed:
```
backwardCandidates = ∩ seq[0, endPos) for all SIDs
```

This is for **backward closure** (emit decision), NOT **subtree pruning**.
Using it for pruning was **incorrect** (found 0 patterns instead of 3,972).

### The Correct BIDE Condition

BIDE's BackScan uses **semi-maximum periods**:
```
semiMaxPeriod = seq[startPos, endPos-1]
              = gap between parent pattern end and current item
```

A witness exists if:
```
∃ item e: e ∈ semiMaxPeriod(S) for ALL S in support
```

If witness exists → entire subtree prunable.

### Implementation Change

PointerStore now stores **triples** instead of pairs:
```
Before: (sid, endPos)          // Can't compute semi-max period
After:  (sid, startPos, endPos) // startPos = parent's endPos
```

---

## Code Changes Summary

| File | Change |
|------|--------|
| `PointerStore.scala` | Rewritten with triples, STRIDE=3, correct detectBackScanWitness |
| `APVLocalMiner.scala` | Added prune gate before enumeration |
| `OccurrenceStore.scala` | Added detectBackScanWitness to trait |

---

## Profiling Comparison

### V1.0 at minsup=25 (795s)
```
forwardScan: 591s (75%)
backwardScan: 107s (13%)
DFS nodes: 28,341,065
itemUpdates: 23,767,762,890
```

### V2.0 at minsup=25 (4.35s)
```
forwardScan: 2.9s (67%)
backwardScan: 0.5s (11%)
DFS nodes: 264,773 (pruned 58,257)
itemUpdates: 94,576,375
```

---

## Conclusion

TriBack-Clo V2.0 is now competitive with or faster than BIDE+ across all minsup levels, while maintaining the same pattern count and correctness.

The key insight: **Correct semi-maximum period tracking enables subtree pruning that cuts 99% of the search space at low minsup.**
