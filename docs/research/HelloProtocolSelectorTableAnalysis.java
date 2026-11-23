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

public class HelloProtocolSelectorTableAnalysis extends GhidraScript {
    
    private List<String> results = new ArrayList<>();
    
    @Override
    protected void run() throws Exception {
        collectBinaryInfo();
        
        // The selector table entries we found - trace code that references THESE addresses
        traceCodeRefsToSelectorTable("10b4d8b08", "sendGetHelloPacketWithCompletion:");
        traceCodeRefsToSelectorTable("10b4cc260", "processCommandDidGetHelloPacket:");
        traceCodeRefsToSelectorTable("10b4cc258", "processCommandDidGetHelloInfoWithSerial:signature:boardId:");
        traceCodeRefsToSelectorTable("10b396a00", "didCallSendGetHelloPacket:");
        traceCodeRefsToSelectorTable("10aca74b8", "GetHelloPacket");
        
        // Also trace FD4B locations
        traceCodeRefsToAddress("10978f2f0", "FD4B at 10978f2f0");
        traceCodeRefsToAddress("1099f51ed", "B4FD at 1099f51ed");
        
        // Search for objc_msgSend calls and trace their arguments
        searchForObjcMsgSend();
        
        outputResults();
    }
    
    private void collectBinaryInfo() {
        println("Binary: " + currentProgram.getName());
    }
    
    private void traceCodeRefsToSelectorTable(String addrStr, String selectorName) {
        results.add("\n=== TRACING CODE REFS TO SELECTOR TABLE ENTRY: " + selectorName + " @ " + addrStr + " ===");
        
        try {
            Address addr = currentProgram.getAddressFactory().getAddress(addrStr);
            var refs = currentProgram.getReferenceManager().getReferencesTo(addr);
            
            boolean foundCodeRef = false;
            for (var ref : refs) {
                Address fromAddr = ref.getFromAddress();
                Instruction instr = currentProgram.getListing().getInstructionAt(fromAddr);
                if (instr != null) {
                    foundCodeRef = true;
                    results.add(String.format("  Code ref from %s: %s", fromAddr, instr));
                    disassembleAround(fromAddr, selectorName, 20);
                    traceFunctionContaining(fromAddr, selectorName, 0);
                }
            }
            
            if (!foundCodeRef) {
                results.add("  No code references found (only data refs)");
            }
        } catch (Exception e) {
            results.add("  Error: " + e.getMessage());
        }
    }
    
    private void traceCodeRefsToAddress(String addrStr, String context) {
        results.add("\n=== TRACING CODE REFS TO: " + context + " @ " + addrStr + " ===");
        
        try {
            Address addr = currentProgram.getAddressFactory().getAddress(addrStr);
            var refs = currentProgram.getReferenceManager().getReferencesTo(addr);
            
            boolean foundCodeRef = false;
            for (var ref : refs) {
                Address fromAddr = ref.getFromAddress();
                Instruction instr = currentProgram.getListing().getInstructionAt(fromAddr);
                if (instr != null) {
                    foundCodeRef = true;
                    results.add(String.format("  Code ref from %s: %s", fromAddr, instr));
                    disassembleAround(fromAddr, context, 15);
                    traceFunctionContaining(fromAddr, context, 0);
                }
            }
            
            if (!foundCodeRef) {
                results.add("  No code references found");
            }
        } catch (Exception e) {
            results.add("  Error: " + e.getMessage());
        }
    }
    
    private void searchForObjcMsgSend() {
        results.add("\n=== SEARCHING FOR objc_msgSend CALLS ===");
        
        // objc_msgSend is typically imported from libobjc.A.dylib
        // Search for BL/BLR to objc_msgSend
        try {
            String[] patterns = {"objc_msgSend", "_objc_msgSend", "objc_msgSendSuper"};
            
            for (String pattern : patterns) {
                byte[] bytes = pattern.getBytes();
                byte[] mask = new byte[bytes.length];
                for (int i = 0; i < mask.length; i++) mask[i] = (byte)0xFF;
                
                Address addr = currentProgram.getMinAddress();
                addr = currentProgram.getMemory().findBytes(addr, bytes, mask, false, new ConsoleTaskMonitor());
                
                if (addr != null) {
                    results.add(String.format("  Symbol '%s' found at %s", pattern, addr));
                    var refs = currentProgram.getReferenceManager().getReferencesTo(addr);
                    for (var ref : refs) {
                        if (ref.getReferenceType().isCall()) {
                            Address fromAddr = ref.getFromAddress();
                            Instruction instr = currentProgram.getListing().getInstructionAt(fromAddr);
                            if (instr != null) {
                                results.add(String.format("    Call to objc_msgSend from %s: %s", fromAddr, instr));
                                disassembleAround(fromAddr, "objc_msgSend", 20);
                            }
                        }
                    }
                }
            }
        } catch (Exception e) {
            results.add("  Error searching for objc_msgSend: " + e.getMessage());
        }
    }
    
    private void traceFunctionContaining(Address addr, String context, int depth) {
        if (depth > 3) return;
        
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
    
    private void disassembleAround(Address addr, String context, int numInstr) {
        Listing listing = currentProgram.getListing();
        
        Address start = addr;
        for (int i = 0; i < 10; i++) {
            Instruction prev = listing.getInstructionBefore(start);
            if (prev != null) start = prev.getAddress();
            else break;
        }
        
        Instruction instr = listing.getInstructionAt(start);
        int count = 0;
        while (instr != null && count < numInstr) {
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
                    opStr.contains("secsignature") || opStr.contains("seckey") || opStr.contains("crypto") ||
                    opStr.contains("msg_send") || opStr.contains("objc")) {
                    line += " *** INTERESTING ***";
                }
            }
            
            // Highlight ADRP/ADRL/LDR which load addresses
            if (mnemonic.equals("ADRP") || mnemonic.equals("ADRL") || mnemonic.equals("LDR")) {
                line += " [LOAD]";
            }
            
            results.add(line);
            instr = listing.getInstructionAfter(instr.getAddress());
            count++;
        }
    }
    
    private void outputResults() {
        String outputPath = "C:/Users/ribhu/kilo-test/whoop-mg-client/docs/research/hello_5802_selectortable_analysis.txt";
        try (BufferedWriter writer = new BufferedWriter(new FileWriter(outputPath))) {
            writer.write("=== BINARY INFO ===\n");
            writer.write("Name: " + currentProgram.getName() + "\n");
            writer.write("SHA256: A82E252BDF11D1AB45C106F26702D1292E301B3FB6AE82D37E15E9F7CE7871B9\n");
            writer.write("Size: 209853712\n");
            writer.write("Architecture: " + currentProgram.getLanguage().toString() + "\n");
            writer.write("Image Base: " + currentProgram.getImageBase() + "\n\n");
            
            writer.write("=== SELECTOR TABLE AND OBJC_MSGSEND ANALYSIS ===\n");
            for (String s : results) writer.write(s + "\n");
            
            println("Results written to " + outputPath);
        } catch (Exception e) {
            println("Error writing results: " + e.getMessage());
        }
    }
}