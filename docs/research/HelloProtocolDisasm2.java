import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Listing;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.address.Address;
import ghidra.program.model.mem.Memory;
import ghidra.program.disassemble.Disassembler;
import ghidra.util.task.ConsoleTaskMonitor;
import java.io.FileWriter;
import java.io.BufferedWriter;
import java.util.ArrayList;
import java.util.List;

public class HelloProtocolDisasm2 extends GhidraScript {
    
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
        Disassembler dis = Disassembler.getDisassembler(currentProgram);
        
        results.add("=== HELLO DISASSEMBLE AT REF ADDRESSES (v2) ===");
        
        for (long refAddr : REF_ADDRESSES) {
            results.add(String.format("\n=== Address 0x%X ===", refAddr));
            
            Address addr = toAddr(refAddr);
            
            // Disassemble at this address
            try {
                dis.disassemble(addr, new ConsoleTaskMonitor());
                results.add("  Disassembly triggered");
            } catch (Exception e) {
                results.add("  Disassembly error: " + e.getMessage());
            }
            
            // Now read instructions
            Address current = addr;
            int count = 0;
            // Go back a bit to find function start
            long start = refAddr - 0x100;
            current = toAddr(start);
            while (current.getOffset() < refAddr + 0x100 && count < 100) {
                Instruction instr = listing.getInstructionAt(current);
                if (instr != null) {
                    String marker = "";
                    String opStr = instr.toString().toLowerCase();
                    if (opStr.contains("10b4cc") || opStr.contains("10b4d8") || opStr.contains("10b396") || opStr.contains("10aca7")) {
                        marker = " *** SELECTOR REF ***";
                    }
                    if (opStr.contains("bl ") || opStr.contains("blr ")) {
                        marker += " [CALL]";
                    }
                    if (opStr.contains("adrp")) {
                        marker += " [ADRP]";
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
        String outputPath = "C:/Users/ribhu/kilo-test/whoop-mg-client/docs/research/hello_5802_disassemble2.txt";
        try (BufferedWriter writer = new BufferedWriter(new FileWriter(outputPath))) {
            for (String s : results) writer.write(s + "\n");
            println("Results written to " + outputPath);
        } catch (Exception e) {
            println("Error writing results: " + e.getMessage());
        }
    }
}