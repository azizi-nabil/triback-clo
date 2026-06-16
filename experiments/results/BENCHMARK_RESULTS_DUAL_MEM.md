# TriBack-Clo Benchmark Results (Dual Memory)

**Experiments on Single-Itemset Sequences**

Results showing both Internal (JVM MemoryLogger) and External (MaxRSS) memory.

---

## BIKE Dataset (21,078 sequences)

| Support % | Algorithm | Mining (s) | Internal Mem | External Mem | Gap |
|-----------|-----------|------------|--------------|--------------|-----|
| 20% | BIDE+ | — | 129 MB | 183 MB | 1.42x |
| 20% | CloFast | — | 2.11 GB | 9.71 GB | 4.61x |
| 20% | TriBack-Clo | — | 161 MB | 186 MB | 1.14x |
| 10% | BIDE+ | — | 145 MB | 198 MB | 1.36x |
| 10% | CloFast | — | 2.31 GB | 9.71 GB | 4.20x |
| 10% | TriBack-Clo | — | 177 MB | 194 MB | 1.10x |
| 5% | BIDE+ | — | 161 MB | 221 MB | 1.37x |
| 5% | CloFast | — | 2.93 GB | 9.71 GB | 3.31x |
| 5% | TriBack-Clo | — | 177 MB | 192 MB | 1.08x |
| 2% | BIDE+ | — | 289 MB | 343 MB | 1.19x |
| 2% | CloFast | — | 5.90 GB | 9.71 GB | 1.65x |
| 2% | TriBack-Clo | — | 177 MB | 198 MB | 1.10x |
| 1% | BIDE+ | — | 497 MB | 558 MB | 1.12x |
| 1% | CloFast | — | 8.59 GB | 9.79 GB | 1.14x |
| 1% | TriBack-Clo | — | 177 MB | 196 MB | 1.10x |
| 0.50% | BIDE+ | — | 769 MB | 818 MB | 1.06x |
| 0.50% | CloFast | — | 2.42 GB | 19.51 GB | 8.07x |
| 0.50% | TriBack-Clo | — | 177 MB | 200 MB | 1.13x |
| 0.20% | BIDE+ | — | 801 MB | 918 MB | 1.15x |
| 0.20% | CloFast | — | 4.37 GB | 11.59 GB | 2.65x |
| 0.20% | TriBack-Clo | — | 177 MB | 198 MB | 1.12x |
| 0.10% | BIDE+ | — | 888 MB | 1002 MB | 1.13x |
| 0.10% | CloFast | — | 10.95 GB | 19.59 GB | 1.79x |
| 0.10% | TriBack-Clo | — | 177 MB | 202 MB | 1.12x |
| 0.05% | BIDE+ | — | 4.09 GB | 4.22 GB | 1.03x |
| 0.05% | CloFast | — | 21.78 GB | 32.08 GB | 1.48x |
| 0.05% | TriBack-Clo | — | 177 MB | 205 MB | 1.20x |
| 0.01% | BIDE+ | — | 9.57 GB | 9.72 GB | 1.02x |
| 0.01% | TriBack-Clo | — | 289 MB | 312 MB | 1.08x |

---

## BMS2 Dataset (77,512 sequences)

| Support % | Algorithm | Mining (s) | Internal Mem | External Mem | Gap |
|-----------|-----------|------------|--------------|--------------|-----|
| 20% | CloFast | — | 16.51 GB | 23.62 GB | 1.43x |
| 20% | TriBack-Clo | — | 290 MB | 319 MB | 1.10x |
| 10% | CloFast | — | 7.64 GB | 23.39 GB | 3.06x |
| 10% | TriBack-Clo | — | 290 MB | 322 MB | 1.11x |
| 5% | CloFast | — | 8.14 GB | 23.35 GB | 2.86x |
| 5% | TriBack-Clo | — | 290 MB | 320 MB | 1.09x |
| 2% | BIDE+ | — | 209 MB | 252 MB | 1.22x |
| 2% | CloFast | — | 16.49 GB | 23.77 GB | 1.33x |
| 2% | TriBack-Clo | — | 307 MB | 323 MB | 1.05x |
| 1% | BIDE+ | — | 241 MB | 280 MB | 1.16x |
| 1% | CloFast | — | 18.91 GB | 23.70 GB | 1.27x |
| 1% | TriBack-Clo | — | 308 MB | 327 MB | 1.05x |
| 0.50% | BIDE+ | — | 369 MB | 406 MB | 1.10x |
| 0.50% | CloFast | — | 13.30 GB | 23.94 GB | 1.81x |
| 0.50% | TriBack-Clo | — | 307 MB | 330 MB | 1.08x |
| 0.10% | BIDE+ | — | 2.88 GB | 3.00 GB | 1.05x |
| 0.10% | CloFast | — | 29.63 GB | 35.96 GB | 1.27x |
| 0.10% | TriBack-Clo | — | 337 MB | 348 MB | 1.05x |
| 0.05% | BIDE+ | — | 9.58 GB | 9.73 GB | 1.02x |
| 0.05% | TriBack-Clo | — | 321 MB | 354 MB | 1.12x |
| 0.01% | BIDE+ | — | 9.58 GB | 9.74 GB | 1.02x |
| 0.01% | TriBack-Clo | — | 561 MB | 567 MB | 1.02x |
| 0.0050% | BIDE+ | — | 9.58 GB | 9.75 GB | 1.02x |
| 0.0050% | TriBack-Clo | — | 801 MB | 970 MB | 1.21x |
| 0.0010% | BIDE+ | — | 9.58 GB | 9.76 GB | 1.02x |
| 0.0005% | BIDE+ | — | 9.58 GB | 9.77 GB | 1.02x |

---

## MSNBC Dataset (989,818 sequences)

| Support % | Algorithm | Mining (s) | Internal Mem | External Mem | Gap |
|-----------|-----------|------------|--------------|--------------|-----|
| 5% | BIDE+ | — | 786 MB | 1003 MB | 1.28x |
| 5% | CloFast | — | 12.05 GB | 13.69 GB | 1.14x |
| 5% | TriBack-Clo | — | 413 MB | 1.09 GB | 2.68x |
| 2% | BIDE+ | — | 785 MB | 1.01 GB | 1.32x |
| 2% | TriBack-Clo | — | 440 MB | 1.10 GB | 2.56x |
| 1% | BIDE+ | — | 801 MB | 1.10 GB | 1.41x |
| 1% | TriBack-Clo | — | 442 MB | 1.07 GB | 2.49x |
| 0.50% | BIDE+ | — | 911 MB | 1.13 GB | 1.26x |
| 0.50% | TriBack-Clo | — | 449 MB | 1.07 GB | 2.47x |
| 0.20% | BIDE+ | — | 2.07 GB | 2.18 GB | 1.05x |
| 0.20% | TriBack-Clo | — | 457 MB | 1.07 GB | 2.35x |
| 0.10% | BIDE+ | — | 9.71 GB | 9.83 GB | 1.01x |
| 0.10% | TriBack-Clo | — | 470 MB | 1.07 GB | 2.33x |
| 0.05% | BIDE+ | — | 9.73 GB | 9.87 GB | 1.01x |
| 0.05% | TriBack-Clo | — | 476 MB | 1.10 GB | 2.36x |

---

## Kosarak Dataset (990,002 sequences)

| Support % | Algorithm | Mining (s) | Internal Mem | External Mem | Gap |
|-----------|-----------|------------|--------------|--------------|-----|
| 10% | BIDE+ | — | 510 MB | 1.17 GB | 2.35x |
| 10% | TriBack-Clo | — | 607 MB | 1.25 GB | 2.10x |
| 5% | BIDE+ | — | 831 MB | 1.17 GB | 1.45x |
| 5% | TriBack-Clo | — | 550 MB | 1.19 GB | 2.20x |
| 2% | BIDE+ | — | 1.08 GB | 1.35 GB | 1.26x |
| 2% | TriBack-Clo | — | 589 MB | 1.17 GB | 2.03x |
| 1% | BIDE+ | — | 1.18 GB | 1.41 GB | 1.20x |
| 1% | TriBack-Clo | — | 648 MB | 1.19 GB | 1.87x |
| 0.50% | BIDE+ | — | 8.14 GB | 8.32 GB | 1.02x |
| 0.50% | TriBack-Clo | — | 747 MB | 1.19 GB | 1.63x |
| 0.20% | BIDE+ | — | 12.25 GB | 12.58 GB | 1.03x |
| 0.20% | TriBack-Clo | — | 918 MB | 1.19 GB | 1.31x |
| 0.10% | BIDE+ | — | 10.51 GB | 10.88 GB | 1.04x |
| 0.10% | TriBack-Clo | — | 1001 MB | 1.81 GB | 1.86x |

---

## Kosarak25k Dataset (25,000 sequences)

| Support % | Algorithm | Mining (s) | Internal Mem | External Mem | Gap |
|-----------|-----------|------------|--------------|--------------|-----|
| 10% | BIDE+ | — | 145 MB | 205 MB | 1.41x |
| 10% | CloFast | — | 7.58 GB | 16.04 GB | 2.16x |
| 10% | TriBack-Clo | — | 193 MB | 215 MB | 1.12x |
| 1% | BIDE+ | — | 225 MB | 292 MB | 1.30x |
| 1% | CloFast | — | 7.57 GB | 15.95 GB | 2.09x |
| 1% | TriBack-Clo | — | 209 MB | 219 MB | 1.10x |
| 0.50% | BIDE+ | — | 545 MB | 601 MB | 1.10x |
| 0.50% | CloFast | — | 20.41 GB | 34.17 GB | 1.66x |
| 0.50% | TriBack-Clo | — | 209 MB | 223 MB | 1.11x |
| 0.20% | BIDE+ | — | 1006 MB | 1.11 GB | 1.13x |
| 0.20% | CloFast | — | 21.75 GB | 36.89 GB | 1.67x |
| 0.20% | TriBack-Clo | — | 209 MB | 228 MB | 1.12x |
| 0.10% | BIDE+ | — | 9.58 GB | 9.73 GB | 1.02x |
| 0.10% | CloFast | — | 30.81 GB | 49.23 GB | 1.59x |
| 0.10% | TriBack-Clo | — | 209 MB | 235 MB | 1.12x |
| 0.05% | BIDE+ | — | 9.58 GB | 9.74 GB | 1.02x |
| 0.05% | TriBack-Clo | — | 801 MB | 929 MB | 1.16x |
| 0.02% | BIDE+ | — | 9.61 GB | 9.77 GB | 1.02x |
| 0.02% | TriBack-Clo | — | 9.57 GB | 9.73 GB | 1.02x |

---

## FIFA Dataset (20,450 sequences)

| Support % | Algorithm | Mining (s) | Internal Mem | External Mem | Gap |
|-----------|-----------|------------|--------------|--------------|-----|
| 20% | BIDE+ | — | 2.83 GB | 2.95 GB | 1.04x |
| 20% | CloFast | — | 14.41 GB | 20.07 GB | 1.39x |
| 20% | TriBack-Clo | — | 449 MB | 478 MB | 1.06x |
| 10% | BIDE+ | — | 9.60 GB | 9.77 GB | 1.02x |
| 10% | CloFast | — | 16.77 GB | 26.45 GB | 1.58x |
| 10% | TriBack-Clo | — | 513 MB | 541 MB | 1.05x |
| 5% | BIDE+ | — | 9.68 GB | 9.85 GB | 1.02x |
| 5% | TriBack-Clo | — | 657 MB | 690 MB | 1.05x |
| 2% | TriBack-Clo | — | 801 MB | 1.00 GB | 1.28x |

---

## SIGN Dataset (730 sequences)

| Support % | Algorithm | Mining (s) | Internal Mem | External Mem | Gap |
|-----------|-----------|------------|--------------|--------------|-----|
| 20% | BIDE+ | — | 1.80 GB | 1.90 GB | 1.05x |
| 20% | CloFast | — | 1.57 GB | 4.22 GB | 2.69x |
| 20% | TriBack-Clo | — | 113 MB | 136 MB | 1.21x |
| 10% | BIDE+ | — | 9.57 GB | 9.70 GB | 1.01x |
| 10% | CloFast | — | 4.60 GB | 10.49 GB | 2.28x |
| 10% | TriBack-Clo | — | 113 MB | 152 MB | 1.34x |
| 5% | BIDE+ | — | 9.57 GB | 9.71 GB | 1.02x |
| 5% | CloFast | — | 9.54 GB | 16.14 GB | 1.69x |
| 5% | TriBack-Clo | — | 161 MB | 187 MB | 1.16x |
| 2% | BIDE+ | — | 9.57 GB | 9.71 GB | 1.01x |
| 2% | TriBack-Clo | — | 785 MB | 816 MB | 1.04x |
| 1% | BIDE+ | — | 9.57 GB | 9.71 GB | 1.01x |
| 1% | TriBack-Clo | — | 1.52 GB | 1.62 GB | 1.06x |

---

## MSNBC_small Dataset (31,790 sequences)

| Support % | Algorithm | Mining (s) | Internal Mem | External Mem | Gap |
|-----------|-----------|------------|--------------|--------------|-----|
| 5% | BIDE+ | — | 801 MB | 930 MB | 1.16x |
| 5% | TriBack-Clo | — | 305 MB | 333 MB | 1.09x |
| 2% | BIDE+ | — | 2.74 GB | 2.85 GB | 1.04x |
| 2% | TriBack-Clo | — | 337 MB | 343 MB | 1.03x |
| 1% | BIDE+ | — | 9.58 GB | 9.72 GB | 1.01x |
| 1% | TriBack-Clo | — | 321 MB | 349 MB | 1.07x |
| 0.50% | BIDE+ | — | 9.58 GB | 9.73 GB | 1.01x |
| 0.50% | TriBack-Clo | — | 337 MB | 366 MB | 1.08x |
| 0.20% | BIDE+ | — | 9.59 GB | 9.75 GB | 1.02x |
| 0.20% | TriBack-Clo | — | 801 MB | 914 MB | 1.14x |

---

## Summary

**TriBack-Clo** shows minimal Internal/External gap (~1.1x), indicating efficient memory utilization.
**CloFast** shows larger gaps (~1.5-1.7x), suggesting fragmentation from its Global Inverted Index.
