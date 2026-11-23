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
import java.util.HashSet;
import java.util.Set;

public class HelloProtocolFindImplementations extends GhidraScript {
    
    private List<String> results = new ArrayList<>();
    
    @Override
    protected void run() throws Exception {
        collectBinaryInfo();
        
        // The selector string addresses
        String[] selectorStrings = {
            "109abaff8", // "sendGetHelloPacketWithCompletion:"
            "109aae6a3", // "processCommandDidGetHelloPacket:"
            "109aae668", // "processCommandDidGetHelloInfoWithSerial:signature:boardId:" (truncated)
            "109a79ff0", // "didCallSendGetHelloPacket:"
            "109781892", // "GetHelloPacket"
        };
        
        // Find ObjC method list entries that reference these selectors
        // Method list entries are typically: [selector_ptr, types_ptr, imp_ptr]
        findMethodImplementations(selectorStrings);
        
        // Search for classes that might implement HELLO protocol
        findHelloClasses();
        
        // Trace the BLE write path from known functions
        traceBleWriteFromKnownFunctions();
        
        outputResults();
    }
    
    private void collectBinaryInfo() {
        println("Binary: " + currentProgram.getName());
        println("SHA256: A82E252BDF11D1AB45C106F26702D1292E301B3FB6AE82D37E15E9F7CE7871B9");
        println("Architecture: " + currentProgram.getLanguage().toString());
        println("Image Base: " + currentProgram.getImageBase());
    }
    
    private void findMethodImplementations(String[] selectorStrings) {
        results.add("\n=== FINDING METHOD IMPLEMENTATIONS FROM SELECTORS ===");
        
        Memory memory = currentProgram.getMemory();
        
        for (String selAddrStr : selectorStrings) {
            try {
                Address selAddr = currentProgram.getAddressFactory().getAddress(selAddrStr);
                
                // Search for references to this selector in memory (method list entries)
                // Method list entry: 24 bytes - [sel_ptr, types_ptr, imp_ptr] (each 8 bytes on ARM64)
                // We need to find where this selector address is stored as a pointer
                byte[] selBytes = new byte[8];
                long selVal = Long.parseUnsignedLong(selAddrStr, 16);
                for (int i = 0; i < 8; i++) {
                    selBytes[i] = (byte)((selVal >> (i * 8)) & 0xFF);
                }
                
                Address addr = currentProgram.getMinAddress();
                byte[] mask = new byte[8];
                for (int i = 0; i < 8; i++) mask[i] = (byte)0xFF;
                
                int found = 0;
                while (addr != null && found < 20) {
                    addr = memory.findBytes(addr, selBytes, mask, false, new ConsoleTaskMonitor());
                    if (addr != null) {
                        // Check if this looks like a method list entry (check surrounding pointers)
                        results.add(String.format("\n  Selector %s referenced at %s", selAddrStr, addr));
                        analyzeMethodListEntry(addr, selAddrStr);
                        addr = addr.add(1);
                        found++;
                    }
                }
                
                if (found == 0) {
                    results.add(String.format("\n  No method list entries found for selector at %s", selAddrStr));
                }
                
            } catch (Exception e) {
                println("Error finding implementations for " + selAddrStr + ": " + e.getMessage());
            }
        }
    }
    
    private void analyzeMethodListEntry(Address selRefAddr, String selLabel) {
        Memory memory = currentProgram.getMemory();
        
        // Method list entry is typically aligned. Check nearby for imp pointer
        // Try to read the potential imp pointer (8 bytes after selector pointer in entry)
        try {
            // The method list entry structure varies. Let's check a range around the reference
            for (long offset = -32; offset <= 32; offset += 8) {
                Address checkAddr = selRefAddr.add(offset);
                if (!memory.contains(checkAddr)) continue;
                
                byte[] bytes = new byte[8];
                memory.getBytes(checkAddr, bytes);
                
                long val = 0;
                for (int i = 0; i < 8; i++) {
                    val |= ((long)(bytes[i] & 0xFF)) << (i * 8);
                }
                
                // Check if this looks like a code address (in the text section)
                if (val >= 0x100000000L && val < 0x110000000L) {
                    String addrStr = Long.toHexString(val);
                    Address implAddr = currentProgram.getAddressFactory().getAddress(addrStr);
                    Function func = currentProgram.getFunctionManager().getFunctionAt(implAddr);
                    if (func != null) {
                        results.add(String.format("    Possible IMP at %s: %s @ %s", checkAddr, func.getName(), implAddr));
                        disassembleFunction(func, "IMP for " + selLabel);
                    } else {
                        // Check if there's code at this address
                        Instruction instr = currentProgram.getListing().getInstructionAt(implAddr);
                        if (instr != null) {
                            results.add(String.format("    Possible IMP at %s: code at %s (no function)", checkAddr, implAddr));
                            disassembleAround(implAddr, "IMP for " + selLabel);
                        }
                    }
                }
            }
        } catch (Exception e) {
            results.add("    Error analyzing method list entry: " + e.getMessage());
        }
    }
    
    private void findHelloClasses() {
        results.add("\n=== SEARCHING FOR HELLO-RELATED CLASSES ===");
        
        // Search for class names containing relevant terms
        String[] classTerms = {"strap", "ble", "bluetooth", "pairing", "hello", "puffin", "device"};
        
        FunctionManager funcMgr = currentProgram.getFunctionManager();
        for (Function func : funcMgr.getFunctions(true)) {
            String name = func.getName();
            // Look for class method patterns like +[ClassName methodName] or -[ClassName methodName]
            for (String term : classTerms) {
                if (name.toLowerCase().contains(term.toLowerCase()) && 
                    (name.contains("WHP") || name.contains("Whoop") || name.contains("Puffin") || 
                     name.contains("Bluetooth") || name.contains("Pairing") || name.contains("Device"))) {
                    
                    results.add(String.format("\n--- CLASS METHOD: %s @ %s ---", name, func.getEntryPoint()));
                    disassembleFunction(func, "class method");
                    break;
                }
            }
        }
        
        // Also search for ObjC class references in data
        searchForClassNames();
    }
    
    private void searchForClassNames() {
        String[] classNames = {"WHPBLEStrapManager", "PuffinDeviceSerialProvider", "WhoopDeviceAPIs", 
                              "BluetoothPairing", "BleStrap", "StrapManager"};
        
        for (String className : classNames) {
            try {
                byte[] bytes = className.getBytes();
                byte[] mask = new byte[bytes.length];
                for (int i = 0; i < mask.length; i++) mask[i] = (byte)0xFF;
                
                Address addr = currentProgram.getMinAddress();
                addr = currentProgram.getMemory().findBytes(addr, bytes, mask, false, new ConsoleTaskMonitor());
                
                if (addr != null) {
                    results.add(String.format("\n  Class name '%s' found at %s", className, addr));
                    var refs = currentProgram.getReferenceManager().getReferencesTo(addr);
                    for (var ref : refs) {
                        Address fromAddr = ref.getFromAddress();
                        Instruction instr = currentProgram.getListing().getInstructionAt(fromAddr);
                        if (instr != null) {
                            results.add(String.format("    Referenced from %s: %s", fromAddr, instr));
                            disassembleAround(fromAddr, className);
                        }
                    }
                }
            } catch (Exception e) {
            }
        }
    }
    
    private void traceBleWriteFromKnownFunctions() {
        results.add("\n=== TRACING BLE WRITE FROM KNOWN FUNCTIONS ===");
        
        // We know setLastConnectedStrapSignature: at 0x1000594b4
        // Let's trace what calls it and what it calls
        String[] knownAddrs = {
            "1000594b4", // setLastConnectedStrapSignature:
            "10005a6c0", // lastConnectedStrapSignature
        };
        
        for (String addrStr : knownAddrs) {
            try {
                Address addr = currentProgram.getAddressFactory().getAddress(addrStr);
                Function func = currentProgram.getFunctionManager().getFunctionAt(addr);
                if (func != null) {
                    results.add(String.format("\n--- TRACING: %s @ %s ---", func.getName(), func.getEntryPoint()));
                    
                    // Find callers
                    traceCallersDeep(func, 2);
                    
                    // Disassemble the function
                    disassembleFunction(func, "known function");
                }
            } catch (Exception e) {
            }
        }
        
        // Search for CBPeripheral writeValue:forCharacteristic:type:
        searchForWriteValueCalls();
    }
    
    private void traceCallersDeep(Function func, int depth) {
        if (depth <= 0) return;
        
        Address entry = func.getEntryPoint();
        var refs = currentProgram.getReferenceManager().getReferencesTo(entry);
        
        for (var ref : refs) {
            if (ref.getReferenceType().isCall()) {
                Address fromAddr = ref.getFromAddress();
                Function caller = currentProgram.getFunctionManager().getFunctionContaining(fromAddr);
                if (caller != null) {
                    String name = caller.getName();
                    results.add(String.format("  %sCALLER (depth %d): %s @ %s from %s", 
                        "  ".repeat(3-depth), depth, name, caller.getEntryPoint(), fromAddr));
                    
                    if (depth > 1) {
                        traceCallersDeep(caller, depth - 1);
                    }
                }
            }
        }
    }
    
    private void searchForWriteValueCalls() {
        // Search for objc_msgSend calls that might be writeValue:forCharacteristic:type:
        // The selector for this would be a string like "writeValue:forCharacteristic:type:"
        
        String[] bleSelectors = {"writeValue", "forCharacteristic", "characteristic", "CBPeripheral", "writeWithoutResponse"};
        
        for (String term : bleSelectors) {
            try {
                byte[] bytes = term.getBytes();
                byte[] mask = new byte[bytes.length];
                for (int i = 0; i < mask.length; i++) mask[i] = (byte)0xFF;
                
                Address addr = currentProgram.getMinAddress();
                addr = currentProgram.getMemory().findBytes(addr, bytes, mask, true, new ConsoleTaskMonitor());
                
                if (addr != null) {
                    results.add(String.format("\n  BLE selector '%s' found at %s", term, addr));
                    var refs = currentProgram.getReferenceManager().getReferencesTo(addr);
                    for (var ref : refs) {
                        Address fromAddr = ref.getFromAddress();
                        Instruction instr = currentProgram.getListing().getInstructionAt(fromAddr);
                        if (instr != null) {
                            results.add(String.format("    Code ref from %s: %s", fromAddr, instr));
                            disassembleAround(fromAddr, term);
                        }
                    }
                }
            } catch (Exception e) {
            }
        }
    }
    
    private void disassembleFunction(Function func, String context) {
        Listing listing = currentProgram.getListing();
        Address entry = func.getEntryPoint();
        Address end = func.getBody().getMaxAddress();
        
        Instruction instr = listing.getInstructionAt(entry);
        int instrCount = 0;
        while (instr != null && instrCount < 150) {
            String instrStr = String.format("  %s: %s", instr.getAddress(), instr);
            results.add(instrStr);
            
            String mnemonic = instr.getMnemonicString().toUpperCase();
            if (mnemonic.equals("BL") || mnemonic.equals("BLR") || mnemonic.equals("B")) {
                String opStr = instr.toString().toLowerCase();
                if (opStr.contains("hello") || opStr.contains("signature") || opStr.contains("serial") ||
                    opStr.contains("board") || opStr.contains("strap") || opStr.contains("write") ||
                    opStr.contains("characteristic") || opStr.contains("ble") || opStr.contains("packet") ||
                    opStr.contains("send") || opStr.contains("verify") || opStr.contains("sign")) {
                    results.add("    *** INTERESTING CALL ***");
                }
            }
            
            instr = listing.getInstructionAfter(instr.getAddress());
            instrCount++;
        }
        
        if (instrCount >= 150) {
            results.add(String.format("  ... (%d more instructions truncated)", 
                (int)((end.subtract(entry) + 1) / 4) - 150));
        }
    }
    
    private void disassembleAround(Address addr, String context) {
        Listing listing = currentProgram.getListing();
        
        Address start = addr;
        for (int i = 0; i < 8; i++) {
            Instruction prev = listing.getInstructionBefore(start);
            if (prev != null) start = prev.getAddress();
            else break;
        }
        
        Instruction instr = listing.getInstructionAt(start);
        int count = 0;
        while (instr != null && count < 30) {
            String marker = (instr.getAddress().equals(addr)) ? " >>> " : "     ";
            results.add(String.format("    %s%s: %s", marker, instr.getAddress(), instr));
            instr = listing.getInstructionAfter(instr.getAddress());
            count++;
        }
    }
    
    private void outputResults() {
        String outputPath = "C:/Users/ribhu/kilo-test/whoop-mg-client/docs/research/hello_5802_implementations.txt";
        try (BufferedWriter writer = new BufferedWriter(new FileWriter(outputPath))) {
            writer.write("=== BINARY INFO ===\n");
            writer.write("Name: " + currentProgram.getName() + "\n");
            writer.write("SHA256: A82E252BDF11D1AB45C106F26702D1292E301B3FB6AE82D37E15E9F7CE7871B9\n");
            writer.write("Size: 209853712\n");
            writer.write("Architecture: " + currentProgram.getLanguage().toString() + "\n");
            writer.write("Image Base: " + currentProgram.getImageBase() + "\n\n");
            
            writer.write("=== FINDING HELLO PROTOCOL IMPLEMENTATIONS ===\n");
            for (String s : results) writer.write(s + "\n");
            
            println("Results written to " + outputPath);
        } catch (Exception e) {
            println("Error writing results: " + e.getMessage());
        }
    }
}