package ca.pfv.spmf.algorithms.sequentialpatterns.tribackclo;

import java.io.IOException;

/**
 * Main test class for TriBack-Clo algorithm.
 * Usage: java MainTestTriBackClo <input_file> <output_file> <minsup>
 *        java MainTestTriBackClo <input_file> <output_file> <minsup%>
 * 
 * Examples:
 *   java MainTestTriBackClo kosarak.txt /dev/null 5%
 *   java MainTestTriBackClo kosarak.txt output.txt 1000
 */
public class MainTestTriBackClo {
    
    public static void main(String[] args) throws IOException {
        if (args.length < 3) {
            System.out.println("Usage: MainTestTriBackClo <input_file> <output_file> <minsup>");
            System.out.println("  minsup can be an integer (absolute) or percentage (e.g., 5%)");
            System.out.println("  use 'null' or '/dev/null' as output_file for count-only mode");
            return;
        }
        
        String inputFile = args[0];
        String outputFile = args[1];
        String minsupStr = args[2];
        
        // Parse minsup (either absolute or percentage)
        int minsup;
        if (minsupStr.endsWith("%")) {
            // Need to count sequences first
            ca.pfv.spmf.algorithms.sequentialpatterns.prefixspan.SequenceDatabase tempDb = 
                new ca.pfv.spmf.algorithms.sequentialpatterns.prefixspan.SequenceDatabase();
            tempDb.loadFile(inputFile);
            int seqCount = tempDb.size();
            double percentage = Double.parseDouble(minsupStr.replace("%", "")) / 100.0;
            minsup = (int) Math.ceil(seqCount * percentage);
            System.out.println("Database size: " + seqCount + " sequences");
            System.out.println("Minsup: " + minsupStr + " = " + minsup + " sequences");
        } else {
            minsup = Integer.parseInt(minsupStr);
        }
        
        // Run algorithm
        AlgoTriBackClo algo = new AlgoTriBackClo();
        for (int i = 3; i < args.length; i++) {
            if (args[i].equals("--no-prune")) {
                algo.enableSubtreePruning = false;
            } else if (args[i].equals("--no-gate")) {
                algo.enableNodeGating = false;
            } else if (args[i].equals("--eager-verify")) {
                algo.enableEagerVerification = true;
            } else {
                System.out.println("Unknown option: " + args[i]);
            }
        }
        algo.runAlgorithm(inputFile, outputFile, minsup);
        algo.printStatistics();
    }
}
