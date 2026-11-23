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
import java.util.Set;
import java.util.HashSet;

public class HelloProtocolObjcMsgSendAnalysis extends GhidraScript {
    
    private List<String> results = new ArrayList<>();
    private Set<String> visitedFunctions = new HashSet<>();
    
    @Override
    protected void run() throws Exception {
        collectBinaryInfo();
        
        // Find objc_msgSend in the symbol table / PLT
        findAndTraceObjcMsgSend();
        
        // Search for functions that load HELLO selectors and call objc_msgSend
        searchForHelloSelectorUsage();
        
        // Trace the crypto functions we found earlier
        traceCryptoCallers();
        
        outputResults();
    }
    
    private void collectBinaryInfo() {
        println("Binary: " + currentProgram.getName());
    }
    
    private void findAndTraceObjcMsgSend() {
        results.add("\n=== FINDING AND TRACING objc_msgSend ===");
        
        // Search for objc_msgSend in external symbols / PLT
        try {
            String[] searchTerms = {"objc_msgSend", "_objc_msgSend", "objc_msgSendSuper", "_objc_msgSendSuper"};
            
            for (String term : searchTerms) {
                byte[] bytes = term.getBytes();
                byte[] mask = new byte[bytes.length];
                for (int i = 0; i < mask.length; i++) mask[i] = (byte)0xFF;
                
                Address addr = currentProgram.getMinAddress();
                addr = currentProgram.getMemory().findBytes(addr, bytes, mask, false, new ConsoleTaskMonitor());
                
                if (addr != null) {
                    results.add(String.format("  Found '%s' at %s", term, addr));
                    
                    // Get references to this symbol
                    var refs = currentProgram.getReferenceManager().getReferencesTo(addr);
                    for (var ref : refs) {
                        if (ref.getReferenceType().isCall()) {
                            Address fromAddr = ref.getFromAddress();
                            Instruction instr = currentProgram.getListing().getInstructionAt(fromAddr);
                            if (instr != null) {
                                results.add(String.format("    CALL from %s: %s", fromAddr, instr));
                                analyzeObjcMsgSendCallSite(fromAddr);
                            }
                        }
                    }
                }
            }
        } catch (Exception e) {
            results.add("  Error: " + e.getMessage());
        }
        
        // Also look in the PLT / .la_symbol_ptr section
        searchInPLT();
    }
    
    private void searchInPLT() {
        results.add("\n  Searching PLT/GOT for objc_msgSend...");
        
        // Look for functions that might be objc_msgSend thunks
        FunctionManager fm = currentProgram.getFunctionManager();
        var functions = fm.getFunctions(true);
        
        int count = 0;
        for (Function func : functions) {
            String name = func.getName();
            if (name.contains("objc_msgSend") || name.contains("msgSend")) {
                count++;
                results.add(String.format("  Function: %s @ %s", name, func.getEntryPoint()));
                
                // Trace callers of this function
                var refs = currentProgram.getReferenceManager().getReferencesTo(func.getEntryPoint());
                for (var ref : refs) {
                    if (ref.getReferenceType().isCall()) {
                        Address fromAddr = ref.getFromAddress();
                        Instruction instr = currentProgram.getListing().getInstructionAt(fromAddr);
                        if (instr != null) {
                            results.add(String.format("    CALL from %s: %s", fromAddr, instr));
                            analyzeObjcMsgSendCallSite(fromAddr);
                        }
                    }
                }
            }
            if (count > 50) break; // Limit output
        }
        
        if (count == 0) {
            results.add("  No objc_msgSend functions found in function list");
        }
    }
    
    private void analyzeObjcMsgSendCallSite(Address callAddr) {
        // Look at instructions before the call to see what selector is loaded
        Listing listing = currentProgram.getListing();
        
        Address addr = callAddr;
        for (int i = 0; i < 15; i++) {
            Instruction prev = listing.getInstructionBefore(addr);
            if (prev == null) break;
            addr = prev.getAddress();
            
            String mnemonic = prev.getMnemonicString().toUpperCase();
            String opStr = prev.toString().toLowerCase();
            
            // Look for selector loads (ADRP + LDR, or MOV with selector address)
            if (mnemonic.equals("ADRP") || mnemonic.equals("LDR") || mnemonic.equals("MOV") || 
                mnemonic.equals("ADRL") || mnemonic.equals("LDRSW")) {
                
                // Check if this loads one of our HELLO selector addresses
                String[] helloSelectors = {"109abaff8", "109aae6a3", "109aae668", "109a79ff0", "109781892"};
                for (String selAddr : helloSelectors) {
                    if (opStr.contains(selAddr.toLowerCase())) {
                        results.add(String.format("      *** HELLO SELECTOR LOAD: %s: %s", prev.getAddress(), prev));
                        break;
                    }
                }
                
                // Also check for any selector table loads
                if (opStr.contains("10b4") || opStr.contains("10b3") || opStr.contains("10ac")) {
                    results.add(String.format("      Possible selector table load: %s: %s", prev.getAddress(), prev));
                }
            }
        }
    }
    
    private void searchForHelloSelectorUsage() {
        results.add("\n=== SEARCHING FOR HELLO SELECTOR USAGE IN CODE ===");
        
        // The selector strings themselves are at these addresses
        // Code that uses them will load them via ADRP/ADRL + LDR
        String[] selectorAddrs = {
            "109abaff8", // sendGetHelloPacketWithCompletion:
            "109aae6a3", // processCommandDidGetHelloPacket:
            "109aae668", // processCommandDidGetHelloInfoWithSerial:signature:boardId:
            "109a79ff0", // didCallSendGetHelloPacket:
            "109781892"  // GetHelloPacket
        };
        
        for (String selAddr : selectorAddrs) {
            try {
                Address addr = currentProgram.getAddressFactory().getAddress(selAddr);
                
                // Search for ADRP instructions that reference this address range
                // ADRP loads a 4KB page, so we need to find ADRP to the page containing this address
                long pageAddr = (Long.parseLong(selAddr, 16) >> 12) << 12;
                String pageAddrHex = Long.toHexString(pageAddr);
                
                results.add(String.format("\n  Checking selector at %s (page %s)", selAddr, pageAddrHex));
                
                // Search for ADRP to this page
                byte[] adrpBytes = new byte[] {(byte)0x90}; // ADRP opcode starts with 0x90
                // Actually, let's search for references to the page
                
            } catch (Exception e) {
            }
        }
    }
    
    private void traceCryptoCallers() {
        results.add("\n=== TRACING CRYPTO FUNCTION CALLERS ===");
        
        String[] cryptoAddrs = {
            "10908a798", // SecKeyCreateSignature
            "10908a7b0", // SecKeyVerifySignature
        };
        
        for (String addrStr : cryptoAddrs) {
            try {
                Address addr = currentProgram.getAddressFactory().getAddress(addrStr);
                Function func = currentProgram.getFunctionManager().getFunctionAt(addr);
                
                if (func != null) {
                    results.add(String.format("\n--- CRYPTO: %s @ %s ---", func.getName(), func.getEntryPoint()));
                    
                    // Find all callers
                    var refs = currentProgram.getReferenceManager().getReferencesTo(func.getEntryPoint());
                    for (var ref : refs) {
                        if (ref.getReferenceType().isCall()) {
                            Address fromAddr = ref.getFromAddress();
                            Function caller = currentProgram.getFunctionManager().getFunctionContaining(fromAddr);
                            if (caller != null) {
                                results.add(String.format("  CALLER: %s @ %s (from %s)", 
                                    caller.getName(), caller.getEntryPoint(), fromAddr));
                                
                                // Disassemble the caller around the call site
                                disassembleAroundCaller(caller, fromAddr);
                                
                                // Trace further up
                                traceCallersRecursive(caller, 1);
                            }
                        }
                    }
                }
            } catch (Exception e) {
                results.add("  Error tracing " + addrStr + ": " + e.getMessage());
            }
        }
    }
    
    private void traceCallersRecursive(Function func, int depth) {
        if (depth > 3) return;
        
        var refs = currentProgram.getReferenceManager().getReferencesTo(func.getEntryPoint());
        for (var ref : refs) {
            if (ref.getReferenceType().isCall()) {
                Address fromAddr = ref.getFromAddress();
                Function caller = currentProgram.getFunctionManager().getFunctionContaining(fromAddr);
                if (caller != null && !caller.equals(func) && visitedFunctions.add(caller.getEntryPoint().toString())) {
                    results.add(String.format("  [%d] CALLER: %s @ %s (from %s)", 
                        depth, caller.getName(), caller.getEntryPoint(), fromAddr));
                    
                    disassembleAroundCaller(caller, fromAddr);
                    traceCallersRecursive(caller, depth + 1);
                }
            }
        }
    }
    
    private void disassembleAroundCaller(Function func, Address callAddr) {
        Listing listing = currentProgram.getListing();
        
        // Get instructions around the call site
        Address start = callAddr;
        for (int i = 0; i < 15; i++) {
            Instruction prev = listing.getInstructionBefore(start);
            if (prev == null) break;
            start = prev.getAddress();
        }
        
        Instruction instr = listing.getInstructionAt(start);
        int count = 0;
        while (instr != null && count < 35) {
            String marker = (instr.getAddress().equals(callAddr)) ? " >>> " : "     ";
            String mnemonic = instr.getMnemonicString().toUpperCase();
            String line = String.format("      %s%s: %s", marker, instr.getAddress(), instr);
            
            if (mnemonic.equals("BL") || mnemonic.equals("BLR") || mnemonic.equals("B")) {
                String opStr = instr.toString().toLowerCase();
                if (opStr.contains("hello") || opStr.contains("signature") || opStr.contains("serial") ||
                    opStr.contains("board") || opStr.contains("strap") || opStr.contains("write") ||
                    opStr.contains("characteristic") || opStr.contains("ble") || opStr.contains("packet") ||
                    opStr.contains("send") || opStr.contains("verify") || opStr.contains("sign") ||
                    opStr.contains("secp") || opStr.contains("ecdsa") || opStr.contains("ed25519") ||
                    opStr.contains("msg_send") || opStr.contains("objc")) {
                    line += " *** INTERESTING ***";
                }
            }
            
            if (mnemonic.equals("ADRP") || mnemonic.equals("ADRL") || mnemonic.equals("LDR")) {
                line += " [LOAD]";
            }
            
            results.add(line);
            instr = listing.getInstructionAfter(instr.getAddress());
            count++;
        }
    }
    
    private void outputResults() {
        String outputPath = "C:/Users/ribhu/kilo-test/whoop-mg-client/docs/research/hello_5802_objcmsgsend_analysis.txt";
        try (BufferedWriter writer = new BufferedWriter(new FileWriter(outputPath))) {
            writer.write("=== BINARY INFO ===\n");
            writer.write("Name: " + currentProgram.getName() + "\n");
            writer.write("SHA256: A82E252BDF11D1AB45C106F26702D1292E301B3FB6AE82D37E15E9F7CE7871B9\n");
            writer.write("Size: 209853712\n");
            writer.write("Architecture: " + currentProgram.getLanguage().toString() + "\n");
            writer.write("Image Base: " + currentProgram.getImageBase() + "\n\n");
            
            writer.write("=== OBJC_MSGSEND AND CRYPTO CALL CHAIN ANALYSIS ===\n");
            for (String s : results) writer.write(s + "\n");
            
            println("Results written to " + outputPath);
        } catch (Exception e) {
            println("Error writing results: " + e.getMessage());
        }
    }
}