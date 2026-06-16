package tribackclo

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
 * 
 * @param sequences The array of ItemsetSequence objects
 * @param precomputedSingletonSeqs Optional pre-computed singleton sequences for fast access
 */
class ItemsetSequenceDatabase(
    val sequences: Array[ItemsetSequence],
    precomputedSingletonSeqs: Option[Array[Array[Int]]] = None
) {
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
    precomputedSingletonSeqs match {
      case Some(_) => 1 // Pre-computed means it's singleton
      case None =>
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
  }
  
  /** Is this a singleton-itemset database (Kosarak-style)? */
  lazy val isSingleton: Boolean = precomputedSingletonSeqs.isDefined || maxItemsetSize == 1
  
  /** Flattened view for singleton datasets: Array[Array[Int]] where inner is just items */
  lazy val singletonSeqs: Array[Array[Int]] = {
    precomputedSingletonSeqs match {
      case Some(seqs) => seqs
      case None =>
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
  }
  
  /**
   * Position index for binary-search enumeration on long sequences.
   * Format: positionIndex(item)(sid) = sorted array of itemsetIdx where item occurs
   * Lazy-built, only for singleton datasets.
   */
  lazy val positionIndex: PositionIndex = {
    if (!isSingleton) null
    else buildPositionIndex()
  }
  
  private def buildPositionIndex(): PositionIndex = {
    import scala.collection.mutable
    
    // Map: item -> (sid -> ArrayBuffer[idx])
    val builders = mutable.Map[Int, mutable.Map[Int, mutable.ArrayBuilder.ofInt]]()
    
    val seqs = singletonSeqs
    var sid = 0
    while (sid < numSequences) {
      val seq = seqs(sid)
      var idx = 0
      while (idx < seq.length) {
        val item = seq(idx)
        val itemMap = builders.getOrElseUpdate(item, mutable.Map[Int, mutable.ArrayBuilder.ofInt]())
        val sidBuilder = itemMap.getOrElseUpdate(sid, new mutable.ArrayBuilder.ofInt())
        sidBuilder += idx
        idx += 1
      }
      sid += 1
    }
    
    // Finalize: convert to arrays
    val itemPositions = new Array[Array[Array[Int]]](maxItem + 1)
    for ((item, sidMap) <- builders) {
      val sidPositions = new Array[Array[Int]](numSequences)
      for ((sid, builder) <- sidMap) {
        sidPositions(sid) = builder.result()
      }
      itemPositions(item) = sidPositions
    }
    
    new PositionIndex(itemPositions, numSequences)
  }
  
  /** 
   * Global support (frequency) of each item across the database.
   * Used for Witness Frequency Pre-filtering optimization.
   */
  lazy val itemSupport: Array[Int] = {
    val counts = new Array[Int](maxItem + 1)
    val seen = new Array[Int](maxItem + 1) // Use Int as timestamp instead of clearing boolean array
    var sid = 0
    
    // Optimized counting for singleton datasets
    if (isSingleton) {
      val seqs = singletonSeqs
      while (sid < numSequences) {
        val seq = seqs(sid)
        val stamp = sid + 1
        var i = 0
        while (i < seq.length) {
          val item = seq(i)
          if (seen(item) != stamp) {
            seen(item) = stamp
            counts(item) += 1
          }
          i += 1
        }
        sid += 1
      }
    } else {
      // General itemsets
      while (sid < numSequences) {
        val seqItemsets = sequences(sid).itemsets // Access raw array directly
        val stamp = sid + 1
        var i = 0
        while (i < seqItemsets.length) {
          val itemset = seqItemsets(i)
          var j = 0
          while (j < itemset.length) {
            val item = itemset(j)
            if (seen(item) != stamp) {
              seen(item) = stamp
              counts(item) += 1
            }
            j += 1
          }
          i += 1
        }
        sid += 1
      }
    }
    counts
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
 * Position index for binary-search based enumeration.
 * itemPositions(item)(sid) = sorted array of indices where item occurs in sequence sid
 */
class PositionIndex(
    private val itemPositions: Array[Array[Array[Int]]],
    private val numSequences: Int
) {
  /**
   * Find the first occurrence of item in sequence sid after position afterIdx.
   * Returns -1 if not found.
   */
  def nextOccurrence(item: Int, sid: Int, afterIdx: Int): Int = {
    if (item >= itemPositions.length || itemPositions(item) == null) return -1
    val sidPositions = itemPositions(item)
    if (sid >= sidPositions.length || sidPositions(sid) == null) return -1
    
    val positions = sidPositions(sid)
    // Binary search for first position > afterIdx
    var lo = 0
    var hi = positions.length
    while (lo < hi) {
      val mid = (lo + hi) >>> 1
      if (positions(mid) <= afterIdx) lo = mid + 1
      else hi = mid
    }
    if (lo < positions.length) positions(lo) else -1
  }
  
  def hasItem(item: Int): Boolean = item < itemPositions.length && itemPositions(item) != null
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
   * 
   * V2: Uses two-pass loading for singleton optimization:
   * 1. First pass: Detect if all itemsets are singletons (very fast line scan)
   * 2. Second pass: Parse with appropriate storage format
   * 
   * For singleton datasets, this avoids allocating millions of 1-element arrays.
   */
  def loadSequences(filename: String): ItemsetSequenceDatabase = {
    // Quick first pass: check if this is a singleton dataset
    // For singleton datasets like Kosarak, each itemset has exactly 1 item
    // Detection: count items between -1 separators; if always 1, it's singleton
    val isSingleton = detectSingleton(filename)
    
    if (isSingleton) {
      loadSingletonOptimized(filename)
    } else {
      loadGeneral(filename)
    }
  }
  
  /**
   * Detect if a file contains only singleton itemsets.
   * Quick scan: look for patterns like "item -1" with no multi-item itemsets.
   */
  private def detectSingleton(filename: String): Boolean = {
    val reader = new BufferedReader(new FileReader(filename))
    var isSingleton = true
    var lineCount = 0
    val maxLinesToCheck = 1000 // Sample first 1000 lines
    
    try {
      var line = reader.readLine()
      while (line != null && lineCount < maxLinesToCheck && isSingleton) {
        if (line.nonEmpty && !line.startsWith("#")) {
          // Check if any itemset has more than 1 item
          val tokens = line.trim.split("\\s+")
          var itemsInCurrentSet = 0
          var i = 0
          while (i < tokens.length && isSingleton) {
            val token = tokens(i)
            if (token.nonEmpty) {
              try {
                val item = token.toInt
                if (item == -1 || item == -2) {
                  if (itemsInCurrentSet > 1) isSingleton = false
                  itemsInCurrentSet = 0
                } else if (item >= 0) {
                  itemsInCurrentSet += 1
                  if (itemsInCurrentSet > 1) isSingleton = false
                }
              } catch {
                case _: NumberFormatException =>
              }
            }
            i += 1
          }
          lineCount += 1
        }
        line = reader.readLine()
      }
    } finally {
      reader.close()
    }
    
    isSingleton
  }
  
  /**
   * Optimized loader for singleton datasets.
   * Parses directly into Array[Int] without intermediate Array[Array[Int]].
   */
  private def loadSingletonOptimized(filename: String): ItemsetSequenceDatabase = {
    val sequences = mutable.ArrayBuffer[ItemsetSequence]()
    val singletonSeqs = mutable.ArrayBuffer[Array[Int]]()
    val reader = new BufferedReader(new FileReader(filename))
    
    try {
      var line = reader.readLine()
      while (line != null) {
        if (line.nonEmpty && !line.startsWith("#")) {
          val flatSeq = parseSingletonSequence(line)
          if (flatSeq.nonEmpty) {
            // Create ItemsetSequence with singleton arrays
            val itemsets = new Array[Array[Int]](flatSeq.length)
            var i = 0
            while (i < flatSeq.length) {
              itemsets(i) = Array(flatSeq(i))
              i += 1
            }
            sequences += ItemsetSequence(itemsets)
            singletonSeqs += flatSeq
          }
        }
        line = reader.readLine()
      }
    } finally {
      reader.close()
    }
    
    // Create database with pre-computed singletonSeqs
    new ItemsetSequenceDatabase(sequences.toArray, Some(singletonSeqs.toArray))
  }
  
  /**
   * Parse a singleton sequence line directly to Array[Int].
   * Optimized for SPMF-like performance: simple split, minimal allocations.
   */
  private def parseSingletonSequence(line: String): Array[Int] = {
    // Use simple space split like SPMF (not regex)
    val tokens = line.split(" ")
    
    // Pre-allocate array (most tokens are items, some are -1/-2)
    val tempItems = new Array[Int](tokens.length)
    var count = 0
    var i = 0
    
    while (i < tokens.length) {
      val token = tokens(i)
      if (token.nonEmpty) {
        try {
          val item = java.lang.Integer.parseInt(token)
          if (item >= 0) {
            tempItems(count) = item
            count += 1
          } else if (item == -2) {
            // End of sequence - return truncated array
            val result = new Array[Int](count)
            System.arraycopy(tempItems, 0, result, 0, count)
            return result
          }
          // Skip -1 (itemset separator) as we only keep items
        } catch {
          case _: NumberFormatException => // Skip non-numeric
        }
      }
      i += 1
    }
    
    // Return truncated array if no -2 found
    val result = new Array[Int](count)
    System.arraycopy(tempItems, 0, result, 0, count)
    result
  }
  
  /**
   * General loader for multi-item itemset datasets.
   */
  private def loadGeneral(filename: String): ItemsetSequenceDatabase = {
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
   * Optimized for SPMF-like performance: simple split, minimal allocations.
   */
  def parseSequence(line: String): ItemsetSequence = {
    // Use simple space split like SPMF (not regex)
    val tokens = line.split(" ")
    
    // Pre-allocate with reasonable capacity
    val itemsets = new mutable.ArrayBuffer[Array[Int]](16)
    val currentItemset = new mutable.ArrayBuffer[Int](8)
    
    var i = 0
    while (i < tokens.length) {
      val token = tokens(i)
      if (token.nonEmpty) {
        try {
          val item = java.lang.Integer.parseInt(token)
          if (item == -2) {
            // End of sequence - flush current itemset if non-empty
            if (currentItemset.nonEmpty) {
              itemsets += currentItemset.sorted.toArray
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
