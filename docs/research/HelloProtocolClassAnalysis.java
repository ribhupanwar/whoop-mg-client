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

public class HelloProtocolClassAnalysis extends GhidraScript {
    
    private List<String> results = new ArrayList<>();
    
    @Override
    protected void run() throws Exception {
        collectBinaryInfo();
        
        // Search for class metadata for key classes
        analyzeClassMetadata("WHPBLEStrapManager");
        analyzeClassMetadata("PuffinDeviceSerialProvider");
        analyzeClassMetadata("WhoopDeviceAPIs");
        analyzeClassMetadata("BluetoothPairingConnectingViewModel");
        analyzeClassMetadata("BluetoothPairingFeature");
        analyzeClassMetadata("WHPBand");
        analyzeClassMetadata("WHPStrap");
        
        // Search for Swift metadata that might contain HELLO method implementations
        searchSwiftMetadataForHello();
        
        // Trace the signature verification path
        traceSignatureVerification();
        
        outputResults();
    }
    
    private void collectBinaryInfo() {
        println("Binary: " + currentProgram.getName());
        println("SHA256: A82E252BDF11D1AB45C106F26702D1292E301B3FB6AE82D37E15E9F7CE7871B9");
        println("Architecture: " + currentProgram.getLanguage().toString());
        println("Image Base: " + currentProgram.getImageBase());
    }
    
    private void analyzeClassMetadata(String className) {
        results.add("\n=== ANALYZING CLASS: " + className + " ===");
        
        try {
            byte[] bytes = className.getBytes();
            byte[] mask = new byte[bytes.length];
            for (int i = 0; i < mask.length; i++) mask[i] = (byte)0xFF;
            
            Address addr = currentProgram.getMinAddress();
            addr = currentProgram.getMemory().findBytes(addr, bytes, mask, false, new ConsoleTaskMonitor());
            
            if (addr != null) {
                results.add(String.format("  Class name '%s' found at %s", className, addr));
                
                var refs = currentProgram.getReferenceManager().getReferencesTo(addr);
                for (var ref : refs) {
                    Address fromAddr = ref.getFromAddress();
                    Instruction instr = currentProgram.getListing().getInstructionAt(fromAddr);
                    if (instr != null) {
                        results.add(String.format("    Code ref from %s: %s", fromAddr, instr));
                        disassembleAround(fromAddr, className);
                    } else {
                        results.add(String.format("    Data ref from %s", fromAddr));
                    }
                }
                
                // Also check nearby for class metadata structures
                analyzeClassMetadataStructure(addr, className);
            } else {
                results.add(String.format("  Class name '%s' NOT found", className));
            }
        } catch (Exception e) {
            results.add("  Error analyzing class " + className + ": " + e.getMessage());
        }
    }
    
    private void analyzeClassMetadataStructure(Address classNameAddr, String className) {
        // ObjC class metadata is typically near the class name
        // Swift metadata is more complex
        Memory memory = currentProgram.getMemory();
        
        try {
            // Check a range around the class name for metadata pointers
            for (long offset = -256; offset <= 256; offset += 8) {
                Address checkAddr = classNameAddr.add(offset);
                if (!memory.contains(checkAddr)) continue;
                
                byte[] bytes = new byte[8];
                memory.getBytes(checkAddr, bytes);
                
                long val = 0;
                for (int i = 0; i < 8; i++) {
                    val |= ((long)(bytes[i] & 0xFF)) << (i * 8);
                }
                
                // Check if this points to a method list or other metadata
                if (val >= 0x100000000L && val < 0x110000000L) {
                    String addrStr = Long.toHexString(val);
                    Address targetAddr = currentProgram.getAddressFactory().getAddress(addrStr);
                    
                    // Check if there's a function or data here
                    Function func = currentProgram.getFunctionManager().getFunctionAt(targetAddr);
                    if (func != null) {
                        results.add(String.format("    Metadata ptr at %s -> %s @ %s", checkAddr, func.getName(), targetAddr));
                    } else {
                        Instruction instr = currentProgram.getListing().getInstructionAt(targetAddr);
                        if (instr != null) {
                            results.add(String.format("    Metadata ptr at %s -> code at %s", checkAddr, targetAddr));
                        }
                    }
                }
            }
        } catch (Exception e) {
            results.add("    Error analyzing metadata structure: " + e.getMessage());
        }
    }
    
    private void searchSwiftMetadataForHello() {
        results.add("\n=== SEARCHING SWIFT METADATA FOR HELLO ===");
        
        // Search for Swift method names that might contain HELLO
        String[] swiftTerms = {"sendGetHelloPacket", "processCommandDidGetHelloPacket", "processCommandDidGetHelloInfo", 
                              "didCallSendGetHelloPacket", "GetHelloPacket", "helloResponse", "helloResponseTask"};
        
        for (String term : swiftTerms) {
            try {
                byte[] bytes = term.getBytes();
                byte[] mask = new byte[bytes.length];
                for (int i = 0; i < mask.length; i++) mask[i] = (byte)0xFF;
                
                Address addr = currentProgram.getMinAddress();
                addr = currentProgram.getMemory().findBytes(addr, bytes, mask, false, new ConsoleTaskMonitor());
                
                if (addr != null) {
                    results.add(String.format("  Swift term '%s' found at %s", term, addr));
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
    
    private void traceSignatureVerification() {
        results.add("\n=== TRACING SIGNATURE VERIFICATION PATH ===");
        
        // We found SecKeyVerifySignature at 0x10908a7b0
        // Let's trace what calls it and what it calls
        String[] cryptoAddrs = {
            "10908a798", // SecKeyCreateSignature
            "10908a7b0", // SecKeyVerifySignature
        };
        
        for (String addrStr : cryptoAddrs) {
            try {
                Address addr = currentProgram.getAddressFactory().getAddress(addrStr);
                Function func = currentProgram.getFunctionManager().getFunctionAt(addr);
                if (func != null) {
                    results.add(String.format("\n--- CRYPTO FUNCTION: %s @ %s ---", func.getName(), func.getEntryPoint()));
                    disassembleFunction(func);
                    
                    // Find callers
                    traceCallers(func, 2);
                }
            } catch (Exception e) {
            }
        }
        
        // Also search for where strap_signature is used in verification context
        searchForSignatureUsage();
    }
    
    private void searchForSignatureUsage() {
        String[] sigTerms = {"strap_signature", "signature", "verify", "SecKeyVerify"};
        
        for (String term : sigTerms) {
            try {
                byte[] bytes = term.getBytes();
                byte[] mask = new byte[bytes.length];
                for (int i = 0; i < mask.length; i++) mask[i] = (byte)0xFF;
                
                Address addr = currentProgram.getMinAddress();
                addr = currentProgram.getMemory().findBytes(addr, bytes, mask, true, new ConsoleTaskMonitor());
                
                if (addr != null) {
                    results.add(String.format("\n  Signature term '%s' found at %s", term, addr));
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
    
    private void traceCallers(Function func, int depth) {
        if (depth <= 0) return;
        
        Address entry = func.getEntryPoint();
        var refs = currentProgram.getReferenceManager().getReferencesTo(entry);
        
        for (var ref : refs) {
            if (ref.getReferenceType().isCall()) {
                Address fromAddr = ref.getFromAddress();
                Function caller = currentProgram.getFunctionManager().getFunctionContaining(fromAddr);
                if (caller != null) {
                    results.add(String.format("  CALLER: %s @ %s (from %s)", 
                        caller.getName(), caller.getEntryPoint(), fromAddr));
                    
                    if (depth > 1) {
                        traceCallers(caller, depth - 1);
                    }
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
        while (instr != null && instrCount < 100) {
            String instrStr = String.format("  %s: %s", instr.getAddress(), instr);
            results.add(instrStr);
            
            String mnemonic = instr.getMnemonicString().toUpperCase();
            if (mnemonic.equals("BL") || mnemonic.equals("BLR") || mnemonic.equals("B")) {
                String opStr = instr.toString().toLowerCase();
                if (opStr.contains("hello") || opStr.contains("signature") || opStr.contains("serial") ||
                    opStr.contains("board") || opStr.contains("strap") || opStr.contains("write") ||
                    opStr.contains("characteristic") || opStr.contains("ble") || opStr.contains("packet") ||
                    opStr.contains("send") || opStr.contains("verify") || opStr.contains("sign") ||
                    opStr.contains("secp") || opStr.contains("ecdsa") || opStr.contains("ed25519")) {
                    results.add("    *** INTERESTING CALL ***");
                }
            }
            
            instr = listing.getInstructionAfter(instr.getAddress());
            instrCount++;
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
        String outputPath = "C:/Users/ribhu/kilo-test/whoop-mg-client/docs/research/hello_5802_class_analysis.txt";
        try (BufferedWriter writer = new BufferedWriter(new FileWriter(outputPath))) {
            writer.write("=== BINARY INFO ===\n");
            writer.write("Name: " + currentProgram.getName() + "\n");
            writer.write("SHA256: A82E252BDF11D1AB45C106F26702D1292E301B3FB6AE82D37E15E9F7CE7871B9\n");
            writer.write("Size: 209853712\n");
            writer.write("Architecture: " + currentProgram.getLanguage().toString() + "\n");
            writer.write("Image Base: " + currentProgram.getImageBase() + "\n\n");
            
            writer.write("=== CLASS METADATA AND SIGNATURE VERIFICATION ANALYSIS ===\n");
            for (String s : results) writer.write(s + "\n");
            
            println("Results written to " + outputPath);
        } catch (Exception e) {
            println("Error writing results: " + e.getMessage());
        }
    }
}