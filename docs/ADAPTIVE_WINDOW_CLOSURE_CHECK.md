# Wide-Window Envelope Closure Checking

This note records the envelope-window correction that is used in the published TriBack-Clo paper and in the public Java implementation. Older development notes experimented with an adaptive tight-vs-wide strategy; the final paper uses the wide middle S-insert window as the formal rule.

## Closure Conditions

For a pattern `P = <E0, E1, ..., E{k-1}>`, exact closure verification rejects `P` if a same-support superpattern can be formed by:

1. S-prepending an item before `E0`;
2. I-augmenting an existing matched itemset;
3. S-inserting a new itemset between two consecutive pattern elements.

TriBack-Clo computes first/last embedding envelopes for each supporting sequence:

- `first_s(i)`: the leftmost feasible match position of pattern element `P_i` in sequence `s`;
- `last_s(i)`: the rightmost feasible match position of pattern element `P_i` in sequence `s`.

## Middle S-Insert Window

For a possible S-insert between `P_g` and `P_{g+1}`, the final rule is the wide forcing window:

```text
W_s(g) = [first_s(g) + 1, last_s(g + 1))
```

If an item occurs in this interval for every supporting sequence, it can be inserted between `P_g` and `P_{g+1}` in at least one feasible embedding per sequence, yielding a same-support superpattern. The pattern is therefore not closed.

## Why The Tight Window Is Insufficient

The tempting tight window is:

```text
[last_s(g) + 1, first_s(g + 1))
```

This captures positions that are valid for all embeddings, but closure checking needs an existential condition: a same-support insertion only needs one feasible embedding per supporting sequence. With repeated items, first and last envelopes may overlap or invert, and the tight window can miss a valid insertion.

Example:

```text
Pattern:  <(a)(a)>
Sequence: <(a)(x)(a)(a)>

first_s(1) = 1, first_s(2) = 3
last_s(1)  = 3, last_s(2)  = 4

tight: [last_s(1)+1, first_s(2)) = [4, 3)  empty
wide:  [first_s(1)+1, last_s(2)) = [2, 4)  contains x
```

The wide window correctly detects the same-support superpattern `<(a)(x)(a)>`.

## Implementation Status

The public Java implementation uses the wide window directly in `ClosureCheckerFast.hasCommonItemInGapRange`:

```text
from = firstBuf[gapIdx] + 1
to   = lastBuf[gapIdx + 1]
```

The same rule appears in the accepted paper's envelope-verification proposition and algorithm. This document is retained to explain why the earlier tight-window idea was replaced.

## Historical Note

During development, an adaptive optimization was considered: use the tight window when envelopes are point-tight and switch to the wide window for repeated or ambiguous cases. That optimization is not the published rule and should not be treated as part of the public reproducibility path. The final implementation favors the simpler uniform wide-window test because it matches the proof statement and avoids a brittle precondition check.
