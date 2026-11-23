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

public class HelloProtocolDataRefs extends GhidraScript {
    
    private List<String> results = new ArrayList<>();
    
    // Data reference addresses from known strings
    private static final long[] DATA_REFS = {
        0x10B36AC78L,  // helloResponse
        0x10B3524C8L,  // helloResponseTask
        0x10AD1B6E0L,  // strap_signature
        0x10AD1B718L,  // strap_signature
        0x10AF28510L,  // strapSerial
        0x10B356EB8L,  // boardId
        0x10B4C9F80L,  // lastConnectedStrapSerial
        0x10B345CB0L,  // lastConnectedStrapSerial
        0x10B38ABE8L,  // lastConnectedStrapSerial
        0x10B402C00L,  // lastConnectedStrapSerial
        0x10B4640A8L,  // lastConnectedStrapSerial
        0x10B4C9F88L,  // lastConnectedStrapSignature
        0x10B345CC0L,  // lastConnectedStrapSignature
        0x10B38ABF8L,  // lastConnectedStrapSignature
        0x10B4CF798L,  // setLastConnectedStrapSignature:
        0x10B4CC260L,  // processCommandDidGetHelloPacket:
        0x10B4CC258L,  // processCommandDidGetHelloInfoWithSerial:signature:boardId:
        0x10B4D8B08L,  // sendGetHelloPacketWithCompletionHandler:
        0x10B396A00L,  // didCallSendGetHelloPacket
        0x10ACA74B8L,  // GetHelloPacket
    };
    
    @Override
    protected void run() throws Exception {
        Listing listing = currentProgram.getListing();
        Memory mem = currentProgram.getMemory();
        ReferenceManager rm = currentProgram.getReferenceManager();
        
        results.add("=== DATA REFERENCE TRACING ===");
        
        for (long dataAddr : DATA_REFS) {
            results.add(String.format("\n=== Data @ 0x%X ===", dataAddr));
            
            // Find code references to this data address
            var refs = rm.getReferencesTo(toAddr(dataAddr));
            int count = 0;
            while (refs.hasNext()) {
                Reference ref = refs.next();
                Address fromAddr = ref.getFromAddress();
                results.add(String.format("  Ref from 0x%X type=%s", fromAddr.getOffset(), ref.getReferenceType()));
                
                // Try to disassemble around the reference
                long start = fromAddr.getOffset() - 0x20;
                long end = fromAddr.getOffset() + 0x20;
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
            if (count == 0) {
                results.add("  No references found");
            }
        }
        
        outputResults();
    }
    
    private void outputResults() {
        String outputPath = "C:/Users/ribhu/kilo-test/whoop-mg-client/docs/research/hello_5802_data_refs.txt";
        try (BufferedWriter writer = new BufferedWriter(new FileWriter(outputPath))) {
            for (String s : results) writer.write(s + "\n");
            println("Results written to " + outputPath);
        } catch (Exception e) {
            println("Error writing results: " + e.getMessage());
        }
    }
}