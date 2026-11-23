import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionManager;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.Listing;
import ghidra.program.model.address.Address;
import ghidra.program.model.mem.Memory;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceManager;
import ghidra.util.task.ConsoleTaskMonitor;
import java.io.FileWriter;
import java.io.BufferedWriter;
import java.util.ArrayList;
import java.util.List;

public class HelloProtocolTargetedDisasm extends GhidraScript {
    
    private List<String> results = new ArrayList<>();
    
    // Call sites that load HELLO selector pages
    private static final long[] CALL_SITES = {
        0x10903b618L, 0x10903b74cL, 0x10904b148L, 0x10904aee8L,
        0x10904af18L, 0x1090511c4L, 0x1090745a0L, 0x1090745b8L
    };
    
    // Selector table entry addresses
    private static final long[] SELECTOR_ENTRIES = {
        0x10b4cc260L, 0x10b4cc258L, 0x10b4d8b08L, 0x10b396a00L, 0x10aca74b8L
    };
    
    // Crypto function addresses
    private static final long[] CRYPTO_ADDRS = {0x10908a798L, 0x10908a7b0L};
    
    // Key string addresses (from previous analysis)
    private static final String[] KEY_STRINGS = {
        "helloResponse", "helloResponseTask", "strap_signature", 
        "strapSerial", "boardId", "lastConnectedStrapSerial", 
        "lastConnectedStrapSignature", "setLastConnectedStrapSignature:"
    };
    
    @Override
    protected void run() throws Exception {
        Listing listing = currentProgram.getListing();
        FunctionManager fm = currentProgram.getFunctionManager();
        ReferenceManager rm = currentProgram.getReferenceManager();
        
        println("=== TARGETED HELLO DISASSEMBLY ===");
        
        // 1. Disassemble around each call site and identify containing function
        results.add("=== CALL SITE ANALYSIS ===");
        for (long addr : CALL_SITES) {
            Address a = toAddr(addr);
            Function func = fm.getFunctionContaining(a);
            results.add(String.format("\n--- Call site 0x%X ---", addr));
            if (func != null) {
                results.add(String.format("  Containing function: %s @ %s", func.getName(), func.getEntryPoint()));
                results.add(String.format("  Signature: %s", func.getSignature().getPrototypeString()));
            } else {
                results.add("  No function defined at this address");
            }
            
            // Disassemble 60 instructions before and after
            disassembleRange(listing, addr - 0x100, addr + 0x100);
        }
        
        // 2. Trace data refs to selector entries
        results.add("\n\n=== SELECTOR ENTRY REFERENCES ===");
        for (long entry : SELECTOR_ENTRIES) {
            Address a = toAddr(entry);
            var refs = rm.getReferencesTo(a);
            results.add(String.format("\n--- Selector entry 0x%X ---", entry));
            int count = 0;
            for (var ref : refs) {
                Function func = fm.getFunctionContaining(ref.getFromAddress());
                String funcName = (func != null) ? func.getName() : "NO_FUNC";
                results.add(String.format("  0x%X (%s) type=%s", ref.getFromAddress().getOffset(), funcName, ref.getReferenceType()));
                count++;
                if (count > 20) break;
            }
            if (count == 0) results.add("  No references found");
        }
        
        // 3. Trace crypto function callers
        results.add("\n\n=== CRYPTO FUNCTION CALLERS ===");
        for (long cryptoAddr : CRYPTO_ADDRS) {
            Address a = toAddr(cryptoAddr);
            Function func = fm.getFunctionAt(a);
            results.add(String.format("\n--- Crypto @ 0x%X ---", cryptoAddr));
            if (func != null) results.add(String.format("  Function: %s", func.getName()));
            
            var refs = rm.getReferencesTo(a);
            int count = 0;
            for (var ref : refs) {
                if (ref.getReferenceType().isCall()) {
                    Address fromAddr = ref.getFromAddress();
                    Function caller = fm.getFunctionContaining(fromAddr);
                    String callerName = (caller != null) ? caller.getName() : "UNKNOWN";
                    results.add(String.format("  CALL from 0x%X (%s)", fromAddr.getOffset(), callerName));
                    count++;
                }
            }
            if (count == 0) results.add("  No callers found");
        }
        
        // 4. Find key strings and their references
        results.add("\n\n=== KEY STRING REFERENCES ===");
        Memory mem = currentProgram.getMemory();
        for (String str : KEY_STRINGS) {
            byte[] bytes = str.getBytes();
            byte[] mask = new byte[bytes.length];
            for (int i = 0; i < mask.length; i++) mask[i] = (byte)0xFF;
            
            Address addr = mem.findBytes(currentProgram.getMinAddress(), bytes, mask, false, new ConsoleTaskMonitor());
            if (addr != null) {
                results.add(String.format("\n--- String '%s' at %s ---", str, addr));
                var refs = rm.getReferencesTo(addr);
                int count = 0;
                for (var ref : refs) {
                    Function func = fm.getFunctionContaining(ref.getFromAddress());
                    String funcName = (func != null) ? func.getName() : "NO_FUNC";
                    results.add(String.format("  0x%X (%s) type=%s", ref.getFromAddress().getOffset(), funcName, ref.getReferenceType()));
                    count++;
                    if (count > 10) break;
                }
                if (count == 0) results.add("  No references found");
            } else {
                results.add(String.format("\nString '%s' NOT FOUND", str));
            }
        }
        
        // 5. Write output
        outputResults();
    }
    
    private void disassembleRange(Listing listing, long startAddr, long endAddr) {
        Address addr = toAddr(startAddr);
        int count = 0;
        while (addr.getOffset() < endAddr && count < 100) {
            Instruction instr = listing.getInstructionAt(addr);
            if (instr != null) {
                results.add(String.format("    %s: %s", instr.getAddress(), instr));
                addr = instr.getAddress().add(instr.getLength());
            } else {
                // Try to get next instruction
                addr = addr.add(4);
            }
            count++;
        }
    }
    
    private void outputResults() {
        String outputPath = "C:/Users/ribhu/kilo-test/whoop-mg-client/docs/research/hello_5802_targeted_disasm.txt";
        try (BufferedWriter writer = new BufferedWriter(new FileWriter(outputPath))) {
            for (String s : results) writer.write(s + "\n");
            println("Results written to " + outputPath);
        } catch (Exception e) {
            println("Error writing results: " + e.getMessage());
        }
    }
}