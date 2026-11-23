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

public class HelloProtocolTargetedDecompile extends GhidraScript {
    
    private List<String> results = new ArrayList<>();
    
    @Override
    protected void run() throws Exception {
        collectBinaryInfo();
        decompileTargetFunctions();
        outputResults();
    }
    
    private void collectBinaryInfo() {
        println("Binary: " + currentProgram.getName());
        println("SHA256: A82E252BDF11D1AB45C106F26702D1292E301B3FB6AE82D37E15E9F7CE7871B9");
        println("Size: 209853712");
        println("Architecture: " + currentProgram.getLanguage().toString());
        println("Image Base: " + currentProgram.getImageBase());
    }
    
    private void decompileTargetFunctions() {
        FunctionManager funcMgr = currentProgram.getFunctionManager();
        DecompInterface decompiler = new DecompInterface();
        decompiler.openProgram(currentProgram);
        DecompileOptions options = new DecompileOptions();
        decompiler.setOptions(options);
        
        // Key addresses from string search - functions that reference these strings
        String[] targetAddrs = {
            "109781892", // s_GetHelloPacket
            "109aae6a3", // s_processCommandDidGetHelloPacket:
            "109abaff8", // s_sendGetHelloPacketWithCompletion
            "109a2c151", // s_boardId
            "1097b1e0e", // s_strap_signature
            "1098550e4", // s_strapSerial
            "109a79ff0", // s_didCallSendGetHelloPacket
            "109a98a40", // s_lastConnectedStrapSerial
            "109a98a60", // s_lastConnectedStrapSignature
            "109a46aad", // s_setLastConnectedStrapSignature:
            "1099ec180", // PuffinDeviceSerialProvider
            "109aa7bf0", // s_pairedStrapSerial
            "109aa7c10", // s_pairedStrapSignature
        };
        
        for (String addrStr : targetAddrs) {
            try {
                Address addr = currentProgram.getAddressFactory().getAddress(addrStr);
                var refs = currentProgram.getReferenceManager().getReferencesTo(addr);
                
                for (var ref : refs) {
                    Address fromAddr = ref.getFromAddress();
                    Function func = funcMgr.getFunctionContaining(fromAddr);
                    if (func != null) {
                        String funcName = func.getName();
                        // Only decompile if not already done
                        boolean alreadyDone = false;
                        for (String r : results) {
                            if (r.contains("FUNCTION: name=" + funcName)) {
                                alreadyDone = true;
                                break;
                            }
                        }
                        if (!alreadyDone) {
                            try {
                                var result = decompiler.decompileFunction(func, 30, new ConsoleTaskMonitor());
                                if (result != null && result.decompileCompleted()) {
                                    String decompiled = result.getDecompiledFunction().getC();
                                    results.add(String.format("FUNCTION: name=%s addr=%s (references %s)\n%s", 
                                        funcName, func.getEntryPoint(), addrStr, decompiled.substring(0, Math.min(decompiled.length(), 10000))));
                                    println("Decompiled: " + funcName + " at " + func.getEntryPoint());
                                }
                            } catch (Exception e) {
                                results.add(String.format("FUNCTION: name=%s addr=%s (references %s) - DECOMPILE ERROR: %s", 
                                    funcName, func.getEntryPoint(), addrStr, e.getMessage()));
                            }
                        }
                    }
                }
            } catch (Exception e) {
                println("Error processing " + addrStr + ": " + e.getMessage());
            }
        }
        
        decompiler.dispose();
        println("Decompiled " + results.size() + " unique functions");
    }
    
    private void outputResults() {
        String outputPath = "C:/Users/ribhu/kilo-test/whoop-mg-client/docs/research/hello_5802_targeted_decompile.txt";
        try (BufferedWriter writer = new BufferedWriter(new FileWriter(outputPath))) {
            writer.write("=== BINARY INFO ===\n");
            writer.write("Name: " + currentProgram.getName() + "\n");
            writer.write("SHA256: A82E252BDF11D1AB45C106F26702D1292E301B3FB6AE82D37E15E9F7CE7871B9\n");
            writer.write("Size: 209853712\n");
            writer.write("Architecture: " + currentProgram.getLanguage().toString() + "\n");
            writer.write("Image Base: " + currentProgram.getImageBase() + "\n\n");
            
            writer.write("=== TARGETED DECOMPILATIONS ===\n");
            for (String s : results) writer.write(s + "\n\n");
            
            println("Results written to " + outputPath);
        } catch (Exception e) {
            println("Error writing results: " + e.getMessage());
        }
    }
}