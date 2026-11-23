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

public class HelloProtocolDisassemblyTrace extends GhidraScript {
    
    private List<String> results = new ArrayList<>();
    private Set<String> seenFunctions = new HashSet<>();
    
    @Override
    protected void run() throws Exception {
        collectBinaryInfo();
        traceHelloSelectors();
        traceStringReferences();
        traceHelloResponseStrings();
        traceCoreBluetoothWrites();
        outputResults();
    }
    
    private void collectBinaryInfo() {
        println("Binary: " + currentProgram.getName());
        println("SHA256: A82E252BDF11D1AB45C106F26702D1292E301B3FB6AE82D37E15E9F7CE7871B9");
        println("Size: 209853712");
        println("Architecture: " + currentProgram.getLanguage().toString());
        println("Image Base: " + currentProgram.getImageBase());
    }
    
    private void traceHelloSelectors() {
        String[] selectorAddrs = {
            "109abaff8", // s_sendGetHelloPacketWithCompletion
            "109aae6a3", // s_processCommandDidGetHelloPacket:
            "109aae668", // s_processCommandDidGetHelloInfoWithSerial:signature:boardId: (truncated)
            "109a79ff0", // s_didCallSendGetHelloPacket
            "109781892", // s_GetHelloPacket
        };
        
        for (String addrStr : selectorAddrs) {
            try {
                Address addr = currentProgram.getAddressFactory().getAddress(addrStr);
                traceReferencesToString(addr, addrStr);
            } catch (Exception e) {
                println("Error processing selector at " + addrStr + ": " + e.getMessage());
            }
        }
    }
    
    private void traceStringReferences() {
        String[] stringAddrs = {
            "109a88926", // s_helloResponse
            "109a88940", // s_helloResponseTask
            "109a2c151", // s_boardId
            "1097b1e0e", // s_strap_signature
            "1098550e4", // s_strapSerial
            "109a98a40", // s_lastConnectedStrapSerial
            "109a98a60", // s_lastConnectedStrapSignature
            "109a46aad", // s_setLastConnectedStrapSignature:
        };
        
        for (String addrStr : stringAddrs) {
            try {
                Address addr = currentProgram.getAddressFactory().getAddress(addrStr);
                traceReferencesToString(addr, addrStr);
            } catch (Exception e) {
                println("Error processing string at " + addrStr + ": " + e.getMessage());
            }
        }
    }
    
    private void traceHelloResponseStrings() {
        String[] addrs = {"109a88926", "109a88940"};
        
        for (String addrStr : addrs) {
            try {
                Address addr = currentProgram.getAddressFactory().getAddress(addrStr);
                var refs = currentProgram.getReferenceManager().getReferencesTo(addr);
                
                for (var ref : refs) {
                    Address fromAddr = ref.getFromAddress();
                    Function func = currentProgram.getFunctionManager().getFunctionContaining(fromAddr);
                    if (func != null) {
                        String key = func.getName() + "@" + func.getEntryPoint();
                        if (!seenFunctions.contains(key)) {
                            seenFunctions.add(key);
                            disassembleFunction(func, "references " + addrStr);
                        }
                    }
                }
            } catch (Exception e) {
                println("Error tracing helloResponse at " + addrStr + ": " + e.getMessage());
            }
        }
    }
    
    private void traceCoreBluetoothWrites() {
        FunctionManager funcMgr = currentProgram.getFunctionManager();
        
        for (Function func : funcMgr.getFunctions(true)) {
            String name = func.getName().toLowerCase();
            if (name.contains("writevalue") || (name.contains("write") && 
                (name.contains("characteristic") || name.contains("ble") || name.contains("peripheral")))) {
                
                String key = func.getName() + "@" + func.getEntryPoint();
                if (!seenFunctions.contains(key)) {
                    seenFunctions.add(key);
                    disassembleFunction(func, "CoreBluetooth write candidate");
                }
            }
        }
        
        String[] charUUIDs = {"fd4b0002", "fd4b0003", "FD4B0002", "FD4B0003"};
        for (String uuid : charUUIDs) {
            byte[] bytes = uuid.getBytes();
            byte[] mask = new byte[bytes.length];
            for (int i = 0; i < mask.length; i++) mask[i] = (byte)0xFF;
            
            Address addr = currentProgram.getMinAddress();
            try {
                addr = currentProgram.getMemory().findBytes(addr, bytes, mask, false, new ConsoleTaskMonitor());
                if (addr != null) {
                    results.add(String.format("CHARACTERISTIC UUID '%s' found at %s", uuid, addr));
                    var refs = currentProgram.getReferenceManager().getReferencesTo(addr);
                    for (var ref : refs) {
                        Function func = currentProgram.getFunctionManager().getFunctionContaining(ref.getFromAddress());
                        if (func != null) {
                            String key = func.getName() + "@" + func.getEntryPoint();
                            if (!seenFunctions.contains(key)) {
                                seenFunctions.add(key);
                                disassembleFunction(func, "references characteristic UUID " + uuid);
                            }
                        }
                    }
                }
            } catch (Exception e) {
            }
        }
    }
    
    private void traceReferencesToString(Address stringAddr, String context) {
        var refs = currentProgram.getReferenceManager().getReferencesTo(stringAddr);
        
        if (refs.hasNext()) {
            results.add(String.format("\n=== References to string at %s (%s) ===", stringAddr, context));
            
            for (var ref : refs) {
                Address fromAddr = ref.getFromAddress();
                Function func = currentProgram.getFunctionManager().getFunctionContaining(fromAddr);
                
                if (func != null) {
                    String key = func.getName() + "@" + func.getEntryPoint();
                    if (!seenFunctions.contains(key)) {
                        seenFunctions.add(key);
                        disassembleFunction(func, "references string at " + stringAddr);
                    }
                } else {
                    results.add(String.format("  Data reference from %s (type: %s)", fromAddr, ref.getReferenceType()));
                }
            }
        } else {
            results.add(String.format("\n=== No references to string at %s (%s) ===", stringAddr, context));
        }
    }
    
    private void disassembleFunction(Function func, String context) {
        Listing listing = currentProgram.getListing();
        Address entry = func.getEntryPoint();
        Address end = func.getBody().getMaxAddress();
        
        StringBuilder disasm = new StringBuilder();
        disasm.append(String.format("\n--- FUNCTION: %s @ %s (%s) ---\n", func.getName(), entry, context));
        disasm.append(String.format("  Address range: %s - %s\n", entry, end));
        disasm.append(String.format("  Size: %d bytes\n", end.subtract(entry) + 1));
        
        Instruction instr = listing.getInstructionAt(entry);
        int instrCount = 0;
        while (instr != null && instrCount < 200) {
            String instrStr = String.format("  %s: %s", instr.getAddress(), instr.toString());
            disasm.append(instrStr).append("\n");
            
            String mnemonic = instr.getMnemonicString().toUpperCase();
            if (mnemonic.equals("BL") || mnemonic.equals("BLR") || mnemonic.equals("B") || 
                mnemonic.equals("CBZ") || mnemonic.equals("CBNZ") || mnemonic.equals("TBZ") || mnemonic.equals("TBNZ") ||
                mnemonic.equals("LDR") || mnemonic.equals("STR") || mnemonic.equals("ADRP") || mnemonic.equals("ADD")) {
                String opStr = instr.toString().toLowerCase();
                if (opStr.contains("0x91") || opStr.contains("fd4b") || opStr.contains("hello") ||
                    opStr.contains("signature") || opStr.contains("serial") || opStr.contains("board")) {
                    disasm.append("    *** INTERESTING ***\n");
                }
            }
            
            instr = listing.getInstructionAfter(instr.getAddress());
            instrCount++;
        }
        
        if (instrCount >= 200) {
            disasm.append(String.format("  ... (%d more instructions truncated)\n", 
                (int)((end.subtract(entry) + 1) / 4) - 200));
        }
        
        // Get cross-references FROM this function - use simpler approach
        try {
            var refsFrom = currentProgram.getReferenceManager().getReferencesFrom(entry);
            List<String> calls = new ArrayList<>();
            for (var ref : refsFrom) {
                if (ref.getReferenceType().isCall()) {
                    Address toAddr = ref.getToAddress();
                    Function calledFunc = currentProgram.getFunctionManager().getFunctionAt(toAddr);
                    if (calledFunc != null) {
                        calls.add(String.format("    CALL -> %s @ %s", calledFunc.getName(), toAddr));
                    } else {
                        calls.add(String.format("    CALL -> %s (no function)", toAddr));
                    }
                }
            }
            
            if (!calls.isEmpty()) {
                disasm.append("  CALLS FROM THIS FUNCTION:\n");
                for (String call : calls) disasm.append(call).append("\n");
            }
        } catch (Exception e) {
            disasm.append("  CALLS: error getting references - " + e.getMessage() + "\n");
        }
        
        results.add(disasm.toString());
        println("Disassembled: " + func.getName() + " at " + entry);
    }
    
    private void outputResults() {
        String outputPath = "C:/Users/ribhu/kilo-test/whoop-mg-client/docs/research/hello_5802_disassembly_trace.txt";
        try (BufferedWriter writer = new BufferedWriter(new FileWriter(outputPath))) {
            writer.write("=== BINARY INFO ===\n");
            writer.write("Name: " + currentProgram.getName() + "\n");
            writer.write("SHA256: A82E252BDF11D1AB45C106F26702D1292E301B3FB6AE82D37E15E9F7CE7871B9\n");
            writer.write("Size: 209853712\n");
            writer.write("Architecture: " + currentProgram.getLanguage().toString() + "\n");
            writer.write("Image Base: " + currentProgram.getImageBase() + "\n\n");
            
            writer.write("=== DISASSEMBLY AND CROSS-REFERENCE TRACE ===\n");
            for (String s : results) writer.write(s + "\n");
            
            println("Results written to " + outputPath);
        } catch (Exception e) {
            println("Error writing results: " + e.getMessage());
        }
    }
}