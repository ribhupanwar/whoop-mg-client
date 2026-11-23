import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Listing;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.address.Address;
import ghidra.program.model.mem.Memory;
import java.io.FileWriter;
import java.io.BufferedWriter;
import java.util.ArrayList;
import java.util.List;

public class HelloProtocolDisasmRefs extends GhidraScript {
    
    private List<String> results = new ArrayList<>();
    
    // Data reference addresses to HELLO selector entries
    private static final long[] REF_ADDRESSES = {
        // processCommandDidGetHelloPacket: @ 0x10b4cc260
        0x1091229D4L, 0x10910D3E4L, 0x109111D58L, 0x109122A24L,
        // processCommandDidGetHelloInfoWithSerial:signature:boardId: @ 0x10b4cc258
        0x1091229E0L, 0x109111D64L, 0x109122A30L,
        // sendGetHelloPacketWithCompletionHandler: @ 0x10b4d8b08
        0x109124DA0L, 0x1090E4914L, 0x109124E30L, 0x1090E03CCL, 0x109124EC0L,
    };
    
    @Override
    protected void run() throws Exception {
        Listing listing = currentProgram.getListing();
        Memory mem = currentProgram.getMemory();
        
        results.add("=== HELLO SELECTOR REFERENCE DISASSEMBLY ===");
        
        for (long refAddr : REF_ADDRESSES) {
            results.add(String.format("\n=== Reference at 0x%X ===", refAddr));
            
            // Try to find function boundaries by scanning backward for prologue
            long funcStart = findFunctionStart(mem, refAddr);
            results.add(String.format("  Estimated function start: 0x%X", funcStart));
            
            // Disassemble from function start to refAddr + 0x100
            disassembleRange(listing, funcStart, refAddr + 0x100);
        }
        
        outputResults();
    }
    
    private long findFunctionStart(Memory mem, long addr) {
        // Scan backward for stp x29,x30 or similar prologue
        long current = addr;
        for (int i = 0; i < 200; i++) {
            current -= 4;
            if (current < 0x100000000L) break;
            
            try {
                // Check for common ARM64 function prologue patterns
                int instr = mem.getInt(toAddr(current));
                // stp x29, x30, [sp, #-...] or stp x20, x19, [sp, #-...]
                // These typically start with 0xa9 or 0xa8 in the high byte
                if ((instr & 0xFF000000) == 0xA9000000 || (instr & 0xFF000000) == 0xA8000000) {
                    // Check if next instruction is add x29, sp, #...
                    int nextInstr = mem.getInt(toAddr(current + 4));
                    if ((nextInstr & 0xFFC003FF) == 0x910003FD) {
                        return current;
                    }
                }
            } catch (Exception e) {
                // Ignore
            }
        }
        return addr - 0x200; // Fallback
    }
    
    private void disassembleRange(Listing listing, long startAddr, long endAddr) {
        Address addr = toAddr(startAddr);
        int count = 0;
        while (addr.getOffset() < endAddr && count < 200) {
            Instruction instr = listing.getInstructionAt(addr);
            if (instr != null) {
                String marker = "";
                String mnemonic = instr.getMnemonicString().toUpperCase();
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
                addr = instr.getAddress().add(instr.getLength());
            } else {
                addr = addr.add(4);
            }
            count++;
        }
    }
    
    private void outputResults() {
        String outputPath = "C:/Users/ribhu/kilo-test/whoop-mg-client/docs/research/hello_5802_disasm_refs.txt";
        try (BufferedWriter writer = new BufferedWriter(new FileWriter(outputPath))) {
            for (String s : results) writer.write(s + "\n");
            println("Results written to " + outputPath);
        } catch (Exception e) {
            println("Error writing results: " + e.getMessage());
        }
    }
}