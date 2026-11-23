import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Listing;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.address.Address;
import ghidra.program.model.mem.Memory;
import ghidra.app.plugin.core.analysis.AutoAnalysisManager;
import ghidra.app.util.headless.HeadlessScript;
import ghidra.program.disassemble.Disassembler;
import ghidra.util.task.ConsoleTaskMonitor;
import java.io.FileWriter;
import java.io.BufferedWriter;
import java.util.ArrayList;
import java.util.List;

public class HelloProtocolDisassemble extends GhidraScript {
    
    private List<String> results = new ArrayList<>();
    
    private static final long[] REF_ADDRESSES = {
        0x1091229D4L, 0x10910D3E4L, 0x109111D58L, 0x109122A24L,
        0x1091229E0L, 0x109111D64L, 0x109122A30L,
        0x109124DA0L, 0x1090E4914L, 0x109124E30L, 0x1090E03CCL, 0x109124EC0L,
    };
    
    @Override
    protected void run() throws Exception {
        Listing listing = currentProgram.getListing();
        Memory mem = currentProgram.getMemory();
        
        results.add("=== HELLO DISASSEMBLE AT REF ADDRESSES ===");
        
        for (long refAddr : REF_ADDRESSES) {
            results.add(String.format("\n=== Address 0x%X ===", refAddr));
            
            // Try to disassemble at this address
            Address addr = toAddr(refAddr);
            try {
                // Check if already disassembled
                Instruction instr = listing.getInstructionAt(addr);
                if (instr == null) {
                    // Try to create instruction
                    instr = listing.createInstruction(addr, null);
                    if (instr != null) {
                        results.add(String.format("  Created instruction: %s", instr));
                    } else {
                        results.add("  Could not create instruction at this address");
                        // Try reading raw bytes
                        byte[] bytes = new byte[4];
                        mem.getBytes(addr, bytes);
                        results.add(String.format("  Raw bytes: %02x %02x %02x %02x", bytes[0]&0xFF, bytes[1]&0xFF, bytes[2]&0xFF, bytes[3]&0xFF));
                    }
                } else {
                    results.add(String.format("  Existing instruction: %s", instr));
                }
            } catch (Exception e) {
                results.add("  Error: " + e.getMessage());
                try {
                    byte[] bytes = new byte[4];
                    mem.getBytes(addr, bytes);
                    results.add(String.format("  Raw bytes: %02x %02x %02x %02x", bytes[0]&0xFF, bytes[1]&0xFF, bytes[2]&0xFF, bytes[3]&0xFF));
                } catch (Exception e2) {
                    results.add("  Could not read bytes: " + e2.getMessage());
                }
            }
            
            // Disassemble a range around this address
            results.add("  --- Disassembly ---");
            long start = refAddr - 0x80;
            long end = refAddr + 0x80;
            Address current = toAddr(start);
            int count = 0;
            while (current.getOffset() < end && count < 100) {
                Instruction instr = listing.getInstructionAt(current);
                if (instr == null) {
                    try {
                        instr = listing.createInstruction(current, null);
                    } catch (Exception e) {
                        // skip
                    }
                }
                if (instr != null) {
                    String marker = "";
                    String opStr = instr.toString().toLowerCase();
                    if (opStr.contains("10b4cc") || opStr.contains("10b4d8") || opStr.contains("10b396") || opStr.contains("10aca7")) {
                        marker = " *** SELECTOR REF ***";
                    }
                    if (opStr.contains("bl ") || opStr.contains("blr ")) {
                        marker += " [CALL]";
                    }
                    results.add(String.format("    %s: %s%s", instr.getAddress(), instr, marker));
                    current = instr.getAddress().add(instr.getLength());
                } else {
                    current = current.add(4);
                }
                count++;
            }
        }
        
        outputResults();
    }
    
    private void outputResults() {
        String outputPath = "C:/Users/ribhu/kilo-test/whoop-mg-client/docs/research/hello_5802_disassemble.txt";
        try (BufferedWriter writer = new BufferedWriter(new FileWriter(outputPath))) {
            for (String s : results) writer.write(s + "\n");
            println("Results written to " + outputPath);
        } catch (Exception e) {
            println("Error writing results: " + e.getMessage());
        }
    }
}