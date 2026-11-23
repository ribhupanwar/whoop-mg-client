import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionManager;
import ghidra.program.model.symbol.SymbolTable;
import ghidra.program.model.symbol.Symbol;
import ghidra.program.model.symbol.SymbolType;
import ghidra.program.model.address.Address;
import ghidra.util.task.ConsoleTaskMonitor;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileOptions;
import java.io.FileWriter;
import java.io.BufferedWriter;
import java.util.ArrayList;
import java.util.List;

public class HelloProtocolAddressSearch extends GhidraScript {
    
    private List<String> results = new ArrayList<>();
    
    @Override
    protected void run() throws Exception {
        collectBinaryInfo();
        searchAtAddresses();
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
    
    private void searchAtAddresses() {
        FunctionManager funcMgr = currentProgram.getFunctionManager();
        DecompInterface decompiler = new DecompInterface();
        decompiler.openProgram(currentProgram);
        DecompileOptions options = new DecompileOptions();
        decompiler.setOptions(options);
        
        // Key addresses from our analysis - these are string addresses, but functions may be nearby
        // Let's search for functions at specific addresses that might be the actual implementations
        String[] targetAddrs = {
            "109aae6a3", // s_processCommandDidGetHelloPacket:
            "109aae668", // s_processCommandDidGetHelloInfoWithSerial:signature:boardId:
            "109abaff8", // s_sendGetHelloPacketWithCompletion
            "109a79ff0", // s_didCallSendGetHelloPacket
            "109781892", // s_GetHelloPacket
            "109a88926", // s_helloResponse
            "109a88940", // s_helloResponseTask
            "1099ea6b0", // WHPBLEStrapManager class
            "1099ec180", // PuffinDeviceSerialProvider class
            "109a68c10", // s_bleProcessCommandDelegate
            "109aae450", // s_primaryWhoopStrapDevice
        };
        
        for (String addrStr : targetAddrs) {
            try {
                Address addr = currentProgram.getAddressFactory().getAddress(addrStr);
                
                // Check if there's a function AT this address
                Function func = funcMgr.getFunctionAt(addr);
                if (func != null) {
                    decompileAndSave(func, decompiler, "at " + addrStr);
                }
                
                // Also check functions CONTAINING this address
                func = funcMgr.getFunctionContaining(addr);
                if (func != null) {
                    decompileAndSave(func, decompiler, "containing " + addrStr);
                }
                
                // Search for functions that reference this address
                var refs = currentProgram.getReferenceManager().getReferencesTo(addr);
                for (var ref : refs) {
                    Address fromAddr = ref.getFromAddress();
                    func = funcMgr.getFunctionContaining(fromAddr);
                    if (func != null) {
                        decompileAndSave(func, decompiler, "referencing " + addrStr + " from " + fromAddr);
                    }
                }
                
            } catch (Exception e) {
                println("Error processing " + addrStr + ": " + e.getMessage());
            }
        }
        
        decompiler.dispose();
    }
    
    private void decompileAndSave(Function func, DecompInterface decompiler, String context) {
        String funcKey = func.getName() + "@" + func.getEntryPoint() + "[" + context + "]";
        // Check if already processed
        for (String r : results) {
            if (r.contains("FUNCTION: name=" + func.getName() + " addr=" + func.getEntryPoint())) {
                return;
            }
        }
        
        try {
            var result = decompiler.decompileFunction(func, 30, new ConsoleTaskMonitor());
            if (result != null && result.decompileCompleted()) {
                String decompiled = result.getDecompiledFunction().getC();
                results.add(String.format("FUNCTION: name=%s addr=%s (%s)\n%s", 
                    func.getName(), func.getEntryPoint(), context, decompiled.substring(0, Math.min(decompiled.length(), 12000))));
                println("Decompiled: " + func.getName() + " at " + func.getEntryPoint() + " (" + context + ")");
            }
        } catch (Exception e) {
            results.add(String.format("FUNCTION: name=%s addr=%s (%s) - DECOMPILE ERROR: %s", 
                func.getName(), func.getEntryPoint(), context, e.getMessage()));
        }
    }
    
    private void searchSelectors() {
        // Search for the full selector that was truncated
        String[] selectors = {
            "processCommandDidGetHelloInfoWithSerial:signature:boardId:",
            "processCommandDidGetHelloPacket:",
            "sendGetHelloPacketWithCompletion:",
            "didCallSendGetHelloPacket:",
            "setLastConnectedStrapSignature:",
            "setLastConnectedStrapSerial:"
        };
        
        for (String sel : selectors) {
            byte[] bytes = sel.getBytes();
            byte[] mask = new byte[bytes.length];
            for (int i = 0; i < mask.length; i++) mask[i] = (byte)0xFF;
            
            Address addr = currentProgram.getMinAddress();
            try {
                addr = currentProgram.getMemory().findBytes(addr, bytes, mask, false, new ConsoleTaskMonitor());
                if (addr != null) {
                    results.add(String.format("SELECTOR STRING: '%s' found at %s", sel, addr));
                    
                    // Find functions referencing this
                    var refs = currentProgram.getReferenceManager().getReferencesTo(addr);
                    for (var ref : refs) {
                        Function func = currentProgram.getFunctionManager().getFunctionContaining(ref.getFromAddress());
                        if (func != null) {
                            results.add(String.format("  -> Referenced by function: %s at %s", func.getName(), func.getEntryPoint()));
                        }
                    }
                } else {
                    results.add(String.format("SELECTOR STRING: '%s' NOT FOUND", sel));
                }
            } catch (Exception e) {
                results.add(String.format("SELECTOR STRING: '%s' ERROR: %s", sel, e.getMessage()));
            }
        }
    }
    
    private void outputResults() {
        String outputPath = "C:/Users/ribhu/kilo-test/whoop-mg-client/docs/research/hello_5802_address_search.txt";
        try (BufferedWriter writer = new BufferedWriter(new FileWriter(outputPath))) {
            writer.write("=== BINARY INFO ===\n");
            writer.write("Name: " + currentProgram.getName() + "\n");
            writer.write("SHA256: A82E252BDF11D1AB45C106F26702D1292E301B3FB6AE82D37E15E9F7CE7871B9\n");
            writer.write("Size: 209853712\n");
            writer.write("Architecture: " + currentProgram.getLanguage().toString() + "\n");
            writer.write("Image Base: " + currentProgram.getImageBase() + "\n\n");
            
            writer.write("=== ADDRESS SEARCH RESULTS ===\n");
            for (String s : results) writer.write(s + "\n\n");
            
            println("Results written to " + outputPath);
        } catch (Exception e) {
            println("Error writing results: " + e.getMessage());
        }
    }
}