import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Listing;
import ghidra.program.model.address.Address;
import ghidra.program.model.mem.Memory;
import java.io.FileWriter;
import java.io.BufferedWriter;
import java.util.ArrayList;
import java.util.List;

public class HelloProtocolFD4BSearch extends GhidraScript {
    
    private List<String> results = new ArrayList<>();
    
    @Override
    protected void run() throws Exception {
        Memory mem = currentProgram.getMemory();
        
        results.add("=== FD4B UUID SEARCH ===");
        
        // Search for FD4B pattern
        byte[] pattern1 = {(byte)0xFD, (byte)0x4B};
        byte[] pattern2 = {(byte)0x4B, (byte)0xFD};
        byte[] mask = {(byte)0xFF, (byte)0xFF};
        
        Address addr = currentProgram.getMinAddress();
        int count = 0;
        while (true) {
            Address found = mem.findBytes(addr, pattern1, mask, false, new ghidra.util.task.ConsoleTaskMonitor());
            if (found == null) break;
            results.add(String.format("  FD4B found at %s", found));
            addr = found.add(1);
            count++;
            if (count > 50) break;
        }
        
        addr = currentProgram.getMinAddress();
        count = 0;
        while (true) {
            Address found = mem.findBytes(addr, pattern2, mask, false, new ghidra.util.task.ConsoleTaskMonitor());
            if (found == null) break;
            results.add(String.format("  4BFD found at %s", found));
            addr = found.add(1);
            count++;
            if (count > 50) break;
        }
        
        // Also search for "fd4b" string
        byte[] strBytes = "fd4b".getBytes();
        byte[] strMask = new byte[strBytes.length];
        for (int i = 0; i < strMask.length; i++) strMask[i] = (byte)0xFF;
        
        addr = currentProgram.getMinAddress();
        count = 0;
        while (true) {
            Address found = mem.findBytes(addr, strBytes, strMask, false, new ghidra.util.task.ConsoleTaskMonitor());
            if (found == null) break;
            results.add(String.format("  'fd4b' string found at %s", found));
            addr = found.add(1);
            count++;
            if (count > 50) break;
        }
        
        // Search for "FD4B" string
        byte[] strBytes2 = "FD4B".getBytes();
        byte[] strMask2 = new byte[strBytes2.length];
        for (int i = 0; i < strMask2.length; i++) strMask2[i] = (byte)0xFF;
        
        addr = currentProgram.getMinAddress();
        count = 0;
        while (true) {
            Address found = mem.findBytes(addr, strBytes2, strMask2, false, new ghidra.util.task.ConsoleTaskMonitor());
            if (found == null) break;
            results.add(String.format("  'FD4B' string found at %s", found));
            addr = found.add(1);
            count++;
            if (count > 50) break;
        }
        
        outputResults();
    }
    
    private void outputResults() {
        String outputPath = "C:/Users/ribhu/kilo-test/whoop-mg-client/docs/research/hello_5802_fd4b_search.txt";
        try (BufferedWriter writer = new BufferedWriter(new FileWriter(outputPath))) {
            for (String s : results) writer.write(s + "\n");
            println("Results written to " + outputPath);
        } catch (Exception e) {
            println("Error writing results: " + e.getMessage());
        }
    }
}