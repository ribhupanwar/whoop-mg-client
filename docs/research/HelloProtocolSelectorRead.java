import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Listing;
import ghidra.program.model.address.Address;
import ghidra.program.model.mem.Memory;
import java.io.FileWriter;
import java.io.BufferedWriter;
import java.util.ArrayList;
import java.util.List;

public class HelloProtocolSelectorRead extends GhidraScript {
    
    private List<String> results = new ArrayList<>();
    
    // Selector table entries found in disassembly
    private static final long[] SELECTOR_TABLE_ENTRIES = {
        0x10b4cb618L,  // used at 0x10903b610, 0x10903b744
        0x10b4cbd98L,  // used at 0x10904b13c, 0x10904aedc, 0x10904af94
        0x10b4cc038L,  // used at 0x1090511bc
        0x10b4cc298L,  // used at 0x109074584
        0x10b4d2e98L,  // used at 0x1090745b4
    };
    
    // Known selector entries from previous analysis
    private static final long[] KNOWN_ENTRIES = {
        0x10b4cc260L, 0x10b4cc258L, 0x10b4d8b08L, 0x10b396a00L, 0x10aca74b8L
    };
    
    @Override
    protected void run() throws Exception {
        Memory mem = currentProgram.getMemory();
        Listing listing = currentProgram.getListing();
        
        results.add("=== SELECTOR TABLE ENTRY READER ===");
        results.add("Image base: " + currentProgram.getImageBase());
        
        // Read all selector table entries we found in disassembly
        results.add("\n=== ENTRIES FOUND IN DISASSEMBLY ===");
        for (long entry : SELECTOR_TABLE_ENTRIES) {
            readSelectorEntry(mem, entry);
        }
        
        // Read known entries
        results.add("\n=== KNOWN SELECTOR ENTRIES ===");
        for (long entry : KNOWN_ENTRIES) {
            readSelectorEntry(mem, entry);
        }
        
        // Also scan the selector pages for all entries
        results.add("\n=== SCANNING SELECTOR PAGES ===");
        long[] pages = {0x10b4cb000L, 0x10b4cc000L, 0x10b4d2000L, 0x10b4d8000L};
        for (long page : pages) {
            scanSelectorPage(mem, page);
        }
        
        outputResults();
    }
    
    private void readSelectorEntry(Memory mem, long entryAddr) {
        results.add(String.format("\n--- Entry @ 0x%X ---", entryAddr));
        try {
            // Read 8-byte pointer
            Address addr = toAddr(entryAddr);
            byte[] ptrBytes = new byte[8];
            int read = mem.getBytes(addr, ptrBytes);
            if (read != 8) {
                results.add("  Could not read 8 bytes");
                return;
            }
            
            long ptr = 0;
            for (int i = 0; i < 8; i++) {
                ptr |= ((long)(ptrBytes[i] & 0xFF)) << (i * 8);
            }
            results.add(String.format("  Pointer: 0x%X", ptr));
            
            // Read string at pointer
            if (ptr >= 0x100000000L && ptr < 0x110000000L) {
                Address strAddr = toAddr(ptr);
                StringBuilder sb = new StringBuilder();
                for (int i = 0; i < 256; i++) {
                    byte b = mem.getByte(strAddr.add(i));
                    if (b == 0) break;
                    if (b >= 32 && b < 127) {
                        sb.append((char)b);
                    } else {
                        sb.append(String.format("\\x%02x", b & 0xFF));
                    }
                }
                results.add(String.format("  String: \"%s\"", sb.toString()));
            } else {
                results.add("  Pointer out of range");
            }
        } catch (Exception e) {
            results.add("  Error: " + e.getMessage());
        }
    }
    
    private void scanSelectorPage(Memory mem, long pageAddr) {
        results.add(String.format("\n--- Scanning page 0x%X ---", pageAddr));
        try {
            // Read 4096 bytes (one page) as 8-byte pointers
            int count = 0;
            for (long offset = 0; offset < 0x1000; offset += 8) {
                Address addr = toAddr(pageAddr + offset);
                byte[] ptrBytes = new byte[8];
                int read = mem.getBytes(addr, ptrBytes);
                if (read != 8) continue;
                
                long ptr = 0;
                for (int i = 0; i < 8; i++) {
                    ptr |= ((long)(ptrBytes[i] & 0xFF)) << (i * 8);
                }
                
                // Check if pointer points to a valid string in __cstring
                if (ptr >= 0x109000000L && ptr < 0x10a000000L) {
                    // Read string
                    Address strAddr = toAddr(ptr);
                    StringBuilder sb = new StringBuilder();
                    boolean valid = true;
                    for (int i = 0; i < 128; i++) {
                        byte b = mem.getByte(strAddr.add(i));
                        if (b == 0) break;
                        if (b >= 32 && b < 127) {
                            sb.append((char)b);
                        } else {
                            valid = false;
                            break;
                        }
                    }
                    if (valid && sb.length() > 0 && sb.length() < 128) {
                        // Check if it looks like an ObjC selector
                        String str = sb.toString();
                        if (str.contains(":") || str.contains("Hello") || str.contains("hello") ||
                            str.contains("Packet") || str.contains("signature") || str.contains("Serial") ||
                            str.contains("board") || str.contains("strap") || str.contains("response")) {
                            results.add(String.format("  0x%X -> 0x%X: \"%s\"", pageAddr + offset, ptr, str));
                            count++;
                        }
                    }
                }
            }
            results.add(String.format("  Found %d interesting selectors in page", count));
        } catch (Exception e) {
            results.add("  Error scanning page: " + e.getMessage());
        }
    }
    
    private void outputResults() {
        String outputPath = "C:/Users/ribhu/kilo-test/whoop-mg-client/docs/research/hello_5802_selector_read.txt";
        try (BufferedWriter writer = new BufferedWriter(new FileWriter(outputPath))) {
            for (String s : results) writer.write(s + "\n");
            println("Results written to " + outputPath);
        } catch (Exception e) {
            println("Error writing results: " + e.getMessage());
        }
    }
}