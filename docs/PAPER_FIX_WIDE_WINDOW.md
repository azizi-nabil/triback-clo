# Paper Fix: Wide Window for Middle S-Insert Closure Check

## Summary

The paper (`triback-clo-paper.tex`) describes the **Tight Window** for middle S-insert closure checking in Section 7.2 and Algorithm 2. This formula is **incorrect for repeated items** and must be replaced with the **Wide Window**.

---

## 1. Background: Envelope-Based Closure Checking

The BIDE algorithm [Wang & Han, 2004] checks if a pattern can be extended without losing support. For middle S-insert at gap g between elements Eᵧ and E_{g+1}:

- `firstPos(i)` = earliest position where Eᵢ can match across all embeddings
- `lastPos(i)` = latest position where Eᵢ can match across all embeddings

### Two Window Strategies

| Window | Formula | Represents |
|--------|---------|------------|
| **Tight** | `[lastPos(g)+1, firstPos(g+1))` | Intersection of all gaps |
| **Wide** | `[firstPos(g)+1, lastPos(g+1))` | Union of all gaps |

---

## 2. The Repeated Items Problem

### 2.1 When Tight Windows Fail

For patterns with **repeated items**, envelope positions overlap:

```
Pattern:   ⟨(1)(14)(1)(14)⟩
Sequence:  1, 7, 14, 1, 8, 14, 1, 9, 14

firstPos:  [0, 2, 3, 5]   // earliest matches
lastPos:   [6, 8, 6, 8]   // latest matches

Gap 0 tight window: (lastPos(0)+1, firstPos(1)) = (7, 2) = INVERTED!
```

An **inverted window** (from > to) incorrectly passes the closure check.

### 2.2 Experimental Evidence

- **MSNBC @ 0.2% (Buggy Tight)**: 10,106,825 patterns
- **MSNBC @ 0.2% (Fixed Wide)**: 9,286,171 patterns  
- **BIDE+ Reference**: 9,286,171 patterns

The Tight Window produced **820,654 extra non-closed patterns**.

---

## 3. Theoretical Justification

### BIDE Closure Property

A pattern P is **not closed** if there exists an extension item X that can be inserted between Eᵧ and E_{g+1} in **at least one valid embedding** per sequence.

### Why Union (Wide), Not Intersection (Tight)

- **Intersection (Tight)**: Positions valid in **ALL** embeddings → Under-approximation
- **Union (Wide)**: Positions valid in **ANY** embedding → Correct semantics

The BIDE property requires existential quantifier (∃ embedding), not universal (∀ embeddings).

### Correctness Proof Sketch

The wide window `[firstPos(g)+1, lastPos(g+1))` is the **minimal bounding range** containing all possible gap positions. Any item in this range across all sequences must appear in at least one valid embedding's gap per sequence → correct closure decision.

---

## 4. Current (Buggy) Paper Content

### Section 7.2: "Tight forcing windows" (Lines 551-558)
```latex
\subsection{Tight forcing windows}

For a possible middle S-insert between elements $g$ and $g+1$, the forcing window is:
\[
W_s(g)= [\,last_s(g)+1,\; first_s(g+1)\,).
\]
This window is tight: any item present in $W_s(g)$ for all supporting sequences yields a same-support insertion.
```

### Algorithm 2: EnvelopeClosedExact (Line 592)
```latex
\STATE $W_g \gets \bigcap_s \{\text{items in } [last_s(g)+1, first_s(g+1))\}$
```

---

## 5. Required Changes

### Change 1: Section Title (Line 551)
```diff
-\subsection{Tight forcing windows}
+\subsection{Forcing windows}
```

### Change 2: Window Definition (Lines 553-556)
```diff
 For a possible middle S-insert between elements $g$ and $g+1$, the forcing window is:
 \[
-W_s(g)= [\,last_s(g)+1,\; first_s(g+1)\,).
+W_s(g)= [\,first_s(g)+1,\; last_s(g+1)\,).
 \]
```

### Change 3: Explanation Text (Line 557)
```diff
-This window is tight: any item present in $W_s(g)$ for all supporting sequences yields a same-support insertion.
+This window covers all valid gap positions across embeddings. Any item present in $W_s(g)$ for all supporting sequences can be inserted in at least one valid embedding per sequence, yielding a same-support insertion. For unique items, this equals the tight window; for repeated items, the wider range ensures correctness.
```

### Change 4: Algorithm 2, Line 592
```diff
-\STATE $W_g \gets \bigcap_s \{\text{items in } [last_s(g)+1, first_s(g+1))\}$
+\STATE $W_g \gets \bigcap_s \{\text{items in } [first_s(g)+1, last_s(g+1))\}$
```

### Change 5: Figure 4 Caption (Line 570)
```diff
-\caption{Envelopes and forcing window between consecutive elements. The slack between the rightmost feasible match of $P_1$ and the leftmost feasible match of $P_2$ yields the S-insert forcing window $W_s(1)$.}
+\caption{Envelopes and forcing window between consecutive elements. The window spans from after the leftmost feasible match of $P_g$ to before the rightmost feasible match of $P_{g+1}$, covering all valid insertion positions across embeddings.}
```

---

## 6. Verification Results

| Dataset | Support | TriBack-Clo | BIDE+ | Match | Speedup |
|---------|---------|------------|-------|-------|---------|
| **MSNBC** | 0.2% | 9,286,171 | 9,286,171 | ✅ | 7.6× |
| **MSNBC** | 0.5% | 294,386 | 294,386 | ✅ | 5.3× |
| **Kosarak** | 0.2% | 35,864 | 35,864 | ✅ | 2.3× |
| **FIFA** | 10% | 40,642 | 40,642 | ✅ | 3.5× |
| **SIGN** | 20% | 9,717 | 9,717 | ✅ | 7.5× |
| **Synthetic Dense** | 10% | 5,000 | 5,000 | ✅ | 3.0× |

---

## 7. Implementation Reference

The fix in `ClosureCheckerFast.scala`:

```scala
// BEFORE (Buggy Tight Window)
fromFn = (sidIdx, kk) => lastBuf(sidIdx * kk + gapIdx) + 1,
toFn = (sidIdx, kk) => firstBuf(sidIdx * kk + gapIdx + 1),

// AFTER (Correct Wide Window)
fromFn = (sidIdx, kk) => firstBuf(sidIdx * kk + gapIdx) + 1,
toFn = (sidIdx, kk) => lastBuf(sidIdx * kk + gapIdx + 1),
```

---

## References

- Wang, J., & Han, J. (2004). BIDE: Efficient mining of frequent closed sequences. *ICDE*.
- Wang, J., Han, J., & Li, C. (2007). Frequent closed sequence mining without candidate maintenance. *TKDE*.
