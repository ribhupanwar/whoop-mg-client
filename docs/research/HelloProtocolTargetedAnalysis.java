import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionManager;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.Listing;
import ghidra.program.model.address.Address;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceManager;
import ghidra.util.task.ConsoleTaskMonitor;
import java.io.FileWriter;
import java.io.BufferedWriter;
import java.util.ArrayList;
import java.util.List;
import java.util.HashSet;
import java.util.Set;

public class HelloProtocolTargetedAnalysis extends GhidraScript {
    
    private List<String> results = new ArrayList<>();
    private Set<String> seenFunctions = new HashSet<>();
    
    @Override
    protected void run() throws Exception {
        collectBinaryInfo();
        
        // Find implementations of key HELLO methods by searching for their selector strings
        // and tracing objc_msgSend calls
        traceObjcMsgSendToSelectors();
        
        // Search for specific function names containing HELLO-related terms
        searchForHelloFunctions();
        
        // Trace the signature storage functions we found
        traceSignatureStorage();
        
        // Search for BLE write paths
        traceBleWritePaths();
        
        outputResults();
    }
    
    private void collectBinaryInfo() {
        println("Binary: " + currentProgram.getName());
        println("SHA256: A82E252BDF11D1AB45C106F26702D1292E301B3FB6AE82D37E15E9F7CE7871B9");
        println("Architecture: " + currentProgram.getLanguage().toString());
        println("Image Base: " + currentProgram.getImageBase());
    }
    
    private void traceObjcMsgSendToSelectors() {
        results.add("\n=== TRACING objc_msgSend CALLS TO HELLO SELECTORS ===");
        
        // The selector string addresses from previous analysis
        String[] selectorStrings = {
            "109abaff8", // "sendGetHelloPacketWithCompletion:"
            "109aae6a3", // "processCommandDidGetHelloPacket:"
            "109aae668", // "processCommandDidGetHelloInfoWithSerial:signature:boardId:" (truncated)
            "109a79ff0", // "didCallSendGetHelloPacket:"
            "109781892", // "GetHelloPacket"
        };
        
        for (String selAddrStr : selectorStrings) {
            try {
                Address selAddr = currentProgram.getAddressFactory().getAddress(selAddrStr);
                var refs = currentProgram.getReferenceManager().getReferencesTo(selAddr);
                
                results.add(String.format("\n--- Selector at %s ---", selAddrStr));
                for (var ref : refs) {
                    Address fromAddr = ref.getFromAddress();
                    Instruction instr = currentProgram.getListing().getInstructionAt(fromAddr);
                    if (instr != null) {
                        String instrStr = instr.toString();
                        // Check if this is an objc_msgSend call (loads selector into register then calls)
                        results.add(String.format("  Ref from %s: %s", fromAddr, instrStr));
                        
                        // Disassemble context around this reference
                        disassembleAround(fromAddr);
                    } else {
                        results.add(String.format("  Data ref from %s", fromAddr));
                    }
                }
            } catch (Exception e) {
                println("Error tracing selector " + selAddrStr + ": " + e.getMessage());
            }
        }
    }
    
    private void searchForHelloFunctions() {
        results.add("\n=== SEARCHING FOR HELLO-RELATED FUNCTIONS ===");
        
        FunctionManager funcMgr = currentProgram.getFunctionManager();
        String[] helloTerms = {"hello", "strap", "signature", "serial", "boardid", "pairing", "authenticat"};
        
        for (Function func : funcMgr.getFunctions(true)) {
            String name = func.getName().toLowerCase();
            for (String term : helloTerms) {
                if (name.contains(term)) {
                    String key = func.getName() + "@" + func.getEntryPoint();
                    if (!seenFunctions.contains(key)) {
                        seenFunctions.add(key);
                        results.add(String.format("\n--- FOUND: %s @ %s ---", func.getName(), func.getEntryPoint()));
                        disassembleFunction(func);
                    }
                    break;
                }
            }
        }
    }
    
    private void traceSignatureStorage() {
        results.add("\n=== TRACING SIGNATURE STORAGE FUNCTIONS ===");
        
        // Addresses found in previous run
        String[] sigAddrs = {
            "1000594b4", // setLastConnectedStrapSignature:
            "10005a6c0", // lastConnectedStrapSignature
        };
        
        for (String addrStr : sigAddrs) {
            try {
                Address addr = currentProgram.getAddressFactory().getAddress(addrStr);
                Function func = currentProgram.getFunctionManager().getFunctionAt(addr);
                if (func != null) {
                    results.add(String.format("\n--- SIGNATURE FUNCTION: %s @ %s ---", func.getName(), func.getEntryPoint()));
                    disassembleFunction(func);
                    
                    // Find what calls this function
                    traceCallers(func);
                }
            } catch (Exception e) {
                println("Error tracing signature function " + addrStr + ": " + e.getMessage());
            }
        }
    }
    
    private void traceBleWritePaths() {
        results.add("\n=== TRACING BLE WRITE PATHS ===");
        
        // Search for writeValue:forCharacteristic:type: and similar
        FunctionManager funcMgr = currentProgram.getFunctionManager();
        for (Function func : funcMgr.getFunctions(true)) {
            String name = func.getName().toLowerCase();
            if (name.contains("writevalue") || 
                (name.contains("write") && name.contains("characteristic")) ||
                (name.contains("send") && name.contains("packet")) ||
                name.contains("blewrite") || name.contains("peripheralwrite")) {
                
                String key = func.getName() + "@" + func.getEntryPoint();
                if (!seenFunctions.contains(key)) {
                    seenFunctions.add(key);
                    results.add(String.format("\n--- BLE WRITE CANDIDATE: %s @ %s ---", func.getName(), func.getEntryPoint()));
                    disassembleFunction(func);
                }
            }
        }
        
        // Also search for the characteristic UUID strings in code (not just data)
        searchForUuidInCode();
    }
    
    private void searchForUuidInCode() {
        String[] uuids = {"fd4b0002", "fd4b0003", "FD4B0002", "FD4B0003"};
        
        for (String uuid : uuids) {
            try {
                byte[] bytes = uuid.getBytes();
                byte[] mask = new byte[bytes.length];
                for (int i = 0; i < mask.length; i++) mask[i] = (byte)0xFF;
                
                Address addr = currentProgram.getMinAddress();
                addr = currentProgram.getMemory().findBytes(addr, bytes, mask, false, new ConsoleTaskMonitor());
                
                if (addr != null) {
                    results.add(String.format("\n  UUID '%s' found at %s", uuid, addr));
                    
                    // Check if there are code references
                    var refs = currentProgram.getReferenceManager().getReferencesTo(addr);
                    for (var ref : refs) {
                        Address fromAddr = ref.getFromAddress();
                        Instruction instr = currentProgram.getListing().getInstructionAt(fromAddr);
                        if (instr != null) {
                            results.add(String.format("    Code ref from %s: %s", fromAddr, instr));
                            disassembleAround(fromAddr);
                        }
                    }
                }
            } catch (Exception e) {
            }
        }
    }
    
    private void traceCallers(Function func) {
        Address entry = func.getEntryPoint();
        var refs = currentProgram.getReferenceManager().getReferencesTo(entry);
        
        List<String> callers = new ArrayList<>();
        for (var ref : refs) {
            if (ref.getReferenceType().isCall()) {
                Address fromAddr = ref.getFromAddress();
                Function caller = currentProgram.getFunctionManager().getFunctionContaining(fromAddr);
                if (caller != null) {
                    callers.add(String.format("    Called by: %s @ %s (from %s)", 
                        caller.getName(), caller.getEntryPoint(), fromAddr));
                } else {
                    callers.add(String.format("    Called from: %s (no function)", fromAddr));
                }
            }
        }
        
        if (!callers.isEmpty()) {
            results.add("  CALLERS:");
            for (String c : callers) results.add(c);
        }
    }
    
    private void disassembleFunction(Function func) {
        Listing listing = currentProgram.getListing();
        Address entry = func.getEntryPoint();
        Address end = func.getBody().getMaxAddress();
        
        Instruction instr = listing.getInstructionAt(entry);
        int instrCount = 0;
        while (instr != null && instrCount < 200) {
            String instrStr = String.format("  %s: %s", instr.getAddress(), instr);
            results.add(instrStr);
            
            // Highlight interesting instructions
            String mnemonic = instr.getMnemonicString().toUpperCase();
            if (mnemonic.equals("BL") || mnemonic.equals("BLR") || mnemonic.equals("B")) {
                String opStr = instr.toString().toLowerCase();
                if (opStr.contains("hello") || opStr.contains("signature") || opStr.contains("serial") ||
                    opStr.contains("board") || opStr.contains("strap") || opStr.contains("write") ||
                    opStr.contains("characteristic") || opStr.contains("ble")) {
                    results.add("    *** INTERESTING CALL ***");
                }
            }
            
            instr = listing.getInstructionAfter(instr.getAddress());
            instrCount++;
        }
        
        if (instrCount >= 200) {
            results.add(String.format("  ... (%d more instructions truncated)", 
                (int)((end.subtract(entry) + 1) / 4) - 200));
        }
    }
    
    private void disassembleAround(Address addr) {
        Listing listing = currentProgram.getListing();
        
        // Disassemble 5 instructions before and 15 after
        Address start = addr;
        for (int i = 0; i < 5; i++) {
            Instruction prev = listing.getInstructionBefore(start);
            if (prev != null) start = prev.getAddress();
            else break;
        }
        
        Instruction instr = listing.getInstructionAt(start);
        int count = 0;
        while (instr != null && count < 25) {
            String marker = (instr.getAddress().equals(addr)) ? " >>> " : "     ";
            results.add(String.format("    %s%s: %s", marker, instr.getAddress(), instr));
            instr = listing.getInstructionAfter(instr.getAddress());
            count++;
        }
    }
    
    private void outputResults() {
        String outputPath = "C:/Users/ribhu/kilo-test/whoop-mg-client/docs/research/hello_5802_targeted_analysis.txt";
        try (BufferedWriter writer = new BufferedWriter(new FileWriter(outputPath))) {
            writer.write("=== BINARY INFO ===\n");
            writer.write("Name: " + currentProgram.getName() + "\n");
            writer.write("SHA256: A82E252BDF11D1AB45C106F26702D1292E301B3FB6AE82D37E15E9F7CE7871B9\n");
            writer.write("Size: 209853712\n");
            writer.write("Architecture: " + currentProgram.getLanguage().toString() + "\n");
            writer.write("Image Base: " + currentProgram.getImageBase() + "\n\n");
            
            writer.write("=== TARGETED HELLO PROTOCOL ANALYSIS ===\n");
            for (String s : results) writer.write(s + "\n");
            
            println("Results written to " + outputPath);
        } catch (Exception e) {
            println("Error writing results: " + e.getMessage());
        }
    }
}