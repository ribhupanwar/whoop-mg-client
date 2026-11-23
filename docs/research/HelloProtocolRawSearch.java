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

public class HelloProtocolRawSearch extends GhidraScript {
    
    private List<String> results = new ArrayList<>();
    
    @Override
    protected void run() throws Exception {
        collectBinaryInfo();
        
        // Key addresses from previous analysis (selector strings and metadata)
        String[] targetAddrs = {
            "109abaff8", // s_sendGetHelloPacketWithCompletion
            "109aae6a3", // s_processCommandDidGetHelloPacket:
            "109aae668", // s_processCommandDidGetHelloInfoWithSerial:signature:boardId:
            "109a79ff0", // s_didCallSendGetHelloPacket
            "109781892", // s_GetHelloPacket
            "109a88926", // s_helloResponse
            "109a88940", // s_helloResponseTask
            "109a2c151", // s_boardId
            "1097b1e0e", // s_strap_signature
            "1098550e4", // s_strapSerial
            "109a98a40", // s_lastConnectedStrapSerial
            "109a98a60", // s_lastConnectedStrapSignature
            "109a46aad", // s_setLastConnectedStrapSignature:
        };
        
        // Also search the data reference locations (ObjC method lists, Swift metadata)
        String[] dataRefAddrs = {
            "10b4d8b08", "10b4cc260", "10b4cc258", "10b396a00", "10aca74b8",
            "10b36ac78", "10b3524c8", "10b356eb8", "10ad1b6e0", "10ad1b718",
            "10af28510", "10b4c9f80", "10b38abe8", "10b345cb0", "10b4640a8",
            "10b402c00", "10b4c9f88", "10b38abf8", "10b345cc0", "10b4cf798"
        };
        
        // Search for BL/BLR instructions that reference these areas
        searchForCallsToRegions(targetAddrs, "selector strings");
        searchForCallsToRegions(dataRefAddrs, "data references (method lists/metadata)");
        
        // Search for specific opcodes and patterns
        searchForOpcode0x91();
        searchForCharacteristicUUIDs();
        searchForSignatureVerification();
        
        outputResults();
    }
    
    private void collectBinaryInfo() {
        println("Binary: " + currentProgram.getName());
        println("SHA256: A82E252BDF11D1AB45C106F26702D1292E301B3FB6AE82D37E15E9F7CE7871B9");
        println("Architecture: " + currentProgram.getLanguage().toString());
        println("Image Base: " + currentProgram.getImageBase());
    }
    
    private void searchForCallsToRegions(String[] addrStrs, String label) {
        results.add("\n=== SEARCHING FOR CALLS TO " + label.toUpperCase() + " ===");
        
        for (String addrStr : addrStrs) {
            try {
                Address targetAddr = currentProgram.getAddressFactory().getAddress(addrStr);
                // Search in a window around the target for BL/BLR instructions
                Address start = targetAddr.subtract(0x10000); // 64KB before
                Address end = targetAddr.add(0x10000); // 64KB after
                
                searchForBLInRange(start, end, targetAddr, addrStr);
            } catch (Exception e) {
                println("Error searching near " + addrStr + ": " + e.getMessage());
            }
        }
    }
    
    private void searchForBLInRange(Address start, Address end, Address targetAddr, String targetLabel) {
        Listing listing = currentProgram.getListing();
        Memory memory = currentProgram.getMemory();
        
        try {
            // Read bytes in chunks
            int chunkSize = 4096;
            long totalBytes = end.subtract(start);
            
            for (long offset = 0; offset < totalBytes; offset += chunkSize) {
                Address chunkStart = start.add(offset);
                Address chunkEnd = start.add(Math.min(offset + chunkSize, totalBytes));
                
                if (!memory.contains(chunkStart) || !memory.contains(chunkEnd)) continue;
                
                byte[] bytes = new byte[(int)(chunkEnd.subtract(chunkStart))];
                memory.getBytes(chunkStart, bytes);
                
                // Scan for BL/BLR opcodes (ARM64)
                // BL: 0x94000000 (with 26-bit offset)
                // BLR: 0xd63f0000 | (reg << 5)
                for (int i = 0; i < bytes.length - 3; i += 4) {
                    int instr = ((bytes[i+3] & 0xFF) << 24) | ((bytes[i+2] & 0xFF) << 16) | 
                                ((bytes[i+1] & 0xFF) << 8) | (bytes[i] & 0xFF);
                    
                    // Check for BL (unconditional branch with link)
                    if ((instr & 0xfc000000) == 0x94000000) {
                        // Extract 26-bit signed offset
                        int offset26 = instr & 0x03ffffff;
                        if ((offset26 & 0x02000000) != 0) offset26 |= 0xfc000000; // sign extend
                        long targetOffset = ((long)offset26) << 2;
                        Address callAddr = chunkStart.add(i);
                        Address target = callAddr.add(targetOffset);
                        
                        // Check if target is near our target address
                        if (target.equals(targetAddr) || 
                            (target.subtract(targetAddr) >= -16 && target.subtract(targetAddr) <= 16)) {
                            results.add(String.format("  BL at %s -> %s (near %s)", callAddr, target, targetLabel));
                            disassembleAround(callAddr);
                        }
                    }
                    // Check for BLR (branch with link to register)
                    else if ((instr & 0xfffffc1f) == 0xd63f0000) {
                        int reg = (instr >> 5) & 0x1f;
                        Address callAddr = chunkStart.add(i);
                        results.add(String.format("  BLR x%d at %s (near %s)", reg, callAddr, targetLabel));
                        disassembleAround(callAddr);
                    }
                }
            }
        } catch (Exception e) {
            results.add("  Error scanning range: " + e.getMessage());
        }
    }
    
    private void searchForOpcode0x91() {
        results.add("\n=== SEARCHING FOR OPCODE 0x91 (CLIENT_HELLO) ===");
        
        Memory memory = currentProgram.getMemory();
        Address start = currentProgram.getMinAddress();
        Address end = currentProgram.getMaxAddress();
        
        try {
            byte[] searchBytes = {(byte)0x91};
            byte[] mask = {(byte)0xFF};
            
            Address addr = start;
            int count = 0;
            while (addr != null && count < 50) {
                addr = memory.findBytes(addr, searchBytes, mask, false, new ConsoleTaskMonitor());
                if (addr != null) {
                    // Check context - is this in code?
                    Instruction instr = currentProgram.getListing().getInstructionAt(addr);
                    if (instr != null) {
                        results.add(String.format("  0x91 at %s: %s", addr, instr));
                        disassembleAround(addr);
                    } else {
                        results.add(String.format("  0x91 at %s (data)", addr));
                    }
                    addr = addr.add(1);
                    count++;
                }
            }
            if (count == 0) {
                results.add("  No 0x91 bytes found in executable memory");
            }
        } catch (Exception e) {
            results.add("  Error searching for 0x91: " + e.getMessage());
        }
    }
    
    private void searchForCharacteristicUUIDs() {
        results.add("\n=== SEARCHING FOR FD4B CHARACTERISTIC UUIDS ===");
        
        String[] uuids = {"fd4b0002", "fd4b0003", "FD4B0002", "FD4B0003"};
        
        for (String uuid : uuids) {
            try {
                byte[] bytes = uuid.getBytes();
                byte[] mask = new byte[bytes.length];
                for (int i = 0; i < mask.length; i++) mask[i] = (byte)0xFF;
                
                Address addr = currentProgram.getMinAddress();
                addr = currentProgram.getMemory().findBytes(addr, bytes, mask, false, new ConsoleTaskMonitor());
                
                if (addr != null) {
                    results.add(String.format("  UUID '%s' found at %s", uuid, addr));
                    
                    // Check references
                    var refs = currentProgram.getReferenceManager().getReferencesTo(addr);
                    for (var ref : refs) {
                        Address fromAddr = ref.getFromAddress();
                        Instruction instr = currentProgram.getListing().getInstructionAt(fromAddr);
                        if (instr != null) {
                            results.add(String.format("    Referenced from %s: %s", fromAddr, instr));
                            disassembleAround(fromAddr);
                        } else {
                            results.add(String.format("    Data reference from %s", fromAddr));
                        }
                    }
                } else {
                    results.add(String.format("  UUID '%s' not found", uuid));
                }
            } catch (Exception e) {
                results.add("  Error searching for UUID " + uuid + ": " + e.getMessage());
            }
        }
    }
    
    private void searchForSignatureVerification() {
        results.add("\n=== SEARCHING FOR SIGNATURE VERIFICATION PATTERNS ===");
        
        // Search for common crypto/verify function names
        String[] cryptoTerms = {"verify", "signature", "sign", "ecdsa", "ed25519", "secp256", 
                               "crypto", "hash", "sha256", "hmac", "authenticat"};
        
        FunctionManager funcMgr = currentProgram.getFunctionManager();
        for (Function func : funcMgr.getFunctions(true)) {
            String name = func.getName().toLowerCase();
            for (String term : cryptoTerms) {
                if (name.contains(term)) {
                    results.add(String.format("  Crypto function: %s @ %s", func.getName(), func.getEntryPoint()));
                    disassembleFunction(func.getEntryPoint());
                    break;
                }
            }
        }
        
        // Search for string references to crypto terms
        String[] cryptoStrings = {"verify", "signature", "ecdsa", "ed25519", "secp256r1"};
        for (String term : cryptoStrings) {
            try {
                byte[] bytes = term.getBytes();
                byte[] mask = new byte[bytes.length];
                for (int i = 0; i < mask.length; i++) mask[i] = (byte)0xFF;
                
                Address addr = currentProgram.getMinAddress();
                addr = currentProgram.getMemory().findBytes(addr, bytes, mask, true, new ConsoleTaskMonitor()); // case insensitive
                
                if (addr != null) {
                    results.add(String.format("  String '%s' found at %s", term, addr));
                    var refs = currentProgram.getReferenceManager().getReferencesTo(addr);
                    for (var ref : refs) {
                        Address fromAddr = ref.getFromAddress();
                        Instruction instr = currentProgram.getListing().getInstructionAt(fromAddr);
                        if (instr != null) {
                            results.add(String.format("    Referenced from %s: %s", fromAddr, instr));
                        }
                    }
                }
            } catch (Exception e) {
            }
        }
    }
    
    private void disassembleAround(Address addr) {
        Listing listing = currentProgram.getListing();
        Instruction instr = listing.getInstructionAt(addr);
        
        // Disassemble 10 instructions before and 20 after
        Address start = addr;
        for (int i = 0; i < 10; i++) {
            Instruction prev = listing.getInstructionBefore(start);
            if (prev != null) start = prev.getAddress();
            else break;
        }
        
        StringBuilder disasm = new StringBuilder();
        disasm.append(String.format("    CONTEXT around %s:\n", addr));
        
        instr = listing.getInstructionAt(start);
        int count = 0;
        while (instr != null && count < 35) {
            String marker = (instr.getAddress().equals(addr)) ? " >>> " : "     ";
            disasm.append(String.format("    %s%s: %s\n", marker, instr.getAddress(), instr));
            instr = listing.getInstructionAfter(instr.getAddress());
            count++;
        }
        
        results.add(disasm.toString());
    }
    
    private void disassembleFunction(Address entry) {
        Listing listing = currentProgram.getListing();
        Instruction instr = listing.getInstructionAt(entry);
        
        StringBuilder disasm = new StringBuilder();
        disasm.append(String.format("    FUNCTION at %s:\n", entry));
        
        int count = 0;
        while (instr != null && count < 100) {
            disasm.append(String.format("      %s: %s\n", instr.getAddress(), instr));
            instr = listing.getInstructionAfter(instr.getAddress());
            count++;
        }
        
        results.add(disasm.toString());
    }
    
    private void outputResults() {
        String outputPath = "C:/Users/ribhu/kilo-test/whoop-mg-client/docs/research/hello_5802_raw_search.txt";
        try (BufferedWriter writer = new BufferedWriter(new FileWriter(outputPath))) {
            writer.write("=== BINARY INFO ===\n");
            writer.write("Name: " + currentProgram.getName() + "\n");
            writer.write("SHA256: A82E252BDF11D1AB45C106F26702D1292E301B3FB6AE82D37E15E9F7CE7871B9\n");
            writer.write("Size: 209853712\n");
            writer.write("Architecture: " + currentProgram.getLanguage().toString() + "\n");
            writer.write("Image Base: " + currentProgram.getImageBase() + "\n\n");
            
            writer.write("=== RAW MEMORY SEARCH AND DISASSEMBLY ===\n");
            for (String s : results) writer.write(s + "\n");
            
            println("Results written to " + outputPath);
        } catch (Exception e) {
            println("Error writing results: " + e.getMessage());
        }
    }
}