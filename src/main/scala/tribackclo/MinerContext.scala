package tribackclo

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
