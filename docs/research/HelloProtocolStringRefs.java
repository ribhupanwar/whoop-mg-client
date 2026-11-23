import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Listing;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.address.Address;
import ghidra.program.model.mem.Memory;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceManager;
import java.io.FileWriter;
import java.io.BufferedWriter;
import java.util.ArrayList;
import java.util.List;

public class HelloProtocolStringRefs extends GhidraScript {
    
    private List<String> results = new ArrayList<>();
    
    // Selector string addresses from earlier analysis
    private static final long[] STRING_ADDRS = {
        0x109aae6a3L,  // processCommandDidGetHelloPacket:
        0x109aae668L,  // processCommandDidGetHelloInfoWithSerial:signature:boardId:
        0x109abaff8L,  // sendGetHelloPacketWithCompletion:
        0x109a79ff0L,  // didCallSendGetHelloPacket:
        0x109781892L,  // GetHelloPacket
    };
    
    // Also helloResponse related
    private static final String[] SEARCH_STRINGS = {
        "helloResponse", "helloResponseTask", "strap_signature",
        "strapSerial", "boardId", "lastConnectedStrapSerial",
        "lastConnectedStrapSignature"
    };
    
    @Override
    protected void run() throws Exception {
        Listing listing = currentProgram.getListing();
        Memory mem = currentProgram.getMemory();
        ReferenceManager rm = currentProgram.getReferenceManager();
        
        results.add("=== HELLO STRING REFERENCES ===");
        
        for (long strAddr : STRING_ADDRS) {
            results.add(String.format("\n=== String @ 0x%X ===", strAddr));
            Address addr = toAddr(strAddr);
            
            // Find all references to this address
            var refs = rm.getReferencesTo(addr);
            int count = 0;
            while (refs.hasNext()) {
                Reference ref = refs.next();
                results.add(String.format("  0x%X type=%s", ref.getFromAddress().getOffset(), ref.getReferenceType()));
                
                // Disassemble around the reference
                long refAddr2 = ref.getFromAddress().getOffset();
                long start = refAddr2 - 0x40;
                long end = refAddr2 + 0x40;
                Address current = toAddr(start);
                while (current.getOffset() < end) {
                    Instruction instr = listing.getInstructionAt(current);
                    if (instr != null) {
                        results.add(String.format("    %s: %s", instr.getAddress(), instr));
                        current = instr.getAddress().add(instr.getLength());
                    } else {
                        current = current.add(4);
                    }
                }
                count++;
                if (count > 5) break;
            }
            if (count == 0) results.add("  No references found");
        }
        
        // Search for other key strings in memory
        results.add("\n\n=== KEY STRING SEARCH ===");
        for (String str : SEARCH_STRINGS) {
            byte[] bytes = str.getBytes();
            byte[] mask = new byte[bytes.length];
            for (int i = 0; i < mask.length; i++) mask[i] = (byte)0xFF;
            
            Address addr = mem.findBytes(currentProgram.getMinAddress(), bytes, mask, false, new ghidra.util.task.ConsoleTaskMonitor());
            if (addr != null) {
                results.add(String.format("\n--- '%s' at %s ---", str, addr));
                var refs = rm.getReferencesTo(addr);
                int count = 0;
                while (refs.hasNext()) {
                    Reference ref = refs.next();
                    results.add(String.format("  0x%X type=%s", ref.getFromAddress().getOffset(), ref.getReferenceType()));
                    count++;
                    if (count > 10) break;
                }
                if (count == 0) results.add("  No references found");
            } else {
                results.add(String.format("\n'%s' NOT FOUND", str));
            }
        }
        
        outputResults();
    }
    
    private void outputResults() {
        String outputPath = "C:/Users/ribhu/kilo-test/whoop-mg-client/docs/research/hello_5802_string_refs.txt";
        try (BufferedWriter writer = new BufferedWriter(new FileWriter(outputPath))) {
            for (String s : results) writer.write(s + "\n");
            println("Results written to " + outputPath);
        } catch (Exception e) {
            println("Error writing results: " + e.getMessage());
        }
    }
}