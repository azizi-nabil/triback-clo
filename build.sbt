name := "p-clofast"

version := "6.0"

// Spark 3.5.x works best with Scala 2.12 or 2.13.
scalaVersion := "2.13.14"

val sparkVersion = "3.5.1"

lazy val root = (project in file("."))
  .settings(
    name := "TriBack-Clo",
    Compile / mainClass := Some("tribackclo.TriBackClo_Main"),
    libraryDependencies ++= Seq(
      "org.apache.spark" %% "spark-core" % sparkVersion % "provided",
      "org.apache.spark" %% "spark-sql" % sparkVersion % "provided",
      "org.apache.spark" %% "spark-mllib" % sparkVersion % "provided",
      "it.unimi.dsi" % "fastutil" % "8.5.12",
      "org.roaringbitmap" % "RoaringBitmap" % "1.0.6"
    ),
    // Assembly settings for thin JAR
    assembly / mainClass := Some("tribackclo.TriBackClo_Main"),
    assembly / assemblyJarName := "triback-clo.jar",
    assembly / assemblyMergeStrategy := {
      case PathList("module-info.class") => MergeStrategy.discard
      case PathList("META-INF", "MANIFEST.MF") => MergeStrategy.discard
      case PathList("META-INF", xs @ _*) => MergeStrategy.discard
      case x if x.contains("commons-logging") => MergeStrategy.first
      case x => MergeStrategy.first
    }
  )

unmanagedBase := baseDirectory.value / "lib"

// Critical: Fork the JVM so our memory options apply
run / fork := true

// --- SMART MEMORY DETECTION (V5.37) ---
// 1. Detect Total System RAM
val osMem: Long = {
  val bean = java.lang.management.ManagementFactory.getOperatingSystemMXBean
  bean match {
    case unix: com.sun.management.OperatingSystemMXBean => unix.getTotalMemorySize
    case _ => 16L * 1024 * 1024 * 1024 // Fallback assumption
  }
}

// 2. Define Memory Tiers
// Tier A: Enterprise Server (Rocky Linux) - > 96GB RAM -> Use 100GB Heap
// Tier B: Workstation (Ubuntu Z8)       - > 32GB RAM -> Use 48GB Heap
// Tier C: Laptop (HP Omen/Standard)     - < 32GB RAM -> Use 12GB Heap
val heapSize = if (osMem > 96L * 1024 * 1024 * 1024) {
  "100g"
} else if (osMem > 32L * 1024 * 1024 * 1024) {
  "48g"
} else {
  "12g"
}

// 3. Log the Decision for Verification (using sbt's built-in logging)
val machineType = heapSize match {
  case "100g" => "Enterprise Server (Rocky Linux/Z8)"
  case "48g"  => "High-End Workstation"
  case _      => "Laptop / Standard PC"
}

// Use sbt's logging mechanism
val _ = {
  System.out.println(s"[BUILD] Hardware Detected: $machineType")
  System.out.println(s"[BUILD] Total System RAM : ${osMem / (1024*1024*1024)} GB")
  System.out.println(s"[BUILD] Setting JVM Heap : $heapSize")
}

run / javaOptions ++= Seq(
  s"-Xmx$heapSize",
  s"-Xms$heapSize",
  
  // Java 17+ Exports (Required for Spark 3.5+)
  "--add-opens=java.base/java.lang=ALL-UNNAMED",
  "--add-opens=java.base/java.lang.invoke=ALL-UNNAMED",
  "--add-opens=java.base/java.lang.reflect=ALL-UNNAMED",
  "--add-opens=java.base/java.io=ALL-UNNAMED",
  "--add-opens=java.base/java.net=ALL-UNNAMED",
  "--add-opens=java.base/java.nio=ALL-UNNAMED",
  "--add-opens=java.base/java.util=ALL-UNNAMED",
  "--add-opens=java.base/java.util.concurrent=ALL-UNNAMED",
  "--add-opens=java.base/java.util.concurrent.atomic=ALL-UNNAMED",
  "--add-opens=java.base/sun.nio.ch=ALL-UNNAMED",
  "--add-opens=java.base/sun.nio.cs=ALL-UNNAMED",
  "--add-opens=java.base/sun.security.action=ALL-UNNAMED",
  "--add-opens=java.base/sun.util.calendar=ALL-UNNAMED",
  "--add-opens=java.security.jgss/sun.security.krb5=ALL-UNNAMED"
)
