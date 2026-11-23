import ghidra.app.script.GhidraScript;
import ghidra.program.model.symbol.SymbolTable;
import ghidra.program.model.symbol.Symbol;
import ghidra.program.model.symbol.SymbolType;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionManager;
import ghidra.program.model.listing.Listing;
import ghidra.program.model.mem.Memory;
import ghidra.program.model.address.Address;
import ghidra.util.task.ConsoleTaskMonitor;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileOptions;
import java.io.FileWriter;
import java.io.BufferedWriter;
import java.util.ArrayList;
import java.util.List;

public class HelloProtocolDeepSearch extends GhidraScript {
    
    private List<String> results = new ArrayList<>();
    private List<String> helloFunctions = new ArrayList<>();
    private List<String> stringRefs = new ArrayList<>();
    private List<String> bytePatterns = new ArrayList<>();
    
    @Override
    protected void run() throws Exception {
        collectBinaryInfo();
        searchHelloFunctions();
        searchStringReferences();
        searchBytePatterns();
        searchSelectors();
        outputResults();
    }
    
    private void collectBinaryInfo() {
        println("Binary: " + currentProgram.getName());
        println("SHA256: A82E252BDF11D1AB45C106F26702D1292E301B3FB6AE82D37E15E9F7CE7871B9");
        println("Size: 209853712");
        println("Architecture: " + currentProgram.getLanguage().toString());
        println("Image Base: " + currentProgram.getImageBase());
    }
    
    private void searchHelloFunctions() {
        FunctionManager funcMgr = currentProgram.getFunctionManager();
        DecompInterface decompiler = new DecompInterface();
        decompiler.openProgram(currentProgram);
        DecompileOptions options = new DecompileOptions();
        decompiler.setOptions(options);
        
        int funcCount = 0;
        for (Function func : funcMgr.getFunctions(true)) {
            String name = func.getName().toLowerCase();
            if (name.contains("hello") || name.contains("handshake") ||
                name.contains("pair") || name.contains("client") ||
                name.contains("command") || name.contains("write") ||
                name.contains("ble") || name.contains("bluetooth") ||
                name.contains("auth") || name.contains("challenge") ||
                name.contains("signature") || name.contains("serial")) {
                
                try {
                    var result = decompiler.decompileFunction(func, 15, new ConsoleTaskMonitor());
                    if (result != null && result.decompileCompleted()) {
                        String decompiled = result.getDecompiledFunction().getC();
                        helloFunctions.add(String.format("FUNCTION: name=%s addr=%s\n%s", 
                            func.getName(), func.getEntryPoint(), decompiled.substring(0, Math.min(decompiled.length(), 8000))));
                        funcCount++;
                    }
                } catch (Exception e) {
                    // ignore
                }
            }
        }
        
        decompiler.dispose();
        println("Found " + funcCount + " HELLO-related functions with decompilation");
    }
    
    private void searchStringReferences() {
        Memory mem = currentProgram.getMemory();
        
        // Search for specific strings in memory
        String[] searchStrings = {
            "HelloPacket", "helloPacket", "HelloRev", "helloRev",
            "GetHelloPacket", "getHelloPacket", "SendGetHelloPacket",
            "processCommandDidGetHelloPacket",
            "processCommandDidGetHelloInfoWithSerial",
            "CLIENT_HELLO", "clientHello", "0x91", "145",
            "boardId", "BoardId", "strapSignature", "strapSerial",
            "HelloResponse", "HelloRequest", "HelloPacketRev3", "HelloPacketRev4",
            "HelloResponsePacketRev3", "HelloResponsePacketRev4"
        };
        
        for (String searchStr : searchStrings) {
            byte[] bytes = searchStr.getBytes();
            byte[] mask = new byte[bytes.length];
            for (int i = 0; i < mask.length; i++) mask[i] = (byte)0xFF;
            
            Address addr = currentProgram.getMinAddress();
            while (true) {
                try {
                    addr = mem.findBytes(addr, bytes, mask, false, new ConsoleTaskMonitor());
                    if (addr == null) break;
                    
                    // Get references to this address
                    var refs = currentProgram.getReferenceManager().getReferencesTo(addr);
                    String refStr = "";
                    for (var ref : refs) {
                        refStr += " [" + ref.getFromAddress() + " " + ref.getReferenceType() + "]";
                    }
                    
                    stringRefs.add(String.format("STRING: '%s' at %s%s", searchStr, addr, refStr));
                    addr = addr.add(bytes.length);
                } catch (Exception e) {
                    break;
                }
            }
        }
        
        println("Found " + stringRefs.size() + " string references");
    }
    
    private void searchBytePatterns() {
        Memory mem = currentProgram.getMemory();
        
        // Search for CLIENT_HELLO opcode 0x91 in context
        byte[] helloOpcode = new byte[] {(byte)0x91};
        byte[] mask = new byte[] {(byte)0xFF};
        
        Address addr = currentProgram.getMinAddress();
        int count = 0;
        while (count < 50) { // Limit results
            try {
                addr = mem.findBytes(addr, helloOpcode, mask, false, new ConsoleTaskMonitor());
                if (addr == null) break;
                
                // Read surrounding bytes
                byte[] context = new byte[32];
                mem.getBytes(addr.subtract(16), context);
                
                StringBuilder hex = new StringBuilder();
                for (int i = 0; i < context.length; i++) {
                    hex.append(String.format("%02x ", context[i] & 0xFF));
                }
                
                bytePatterns.add(String.format("BYTE PATTERN: 0x91 at %s\n  Context: %s", addr, hex.toString()));
                addr = addr.add(1);
                count++;
            } catch (Exception e) {
                break;
            }
        }
        
        // Search for common BLE command patterns
        byte[][] patterns = {
            new byte[] {(byte)0x91, (byte)0x00}, // CLIENT_HELLO with length
            new byte[] {(byte)0x91, (byte)0x01}, // CLIENT_HELLO with payload
            new byte[] {(byte)0x00, (byte)0x91}, // reversed
        };
        
        for (byte[] pattern : patterns) {
            byte[] pmask = new byte[pattern.length];
            for (int i = 0; i < pmask.length; i++) pmask[i] = (byte)0xFF;
            
            addr = currentProgram.getMinAddress();
            try {
                addr = mem.findBytes(addr, pattern, pmask, false, new ConsoleTaskMonitor());
                if (addr != null) {
                    bytePatterns.add(String.format("BLE PATTERN: %s at %s", 
                        bytesToHex(pattern), addr));
                }
            } catch (Exception e) {
            }
        }
        
        println("Found " + bytePatterns.size() + " byte patterns");
    }
    
    private void searchSelectors() {
        // Search for Objective-C selectors related to HELLO
        String[] selectorPatterns = {
            "processCommandDidGetHelloPacket:",
            "processCommandDidGetHelloInfoWithSerial:signature:boardId:",
            "sendGetHelloPacketWithCompletion:",
            "didCallSendGetHelloPacket:",
            "setLastConnectedStrapSignature:",
            "setLastConnectedStrapSerial:"
        };
        
        for (String sel : selectorPatterns) {
            byte[] bytes = sel.getBytes();
            byte[] mask = new byte[bytes.length];
            for (int i = 0; i < mask.length; i++) mask[i] = (byte)0xFF;
            
            Address addr = currentProgram.getMinAddress();
            try {
                addr = currentProgram.getMemory().findBytes(addr, bytes, mask, false, new ConsoleTaskMonitor());
                if (addr != null) {
                    var refs = currentProgram.getReferenceManager().getReferencesTo(addr);
                    String refStr = "";
                    for (var ref : refs) {
                        refStr += " [" + ref.getFromAddress() + " " + ref.getReferenceType() + "]";
                    }
                    results.add(String.format("SELECTOR: '%s' at %s%s", sel, addr, refStr));
                }
            } catch (Exception e) {
            }
        }
        
        println("Found " + results.size() + " selector references");
    }
    
    private String bytesToHex(byte[] bytes) {
        StringBuilder sb = new StringBuilder();
        for (byte b : bytes) {
            sb.append(String.format("%02x ", b & 0xFF));
        }
        return sb.toString();
    }
    
    private void outputResults() {
        String outputPath = "C:/Users/ribhu/kilo-test/whoop-mg-client/docs/research/hello_5802_deep_analysis.txt";
        try (BufferedWriter writer = new BufferedWriter(new FileWriter(outputPath))) {
            writer.write("=== BINARY INFO ===\n");
            writer.write("Name: " + currentProgram.getName() + "\n");
            writer.write("SHA256: A82E252BDF11D1AB45C106F26702D1292E301B3FB6AE82D37E15E9F7CE7871B9\n");
            writer.write("Size: 209853712\n");
            writer.write("Architecture: " + currentProgram.getLanguage().toString() + "\n");
            writer.write("Image Base: " + currentProgram.getImageBase() + "\n\n");
            
            writer.write("=== SELECTOR REFERENCES ===\n");
            for (String s : results) writer.write(s + "\n");
            writer.write("\n");
            
            writer.write("=== STRING REFERENCES ===\n");
            for (String s : stringRefs) writer.write(s + "\n");
            writer.write("\n");
            
            writer.write("=== BYTE PATTERNS ===\n");
            for (String s : bytePatterns) writer.write(s + "\n");
            writer.write("\n");
            
            writer.write("=== HELLO-RELATED FUNCTIONS (DECOMPILED) ===\n");
            for (String s : helloFunctions) writer.write(s + "\n\n");
            
            println("Results written to " + outputPath);
        } catch (Exception e) {
            println("Error writing results: " + e.getMessage());
        }
    }
}