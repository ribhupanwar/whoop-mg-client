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

public class HelloProtocolCallChainAnalysis extends GhidraScript {
    
    private List<String> results = new ArrayList<>();
    
    @Override
    protected void run() throws Exception {
        collectBinaryInfo();
        
        // Key addresses we know from previous analysis
        traceSelectorRef("sendGetHelloPacketWithCompletion:", "109abaff8");
        traceSelectorRef("processCommandDidGetHelloPacket:", "109aae6a3");
        traceSelectorRef("processCommandDidGetHelloInfoWithSerial:signature:boardId:", "109aae668");
        traceSelectorRef("didCallSendGetHelloPacket:", "109a79ff0");
        traceSelectorRef("GetHelloPacket", "109781892");
        
        // Trace callers of signature storage functions
        traceCallersOfAddress("setLastConnectedStrapSignature:", "1000594b4");
        traceCallersOfAddress("lastConnectedStrapSignature", "10005a6c0");
        
        // Search for CoreBluetooth write characteristic calls
        searchForCBWriteCalls();
        
        // Search for CLIENT_HELLO opcode (0x91)
        searchForOpcode91();
        
        // Search for FD4B UUID
        searchForFD4B();
        
        outputResults();
    }
    
    private void collectBinaryInfo() {
        println("Binary: " + currentProgram.getName());
    }
    
    private void traceSelectorRef(String selectorName, String addrStr) {
        results.add("\n=== TRACING SELECTOR: " + selectorName + " @ " + addrStr + " ===");
        
        try {
            Address addr = currentProgram.getAddressFactory().getAddress(addrStr);
            var refs = currentProgram.getReferenceManager().getReferencesTo(addr);
            
            if (refs.hasNext()) {
                for (var ref : refs) {
                    Address fromAddr = ref.getFromAddress();
                    Instruction instr = currentProgram.getListing().getInstructionAt(fromAddr);
                    if (instr != null) {
                        results.add(String.format("  Code ref from %s: %s", fromAddr, instr));
                        disassembleAround(fromAddr, selectorName);
                        traceFunctionContaining(fromAddr, selectorName, 0);
                    } else {
                        results.add(String.format("  Data ref from %s", fromAddr));
                    }
                }
            } else {
                results.add("  No references found");
            }
        } catch (Exception e) {
            results.add("  Error: " + e.getMessage());
        }
    }
    
    private void traceCallersOfAddress(String funcName, String addrStr) {
        results.add("\n=== TRACING CALLERS OF: " + funcName + " @ " + addrStr + " ===");
        
        try {
            Address addr = currentProgram.getAddressFactory().getAddress(addrStr);
            Function func = currentProgram.getFunctionManager().getFunctionAt(addr);
            
            if (func != null) {
                results.add(String.format("  Function: %s @ %s", func.getName(), func.getEntryPoint()));
                disassembleFunction(func);
                
                // Find callers
                var refs = currentProgram.getReferenceManager().getReferencesTo(func.getEntryPoint());
                for (var ref : refs) {
                    if (ref.getReferenceType().isCall()) {
                        Address fromAddr = ref.getFromAddress();
                        Function caller = currentProgram.getFunctionManager().getFunctionContaining(fromAddr);
                        if (caller != null) {
                            results.add(String.format("  CALLER: %s @ %s (from %s)", 
                                caller.getName(), caller.getEntryPoint(), fromAddr));
                            traceFunctionContaining(fromAddr, funcName, 1);
                        }
                    }
                }
            } else {
                results.add("  No function at this address");
            }
        } catch (Exception e) {
            results.add("  Error: " + e.getMessage());
        }
    }
    
    private void traceFunctionContaining(Address addr, String context, int depth) {
        if (depth > 3) return; // Limit recursion
        
        Function func = currentProgram.getFunctionManager().getFunctionContaining(addr);
        if (func == null) return;
        
        results.add(String.format("    [%s] In function: %s @ %s", context, func.getName(), func.getEntryPoint()));
        
        // Find callers of this function
        var refs = currentProgram.getReferenceManager().getReferencesTo(func.getEntryPoint());
        for (var ref : refs) {
            if (ref.getReferenceType().isCall()) {
                Address fromAddr = ref.getFromAddress();
                Function caller = currentProgram.getFunctionManager().getFunctionContaining(fromAddr);
                if (caller != null && !caller.equals(func)) {
                    results.add(String.format("      CALLER: %s @ %s (from %s)", 
                        caller.getName(), caller.getEntryPoint(), fromAddr));
                    traceFunctionContaining(fromAddr, context, depth + 1);
                }
            }
        }
    }
    
    private void disassembleFunction(Function func) {
        Listing listing = currentProgram.getListing();
        Address entry = func.getEntryPoint();
        Address end = func.getBody().getMaxAddress();
        
        Instruction instr = listing.getInstructionAt(entry);
        int instrCount = 0;
        while (instr != null && instrCount < 150) {
            String mnemonic = instr.getMnemonicString().toUpperCase();
            if (mnemonic.equals("BL") || mnemonic.equals("BLR") || mnemonic.equals("B")) {
                String opStr = instr.toString().toLowerCase();
                if (opStr.contains("hello") || opStr.contains("signature") || opStr.contains("serial") ||
                    opStr.contains("board") || opStr.contains("strap") || opStr.contains("write") ||
                    opStr.contains("characteristic") || opStr.contains("ble") || opStr.contains("packet") ||
                    opStr.contains("send") || opStr.contains("verify") || opStr.contains("sign") ||
                    opStr.contains("secp") || opStr.contains("ecdsa") || opStr.contains("ed25519") ||
                    opStr.contains("secsignature") || opStr.contains("seckey") || opStr.contains("crypto")) {
                    results.add(String.format("    *** INTERESTING: %s: %s", instr.getAddress(), instr));
                }
            }
            
            // Also check for ADRP/ADRL pairs that might load selector strings
            if (mnemonic.equals("ADRP") || mnemonic.equals("ADRL") || mnemonic.equals("LDR")) {
                String opStr = instr.toString();
                results.add(String.format("    LOAD: %s: %s", instr.getAddress(), instr));
            }
            
            instr = listing.getInstructionAfter(instr.getAddress());
            instrCount++;
        }
    }
    
    private void disassembleAround(Address addr, String context) {
        Listing listing = currentProgram.getListing();
        
        Address start = addr;
        for (int i = 0; i < 10; i++) {
            Instruction prev = listing.getInstructionBefore(start);
            if (prev != null) start = prev.getAddress();
            else break;
        }
        
        Instruction instr = listing.getInstructionAt(start);
        int count = 0;
        while (instr != null && count < 40) {
            String marker = (instr.getAddress().equals(addr)) ? " >>> " : "     ";
            String mnemonic = instr.getMnemonicString().toUpperCase();
            String line = String.format("    %s%s: %s", marker, instr.getAddress(), instr);
            
            if (mnemonic.equals("BL") || mnemonic.equals("BLR") || mnemonic.equals("B")) {
                String opStr = instr.toString().toLowerCase();
                if (opStr.contains("hello") || opStr.contains("signature") || opStr.contains("serial") ||
                    opStr.contains("board") || opStr.contains("strap") || opStr.contains("write") ||
                    opStr.contains("characteristic") || opStr.contains("ble") || opStr.contains("packet") ||
                    opStr.contains("send") || opStr.contains("verify") || opStr.contains("sign") ||
                    opStr.contains("secp") || opStr.contains("ecdsa") || opStr.contains("ed25519") ||
                    opStr.contains("secsignature") || opStr.contains("seckey") || opStr.contains("crypto")) {
                    line += " *** INTERESTING ***";
                }
            }
            
            results.add(line);
            instr = listing.getInstructionAfter(instr.getAddress());
            count++;
        }
    }
    
    private void searchForCBWriteCalls() {
        results.add("\n=== SEARCHING FOR CoreBluetooth writeValue CALLS ===");
        
        String[] cbSelectors = {
            "writeValue:forCharacteristic:type:",
            "writeValue:forCharacteristic:",
            "setNotifyValue:forCharacteristic:",
            "readValueForCharacteristic:",
            "discoverCharacteristics:forService:",
            "discoverServices:",
        };
        
        for (String selector : cbSelectors) {
            try {
                byte[] bytes = selector.getBytes();
                byte[] mask = new byte[bytes.length];
                for (int i = 0; i < mask.length; i++) mask[i] = (byte)0xFF;
                
                Address addr = currentProgram.getMinAddress();
                addr = currentProgram.getMemory().findBytes(addr, bytes, mask, false, new ConsoleTaskMonitor());
                
                if (addr != null) {
                    results.add(String.format("  Selector '%s' found at %s", selector, addr));
                    var refs = currentProgram.getReferenceManager().getReferencesTo(addr);
                    for (var ref : refs) {
                        Address fromAddr = ref.getFromAddress();
                        Instruction instr = currentProgram.getListing().getInstructionAt(fromAddr);
                        if (instr != null) {
                            results.add(String.format("    Code ref from %s: %s", fromAddr, instr));
                            disassembleAround(fromAddr, selector);
                        }
                    }
                }
            } catch (Exception e) {
            }
        }
    }
    
    private void searchForOpcode91() {
        results.add("\n=== SEARCHING FOR CLIENT_HELLO OPCODE 0x91 ===");
        
        // Search for byte 0x91 in context of BLE writes
        try {
            byte[] bytes = new byte[] { (byte)0x91 };
            byte[] mask = new byte[] { (byte)0xFF };
            
            Address addr = currentProgram.getMinAddress();
            int count = 0;
            while (addr != null && count < 50) {
                addr = currentProgram.getMemory().findBytes(addr, bytes, mask, false, new ConsoleTaskMonitor());
                if (addr != null) {
                    // Check if it's in a code section or data section
                    Instruction instr = currentProgram.getListing().getInstructionAt(addr);
                    if (instr != null) {
                        String opStr = instr.toString();
                        if (opStr.toLowerCase().contains("mov") || opStr.toLowerCase().contains("ldr") || 
                            opStr.toLowerCase().contains("str") || opStr.toLowerCase().contains("bl")) {
                            results.add(String.format("  0x91 in code at %s: %s", addr, instr));
                            disassembleAround(addr, "opcode91");
                        }
                    } else {
                        // Check if it's in a data array
                        try {
                            byte[] surrounding = new byte[32];
                            currentProgram.getMemory().getBytes(addr.subtract(16), surrounding);
                            StringBuilder hex = new StringBuilder();
                            for (int i = 0; i < 32; i++) {
                                hex.append(String.format("%02x ", surrounding[i] & 0xFF));
                            }
                            results.add(String.format("  0x91 in data at %s: %s", addr, hex));
                        } catch (Exception e) {
                        }
                    }
                    addr = addr.add(1);
                    count++;
                }
            }
        } catch (Exception e) {
            results.add("  Error searching for 0x91: " + e.getMessage());
        }
    }
    
    private void searchForFD4B() {
        results.add("\n=== SEARCHING FOR FD4B UUID ===");
        
        // FD4B could be in various formats: 0xFD4B, "FD4B", "4bfd", etc.
        String[] patterns = {"FD4B", "4bfd", "FDB4", "B4FD", "fd4b", "4b fd", "fd 4b"};
        
        for (String pattern : patterns) {
            try {
                byte[] bytes = pattern.getBytes();
                byte[] mask = new byte[bytes.length];
                for (int i = 0; i < mask.length; i++) mask[i] = (byte)0xFF;
                
                Address addr = currentProgram.getMinAddress();
                addr = currentProgram.getMemory().findBytes(addr, bytes, mask, true, new ConsoleTaskMonitor());
                
                if (addr != null) {
                    results.add(String.format("  Pattern '%s' found at %s", pattern, addr));
                    var refs = currentProgram.getReferenceManager().getReferencesTo(addr);
                    for (var ref : refs) {
                        Address fromAddr = ref.getFromAddress();
                        Instruction instr = currentProgram.getListing().getInstructionAt(fromAddr);
                        if (instr != null) {
                            results.add(String.format("    Code ref from %s: %s", fromAddr, instr));
                        }
                    }
                }
            } catch (Exception e) {
            }
        }
    }
    
    private void outputResults() {
        String outputPath = "C:/Users/ribhu/kilo-test/whoop-mg-client/docs/research/hello_5802_callchain_analysis.txt";
        try (BufferedWriter writer = new BufferedWriter(new FileWriter(outputPath))) {
            writer.write("=== BINARY INFO ===\n");
            writer.write("Name: " + currentProgram.getName() + "\n");
            writer.write("SHA256: A82E252BDF11D1AB45C106F26702D1292E301B3FB6AE82D37E15E9F7CE7871B9\n");
            writer.write("Size: 209853712\n");
            writer.write("Architecture: " + currentProgram.getLanguage().toString() + "\n");
            writer.write("Image Base: " + currentProgram.getImageBase() + "\n\n");
            
            writer.write("=== CALL CHAIN ANALYSIS ===\n");
            for (String s : results) writer.write(s + "\n");
            
            println("Results written to " + outputPath);
        } catch (Exception e) {
            println("Error writing results: " + e.getMessage());
        }
    }
}