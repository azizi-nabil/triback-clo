# TriBack-Clo Algorithm Summary

This note summarizes the algorithmic boundary used in the published TriBack-Clo paper and in the public Java implementation. The normative reference is the Information Sciences article; this file is a compact implementation-facing guide.

## Core Idea

TriBack-Clo mines exact closed sequential patterns over itemset-sequences under canonical PrefixSpan-style S/I growth. Its key contribution is not a new mining task, but a sound BackScan boundary for itemset-sequences:

- **Temporal witnesses** are safe for subtree pruning.
- **Local-gap and internal intra-itemset witnesses** are safe only for current-node gating.
- Exact envelope verification is invoked lazily for nodes that survive pruning, forward screening, and node gating.

This separation is essential. Pooling temporal and intra-itemset evidence can certify a non-existent same-support superpattern and make subtree pruning unsound.

## Projection State

The Java implementation stores one compact projection tuple per supporting sequence:

```text
(sid, startIdx, currentIdx, lastItem)
```

The fields mean:

- `sid`: supporting sequence identifier.
- `startIdx`: start of the semi-maximum period before the current tail element.
- `currentIdx`: position where the current tail element is matched.
- `lastItem`: largest item currently present in the tail itemset, used for canonical I-extension enumeration.

For S-extensions, `startIdx` becomes `parent_currentIdx + 1`; for I-extensions, `startIdx` and `currentIdx` remain unchanged. This keeps temporal BackScan windows tied to the gap preceding the tail element.

## Prune, Screen, Gate, Verify

At each DFS node, TriBack-Clo follows the same ordering as the accepted paper:

1. **Temporal BackScan pruning.** If an item appears in the semi-maximum period of every supporting sequence, the subtree is pruned.
2. **Forward extension enumeration.** S- and I-extensions are counted and materialized only when frequent.
3. **Forward screening.** If any extension has the same support as the current pattern, the current pattern cannot be closed, so exact verification is skipped, but children are still explored.
4. **Local/internal node gating.** Local-gap and internal witnesses prove the current pattern non-closed, so output and exact verification are skipped, but descendants are still explored.
5. **Lazy exact envelope verification.** Remaining forward-closed, non-gated nodes are checked by exact envelope windows before output.

In pseudocode:

```text
DFS(prefix P, projection S):
  if support(S) < minsup: return

  if P is non-empty and temporalBackScanWitness(S):
      prune subtree and return

  children, hasSameSupportForward = enumerateExtensions(S)

  if P is non-empty and not hasSameSupportForward:
      if not localOrInternalNodeGate(P, S):
          if envelopeClosedExact(P, S):
              output P

  for child in children:
      DFS(child.prefix, child.projection)
```

## Witness Roles

| Witness family | Evidence source | Effect |
|---|---|---|
| Temporal | Items in `[startIdx, currentIdx)` for every supporting sequence | Prune the whole subtree |
| Local-gap | Extra smaller items in the matched tail itemset | Gate the current node only |
| Internal | Extra items in earlier matched itemsets | Gate the current node only |
| Forward equality | Same-support S/I extension | Gate the current node only |
| Envelope | Exact first/last embedding windows | Final closedness decision for output |

The local-gap and internal families are deliberately not subtree-pruning rules. Descendants may use different representative embeddings, so an intra-itemset witness for the parent need not certify one same-support superpattern for every descendant.

## Exact Envelope Verification

Envelope verification checks remaining same-support superpattern forms that the fast gates do not decide:

- backward S-prepend,
- backward I-augment into the first element,
- middle S-insert between pattern elements using the wide forcing window,
- middle I-augment into matched itemsets.

The implementation uses first/last embedding envelopes and stamp-based intersections to avoid dynamic set allocation in the hot path.

## Relationship To BIDE

TriBack-Clo follows the candidate-free closed-mining paradigm of BIDE, but makes the itemset-sequence BackScan boundary explicit under canonical S/I growth. The accepted paper's central distinction is the prune/gate separation: temporal evidence is subtree-stable; intra-itemset evidence is a current-node non-closedness certificate.

## Implementation Files

- `triback-clo-java/.../AlgoTriBackClo.java`: Java implementation used in the paper experiments.
- `triback-clo-java/.../ClosureCheckerFast.java`: exact envelope verification.
- `experiments/README.md`: benchmark and reproduction entry points.

## References

- Wang, J., and Han, J. (2004). BIDE: Efficient mining of frequent closed sequences. ICDE.
- Wang, J., Han, J., and Li, C. (2007). Frequent closed sequence mining without candidate maintenance. IEEE TKDE.
- Azizi et al. (2026). TriBack-clo: Sound triple-witness BackScan for closed pattern mining in itemset-sequences. Information Sciences.
