import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Listing;
import ghidra.program.model.address.Address;
import ghidra.program.model.mem.Memory;
import java.io.FileWriter;
import java.io.BufferedWriter;
import java.util.ArrayList;
import java.util.List;

public class HelloProtocolKnownStrings extends GhidraScript {
    
    private List<String> results = new ArrayList<>();
    
    // Known string addresses from earlier analysis
    private static final long[] KNOWN_STRING_ADDRS = {
        0x109a88926L,  // helloResponse
        0x109a88940L,  // helloResponseTask
        0x1097b1e0eL,  // strap_signature
        0x1098550e4L,  // strapSerial
        0x109a2c151L,  // boardId
        0x109a98a40L,  // lastConnectedStrapSerial
        0x109a98a60L,  // lastConnectedStrapSignature
        0x109a46aadL,  // setLastConnectedStrapSignature:
        0x109aae6a3L,  // processCommandDidGetHelloPacket:
        0x109aae668L,  // processCommandDidGetHelloInfoWithSerial:signature:boardId:
        0x109abaff8L,  // sendGetHelloPacketWithCompletion:
        0x109a79ff0L,  // didCallSendGetHelloPacket:
        0x109781892L,  // GetHelloPacket
    };
    
    @Override
    protected void run() throws Exception {
        Memory mem = currentProgram.getMemory();
        Listing listing = currentProgram.getListing();
        
        results.add("=== KNOWN STRING ADDRESSES ===");
        
        for (long addr : KNOWN_STRING_ADDRS) {
            results.add(String.format("\n--- Address 0x%X ---", addr));
            try {
                Address a = toAddr(addr);
                // Read null-terminated string
                StringBuilder sb = new StringBuilder();
                for (int i = 0; i < 256; i++) {
                    byte b = mem.getByte(a.add(i));
                    if (b == 0) break;
                    if (b >= 32 && b < 127) {
                        sb.append((char)b);
                    } else {
                        sb.append(String.format("\\x%02x", b & 0xFF));
                    }
                }
                results.add(String.format("  String: \"%s\"", sb.toString()));
                
                // Find references
                var rm = currentProgram.getReferenceManager();
                var refs = rm.getReferencesTo(a);
                int count = 0;
                while (refs.hasNext()) {
                    var ref = refs.next();
                    results.add(String.format("  Ref: 0x%X type=%s", ref.getFromAddress().getOffset(), ref.getReferenceType()));
                    count++;
                    if (count > 10) break;
                }
                if (count == 0) results.add("  No references found");
            } catch (Exception e) {
                results.add("  Error: " + e.getMessage());
            }
        }
        
        outputResults();
    }
    
    private void outputResults() {
        String outputPath = "C:/Users/ribhu/kilo-test/whoop-mg-client/docs/research/hello_5802_known_strings.txt";
        try (BufferedWriter writer = new BufferedWriter(new FileWriter(outputPath))) {
            for (String s : results) writer.write(s + "\n");
            println("Results written to " + outputPath);
        } catch (Exception e) {
            println("Error writing results: " + e.getMessage());
        }
    }
}