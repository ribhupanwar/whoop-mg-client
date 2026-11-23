import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionManager;
import ghidra.program.model.symbol.SymbolTable;
import ghidra.program.model.symbol.Symbol;
import ghidra.util.task.ConsoleTaskMonitor;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileOptions;
import java.io.FileWriter;
import java.io.BufferedWriter;
import java.util.ArrayList;
import java.util.List;

public class HelloProtocolFunctionSearch extends GhidraScript {
    
    private List<String> results = new ArrayList<>();
    
    @Override
    protected void run() throws Exception {
        collectBinaryInfo();
        searchFunctionsByName();
        outputResults();
    }
    
    private void collectBinaryInfo() {
        println("Binary: " + currentProgram.getName());
        println("SHA256: A82E252BDF11D1AB45C106F26702D1292E301B3FB6AE82D37E15E9F7CE7871B9");
        println("Size: 209853712");
        println("Architecture: " + currentProgram.getLanguage().toString());
        println("Image Base: " + currentProgram.getImageBase());
    }
    
    private void searchFunctionsByName() {
        FunctionManager funcMgr = currentProgram.getFunctionManager();
        SymbolTable symTab = currentProgram.getSymbolTable();
        DecompInterface decompiler = new DecompInterface();
        decompiler.openProgram(currentProgram);
        DecompileOptions options = new DecompileOptions();
        decompiler.setOptions(options);
        
        // Search in function names (demangled)
        int count = 0;
        for (Function func : funcMgr.getFunctions(true)) {
            String name = func.getName();
            String lowerName = name.toLowerCase();
            
            if (lowerName.contains("hello") || lowerName.contains("handshake") ||
                lowerName.contains("pair") || lowerName.contains("clienthello") ||
                lowerName.contains("gethello") || lowerName.contains("sendhello") ||
                lowerName.contains("processcommand") || lowerName.contains("didgethello")) {
                
                try {
                    var result = decompiler.decompileFunction(func, 30, new ConsoleTaskMonitor());
                    if (result != null && result.decompileCompleted()) {
                        String decompiled = result.getDecompiledFunction().getC();
                        results.add(String.format("FUNCTION: name=%s addr=%s\n%s", 
                            name, func.getEntryPoint(), decompiled.substring(0, Math.min(decompiled.length(), 10000))));
                        count++;
                    }
                } catch (Exception e) {
                    results.add(String.format("FUNCTION: name=%s addr=%s - DECOMPILE ERROR: %s", 
                        name, func.getEntryPoint(), e.getMessage()));
                }
            }
        }
        
        // Also search in symbols for ObjC selectors
        for (Symbol sym : symTab.getAllSymbols(true)) {
            String name = sym.getName();
            String lowerName = name.toLowerCase();
            
            if (lowerName.contains("processcommanddidgethellopacket") ||
                lowerName.contains("processcommanddidgethelloinfo") ||
                lowerName.contains("sendgethellopacket") ||
                lowerName.contains("didgethellopacket") ||
                lowerName.contains("hellopacket") ||
                lowerName.contains("clienthello")) {
                
                results.add(String.format("SYMBOL: name=%s addr=%s type=%s", name, sym.getAddress(), sym.getSymbolType()));
            }
        }
        
        decompiler.dispose();
        println("Found " + count + " HELLO-related functions with decompilation");
    }
    
    private void outputResults() {
        String outputPath = "C:/Users/ribhu/kilo-test/whoop-mg-client/docs/research/hello_5802_function_search.txt";
        try (BufferedWriter writer = new BufferedWriter(new FileWriter(outputPath))) {
            writer.write("=== BINARY INFO ===\n");
            writer.write("Name: " + currentProgram.getName() + "\n");
            writer.write("SHA256: A82E252BDF11D1AB45C106F26702D1292E301B3FB6AE82D37E15E9F7CE7871B9\n");
            writer.write("Size: 209853712\n");
            writer.write("Architecture: " + currentProgram.getLanguage().toString() + "\n");
            writer.write("Image Base: " + currentProgram.getImageBase() + "\n\n");
            
            writer.write("=== FUNCTION SEARCH RESULTS ===\n");
            for (String s : results) writer.write(s + "\n\n");
            
            println("Results written to " + outputPath);
        } catch (Exception e) {
            println("Error writing results: " + e.getMessage());
        }
    }
}