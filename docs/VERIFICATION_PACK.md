# TriBack-Clo Verification Pack

This document contains all source code files needed to audit algorithm consistency for the TriBack-Clo closed sequential pattern miner on itemset-sequences.

---

## Table of Contents

1. [TriBackClo.scala](#1-tribackcloscala) - DFS miner, prune gates, closure logic
2. [ItemsetPointerStore.scala](#2-itemsetpointerstorscala) - 4-tuple store, BackScan, extension enumeration
3. [ClosureCheckerFast.scala](#3-closurecheckerfastscala) - Envelope-based exact verification
4. [EnvelopeComputer.scala](#4-envelopecomputerscala) - First/last embedding computation
5. [MinerContext.scala](#5-minercontextscala) - Epoch stamps, reusable buffers
6. [ItemsetSequence.scala](#6-itemsetsequencescala) - Database model + SPMF loader
7. [Test Dataset](#7-test-dataset) - Small test case with expected output

---

## 1. TriBackClo.scala

**Purpose**: Main DFS controller with:
- BackScan prune gate (line 148)
- Extension enumeration (line 154)
- Forward-closed check (line 157)
- Lazy exact verification trigger (line 160)
- Canonical recursion order: S-extensions then I-extensions (lines 200-214)

```scala
package tribackclo

import scala.collection.mutable

/**
 * ItemsetPattern: A sequential pattern of itemsets.
 * Each itemset is a sorted array of items.
 */
case class ItemsetPattern(itemsets: Array[Array[Int]]) {
  def length: Int = itemsets.length
  def isEmpty: Boolean = itemsets.isEmpty
  
  /** Append item as S-extension (new itemset) */
  def appendS(item: Int): ItemsetPattern = {
    ItemsetPattern(itemsets :+ Array(item))
  }
  
  /** Append item as I-extension (to last itemset) */
  def appendI(item: Int): ItemsetPattern = {
    if (itemsets.isEmpty) {
      ItemsetPattern(Array(Array(item)))
    } else {
      val lastIdx = itemsets.length - 1
      val newLast = (itemsets(lastIdx) :+ item).sorted
      val newItemsets = itemsets.clone()
      newItemsets(lastIdx) = newLast
      ItemsetPattern(newItemsets)
    }
  }
  
  // -- Verification Helpers --
  
  def prependS(item: Int): ItemsetPattern = {
    ItemsetPattern(Array(Array(item)) ++ itemsets)
  }
  
  def insertS(item: Int, idx: Int): ItemsetPattern = {
    val (left, right) = itemsets.splitAt(idx)
    ItemsetPattern(left ++ Array(Array(item)) ++ right)
  }
  
  def mergeItem(item: Int, idx: Int): ItemsetPattern = {
    val newSet = (itemsets(idx) :+ item).sorted
    val newSets = itemsets.clone()
    newSets(idx) = newSet
    ItemsetPattern(newSets)
  }
  
  override def toString: String = {
    itemsets.map(is => if (is.length == 1) is(0).toString else s"(${is.mkString(",")})").mkString(" -> ")
  }
  
  /** SPMF format output */
  def toSPMF: String = {
    itemsets.map(_.mkString(" ")).mkString(" -1 ") + " -1"
  }
}

object ItemsetPattern {
  val empty: ItemsetPattern = ItemsetPattern(Array.empty)
}

/**
 * ItemsetClosedMiner: DFS miner for closed itemset sequences.
 * 
 * Implements proper closedness checking for itemset-sequences:
 * 1. Forward-closed: No S-extension or I-extension has same support
 * 2. Backward-closed: No prepending has same support (via BackScan)
 * 3. Middle-closed: No item can be inserted into existing itemsets with same support
 */
class ItemsetClosedMiner(
    db: ItemsetSequenceDatabase,
    minsup: Int
) {
  
  private val results = mutable.ArrayBuffer[(ItemsetPattern, Int)]()
  private var nodesVisited = 0L
  private var prunedSubtrees = 0L
  
  /**
   * Mine all closed sequential patterns.
   */
  def mine(): Array[(ItemsetPattern, Int)] = {
    println(s"[ItemsetClosedMiner] Starting mining with minsup=$minsup")
    println(db.stats)
    
    val t0 = System.nanoTime()
    
    val rootStore = ItemsetPointerStore.createRoot(db)
    ctx = new MinerContext(db.maxItem, db.numSequences, db.numSequences) // maxSupport <= numSids
    dfs(ItemsetPattern.empty, rootStore, ctx)
    
    val elapsed = (System.nanoTime() - t0) / 1e9
    println(f"[ItemsetClosedMiner] Mining completed in $elapsed%.3f seconds")
    println(f"[ItemsetClosedMiner] Nodes visited: $nodesVisited%,d")
    println(f"[ItemsetClosedMiner] Subtrees pruned: $prunedSubtrees%,d")
    println(f"[ItemsetClosedMiner] Closed patterns found: ${results.length}%,d")
    
    results.toArray
  }
  
  /**
   * DFS with optimized closure checking (BIDE+ style).
   * 
   * Logic: A pattern P is CLOSED iff:
   * 1. It is forward-closed (no same-support extension)
   * 2. It is NOT backward-closed (has no BackScan witness)
   * 
   * We check BackScan first for pruning.
   * Then we check forward-closed.
   * If both pass, output. No expensive explicit verification needed for Kosarak-like data.
   */
  private def lazyExactClosed(prefix: ItemsetPattern, store: ItemsetPointerStore): Boolean = {
    // Only run expensive exact check if forward-closed (fast path passed)
    // 1. Fill supporting SIDs (allocation-free)
    val nSids = store.fillSids(ctx.sidBuf)

    // 2. Compute first/last envelopes into reusable flat buffers
    val k = EnvelopeComputer.computeInto(db, ctx.sidBuf, nSids, prefix, ctx)

    // 3. Use BIDE-style fast closure check (envelope windows + stamp intersection)
    ClosureCheckerFast.isClosedUsingEnvelopes(
      db,
      ctx.sidBuf,
      nSids,
      prefix,
      k,
      ctx.firstBuf,
      ctx.lastBuf,
      ctx
    )
  }
  
  // Shared MinerContext for DFS and lazyExactClosed
  private var ctx: MinerContext = _

  /*
   * DFS with optimized logic.
   * FIX: Materialize children locally to avoid MinerContext state corruption during recursion.
   */
  private def dfs(prefix: ItemsetPattern, store: ItemsetPointerStore, ctx: MinerContext): Unit = {
    nodesVisited += 1
    
    // Support check
    if (store.support < minsup) return
    
    // BackScan pruning: if temporal witness exists, entire subtree is non-closed
    if (prefix.length >= 1 && store.detectBackScanPrune(ctx)) {
      prunedSubtrees += 1
      return
    }
    
    // Enumerate extensions
    val (sCount, sTouched, iCount, iTouched, hasSameSuppForward) = store.enumerateExtensions(minsup, ctx)
    
    // Forward-closed check
    val forwardClosed = !hasSameSuppForward
    
    if (!prefix.isEmpty && forwardClosed) {
      if (lazyExactClosed(prefix, store)) {
        results += ((prefix, store.support))
      }
    }
    
    // Materialize children locally to avoid corruption of shared MinerContext arrays during recursion
    val sChildren = new Array[(Int, ItemsetPointerStore)](sCount)
    var sValid = 0
    var t = 0
    while (t < sCount) {
      val item = sTouched(t)
      val supp = ctx.sExtSupport(item)
      // Reset support for next usage (Zero-Allocation pattern)
      ctx.sExtSupport(item) = 0
      
      if (supp >= minsup) {
          val positions = ctx.sLists(item).toArrayTrimmed()
          sChildren(sValid) = (item, new ItemsetPointerStore(positions, supp, db))
          sValid += 1
      }
      t += 1
    }
    
    val iChildren = new Array[(Int, ItemsetPointerStore)](iCount)
    var iValid = 0
    t = 0
    while (t < iCount) {
      val item = iTouched(t)
      val supp = ctx.iExtSupport(item)
      // Reset support for next usage
      ctx.iExtSupport(item) = 0
      
      if (supp >= minsup) {
          val positions = ctx.iLists(item).toArrayTrimmed()
          iChildren(iValid) = (item, new ItemsetPointerStore(positions, supp, db))
          iValid += 1
      }
      t += 1
    }
    
    // Recurse S-extensions
    var k = 0
    while (k < sValid) {
       val (item, childStore) = sChildren(k)
       dfs(prefix.appendS(item), childStore, ctx)
       k += 1
    }
    
    // Recurse I-extensions
    k = 0
    while (k < iValid) {
       val (item, childStore) = iChildren(k)
       dfs(prefix.appendI(item), childStore, ctx)
       k += 1
    }
  }
}

/**
 * Main entry point for itemset-sequence mining.
 */
object ItemsetClosedMiner_Main {
  
  def main(args: Array[String]): Unit = {
    val argMap = args.sliding(2, 2).collect { case Array(k, v) => k -> v }.toMap
    
    val inputFile = argMap.getOrElse("--input", "data/test.txt")
    val minsup = argMap.get("--minsup").map(_.toInt).getOrElse(2)
    val ratio = argMap.get("--ratio").map(_.toDouble)
    val outputFile = argMap.get("--output")
    
    println("=" * 60)
    println("TriBack-Clo: Itemset-Sequence Closed Sequential Pattern Mining")
    println("=" * 60)
    
    // Load database
    println(s"\n[INFO] Loading: $inputFile")
    val t0 = System.nanoTime()
    val db = SPMFLoaderItemsets.loadSequences(inputFile)
    val loadTime = (System.nanoTime() - t0) / 1e9
    println(f"[INFO] Loaded in $loadTime%.3f seconds")
    println(db.stats)
    
    // Compute actual minsup
    val actualMinsup = ratio match {
      case Some(r) => math.ceil(db.numSequences * r).toInt
      case None => minsup
    }
    val pct = 100.0 * actualMinsup / db.numSequences
    println(f"\n[INFO] Minimum support: $actualMinsup ($pct%.2f%%)")
    
    // Mine patterns (Fast Path)
    val miner = new ItemsetClosedMiner(db, actualMinsup)
    val results = miner.mine()
    
    // Output results
    outputFile match {
      case Some(outPath) =>
        val writer = new java.io.PrintWriter(new java.io.File(outPath))
        try {
          results.foreach { case (pattern, support) =>
            writer.println(s"${pattern.toSPMF} #SUP: $support")
          }
        } finally {
          writer.close()
        }
        println(s"[INFO] Results written to: $outPath")
        
      case None =>
        println(s"[INFO] No output file specified. Use --output to save patterns.")
        if (results.length <= 20) {
          println("\nSample patterns:")
          results.take(20).foreach { case (p, s) => println(s"  $p  [sup=$s]") }
        }
    }
    
    println("\n" + "=" * 60)
    println(f"[RESULT] Found ${results.length}%,d closed patterns")
    
    val totalTime = (System.nanoTime() - t0) / 1e9
    println(f"[TIME] Total Execution Time: $totalTime%.3f seconds")
```scala
package tribackclo
```

---

## 2. ItemsetPointerStore.scala

**Purpose**: 4-tuple projection store with:
- STRIDE=4: `(sid, startIdx, currentIdx, lastItem)`
- BackScan witness detection via stamp intersection
- S/I extension enumeration
- Canonical I-extension: only items > lastItem

```scala
package apvclofast

import scala.collection.mutable

/**
 * Extension types for itemset-sequences.
 */
sealed trait ExtensionType
case object SExtension extends ExtensionType
case object IExtension extends ExtensionType

case class ItemsetExtension(
    item: Int,
    extType: ExtensionType,
    store: ItemsetPointerStore,
    support: Int
)

/**
 * Optimized ItemsetPointerStore with:
 * 1. 5-element stride for correct BackScan properties
 * 2. Allocation-free BackScan (stamp-based intersection)
 * 3. Sparse "touched-items" enumeration
 */
class ItemsetPointerStore(
    private val positions: Array[Int],
    private val numSids: Int,
    private val db: ItemsetSequenceDatabase
) {
  
  private val STRIDE = 5  // (sid, startIdx, currentIdx, lastItem, extType)
  
  def support: Int = numSids
  
  def supportSequences: Array[Int] = {
    val result = new Array[Int](numSids)
    var i = 0
    while (i < numSids) {
      result(i) = positions(i * STRIDE)
      i += 1
    }
    result
  }

  def fillSids(out: Array[Int]): Int = {
    var i = 0
    var idx = 0
    while (i < numSids) {
      out(i) = positions(idx)
      i += 1
      idx += STRIDE
    }
    numSids
  }
  
  /**
   * Allocation-free BackScan Witness Detection.
   * 
   * Uses stamp-based intersection to avoid BitSet allocations per SID.
   * Logic:
   * 1. Collect candidates from FIRST SID's period.
   * 2. For subsequent SIDs, filter candidates that don't appear in their period.
   * 3. Early exit if candidates become empty.
   */
  /**
   * Allocation-free BackScan Witness Detection.
   * Uses MinerContext with epoch stamping to avoid Arrays.fill.
   */
  def detectBackScanPrune(ctx: MinerContext): Boolean = {
    if (numSids == 0) return false
    
    val seenStamp = ctx.seenStamp
    val candidates = ctx.candidates
    var candidateCount = 0
    
    // Use epoch base instead of clearing array.
    val base = ctx.nextBackscanBase()
    
    // Process first SID
    {
      val sid = positions(0)
      val startIdx = positions(1)
      val currentIdx = positions(2)
      val lastItem = positions(3)
      val extType = positions(4)
      val seq = db.getSequence(sid)
      
      // Stamp for first SID is base + 1
      val stamp1 = base + 1
      
      // Collect items from semi-max period
      // 1. Temporal gap: itemsets in [startIdx, currentIdx)
      var isIdx = startIdx
      while (isIdx < currentIdx && isIdx >= 0 && isIdx < seq.length) {
        val itemset = seq(isIdx)
        var j = 0
        while (j < itemset.length) {
          val item = itemset(j)
          if (seenStamp(item) != stamp1) {
            seenStamp(item) = stamp1 // Mark as seen in first SID
            candidates(candidateCount) = item
            candidateCount += 1
          }
          j += 1
        }
        isIdx += 1
      }
      
      // 2. Local gap: items in current itemset < lastItem (Check for both S and I extensions)
      if (currentIdx >= 0 && currentIdx < seq.length) {
        val currentSet = seq(currentIdx)
        var j = 0
        while (j < currentSet.length) {
          val item = currentSet(j)
          // Only check items strictly "before" (lexicographically smaller)
          if (item < lastItem) {
             if (seenStamp(item) != stamp1) {
               seenStamp(item) = stamp1
               candidates(candidateCount) = item
               candidateCount += 1
             }
          }
          j += 1
        }
      }
    }
    
    if (candidateCount == 0) return false
    
    // Process remaining SIDs
    var idx = STRIDE
    var sidCount = 1
    while (idx < numSids * STRIDE) {
      val sid = positions(idx)
      val startIdx = positions(idx + 1)
      val currentIdx = positions(idx + 2)
      val lastItem = positions(idx + 3)
      val seq = db.getSequence(sid)
      
      val currentStamp = base + sidCount + 1
      val prevStamp = currentStamp - 1
      
      var foundAny = false
      // 1. Temporal gap
      var isIdx = startIdx
      while (isIdx < currentIdx && isIdx >= 0 && isIdx < seq.length) {
        val itemset = seq(isIdx)
        var j = 0
        while (j < itemset.length) {
          val item = itemset(j)
          if (seenStamp(item) == prevStamp) {
             seenStamp(item) = currentStamp
             foundAny = true
          }
          j += 1
        }
        isIdx += 1
      }
      
      // 2. Local gap
      if (currentIdx >= 0 && currentIdx < seq.length) {
        val currentSet = seq(currentIdx)
        var j = 0
        while (j < currentSet.length) {
          val item = currentSet(j)
          if (item < lastItem) {
             if (seenStamp(item) == prevStamp) {
                seenStamp(item) = currentStamp
                foundAny = true
             }
          }
          j += 1
        }
      }
      
      // Filter candidates
      var writePos = 0
      var readPos = 0
      while (readPos < candidateCount) {
        val item = candidates(readPos)
        if (seenStamp(item) == currentStamp) {
          candidates(writePos) = item
          writePos += 1
        }
        readPos += 1
      }
      candidateCount = writePos
      
      if (candidateCount == 0) return false
      idx += STRIDE
      sidCount += 1
    }
    
    true
  }
  
  /**
   * Optimized Enumeration with "Touched Items" lists.
   * Avoids iterating 1..maxItem.
   */
  /**
   * Optimized Enumeration with MinerContext.
   */
  def enumerateExtensions(minsup: Int, ctx: MinerContext): (Int, Array[Int], Int, Array[Int], Boolean) = {
    // Reuse arrays from context
    val sExtSupport = ctx.sExtSupport
    val iExtSupport = ctx.iExtSupport
    val sExtSeen = ctx.sExtSeen
    val iExtSeen = ctx.iExtSeen
    val sTouched = ctx.sTouched
    val iTouched = ctx.iTouched
    
    var sTouchedCount = 0
    var iTouchedCount = 0
    
    val sidBase = ctx.nextEnumSidBase()
    val parentSupp = this.support
    var hasSameSuppForward = false
    
    // Check if we can skip I-extensions (optimization for Kosarak)
    val singleItemsets = db.maxItemsetSize == 1
    
    var idx = 0
    while (idx < numSids * STRIDE) {
      val sid = positions(idx)
      val startIdx = positions(idx + 1)
      val currentIdx = positions(idx + 2)
      val lastItem = positions(idx + 3)
      val extType = positions(idx + 4)
      
      val seq = db.getSequence(sid)
      val stamp = sidBase | sid
      
      // I-extension (skip entirely if itemsets are size 1)
      // Also skip if not applicable (currentIdx invalid)
      if (!singleItemsets && currentIdx >= 0 && currentIdx < seq.length) {
        val currentItemset = seq(currentIdx)
        var j = 0
        while (j < currentItemset.length) {
          val item = currentItemset(j)
          if (item > lastItem && iExtSeen(item) != stamp) {
            iExtSeen(item) = stamp
            if (iExtSupport(item) == 0) {
              iTouched(iTouchedCount) = item
              iTouchedCount += 1
              val lst = ctx.iLists(item)
              if (lst == null) {
                  ctx.iLists(item) = new ctx.IntList()
              } else {
                  lst.clear()
              }
            }
            iExtSupport(item) += 1
            
            // Add to reusable list
            val lst = ctx.iLists(item)
            lst.add(sid)
            lst.add(currentIdx)
            lst.add(currentIdx)
            lst.add(item)
            lst.add(1)
          }
          j += 1
        }
      }
      
      // S-extension
      var isIdx = currentIdx + 1
      while (isIdx < seq.length) {
        val itemset = seq(isIdx)
        var j = 0
        while (j < itemset.length) {
          val item = itemset(j)
          if (sExtSeen(item) != stamp) {
            sExtSeen(item) = stamp
            if (sExtSupport(item) == 0) {
              sTouched(sTouchedCount) = item
              sTouchedCount += 1
              val lst = ctx.sLists(item)
              if (lst == null) {
                  ctx.sLists(item) = new ctx.IntList()
              } else {
                  lst.clear()
              }
            }
            sExtSupport(item) += 1
            
            // Add to reusable list
            val lst = ctx.sLists(item)
            lst.add(sid)
            lst.add(currentIdx + 1)
            lst.add(isIdx)
            lst.add(item)
            lst.add(0)
          }
          j += 1
        }
        isIdx += 1
      }
      
      idx += STRIDE
    }
    
    // Check same-support-forward (cheaply)
    // We defer child creation to the caller to avoid allocations here
    var t = 0
    while (t < sTouchedCount && !hasSameSuppForward) {
      if (sExtSupport(sTouched(t)) == parentSupp) hasSameSuppForward = true
      t += 1
    }
    t = 0
    while (t < iTouchedCount && !hasSameSuppForward) {
      if (iExtSupport(iTouched(t)) == parentSupp) hasSameSuppForward = true
      t += 1
    }
    
    // Return raw counts/arrays to avoid allocating wrapper object or extension array
    (sTouchedCount, sTouched, iTouchedCount, iTouched, hasSameSuppForward)
  }

}

object ItemsetPointerStore {
  def createRoot(db: ItemsetSequenceDatabase): ItemsetPointerStore = {
    val positions = new Array[Int](db.numSequences * 5)
    var idx = 0
    var sid = 0
    while (sid < db.numSequences) {
      positions(idx) = sid
      positions(idx + 1) = 0
      positions(idx + 2) = -1
      positions(idx + 3) = 0
      positions(idx + 4) = 0
      idx += 5
      sid += 1
    }
    new ItemsetPointerStore(positions, db.numSequences, db)
  }
}
```

---

## 3. ClosureCheckerFast.scala

**Purpose**: Envelope-based exact verification with:
- Backward S-prepend (lines 44-50)
- Backward I-prepend (lines 52-57)
- Middle S-insert with TIGHT window `[lastPos(g)+1, firstPos(g+1))` (lines 59-70)
- Middle I-insert (lines 72-81)
- Singleton fastpath using `singletonSeqs` (lines 121-136, 174-185)

```scala
package apvclofast

/**
 * BIDE-style fast closure checker using envelope windows + stamp intersections.
 * 
 * V2: Uses flat buffers (firstBuf, lastBuf) instead of EmbeddingCache to
 * eliminate per-node allocations.
 * 
 * Key optimizations:
 * 1. No mutable.BitSet - uses MinerContext stamp arrays
 * 2. No pattern reconstruction - checks windows directly
 * 3. No allSupport() calls - just window intersection
 * 4. No per-SID envelope allocation - uses flat buffers
 */
object ClosureCheckerFast {

  /**
   * Returns true if pattern is backward-closed AND middle-closed (exact BIDE-style).
   * Uses flat envelope buffers for zero per-node allocations.
   * 
   * @param db       Database
   * @param sids     SID buffer
   * @param nSids    Number of SIDs
   * @param pat      Pattern
   * @param k        Pattern length
   * @param firstBuf Flat buffer of first positions [sid0_e0, sid0_e1, ..., sid1_e0, ...]
   * @param lastBuf  Flat buffer of last positions
   * @param ctx      MinerContext for stamp arrays
   */
  def isClosedUsingEnvelopes(
      db: ItemsetSequenceDatabase,
      sids: Array[Int],
      nSids: Int,
      pat: ItemsetPattern,
      k: Int,
      firstBuf: Array[Int],
      lastBuf: Array[Int],
      ctx: MinerContext
  ): Boolean = {
    if (k == 0) return true

    val singleItemsets = db.maxItemsetSize == 1

    // 1) Backward S-prepend witness: item appearing before E0 in all SIDs
    if (hasCommonItemInRange(db, sids, nSids, k, firstBuf, lastBuf, 
        fromFn = (_, _) => 0, 
        toFn = (sidIdx, kk) => lastBuf(sidIdx * kk), // lastPos(0)
        ctx)) {
      return false
    }

    // 2) Backward I-prepend witness (skip for single-itemset datasets)
    if (!singleItemsets) {
      if (hasCommonItemIPrepend(db, sids, nSids, pat.itemsets(0), k, firstBuf, lastBuf, ctx)) {
        return false
      }
    }

    // 3) Middle S-insert in any gap - use TIGHT window: (lastPos(g)+1 .. firstPos(g+1))
    var g = 0
    while (g < k - 1) {
      val gapIdx = g
      if (hasCommonItemInRange(db, sids, nSids, k, firstBuf, lastBuf,
          fromFn = (sidIdx, kk) => lastBuf(sidIdx * kk + gapIdx) + 1,   // after lastPos(Eg)
          toFn = (sidIdx, kk) => firstBuf(sidIdx * kk + gapIdx + 1),    // before firstPos(E(g+1))
          ctx)) {
        return false
      }
      g += 1
    }

    // 4) Middle I-insert into any element (skip for singletons)
    if (!singleItemsets) {
      var i = 0
      while (i < k) {
        if (hasCommonItemIInsert(db, sids, nSids, pat.itemsets(i), k, firstBuf, lastBuf, i, ctx)) {
          return false
        }
        i += 1
      }
    }

    true
  }

  /**
   * Check if there's ANY common item in the range [fromFn, toFn) across ALL SIDs.
   * Uses stamp-based intersection - no allocations.
   * Uses singletonSeqs for singleton datasets.
   */
  private def hasCommonItemInRange(
      db: ItemsetSequenceDatabase,
      sids: Array[Int],
      nSids: Int,
      k: Int,
      firstBuf: Array[Int],
      lastBuf: Array[Int],
      fromFn: (Int, Int) => Int,
      toFn: (Int, Int) => Int,
      ctx: MinerContext
  ): Boolean = {
    if (nSids == 0) return false

    val seen = ctx.seenStamp
    val cand = ctx.candidates
    var candCount = 0

    val base = ctx.nextBackscanBase()
    val stamp1 = base + 1
    
    val isSingleton = db.isSingleton

    // ---- First SID: build candidate set
    {
      val sid = sids(0)
      
      var from = fromFn(0, k)
      var to = toFn(0, k)
      
      // Use singletonSeqs for singleton datasets
      if (isSingleton) {
        val seq = db.singletonSeqs(sid)
        if (from < 0) from = 0
        if (to > seq.length) to = seq.length
        if (to <= from) return false
        
        var j = from
        while (j < to) {
          val x = seq(j)
          if (seen(x) != stamp1) {
            seen(x) = stamp1
            cand(candCount) = x
            candCount += 1
          }
          j += 1
        }
      } else {
        val seq = db.sequences(sid).itemsets
        if (from < 0) from = 0
        if (to > seq.length) to = seq.length
        if (to <= from) return false
        
        var j = from
        while (j < to) {
          val is = seq(j)
          var t = 0
          while (t < is.length) {
            val x = is(t)
            if (seen(x) != stamp1) {
              seen(x) = stamp1
              cand(candCount) = x
              candCount += 1
            }
            t += 1
          }
          j += 1
        }
      }
    }

    if (candCount == 0) return false

    // ---- Remaining SIDs: filter candidates in-place
    var idx = 1
    while (idx < nSids) {
      val sid = sids(idx)

      var from = fromFn(idx, k)
      var to = toFn(idx, k)
      
      val curStamp = base + idx + 1
      val prevStamp = curStamp - 1

      if (isSingleton) {
        val seq = db.singletonSeqs(sid)
        if (from < 0) from = 0
        if (to > seq.length) to = seq.length
        if (to <= from) return false
        
        var j = from
        while (j < to) {
          val x = seq(j)
          if (seen(x) == prevStamp) seen(x) = curStamp
          j += 1
        }
      } else {
        val seq = db.sequences(sid).itemsets
        if (from < 0) from = 0
        if (to > seq.length) to = seq.length
        if (to <= from) return false
        
        var j = from
        while (j < to) {
          val is = seq(j)
          var t = 0
          while (t < is.length) {
            val x = is(t)
            if (seen(x) == prevStamp) seen(x) = curStamp
            t += 1
          }
          j += 1
        }
      }

      // Compact candidates
      var w = 0
      var r = 0
      while (r < candCount) {
        val x = cand(r)
        if (seen(x) == curStamp) {
          cand(w) = x
          w += 1
        }
        r += 1
      }
      candCount = w

      if (candCount == 0) return false

      idx += 1
    }

    true
  }

  /**
   * I-prepend witness: any x not in E0 that appears in some itemset matching E0.
   */
  private def hasCommonItemIPrepend(
      db: ItemsetSequenceDatabase,
      sids: Array[Int],
      nSids: Int,
      e0: Array[Int],
      k: Int,
      firstBuf: Array[Int],
      lastBuf: Array[Int],
      ctx: MinerContext
  ): Boolean = {
    if (nSids == 0) return false

    val seen = ctx.seenStamp
    val cand = ctx.candidates
    var candCount = 0

    val base = ctx.nextBackscanBase()
    val stamp1 = base + 1

    // ---- First SID
    {
      val sid = sids(0)
      val seq = db.sequences(sid).itemsets
      
      val from = math.max(0, firstBuf(0))      // firstPos(0) for SID 0
      val to = math.min(seq.length - 1, lastBuf(0)) // lastPos(0) for SID 0

      var j = from
      while (j <= to && j < seq.length) {
        val is = seq(j)
        if (isSubset(e0, is)) {
          // Linear merge-scan to find items in is but not in e0
          var pi = 0
          var si = 0
          while (si < is.length) {
            val x = is(si)
            // Skip e0 items
            while (pi < e0.length && e0(pi) < x) pi += 1
            if (pi >= e0.length || e0(pi) != x) {
              // x not in e0
              if (seen(x) != stamp1) {
                seen(x) = stamp1
                cand(candCount) = x
                candCount += 1
              }
            }
            si += 1
          }
        }
        j += 1
      }
    }

    if (candCount == 0) return false

    // ---- Remaining SIDs
    var idx = 1
    while (idx < nSids) {
      val sid = sids(idx)
      val seq = db.sequences(sid).itemsets

      val off = idx * k
      val from = math.max(0, firstBuf(off))
      val to = math.min(seq.length - 1, lastBuf(off))

      val curStamp = base + idx + 1
      val prevStamp = curStamp - 1

      var j = from
      while (j <= to && j < seq.length) {
        val is = seq(j)
        if (isSubset(e0, is)) {
          var pi = 0
          var si = 0
          while (si < is.length) {
            val x = is(si)
            while (pi < e0.length && e0(pi) < x) pi += 1
            if (pi >= e0.length || e0(pi) != x) {
              if (seen(x) == prevStamp) seen(x) = curStamp
            }
            si += 1
          }
        }
        j += 1
      }

      // Compact
      var w = 0
      var r = 0
      while (r < candCount) {
        val x = cand(r)
        if (seen(x) == curStamp) { cand(w) = x; w += 1 }
        r += 1
      }
      candCount = w

      if (candCount == 0) return false

      idx += 1
    }

    true
  }

  /**
   * I-insert witness for element iElem.
   */
  private def hasCommonItemIInsert(
      db: ItemsetSequenceDatabase,
      sids: Array[Int],
      nSids: Int,
      ei: Array[Int],
      k: Int,
      firstBuf: Array[Int],
      lastBuf: Array[Int],
      iElem: Int,
      ctx: MinerContext
  ): Boolean = {
    if (nSids == 0) return false

    val seen = ctx.seenStamp
    val cand = ctx.candidates
    var candCount = 0

    val base = ctx.nextBackscanBase()
    val stamp1 = base + 1

    // ---- First SID
    {
      val sid = sids(0)
      val seq = db.sequences(sid).itemsets
      
      val from = math.max(0, firstBuf(iElem))
      val to = math.min(seq.length - 1, lastBuf(iElem))

      var j = from
      while (j <= to && j < seq.length) {
        val is = seq(j)
        if (isSubset(ei, is)) {
          var pi = 0
          var si = 0
          while (si < is.length) {
            val x = is(si)
            while (pi < ei.length && ei(pi) < x) pi += 1
            if (pi >= ei.length || ei(pi) != x) {
              if (seen(x) != stamp1) {
                seen(x) = stamp1
                cand(candCount) = x
                candCount += 1
              }
            }
            si += 1
          }
        }
        j += 1
      }
    }

    if (candCount == 0) return false

    // ---- Remaining SIDs
    var idx = 1
    while (idx < nSids) {
      val sid = sids(idx)
      val seq = db.sequences(sid).itemsets

      val off = idx * k
      val from = math.max(0, firstBuf(off + iElem))
      val to = math.min(seq.length - 1, lastBuf(off + iElem))

      val curStamp = base + idx + 1
      val prevStamp = curStamp - 1

      var j = from
      while (j <= to && j < seq.length) {
        val is = seq(j)
        if (isSubset(ei, is)) {
          var pi = 0
          var si = 0
          while (si < is.length) {
            val x = is(si)
            while (pi < ei.length && ei(pi) < x) pi += 1
            if (pi >= ei.length || ei(pi) != x) {
              if (seen(x) == prevStamp) seen(x) = curStamp
            }
            si += 1
          }
        }
        j += 1
      }

      // Compact
      var w = 0
      var r = 0
      while (r < candCount) {
        val x = cand(r)
        if (seen(x) == curStamp) { cand(w) = x; w += 1 }
        r += 1
      }
      candCount = w

      if (candCount == 0) return false

      idx += 1
    }

    true
  }

  // ---- Subset primitives ----

  private def isSubset(a: Array[Int], b: Array[Int]): Boolean = {
    var i = 0
    var j = 0
    while (i < a.length && j < b.length) {
      val ai = a(i)
      val bj = b(j)
      if (ai == bj) { i += 1; j += 1 }
      else if (bj < ai) j += 1
      else return false
    }
    i == a.length
  }
}
```

---

## 4. EnvelopeComputer.scala

**Purpose**: Allocation-free first/last embedding computation with:
- Singleton fastpath: direct int comparison (lines 48-104)
- General case: subset checks with merge-scan (lines 109-192)

```scala
package apvclofast

/**
 * Allocation-free envelope computation.
 * 
 * V2: Added singleton fastpath for Kosarak-style datasets.
 * Fills flat buffers (firstBuf, lastBuf) in MinerContext instead of
 * allocating EmbeddingEnvelope objects per SID.
 */
object EnvelopeComputer {

  /**
   * Compute first/last embedding positions into flat buffers.
   * 
   * @param db      Database
   * @param sids    SID buffer (from fillSids)
   * @param nSids   Number of SIDs
   * @param pat     Pattern to embed
   * @param ctx     MinerContext with firstBuf/lastBuf
   * @return Pattern length k (for offset calculation)
   */
  def computeInto(
      db: ItemsetSequenceDatabase,
      sids: Array[Int],
      nSids: Int,
      pat: ItemsetPattern,
      ctx: MinerContext
  ): Int = {
    val k = pat.length
    if (k == 0) return 0
    
    // Ensure capacity: need nSids * k slots
    ctx.ensureEnvCapacity(nSids * k)

    // Use singleton fastpath for Kosarak-style datasets
    if (db.isSingleton) {
      computeIntoSingleton(db, sids, nSids, pat, ctx, k)
    } else {
      computeIntoGeneral(db, sids, nSids, pat, ctx, k)
    }
    k
  }

  /**
   * Singleton fastpath: each pattern element is a single item.
   * Just compare integers instead of doing subset checks.
   */
  private def computeIntoSingleton(
      db: ItemsetSequenceDatabase,
      sids: Array[Int],
      nSids: Int,
      pat: ItemsetPattern,
      ctx: MinerContext,
      k: Int
  ): Unit = {
    // Build flat pattern targets
    val targets = new Array[Int](k)
    var p = 0
    while (p < k) {
      targets(p) = pat.itemsets(p)(0)
      p += 1
    }

    var i = 0
    while (i < nSids) {
      val sid = sids(i)
      val seq = db.singletonSeqs(sid)
      val off = i * k

      // First embedding: scan forward
      var j = 0
      var pi = 0
      while (pi < k && j < seq.length) {
        if (seq(j) == targets(pi)) {
          ctx.firstBuf(off + pi) = j
          pi += 1
        }
        j += 1
      }
      // Mark remaining as invalid
      while (pi < k) {
        ctx.firstBuf(off + pi) = -1
        pi += 1
      }

      // Last embedding: scan backward
      j = seq.length - 1
      pi = k - 1
      while (pi >= 0 && j >= 0) {
        if (seq(j) == targets(pi)) {
          ctx.lastBuf(off + pi) = j
          pi -= 1
        }
        j -= 1
      }
      // Mark remaining as invalid
      while (pi >= 0) {
        ctx.lastBuf(off + pi) = -1
        pi -= 1
      }

      i += 1
    }
  }

  /**
   * General case: handle multi-item itemsets with subset checks.
   */
  private def computeIntoGeneral(
      db: ItemsetSequenceDatabase,
      sids: Array[Int],
      nSids: Int,
      pat: ItemsetPattern,
      ctx: MinerContext,
      k: Int
  ): Unit = {
    var i = 0
    while (i < nSids) {
      val sid = sids(i)
      val seq = db.sequences(sid).itemsets
      val off = i * k

      firstInto(seq, pat.itemsets, ctx.firstBuf, off)
      lastInto(seq, pat.itemsets, ctx.lastBuf, off)

      i += 1
    }
  }

  /**
   * Compute first embedding positions (earliest match for each pattern element).
   */
  private def firstInto(
      seq: Array[Array[Int]], 
      pat: Array[Array[Int]], 
      out: Array[Int], 
      off: Int
  ): Unit = {
    var j = 0
    var i = 0
    while (i < pat.length) {
      var found = false
      while (j < seq.length && !found) {
        if (isSubset(pat(i), seq(j))) {
          out(off + i) = j
          found = true
        }
        j += 1
      }
      if (!found) {
        var t = i
        while (t < pat.length) {
          out(off + t) = -1
          t += 1
        }
        return
      }
      i += 1
    }
  }

  /**
   * Compute last embedding positions (latest match for each pattern element).
   */
  private def lastInto(
      seq: Array[Array[Int]], 
      pat: Array[Array[Int]], 
      out: Array[Int], 
      off: Int
  ): Unit = {
    var j = seq.length - 1
    var i = pat.length - 1
    while (i >= 0) {
      var found = false
      while (j >= 0 && !found) {
        if (isSubset(pat(i), seq(j))) {
          out(off + i) = j
          found = true
        }
        j -= 1
      }
      if (!found) {
        var t = 0
        while (t <= i) {
          out(off + t) = -1
          t += 1
        }
        return
      }
      i -= 1
    }
  }

  private def isSubset(pat: Array[Int], seq: Array[Int]): Boolean = {
    var i = 0
    var j = 0
    while (i < pat.length && j < seq.length) {
      val pi = pat(i)
      val sj = seq(j)
      if (pi == sj) {
        i += 1
        j += 1
      } else if (sj < pi) {
        j += 1
      } else {
        return false
      }
    }
    i == pat.length
  }
}
```

---

## 5. MinerContext.scala

**Purpose**: Reusable buffers with epoch-based stamping to avoid allocation:
- BackScan stamps with overflow protection (lines 25-40)
- Enumeration stamps (lines 50-68)
- Envelope flat buffers (lines 12-20)
- Reusable IntLists (lines 70-84)

```scala
package apvclofast

import java.util.Arrays

final class MinerContext(val maxItem: Int, val maxSid: Int, val maxSupport: Int) {

  // ---- BackScan scratch ----
  val seenStamp = new Array[Int](maxItem + 1)
  val candidates = new Array[Int](maxItem + 1)
  var bsEpoch: Int = 1

  // ---- Envelope buffers (allocation-free embedding cache) ----
  val sidBuf = new Array[Int](maxSupport)
  var firstBuf: Array[Int] = Array.emptyIntArray
  var lastBuf: Array[Int] = Array.emptyIntArray

  def ensureEnvCapacity(n: Int): Unit = {
    if (firstBuf.length < n) firstBuf = Arrays.copyOf(firstBuf, n * 2)
    if (lastBuf.length < n) lastBuf = Arrays.copyOf(lastBuf, n * 2)
  }

  // Enough bits to encode support index (assuming stamps are local to verification)
  // Actually, for BackScan: we use `base + k` where k is 0..numSids. 
  // So shift must accommodate `maxSupport` (upper bound on numSids).
  private val bsShift: Int = {
    var v = maxSupport + 2
    var bits = 0
    while (v > 0) { bits += 1; v >>>= 1 }
    bits
  }

  def nextBackscanBase(): Int = {
    bsEpoch += 1
    // avoid overflow corner; rare
    if (bsEpoch == 0 || (bsEpoch << bsShift) < 0) { 
      java.util.Arrays.fill(seenStamp, 0)
      bsEpoch = 1 
    }
    bsEpoch << bsShift
  }

  // ---- Enumeration scratch ----
  val sExtSupport = new Array[Int](maxItem + 1)
  val iExtSupport = new Array[Int](maxItem + 1)
  val sExtSeen = new Array[Int](maxItem + 1)
  val iExtSeen = new Array[Int](maxItem + 1)
  val sTouched = new Array[Int](maxItem + 1)
  val iTouched = new Array[Int](maxItem + 1)

  var enumEpoch: Int = 1

  // Enough bits to encode sid (<= maxSid)
  private val sidShift: Int = {
    var v = maxSid + 2
    var bits = 0
    while (v > 0) { bits += 1; v >>>= 1 }
    bits
  }

  def nextEnumSidBase(): Int = {
    enumEpoch += 1
    if (enumEpoch == 0 || (enumEpoch << sidShift) < 0) { // overflow check
      java.util.Arrays.fill(sExtSeen, 0)
      java.util.Arrays.fill(iExtSeen, 0)
      enumEpoch = 1
    }
    enumEpoch << sidShift
  }

  // ---- Reusable position lists (kills per-node maxItem arrays) ----
  final class IntList(initialCap: Int = 16) {
    private var a = new Array[Int](initialCap)
    var size: Int = 0
    def clear(): Unit = size = 0
    def add(x: Int): Unit = {
      if (size == a.length) a = java.util.Arrays.copyOf(a, a.length << 1)
      a(size) = x
      size += 1
    }
    def toArrayTrimmed(): Array[Int] = java.util.Arrays.copyOf(a, size)
  }

  val sLists = new Array[IntList](maxItem + 1)
  val iLists = new Array[IntList](maxItem + 1)
}
```

---

## 6. ItemsetSequence.scala

**Purpose**: Database model with:
- ItemsetSequence data structure (lines 7-17)
- ItemsetSequenceDatabase with maxItem, maxItemsetSize, isSingleton (lines 23-108)
- SPMFLoaderItemsets parser (lines 115-192)
- singletonSeqs flat view (lines 70-88)

```scala
package apvclofast

/**
 * ItemsetSequence: Represents a sequence of itemsets.
 * Each itemset is an Array[Int] of items sorted in increasing order.
 */
case class ItemsetSequence(itemsets: Array[Array[Int]]) {
  def length: Int = itemsets.length
  def apply(idx: Int): Array[Int] = itemsets(idx)
  def isEmpty: Boolean = itemsets.isEmpty
  
  /** Total number of items across all itemsets */
  def totalItems: Int = itemsets.map(_.length).sum
  
  /** Get all unique items in this sequence */
  def uniqueItems: Set[Int] = itemsets.flatMap(_.toSet).toSet
}

/**
 * ItemsetSequenceDatabase: Database of itemset sequences.
 * Replaces SequenceDatabase for itemset-aware mining.
 */
class ItemsetSequenceDatabase(val sequences: Array[ItemsetSequence]) {
  val numSequences: Int = sequences.length
  
  def getSequence(sid: Int): ItemsetSequence = sequences(sid)
  
  /** Maximum item ID across all sequences */
  lazy val maxItem: Int = {
    var max = 0
    var sid = 0
    while (sid < numSequences) {
      val seq = sequences(sid)
      var i = 0
      while (i < seq.length) {
        val itemset = seq(i)
        var j = 0
        while (j < itemset.length) {
          if (itemset(j) > max) max = itemset(j)
          j += 1
        }
        i += 1
      }
      sid += 1
    }
    max
  }
  
  /** Maximum size of any itemset in the database */
  lazy val maxItemsetSize: Int = {
    var max = 0
    var sid = 0
    while (sid < numSequences) {
      val seq = sequences(sid)
      var i = 0
      while (i < seq.length) {
        val len = seq(i).length
        if (len > max) max = len
        i += 1
      }
      sid += 1
    }
    max
  }
  
  /** Is this a singleton-itemset database (Kosarak-style)? */
  lazy val isSingleton: Boolean = maxItemsetSize == 1
  
  /** Flattened view for singleton datasets: Array[Array[Int]] where inner is just items */
  lazy val singletonSeqs: Array[Array[Int]] = {
    if (!isSingleton) null
    else {
      val result = new Array[Array[Int]](numSequences)
      var sid = 0
      while (sid < numSequences) {
        val seq = sequences(sid)
        val flat = new Array[Int](seq.length)
        var i = 0
        while (i < seq.length) {
          flat(i) = seq(i)(0)
          i += 1
        }
        result(sid) = flat
        sid += 1
      }
      result
    }
  }
  
  /** Statistics about the database */
  def stats: String = {
    val totalItemsets = sequences.map(_.length).sum
    val totalItems = sequences.map(_.totalItems).sum
    val avgItemsets = if (numSequences > 0) totalItemsets.toDouble / numSequences else 0.0
    val avgItemsPerItemset = if (totalItemsets > 0) totalItems.toDouble / totalItemsets else 0.0
    val maxLen = sequences.map(_.length).maxOption.getOrElse(0)
    
    f"""ItemsetSequenceDatabase Statistics:
       |  Sequences: $numSequences%,d
       |  Total itemsets: $totalItemsets%,d
       |  Total items: $totalItems%,d
       |  Avg itemsets/seq: $avgItemsets%.1f
       |  Avg items/itemset: $avgItemsPerItemset%.1f
       |  Max itemset size: $maxItemsetSize
       |  Max sequence length: $maxLen
       |  Max item ID: $maxItem%,d""".stripMargin
  }
}

/**
 * SPMFLoaderItemsets: Parser for SPMF format that preserves itemset structure.
 * Format: item1 item2 -1 item3 item4 -1 item5 -1 -2
 * Where -1 separates itemsets and -2 ends the sequence.
 */
object SPMFLoaderItemsets {
  
  import java.io.{BufferedReader, FileReader}
  import scala.collection.mutable
  
  /**
   * Load sequences from SPMF format file, preserving itemset structure.
   */
  def loadSequences(filename: String): ItemsetSequenceDatabase = {
    val sequences = mutable.ArrayBuffer[ItemsetSequence]()
    val reader = new BufferedReader(new FileReader(filename))
    
    try {
      var line = reader.readLine()
      while (line != null) {
        if (line.nonEmpty && !line.startsWith("#")) {
          val seq = parseSequence(line)
          if (!seq.isEmpty) {
            sequences += seq
          }
        }
        line = reader.readLine()
      }
    } finally {
      reader.close()
    }
    
    new ItemsetSequenceDatabase(sequences.toArray)
  }
  
  /**
   * Parse a single SPMF sequence line.
   * Returns ItemsetSequence with preserved itemset structure.
   */
  def parseSequence(line: String): ItemsetSequence = {
    val itemsets = mutable.ArrayBuffer[Array[Int]]()
    val currentItemset = mutable.ArrayBuffer[Int]()
    val tokens = line.trim.split("\\s+")
    
    var i = 0
    while (i < tokens.length) {
      val token = tokens(i)
      if (token.nonEmpty) {
        try {
          val item = token.toInt
          if (item == -2) {
            // End of sequence - flush current itemset if non-empty
            if (currentItemset.nonEmpty) {
              itemsets += currentItemset.sorted.toArray
              currentItemset.clear()
            }
            // Done with this sequence
            return ItemsetSequence(itemsets.toArray)
          } else if (item == -1) {
            // End of itemset - flush current itemset if non-empty
            if (currentItemset.nonEmpty) {
              itemsets += currentItemset.sorted.toArray
              currentItemset.clear()
            }
          } else if (item >= 0) {
            // Regular item
            currentItemset += item
          }
        } catch {
          case _: NumberFormatException => // Skip non-numeric tokens
        }
      }
      i += 1
    }
    
    // Handle case where -2 is missing
    if (currentItemset.nonEmpty) {
      itemsets += currentItemset.sorted.toArray
    }
    
    ItemsetSequence(itemsets.toArray)
  }
}
```

---

## 7. Test Dataset

### 7.1 Input File (tiny_test.txt)

```
1 -1 2 -1 3 -1 -2
1 -1 2 -1 3 -1 -2
1 -1 2 -1 -2
1 -1 3 -1 -2
2 -1 3 -1 -2
```

### 7.2 Expected Output (minsup=2)

```
Closed patterns:
  1 -1           #SUP: 4
  2 -1           #SUP: 4
  3 -1           #SUP: 4
  1 -1 2 -1      #SUP: 3
  1 -1 3 -1      #SUP: 3
  2 -1 3 -1      #SUP: 4
  1 -1 2 -1 3 -1 #SUP: 2

Total: 7 closed patterns
```

### 7.3 Run Command

```bash
java -Xmx4g -cp target/scala-2.13/triback-clo.jar \
  tribackclo.TriBackClo_Main \
  --input tiny_test.txt \
  --minsup 2 \
  --output /tmp/out.txt
```

---

## Critical Points for Verification

1. **Canonical I-extension order**: Items > lastItem only (ItemsetPointerStore line 241)
2. **BackScan period**: `[startIdx, currentIdx)` temporal gap + items < lastItem in current itemset
3. **Gap window**: `[firstPos(g)+1, lastPos(g+1))` (wide forcing window; tight windows are unsafe for repeated items)
4. **Epoch overflow**: Check `nextBackscanBase()` and `nextEnumSidBase()` for overflow handling
5. **Singleton detection**: `db.maxItemsetSize == 1` → skip I-extension entirely
6. **4-tuple STRIDE**: `(sid, startIdx, currentIdx, lastItem)` — watch for off-by-one errors in array indexing.
