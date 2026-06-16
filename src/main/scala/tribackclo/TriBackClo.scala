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
  /** Append item as I-extension (to last itemset) 
   * 
   * Optimization: Canonical I-extension ordering enforces item > max(last itemset),
   * so the new item is always the largest - we just append to the end.
   * This is O(m) instead of O(m log m) sort.
   */
  def appendI(item: Int): ItemsetPattern = {
    if (itemsets.isEmpty) {
      ItemsetPattern(Array(Array(item)))
    } else {
      val lastIdx = itemsets.length - 1
      val lastItemset = itemsets(lastIdx)
      // Allocate new array, copy existing items, append new item at end
      val newLast = new Array[Int](lastItemset.length + 1)
      System.arraycopy(lastItemset, 0, newLast, 0, lastItemset.length)
      newLast(lastItemset.length) = item
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
class TriBackCloMiner(
    db: ItemsetSequenceDatabase,
    minsup: Int,
    countOnly: Boolean = false,  // If true, count patterns but don't store them (for fair memory benchmarking)
    loadTimeNs: Long = 0  // Loading time in nanoseconds (to match SPMF's Total time methodology)
) {
  
  private val results = if (countOnly) null else mutable.ArrayBuffer[(ItemsetPattern, Int)]()
  private var closedCount = 0L  // Always count patterns, even in countOnly mode
  private var nodesVisited = 0L
  private var prunedSubtrees = 0L
  private var nodesGated = 0L  // Nodes skipped by local/internal witness gating
  private var peakMemory = 0L  // Track peak memory usage
  private val runtime = Runtime.getRuntime
  
  /** Check memory like SPMF's MemoryLogger.checkMemory() */
  private def checkMemory(): Unit = {
    val currentMem = runtime.totalMemory - runtime.freeMemory
    if (currentMem > peakMemory) peakMemory = currentMem
  }
  
  /**
   * Mine all closed sequential patterns.
   */
  /**
   * Mine all closed sequential patterns.
   */
  def mine(): Array[(ItemsetPattern, Int)] = {
    println(s"[TriBackCloMiner] Starting mining with minsup=$minsup")
    println(db.stats)
    
    // Check memory after database loading (like SPMF)
    checkMemory()
    
    val t0 = System.nanoTime()
    
    val rootStore = ItemsetPointerStore.createRoot(db)
    ctx = new MinerContext(db.maxItem, db.numSequences, db.numSequences) // maxSupport <= numSids
    dfs(ItemsetPattern.empty, rootStore, ctx)
    
    val miningTime = (System.nanoTime() - t0) / 1e9
    val totalTime = (loadTimeNs + System.nanoTime() - t0) / 1e9  // Include loading time like SPMF
    
    // Final memory sample with GC for fair comparison with SPMF's MemoryLogger
    System.gc()
    checkMemory()
    val peakMB = peakMemory / (1024.0 * 1024.0)
    
    println(f"[TriBackCloMiner] Mining: $miningTime%.3f seconds")
    println(f"[TriBackCloMiner] Total time: $totalTime%.3f seconds")  // SPMF-compatible (includes loading)
    println(f"[TriBackCloMiner] Peak memory: $peakMB%.2f MB")
    println(f"[TriBackCloMiner] Nodes visited: $nodesVisited%,d")
    println(f"[TriBackCloMiner] Subtrees pruned: $prunedSubtrees%,d")
    println(f"[TriBackCloMiner] Nodes gated: $nodesGated%,d")
    println(f"[TriBackCloMiner] Closed patterns found: $closedCount%,d")
    if (countOnly) println("[TriBackCloMiner] Count-only mode: patterns not stored in memory")
    
    if (countOnly) Array.empty else results.toArray
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
   * If both pass, we perform explicit envelope-based verification (lazily) for general databases.
   * For singleton datasets (like Kosarak), this verification is optimized away or simplified.
   */
  private def lazyExactClosed(prefix: ItemsetPattern, store: ItemsetPointerStore): Boolean = {
    val k = prefix.length
    
    // FAST PATH: For singleton datasets, closure checking is simpler
    // - No I-prepend (itemsets are singletons)
    // - No I-insert (itemsets are singletons)
    // - Only need S-prepend and S-insert in gaps
    //
    // For length-1 patterns: only S-prepend matters (no gaps)
    // For length-k patterns: S-prepend + (k-1) gap S-inserts
    if (db.isSingleton && k == 1) {
      // Length-1 singleton: backward S-prepend must consider the widest feasible prefix window.
      // For pattern <a>, each supporting sequence may match a at a later occurrence; hence we must
      // intersect items in [0, lastOcc(a)) (paper's [1, last_s(1)) in 1-based).
      val nSids = store.fillSids(ctx.sidBuf)
      return !hasCommonItemBeforeLastOccurrence(ctx.sidBuf, nSids, prefix.itemsets(0)(0))
    }
    
    // GENERAL PATH: Full envelope-based closure check
    // 1. Fill supporting SIDs (allocation-free)
    val nSids = store.fillSids(ctx.sidBuf)

    // 2. Compute first/last envelopes into reusable flat buffers
    EnvelopeComputer.computeInto(db, ctx.sidBuf, nSids, prefix, ctx)

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
  
  /**
   * Fast check for length-1 patterns on singleton datasets.
   *
   * Returns true iff there exists an item x such that for every supporting sequence s,
   * x appears before the rightmost feasible match of the target item (i.e., before its last
   * occurrence). This is the correct backward S-prepend window for k=1.
   */
  private def hasCommonItemBeforeLastOccurrence(sids: Array[Int], nSids: Int, targetItem: Int): Boolean = {
    if (nSids == 0) return false
    
    val seen = ctx.seenStamp
    val cand = ctx.candidates
    var candCount = 0
    val base = ctx.nextBackscanBase()
    
    // Use singletonSeqs for efficiency
    val seqs = db.singletonSeqs
    
    // First SID: build candidate set (items before last occurrence of target)
    {
      val seq = seqs(sids(0))
      val stamp1 = base + 1

      var last = seq.length - 1
      while (last >= 0 && seq(last) != targetItem) last -= 1
      if (last <= 0) return false

      var j = 0
      while (j < last) {
        val x = seq(j)
        if (seen(x) != stamp1) {
          seen(x) = stamp1
          cand(candCount) = x
          candCount += 1
        }
        j += 1
      }
    }
    
    if (candCount == 0) return false
    
    // Remaining SIDs: intersect
    var idx = 1
    while (idx < nSids) {
      val seq = seqs(sids(idx))
      var last = seq.length - 1
      while (last >= 0 && seq(last) != targetItem) last -= 1
      if (last <= 0) return false

      val curStamp = base + idx + 1
      val prevStamp = curStamp - 1
      
      var j = 0
      while (j < last) {
        val x = seq(j)
        if (seen(x) == prevStamp) seen(x) = curStamp
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
  
  // Shared MinerContext for DFS and lazyExactClosed
  private var ctx: MinerContext = _

  /*
   * DFS with optimized logic.
   * FIX: Materialize children locally to avoid MinerContext state corruption during recursion.
   */
  private def dfs(prefix: ItemsetPattern, store: ItemsetPointerStore, ctx: MinerContext): Unit = {
    nodesVisited += 1
    
    // Sample memory periodically (every 1000 nodes) for accurate peak tracking
    if ((nodesVisited & 0x3FF) == 0) {  // Every 1024 nodes
      val currentMem = runtime.totalMemory - runtime.freeMemory
      if (currentMem > peakMemory) peakMemory = currentMem
    }
    
    // Support check
    if (store.support < minsup) return
    
    // 1. BackScan subtree pruning (SOUND for all descendants)
    // Only Temporal witnesses are safe to prune the entire subtree.
    if (prefix.length >= 1 && store.detectBackScanPrune(ctx)) {
      prunedSubtrees += 1
      return
    }
    
    // 2. Enumerate extensions (+ same-support forward detection for forward-closed gating)
    val tailItemset = if (prefix.isEmpty) null else prefix.itemsets.last
    val (sCount, sTouched, iCount, iTouched, hasSameSuppForward) =
      store.enumerateExtensions(minsup, ctx, tailItemset)
    
    // 3. Output logic with Node Gating (SOUND only for current pattern)
    // Generalized witnesses (Local/Internal) can skip current output but NOT subtree.
    val forwardClosed = !hasSameSuppForward
    if (!prefix.isEmpty && forwardClosed) {
      val lastElement = prefix.itemsets.last
      val prevElement = if (prefix.length > 1) prefix.itemsets(prefix.length - 2) else null
      
      // Node Gating: cheap check before expensive lazyExactClosed
      if (!store.detectNotClosedFast(ctx, lastElement, prevElement)) {
        if (lazyExactClosed(prefix, store)) {
          closedCount += 1
          if (countOnly) {
            // Strict fairness: serialize pattern like SPMF does (then discard)
            // This ensures equal work with SPMF's /dev/null output mode
            val _ = s"${prefix.toSPMF} #SUP: ${store.support}"
          } else {
            results += ((prefix, store.support))
          }
          // Memory checkpoint like SPMF's MemoryLogger.checkMemory()
          checkMemory()
        }
      } else {
        nodesGated += 1
      }
    }
    
    // Materialize S-children locally to avoid corruption of shared MinerContext arrays during recursion
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
    
    // Materialize I-children locally
    val iChildren = new Array[(Int, ItemsetPointerStore)](iCount)
    var iValid = 0
    var jumpK = 0
    while (jumpK < iCount) {
      val item = iTouched(jumpK)
      val newSupport = ctx.iExtSupport(item)
      // Reset support for next usage
      ctx.iExtSupport(item) = 0
      
      if (newSupport >= minsup) {
          val positions = ctx.iLists(item).toArrayTrimmed()
          iChildren(iValid) = (item, new ItemsetPointerStore(positions, newSupport, db))
          iValid += 1
      }
      jumpK += 1
    }

    // Recurse on frequent S- and I-children
    var k = 0
    while (k < sValid) {
       val (item, childStore) = sChildren(k)
       dfs(prefix.appendS(item), childStore, ctx)
       k += 1
    }
    
    var i = 0
    while (i < iValid) {
       val (item, childStore) = iChildren(i)
       dfs(prefix.appendI(item), childStore, ctx)
       i += 1
    }
  }
}

/**
 * Main entry point for itemset-sequence mining.
 */
object TriBackClo_Main {
  
  def main(args: Array[String]): Unit = {
    val argMap = args.sliding(2, 2).collect { case Array(k, v) => k -> v }.toMap
    val flags = args.filter(_.startsWith("--")).filterNot(_.contains(" ")).toSet
    
    val inputFile = argMap.getOrElse("--input", "data/test.txt")
    val minsup = argMap.get("--minsup").map(_.toInt).getOrElse(2)
    val ratio = argMap.get("--ratio").map(_.toDouble)
    val outputFile = argMap.get("--output")
    val countOnly = flags.contains("--countOnly") || args.contains("--countOnly")
    
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
    if (countOnly) println("[INFO] Count-only mode enabled (patterns not stored in memory)")
    val loadTimeNs = System.nanoTime() - t0  // Nanoseconds spent loading
    val miner = new TriBackCloMiner(db, actualMinsup, countOnly, loadTimeNs)
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
    println("=" * 60)
  }


}
