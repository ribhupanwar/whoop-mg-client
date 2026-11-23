import ghidra.app.script.GhidraScript;
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
import java.util.HashSet;
import java.util.Set;

public class HelloProtocolRefSearch extends GhidraScript {
    
    private List<String> results = new ArrayList<>();
    private Set<String> seenFunctions = new HashSet<>();
    
    @Override
    protected void run() throws Exception {
        collectBinaryInfo();
        searchFunctionsReferencingStrings();
        outputResults();
    }
    
    private void collectBinaryInfo() {
        println("Binary: " + currentProgram.getName());
        println("SHA256: A82E252BDF11D1AB45C106F26702D1292E301B3FB6AE82D37E15E9F7CE7871B9");
        println("Size: 209853712");
        println("Architecture: " + currentProgram.getLanguage().toString());
        println("Image Base: " + currentProgram.getImageBase());
    }
    
    private void searchFunctionsReferencingStrings() {
        FunctionManager funcMgr = currentProgram.getFunctionManager();
        DecompInterface decompiler = new DecompInterface();
        decompiler.openProgram(currentProgram);
        DecompileOptions options = new DecompileOptions();
        decompiler.setOptions(options);
        
        // Key string addresses from symbol search
        String[] stringAddrs = {
            "109781892", // s_GetHelloPacket
            "109a79ff0", // s_didCallSendGetHelloPacket
            "109aae668", // s_processCommandDidGetHelloInfoWithSerial:signature:boardId:
            "109aae6a3", // s_processCommandDidGetHelloPacket:
            "109abaff8", // s_sendGetHelloPacketWithCompletion
            "109a2c151", // s_boardId
            "1097b1e0e", // s_strap_signature
            "1098550e4", // s_strapSerial
            "109a98a40", // s_lastConnectedStrapSerial
            "109a98a60", // s_lastConnectedStrapSignature
            "109a46aad", // s_setLastConnectedStrapSignature:
        };
        
        int funcCount = 0;
        for (String addrStr : stringAddrs) {
            try {
                Address addr = currentProgram.getAddressFactory().getAddress(addrStr);
                var refs = currentProgram.getReferenceManager().getReferencesTo(addr);
                
                for (var ref : refs) {
                    Address fromAddr = ref.getFromAddress();
                    Function func = funcMgr.getFunctionContaining(fromAddr);
                    if (func != null) {
                        String funcKey = func.getName() + "@" + func.getEntryPoint();
                        if (!seenFunctions.contains(funcKey)) {
                            seenFunctions.add(funcKey);
                            
                            try {
                                var result = decompiler.decompileFunction(func, 30, new ConsoleTaskMonitor());
                                if (result != null && result.decompileCompleted()) {
                                    String decompiled = result.getDecompiledFunction().getC();
                                    results.add(String.format("FUNCTION: name=%s addr=%s (references string at %s)\n%s", 
                                        func.getName(), func.getEntryPoint(), addrStr, decompiled.substring(0, Math.min(decompiled.length(), 12000))));
                                    funcCount++;
                                    println("Decompiled: " + func.getName() + " at " + func.getEntryPoint() + " (refs " + addrStr + ")");
                                }
                            } catch (Exception e) {
                                results.add(String.format("FUNCTION: name=%s addr=%s (references string at %s) - DECOMPILE ERROR: %s", 
                                    func.getName(), func.getEntryPoint(), addrStr, e.getMessage()));
                            }
                        }
                    }
                }
            } catch (Exception e) {
                println("Error processing " + addrStr + ": " + e.getMessage());
            }
        }
        
        decompiler.dispose();
        println("Decompiled " + funcCount + " unique functions referencing HELLO strings");
    }
    
    private void outputResults() {
        String outputPath = "C:/Users/ribhu/kilo-test/whoop-mg-client/docs/research/hello_5802_ref_search.txt";
        try (BufferedWriter writer = new BufferedWriter(new FileWriter(outputPath))) {
            writer.write("=== BINARY INFO ===\n");
            writer.write("Name: " + currentProgram.getName() + "\n");
            writer.write("SHA256: A82E252BDF11D1AB45C106F26702D1292E301B3FB6AE82D37E15E9F7CE7871B9\n");
            writer.write("Size: 209853712\n");
            writer.write("Architecture: " + currentProgram.getLanguage().toString() + "\n");
            writer.write("Image Base: " + currentProgram.getImageBase() + "\n\n");
            
            writer.write("=== FUNCTIONS REFERENCING HELLO STRINGS ===\n");
            for (String s : results) writer.write(s + "\n\n");
            
            println("Results written to " + outputPath);
        } catch (Exception e) {
            println("Error writing results: " + e.getMessage());
        }
    }
}