package tribackclo

import scala.collection.mutable



/**
 * Optimized ItemsetPointerStore with:
 * 1. 4-element stride for correct BackScan properties (sid, startIdx, currentIdx, lastItem)
 * 2. Allocation-free BackScan (stamp-based intersection)
 * 3. Sparse "touched-items" enumeration
 */
class ItemsetPointerStore(
    private val positions: Array[Int],
    private val numSids: Int,
    private val db: ItemsetSequenceDatabase
) {
  
  private val STRIDE = 4  // (sid, startIdx, currentIdx, lastItem)
  
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
   * Allocation-free witness detection using stamp-based intersections (no BitSet allocations).
   *
   * TriBack-Clo keeps witness families structurally separate:
   *   1) Temporal witness T(s): items in [startIdx, currentIdx)  → sound for subtree pruning.
   *   2) Local-gap witness L(s): items in E_currentIdx with x < max(P_k) and x ∉ P_k → node gating only.
   *   3) Internal proxy Int_{k-1}(s): E_{startIdx-1} \ P_{k-1} → node gating only.
   */
  /**
   * Sound SUBTREE PRUNING: Only temporal witnesses are safe to prune the entire subtree
   * in itemset-sequences with a First-Occurrence projection model.
   * (Internal/Local witnesses might be bypassed by I-extensions jumping forward).
   */
  def detectBackScanPrune(ctx: MinerContext): Boolean = {
    if (numSids == 0) return false
    hasTemporalWitness(ctx)
  }

  /**
   * Sound NODE GATING: All generalized witnesses (Temporal, Local, Internal)
   * can be used to skip output and verification for the CURRENT node.
   */
  def detectNotClosedFast(ctx: MinerContext, lastElement: Array[Int], prevElement: Array[Int]): Boolean = {
    if (numSids == 0) return false
    
    // FAST PATH: Singleton datasets only need temporal witness check
    // Local-gap and Internal witnesses are impossible with single-item itemsets
    if (db.isSingleton) {
      return hasTemporalWitness(ctx)
    }
    
    // GENERAL PATH: Multi-item itemsets
    // 1. Temporal (Safe for both)
    if (hasTemporalWitness(ctx)) return true
    
    // 2. Local-gap (Tail residuals)
    if (lastElement != null && lastElement.length > 0) {
      val maxTailItem = lastElement.last
      if (hasLocalWitness(ctx, lastElement, maxTailItem)) return true
      
      // 3. Internal backward-I (Previous itemset residuals)
      if (prevElement != null) {
        if (hasLocalWitnessInternal(ctx, prevElement)) return true
      }
    }
    
    false
  }
  
  /**
   * Check for temporal witness: item in [startIdx, currentIdx) for ALL SIDs
   */
  private def hasTemporalWitness(ctx: MinerContext): Boolean = {
    val seenStamp = ctx.seenStamp
    val candidates = ctx.candidates
    var candidateCount = 0
    
    val base = ctx.nextBackscanBase()
    
    // Fast-path for singleton datasets
    if (db.isSingleton) {
      val singletonSeqs = db.singletonSeqs
      
      // Process first SID
      {
        val startIdx = positions(1)
        val currentIdx = positions(2)
        val seq = singletonSeqs(positions(0))
        val stamp1 = base + 1
        
        var isIdx = startIdx
        while (isIdx < currentIdx && isIdx >= 0 && isIdx < seq.length) {
          val item = seq(isIdx)
          if (seenStamp(item) != stamp1) {
            // Optimization: Only consider items with enough global support
            if (db.itemSupport(item) >= this.support) {
              seenStamp(item) = stamp1
              candidates(candidateCount) = item
              candidateCount += 1
            }
          }
          isIdx += 1
        }
      }
      
      if (candidateCount == 0) return false
      
      // Intersect with remaining SIDs
      var idx = STRIDE
      var sidCount = 1
      while (idx < numSids * STRIDE) {
        val startIdx = positions(idx + 1)
        val currentIdx = positions(idx + 2)
        val seq = singletonSeqs(positions(idx))
        
        val currentStamp = base + sidCount + 1
        val prevStamp = currentStamp - 1
        
        var isIdx = startIdx
        while (isIdx < currentIdx && isIdx >= 0 && isIdx < seq.length) {
          val item = seq(isIdx)
          if (seenStamp(item) == prevStamp) {
            seenStamp(item) = currentStamp
          }
          isIdx += 1
        }
        
        // Compact candidates
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
      
      return true
    }
    
    // General path: multi-item itemsets
    // Process first SID
    {
      val startIdx = positions(1)
      val currentIdx = positions(2)
      val seq = db.getSequence(positions(0))
      val stamp1 = base + 1
      
      var isIdx = startIdx
      while (isIdx < currentIdx && isIdx >= 0 && isIdx < seq.length) {
        val itemset = seq(isIdx)
        var j = 0
        while (j < itemset.length) {
          val item = itemset(j)
          if (seenStamp(item) != stamp1) {
            // Optimization: Only consider items with enough global support
            if (db.itemSupport(item) >= this.support) {
              seenStamp(item) = stamp1
              candidates(candidateCount) = item
              candidateCount += 1
            }
          }
          j += 1
        }
        isIdx += 1
      }
    }
    
    if (candidateCount == 0) return false
    
    // Intersect with remaining SIDs
    var idx = STRIDE
    var sidCount = 1
    while (idx < numSids * STRIDE) {
      val startIdx = positions(idx + 1)
      val currentIdx = positions(idx + 2)
      val seq = db.getSequence(positions(idx))
      
      val currentStamp = base + sidCount + 1
      val prevStamp = currentStamp - 1
      
      var isIdx = startIdx
      while (isIdx < currentIdx && isIdx >= 0 && isIdx < seq.length) {
        val itemset = seq(isIdx)
        var j = 0
        while (j < itemset.length) {
          val item = itemset(j)
          if (seenStamp(item) == prevStamp) {
            seenStamp(item) = currentStamp
          }
          j += 1
        }
        isIdx += 1
      }
      
      // Compact candidates
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
   * Check for backward-I witness in the itemset preceding currentIdx (startIdx - 1)
   */
  /**
   * Check for backward-I witness in the itemset preceding currentIdx (startIdx - 1).
   * @param internalItemset The previous element P_{k-1}. MUST BE SORTED.
   */
  private def hasLocalWitnessInternal(ctx: MinerContext, internalItemset: Array[Int]): Boolean = {
    val seenStamp = ctx.seenStamp
    val candidates = ctx.candidates
    var candidateCount = 0
    
    val base = ctx.nextBackscanBase()
    
    // Process first SID
    {
      val startIdx = positions(1)
      val seq = db.getSequence(positions(0))
      val stamp1 = base + 1
      
      val prevMatchIdx = startIdx - 1
      if (prevMatchIdx >= 0 && prevMatchIdx < seq.length) {
        val currentSet = seq(prevMatchIdx)
        var j = 0
        while (j < currentSet.length) {
          val item = currentSet(j)
          if (java.util.Arrays.binarySearch(internalItemset, item) < 0 && seenStamp(item) != stamp1) {
            // Optimization: Only consider items with enough global support
            if (db.itemSupport(item) >= this.support) {
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
    
    // Intersect with remaining SIDs
    var idx = STRIDE
    var sidCount = 1
    while (idx < numSids * STRIDE) {
      val startIdx = positions(idx + 1)
      val seq = db.getSequence(positions(idx))
      
      val currentStamp = base + sidCount + 1
      val prevStamp = currentStamp - 1
      
      val prevMatchIdx = startIdx - 1
      if (prevMatchIdx >= 0 && prevMatchIdx < seq.length) {
        val currentSet = seq(prevMatchIdx)
        var j = 0
        while (j < currentSet.length) {
          val item = currentSet(j)
          if (java.util.Arrays.binarySearch(internalItemset, item) < 0 && seenStamp(item) == prevStamp) {
            seenStamp(item) = currentStamp
          }
          j += 1
        }
      }
      
      // Compact candidates
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
   * Check for local witness: item < max(P_k) AND item NOT in P_k.
   * @param tailItemset The last element P_k. MUST BE SORTED.
   */
  private def hasLocalWitness(ctx: MinerContext, tailItemset: Array[Int], maxTailItem: Int): Boolean = {
    val seenStamp = ctx.seenStamp
    val candidates = ctx.candidates
    var candidateCount = 0
    
    val base = ctx.nextBackscanBase()
    
    // Process first SID
    {
      val currentIdx = positions(2)
      val seq = db.getSequence(positions(0))
      val stamp1 = base + 1
      
      if (currentIdx >= 0 && currentIdx < seq.length) {
        val currentSet = seq(currentIdx)
        var j = 0
        while (j < currentSet.length) {
          val item = currentSet(j)
          // Strong Generalized Logic: item < maxTailItem AND item not in tailItemset
          if (item < maxTailItem && seenStamp(item) != stamp1) {
             // Check strict non-membership (item NOT in tailItemset)
             if (tailItemset == null || java.util.Arrays.binarySearch(tailItemset, item) < 0) {
                 // Optimization: Only consider items with enough global support
                 if (db.itemSupport(item) >= this.support) {
                     seenStamp(item) = stamp1
                     candidates(candidateCount) = item
                     candidateCount += 1
                 }
             }
          }
          j += 1
        }
      }
    }
    
    if (candidateCount == 0) return false
    
    // Intersect with remaining SIDs
    var idx = STRIDE
    var sidCount = 1
    while (idx < numSids * STRIDE) {
      val currentIdx = positions(idx + 2)
      val seq = db.getSequence(positions(idx))
      
      val currentStamp = base + sidCount + 1
      val prevStamp = currentStamp - 1
      
      if (currentIdx >= 0 && currentIdx < seq.length) {
        val currentSet = seq(currentIdx)
        var j = 0
        while (j < currentSet.length) {
          val item = currentSet(j)
          if (item < maxTailItem && seenStamp(item) == prevStamp) {
            seenStamp(item) = currentStamp
          }
          j += 1
        }
      }
      
      // Compact candidates
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
  def enumerateExtensions(
      minsup: Int,
      ctx: MinerContext,
      tailItemset: Array[Int]
  ): (Int, Array[Int], Int, Array[Int], Boolean) = {
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
    
    // Check if we can use the optimized singleton path
    val isSingleton = db.isSingleton
    
    if (isSingleton) {
      // FAST PATH: Singleton datasets (like Kosarak)
      // Use singletonSeqs (Array[Int]) for better cache locality - no pointer chases
      val singletonSeqs = db.singletonSeqs
      
      // Two-Pass Enumeration Strategy:
      // Pass 1: Count support for all items (very fast, no allocations/list builds)
      // Pass 2: Build position lists ONLY for items with support >= minsup
      
      // --- Pass 1: Counting ---
      var idx = 0
      while (idx < numSids * STRIDE) {
        val sid = positions(idx)
        val currentIdx = positions(idx + 2)
        
        val seq = singletonSeqs(sid)
        val stamp = sidBase | sid
        
        var isIdx = currentIdx + 1
        while (isIdx < seq.length) {
          val item = seq(isIdx)
          if (sExtSeen(item) != stamp) {
            sExtSeen(item) = stamp
            if (sExtSupport(item) == 0) {
              sTouched(sTouchedCount) = item
              sTouchedCount += 1
              // Initialize list (allocation check) but don't fill yet
              if (ctx.sLists(item) == null) {
                  ctx.sLists(item) = new ctx.IntList()
              } else {
                  ctx.sLists(item).clear()
              }
            }
            sExtSupport(item) += 1
          }
          isIdx += 1
        }
        idx += STRIDE
      }
      
      // --- Pass 2: Materialization (Filtered) ---
      val sidBase2 = ctx.nextEnumSidBase()
      idx = 0
      while (idx < numSids * STRIDE) {
        val sid = positions(idx)
        val currentIdx = positions(idx + 2)
        
        val seq = singletonSeqs(sid)
        val stamp = sidBase2 | sid
        
        var isIdx = currentIdx + 1
        while (isIdx < seq.length) {
          val item = seq(isIdx)
          // Optimization: Check global frequency filter first
          if (sExtSupport(item) >= minsup) {
            if (sExtSeen(item) != stamp) {
              sExtSeen(item) = stamp
              
              // Add to reusable list (only for frequent items)
              val lst = ctx.sLists(item)
              lst.add(sid)
              lst.add(currentIdx + 1)
              lst.add(isIdx)
              lst.add(item)
            }
          }
          isIdx += 1
        }
        idx += STRIDE
      }
    } else {
      // GENERAL PATH: Multi-item itemset datasets
      val requireFullTailSubsetCheck = tailItemset != null && tailItemset.length > 1

        
      
      // Two-Pass Enumeration Strategy: General Path
      // Pass 1: Count support (alloc-free, but repeats isSubset checks)
      var idx = 0
      while (idx < numSids * STRIDE) {
        val sid = positions(idx)
        val startIdx = positions(idx + 1)
        val currentIdx = positions(idx + 2)
        val lastItem = positions(idx + 3)
        
        val seq = db.getSequence(sid).itemsets
        val stamp = sidBase | sid
        
        // I-extension (Pass 1)
        if (tailItemset != null && currentIdx >= 0 && currentIdx < seq.length) {
          var pos = currentIdx
          while (pos < seq.length) {
            val ev = seq(pos)
            if (ev.length > 0) {
              val evLast = ev(ev.length - 1)
              if (evLast > lastItem && (!requireFullTailSubsetCheck || ev.length >= tailItemset.length)) {
                val idxLast = java.util.Arrays.binarySearch(ev, lastItem)
                if (idxLast >= 0 && (!requireFullTailSubsetCheck || isSubset(tailItemset, ev))) {
                  // Valid event: count candidates
                  var j = idxLast + 1
                  while (j < ev.length && ev(j) == lastItem) j += 1
                  while (j < ev.length) {
                    val item = ev(j)
                    if (iExtSeen(item) != stamp) {
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
                    }
                    j += 1
                  }
                }
              }
            }
            pos += 1
          }
        }
        
        // S-extension (Pass 1)
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
            }
            j += 1
          }
          isIdx += 1
        }
        idx += STRIDE
      }
      
      // Pass 2: Materialization (Filtered)
      val sidBase2 = ctx.nextEnumSidBase()
      idx = 0
      while (idx < numSids * STRIDE) {
        val sid = positions(idx)
        val startIdx = positions(idx + 1)
        val currentIdx = positions(idx + 2)
        val lastItem = positions(idx + 3)
        
        val seq = db.getSequence(sid).itemsets
        val stamp = sidBase2 | sid
        
        // I-extension (Pass 2)
        if (tailItemset != null && currentIdx >= 0 && currentIdx < seq.length) {
          var pos = currentIdx
          while (pos < seq.length) {
            val ev = seq(pos)
            if (ev.length > 0) {
              val evLast = ev(ev.length - 1)
              if (evLast > lastItem && (!requireFullTailSubsetCheck || ev.length >= tailItemset.length)) {
                val idxLast = java.util.Arrays.binarySearch(ev, lastItem)
                // Must re-verify subset (unless we cached it, which is too expensive memory-wise)
                if (idxLast >= 0 && (!requireFullTailSubsetCheck || isSubset(tailItemset, ev))) {
                  // Candidates
                  var j = idxLast + 1
                  while (j < ev.length && ev(j) == lastItem) j += 1
                  while (j < ev.length) {
                    val item = ev(j)
                    // Optimization: Global frequency filter
                    if (iExtSupport(item) >= minsup) {
                        if (iExtSeen(item) != stamp) {
                          iExtSeen(item) = stamp
                          val lst = ctx.iLists(item)
                          lst.add(sid)
                          lst.add(startIdx)
                          lst.add(pos)
                          lst.add(item)
                        }
                    }
                    j += 1
                  }
                }
              }
            }
            pos += 1
          }
        }
        
        // S-extension (Pass 2)
        var isIdx = currentIdx + 1
        while (isIdx < seq.length) {
          val itemset = seq(isIdx)
          var j = 0
          while (j < itemset.length) {
            val item = itemset(j)
            if (sExtSupport(item) >= minsup) {
                if (sExtSeen(item) != stamp) {
                  sExtSeen(item) = stamp
                  val lst = ctx.sLists(item)
                  lst.add(sid)
                  lst.add(currentIdx + 1)
                  lst.add(isIdx)
                  lst.add(item)
                }
            }
            j += 1
          }
          isIdx += 1
        }
        idx += STRIDE
      }
    }

    // Track whether ANY forward extension has the same support as the parent.
    // This is used for forward-closed gating (cheap): if true, the current node is not closed.
    var hasSameSuppForward = false
    var t = 0
    while (t < sTouchedCount && !hasSameSuppForward) {
      val item = sTouched(t)
      if (sExtSupport(item) == parentSupp) hasSameSuppForward = true
      t += 1
    }
    if (!hasSameSuppForward && !isSingleton) {
      t = 0
      while (t < iTouchedCount && !hasSameSuppForward) {
        val item = iTouched(t)
        if (iExtSupport(item) == parentSupp) hasSameSuppForward = true
        t += 1
      }
    }

    // Return raw counts/arrays to avoid allocating wrapper objects.
    (sTouchedCount, sTouched, iTouchedCount, iTouched, hasSameSuppForward)
  }

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

object ItemsetPointerStore {
  def createRoot(db: ItemsetSequenceDatabase): ItemsetPointerStore = {
    val positions = new Array[Int](db.numSequences * 4)
    var idx = 0
    var sid = 0
    while (sid < db.numSequences) {
      positions(idx) = sid
      positions(idx + 1) = 0
      positions(idx + 2) = -1
      positions(idx + 3) = 0
      idx += 4
      sid += 1
    }
    new ItemsetPointerStore(positions, db.numSequences, db)
  }
}
