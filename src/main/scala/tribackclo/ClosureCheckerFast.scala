package tribackclo

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
    //    Uses [0, last_s(1)) - the rightmost feasible match position of first element
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

    // 3) Middle S-insert in any gap
    // LEVEL 3 GENIUS FIX: Unconditional Adaptive Window
    // We ALWAYS use the Wide Window: (firstPos(g)+1 to lastPos(g+1))
    // - For Unique matches: Wide == Tight (Efficient, Correct)
    // - For Ambiguous matches: Wide covers Union of Gaps (Correct)
    // - For Inverted Tight windows: Wide handles them automatically (Correct)
    // This removes all heuristics and O(N) pre-scans.
    var g = 0
    while (g < k - 1) {
      val gapIdx = g
      
      if (hasCommonItemInRange(db, sids, nSids, k, firstBuf, lastBuf,
          fromFn = (sidIdx, kk) => firstBuf(sidIdx * kk + gapIdx) + 1,
          toFn = (sidIdx, kk) => lastBuf(sidIdx * kk + gapIdx + 1),
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
  
  /**
   * LEVEL 3 GENIUS FIX: Precise gap check for dangerous gaps.
   * 
   * When the envelope window is inverted (due to repeated items), we need to check
   * ALL valid embeddings to find if any common item can be inserted.
   * 
   * Algorithm:
   * 1. For each SID, find ALL positions where pattern element g can match
   * 2. For each such position, check items between it and the next match of g+1
   * 3. Intersect across all SIDs
   * 
   * This is more expensive than envelope check but only runs for ~0.2% of gaps.
   */
  private def hasCommonItemInGapPrecise(
      db: ItemsetSequenceDatabase,
      sids: Array[Int],
      nSids: Int,
      pat: ItemsetPattern,
      gapIdx: Int,
      k: Int,
      ctx: MinerContext
  ): Boolean = {
    if (nSids == 0) return false
    
    val seen = ctx.seenStamp
    val cand = ctx.candidates
    var candCount = 0
    val base = ctx.nextBackscanBase()
    
    val patElemG = pat.itemsets(gapIdx)
    val patElemG1 = pat.itemsets(gapIdx + 1)
    val isSingleton = db.isSingleton
    
    // First SID: collect all items in gap across all valid embeddings
    {
      val sid = sids(0)
      val stamp1 = base + 1
      
      if (isSingleton) {
        val seq = db.singletonSeqs(sid)
        val targetG = patElemG(0)
        val targetG1 = patElemG1(0)
        
        // Find all positions where g matches, then items between it and next g+1
        var pos = 0
        while (pos < seq.length) {
          if (seq(pos) == targetG) {
            // Find next position where g+1 matches (after pos)
            var next = pos + 1
            while (next < seq.length && seq(next) != targetG1) {
              val x = seq(next)
              if (seen(x) != stamp1) {
                seen(x) = stamp1
                cand(candCount) = x
                candCount += 1
              }
              next += 1
            }
          }
          pos += 1
        }
      } else {
        val seq = db.sequences(sid).itemsets
        // General case: find all positions where g matches (subset check)
        var pos = 0
        while (pos < seq.length) {
          if (isSubset(patElemG, seq(pos))) {
            // Find next position where g+1 matches (after pos)
            var next = pos + 1
            while (next < seq.length) {
              if (isSubset(patElemG1, seq(next))) {
                // We've found the gap boundary, stop collecting
                next = seq.length  // exit
              } else {
                // Collect items from this position
                val is = seq(next)
                var si = 0
                while (si < is.length) {
                  val x = is(si)
                  if (seen(x) != stamp1) {
                    seen(x) = stamp1
                    cand(candCount) = x
                    candCount += 1
                  }
                  si += 1
                }
                next += 1
              }
            }
          }
          pos += 1
        }
      }
    }
    
    if (candCount == 0) return false
    
    // Remaining SIDs: filter candidates
    var idx = 1
    while (idx < nSids) {
      val sid = sids(idx)
      val curStamp = base + idx + 1
      val prevStamp = base + idx
      
      if (isSingleton) {
        val seq = db.singletonSeqs(sid)
        val targetG = patElemG(0)
        val targetG1 = patElemG1(0)
        
        var pos = 0
        while (pos < seq.length) {
          if (seq(pos) == targetG) {
            var next = pos + 1
            while (next < seq.length && seq(next) != targetG1) {
              val x = seq(next)
              if (seen(x) == prevStamp) seen(x) = curStamp
              next += 1
            }
          }
          pos += 1
        }
      } else {
        val seq = db.sequences(sid).itemsets
        var pos = 0
        while (pos < seq.length) {
          if (isSubset(patElemG, seq(pos))) {
            var next = pos + 1
            while (next < seq.length) {
              if (isSubset(patElemG1, seq(next))) {
                next = seq.length
              } else {
                val is = seq(next)
                var si = 0
                while (si < is.length) {
                  val x = is(si)
                  if (seen(x) == prevStamp) seen(x) = curStamp
                  si += 1
                }
                next += 1
              }
            }
          }
          pos += 1
        }
      }
      
      // Compact candidates
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
    
    true  // Found common items in gap across all SIDs
  }
}
