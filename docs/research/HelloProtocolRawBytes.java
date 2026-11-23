import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Listing;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.address.Address;
import ghidra.program.model.mem.Memory;
import java.io.FileWriter;
import java.io.BufferedWriter;
import java.util.ArrayList;
import java.util.List;

public class HelloProtocolRawBytes extends GhidraScript {
    
    private List<String> results = new ArrayList<>();
    
    private static final long[] REF_ADDRESSES = {
        0x109109BA0L, 0x1091129C4L, 0x10910BE1CL,
        0x109109BACL, 0x1091129DCL,
        0x1091099C0L, 0x1091129E8L,
        0x1091229D4L, 0x10910D3E4L, 0x109111D58L, 0x109122A24L,
        0x1091229E0L, 0x109111D64L, 0x109122A30L,
        0x109124DA0L, 0x1090E4914L, 0x109124E30L, 0x1090E03CCL, 0x109124EC0L,
    };
    
    @Override
    protected void run() throws Exception {
        Listing listing = currentProgram.getListing();
        Memory mem = currentProgram.getMemory();
        
        results.add("=== RAW BYTES AT DATA REF ADDRESSES ===");
        
        for (long addr : REF_ADDRESSES) {
            results.add(String.format("\n=== Address 0x%X ===", addr));
            try {
                Address a = toAddr(addr);
                // Read 32 bytes
                byte[] bytes = new byte[32];
                mem.getBytes(a, bytes);
                StringBuilder hex = new StringBuilder();
                StringBuilder ascii = new StringBuilder();
                for (int i = 0; i < 32; i++) {
                    hex.append(String.format("%02x ", bytes[i] & 0xFF));
                    if (bytes[i] >= 32 && bytes[i] < 127) {
                        ascii.append((char)bytes[i]);
                    } else {
                        ascii.append(".");
                    }
                }
                results.add("  Hex: " + hex.toString());
                results.add("  Ascii: " + ascii.toString());
                
                // Try to get instruction
                Instruction instr = listing.getInstructionAt(a);
                if (instr != null) {
                    results.add("  Instruction: " + instr);
                } else {
                    results.add("  No instruction defined");
                }
            } catch (Exception e) {
                results.add("  Error: " + e.getMessage());
            }
        }
        
        outputResults();
    }
    
    private void outputResults() {
        String outputPath = "C:/Users/ribhu/kilo-test/whoop-mg-client/docs/research/hello_5802_raw_bytes.txt";
        try (BufferedWriter writer = new BufferedWriter(new FileWriter(outputPath))) {
            for (String s : results) writer.write(s + "\n");
            println("Results written to " + outputPath);
        } catch (Exception e) {
            println("Error writing results: " + e.getMessage());
        }
    }
}