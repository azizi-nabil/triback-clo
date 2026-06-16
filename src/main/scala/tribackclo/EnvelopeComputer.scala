package tribackclo

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
