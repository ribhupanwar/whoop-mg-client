import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionManager;
import ghidra.program.model.symbol.SymbolTable;
import ghidra.program.model.symbol.Symbol;
import ghidra.program.model.symbol.SymbolType;
import ghidra.util.task.ConsoleTaskMonitor;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileOptions;
import java.io.FileWriter;
import java.io.BufferedWriter;
import java.util.ArrayList;
import java.util.List;

public class HelloProtocolClassSearch extends GhidraScript {
    
    private List<String> results = new ArrayList<>();
    
    @Override
    protected void run() throws Exception {
        collectBinaryInfo();
        searchClassesAndMethods();
        outputResults();
    }
    
    private void collectBinaryInfo() {
        println("Binary: " + currentProgram.getName());
        println("SHA256: A82E252BDF11D1AB45C106F26702D1292E301B3FB6AE82D37E15E9F7CE7871B9");
        println("Size: 209853712");
        println("Architecture: " + currentProgram.getLanguage().toString());
        println("Image Base: " + currentProgram.getImageBase());
    }
    
    private void searchClassesAndMethods() {
        SymbolTable symTab = currentProgram.getSymbolTable();
        
        // Search for class names related to BLE, Band, Puffin, Strap, Hello
        String[] classPatterns = {
            "Band", "band", "BLE", "ble", "Bluetooth", "bluetooth",
            "Puffin", "puffin", "Strap", "strap", "Hello", "hello",
            "Device", "device", "Peripheral", "peripheral",
            "Command", "command", "Packet", "packet",
            "Rev3", "Rev4", "rev3", "rev4",
            "Handshake", "handshake", "Auth", "auth",
            "Firmware", "firmware", "Hardware", "hardware"
        };
        
        for (Symbol sym : symTab.getAllSymbols(true)) {
            String name = sym.getName();
            String lowerName = name.toLowerCase();
            
            for (String pattern : classPatterns) {
                if (lowerName.contains(pattern.toLowerCase())) {
                    if (sym.getSymbolType() == SymbolType.CLASS || 
                        sym.getSymbolType() == SymbolType.LABEL ||
                        name.contains("Class") || name.contains("Protocol") ||
                        name.contains("Protocol") || name.contains("Impl")) {
                        results.add(String.format("SYMBOL: name=%s addr=%s type=%s match=%s", 
                            name, sym.getAddress(), sym.getSymbolType(), pattern));
                    }
                }
            }
        }
        
        println("Found " + results.size() + " class/symbol matches");
    }
    
    private void outputResults() {
        String outputPath = "C:/Users/ribhu/kilo-test/whoop-mg-client/docs/research/hello_5802_class_search.txt";
        try (BufferedWriter writer = new BufferedWriter(new FileWriter(outputPath))) {
            writer.write("=== BINARY INFO ===\n");
            writer.write("Name: " + currentProgram.getName() + "\n");
            writer.write("SHA256: A82E252BDF11D1AB45C106F26702D1292E301B3FB6AE82D37E15E9F7CE7871B9\n");
            writer.write("Size: 209853712\n");
            writer.write("Architecture: " + currentProgram.getLanguage().toString() + "\n");
            writer.write("Image Base: " + currentProgram.getImageBase() + "\n\n");
            
            writer.write("=== CLASS/SYMBOL SEARCH ===\n");
            for (String s : results) writer.write(s + "\n");
            
            println("Results written to " + outputPath);
        } catch (Exception e) {
            println("Error writing results: " + e.getMessage());
        }
    }
}