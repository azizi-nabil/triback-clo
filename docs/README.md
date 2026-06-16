# TriBack-Clo V2.0

**Adaptive Projected-Vertical Closed Sequential Pattern Mining with BIDE-style BackScan Pruning**

> **Key novelty:** Fused closure certification + BIDE-style BackScan pruning using correct semi-maximum periods, achieving **183x speedup** at low minsup and outperforming BIDE+ by **3x**.

---

## Performance Results (Kosarak25k, 25,000 sequences)

| minsup | Patterns | TriBack-Clo V2.0 | BIDE+ | Speedup vs BIDE+ |
|--------|----------|------------------|-------|------------------|
| 75 | 3,972 | **0.64s** | 1.22s | **1.9x faster** |
| 50 | 9,005 | **1.2s** | ~2s | **1.7x faster** |
| 25 | 42,671 | **4.35s** | 13.6s | **3.1x faster** |

### V2.0 vs V1.0 at minsup=25

| Metric | V1.0 | V2.0 | Improvement |
|--------|------|------|-------------|
| Time | 795s | **4.35s** | **183x faster** |
| DFS nodes | 28M | 264K | 106x fewer |
| Item updates | 23.7B | 95M | 249x fewer |
| Pruned subtrees | 0 | 58,257 | - |

---

## Quick Start

```bash
# Single-node with minsup
sbt "runMain apvclofast.APVCloFAST_Main --input data/kosarak25k.txt --minsup 25"

# With ratio (0.001 = 0.1%)
sbt "runMain apvclofast.APVCloFAST_Main --input data/kosarak25k.txt --ratio 0.001"

# Spark distributed
sbt "runMain apvclofast.APVCloFAST_Spark --input data/kosarak25k.txt --minsup 25 --partitions 16"
```

---

## Algorithm Theory

### 1. Closed Sequential Pattern Mining

A sequential pattern P is **closed** if there exists no super-pattern P' where:
- P is a subsequence of P'
- support(P) = support(P')

Closure eliminates redundancy: instead of mining millions of patterns, we mine only the maximal ones.

### 2. Closure Certification (Fused)

TriBack-Clo computes closure signals **during enumeration**, not as separate scans:

```scala
case class ClosureCert(
    hasSameSuppForward: Boolean,    // ∃ extension with same support?
    backwardWitnessSet: SeqBitset,  // Items appearing before pattern in ALL seqs
    middleClosed: Option[Boolean]   // Future: middle extension check
)
```

**Forward-closed**: No same-support forward extension exists.
**Backward-closed**: No item appears before pattern in ALL supporting sequences.

### 3. BIDE-style BackScan Pruning (Key Innovation in V2.0)

#### The Problem
At low minsup, the DFS search space explodes (28M nodes at minsup=25). Even fast per-node enumeration can't overcome this.

#### The Solution: Semi-Maximum Period Pruning

For pattern P = s₁s₂...sₙ, define the **i-th semi-maximum period** as the segment between:
- Where the (i-1)th pattern item ends
- Where the i-th pattern item starts

```
Sequence:  A  B  C  D  E  F
Pattern:      [B]    [E]
              ↑      ↑
         startPos  endPos

Semi-max period for E: seq[startPos, endPos-1] = {C, D}
```

**BIDE Theorem**: If an item appears in the last semi-maximum period of **ALL** supporting sequences, the entire subtree can be pruned.

#### Implementation

PointerStore now stores **triples** `(sid, startPos, endPos)`:

```scala
class PointerStore(
    sidPositions: Array[Int],  // Triples: (sid, startPos, endPos)
    numSids: Int,
    db: SequenceDatabase
)

def detectBackScanWitness(db: SequenceDatabase, maxItem: Int): Boolean = {
    // Intersect items in [startPos, endPos-1] across ALL SIDs
    // If intersection is non-empty → witness exists → prune subtree
}
```

---

## Algorithm Steps

```
TriBack-Clo Mining Algorithm:

1. BUILD ITEM INDEX
   - Compute support for each item using stamp-based tracking
   - Build global frequency mask for fast pruning
   - Create position index for O(log n) lookups

2. INITIALIZE ROOT STORE
   - Create PointerStore with all sequences at (sid, 0, 0)
   - Start DFS from empty prefix

3. FOR EACH DFS NODE (prefix, store):
   a. BACKSCAN PRUNE CHECK (before expensive enumeration)
      - If detectBackScanWitness returns true → PRUNE entire subtree
      - This is O(support × avgPeriodLen), saves O(support × seqLen) forward scan
   
   b. ENUMERATE EXTENSIONS with closure certificate
      - Scan each supporting sequence ONCE from endPos
      - Track first occurrence of each item per SID
      - Compute hasSameSuppForward during enumeration
   
   c. EMIT if closed
      - Check forward-closed: !hasSameSuppForward
      - Check backward-closed: no item in [0, startPos) for ALL SIDs
      - Emit pattern if both conditions hold
   
   d. RECURSE on frequent extensions
      - Create child PointerStore with (sid, parentEndPos, childEndPos)
      - Pass correct semi-maximum period boundaries

4. RETURN all closed patterns (streaming output, no buffering)
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    TriBack-Clo V2.0 Architecture               │
│   Closed Sequential Mining + BackScan Pruning + Adaptive Stores │
└─────────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌───────────────┐     ┌───────────────┐     ┌───────────────┐
│ APVLocalMiner │     │  PointerStore │     │ VerticalStore │
│               │     │   (V2.0)      │     │   (Dense)     │
│ • DFS mining  │     │               │     │               │
│ • BackScan    │     │ • Triples:    │     │ • Bitset ops  │
│   prune gate  │     │   (sid,start, │     │ • Memory-     │
│ • Closure     │     │    end)       │     │   efficient   │
│   emission    │     │ • Semi-max    │     │               │
└───────────────┘     │   period      │     └───────────────┘
                      │ • Per-SID     │
                      │   scanning    │
                      └───────────────┘
```

---

## Key Files

| File | Purpose |
|------|---------|
| `APVLocalMiner.scala` | DFS mining with BackScan prune gate |
| `PointerStore.scala` | Triple-based pseudo-projection with semi-max periods |
| `OccurrenceStore.scala` | Store trait + ReusableEnumBuffers |
| `VerticalStore.scala` | Bitset-based store for dense patterns |
| `APVCloFAST_Main.scala` | Single-node entry point |
| `APVCloFAST_Spark.scala` | Distributed execution |
| `docs/THROUGHOUT_EXAMPLE.md` | Trace example of PointerStore creation |
| `docs/EXECUTION_EXAMPLE.md` | Step-by-step mining execution trace |

---

## Novel Contributions

1. **Fused Closure Certification**: Closure signals computed as byproduct of enumeration
2. **Correct BackScan Pruning**: Using semi-maximum periods, not backward closure
3. **Triple-based PointerStore**: Enables correct boundary tracking for pruning
4. **3x faster than BIDE+**: At low minsup where BIDE+ traditionally dominates

---

## Mathematical Foundation

### Definition: Semi-Maximum Period

For sequence S and pattern P = s₁s₂...sₙ with first-instance positions p₁ < p₂ < ... < pₙ:

The **n-th semi-maximum period** is `S[pₙ₋₁ + 1, pₙ - 1]`

(The gap between where the (n-1)th item ends and where the nth item starts)

### Theorem: BackScan Pruning (BIDE)

If ∃ item e such that e ∈ SemiMaxPeriodₙ(S) for ALL S in support(P), then:
- P has a same-support backward extension (e prepended to P)
- All descendants of P also have same-support backward extensions
- Therefore, no closed patterns exist in subtree(P)
- **Safe to prune entire subtree**

### Complexity Analysis

| Operation | V1.0 | V2.0 | 
|-----------|------|------|
| Forward scan | O(occ × suffix) | O(supp × seqLen) |
| BackScan check | N/A | O(supp × periodLen) |
| Total at minsup=25 | 23.7B ops | 95M ops |

---

## Tuning Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `enableBackScanPruning` | true | Enable BIDE-style subtree pruning |
| `verticalThreshold` | 100000 | Switch to VerticalStore when estimatedWork exceeds this |
| `minsup` / `ratio` | - | Minimum support threshold |

---

## Citation

If using TriBack-Clo in research, please cite the BIDE paper for the pruning theorem:

```bibtex
@inproceedings{wang2004bide,
  title={BIDE: Efficient mining of frequent closed sequences},
  author={Wang, Jianyong and Han, Jiawei},
  booktitle={ICDE},
  year={2004}
}
```
