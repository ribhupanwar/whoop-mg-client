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
import java.util.HashSet;
import java.util.Set;

public class HelloProtocolKeyClassDecompile extends GhidraScript {
    
    private List<String> results = new ArrayList<>();
    private Set<String> seenFunctions = new HashSet<>();
    
    @Override
    protected void run() throws Exception {
        collectBinaryInfo();
        decompileKeyClasses();
        outputResults();
    }
    
    private void collectBinaryInfo() {
        println("Binary: " + currentProgram.getName());
        println("SHA256: A82E252BDF11D1AB45C106F26702D1292E301B3FB6AE82D37E15E9F7CE7871B9");
        println("Size: 209853712");
        println("Architecture: " + currentProgram.getLanguage().toString());
        println("Image Base: " + currentProgram.getImageBase());
    }
    
    private void decompileKeyClasses() {
        FunctionManager funcMgr = currentProgram.getFunctionManager();
        DecompInterface decompiler = new DecompInterface();
        decompiler.openProgram(currentProgram);
        DecompileOptions options = new DecompileOptions();
        decompiler.setOptions(options);
        
        // Key class names from the symbol search
        String[] classPatterns = {
            "WHPBLEStrapManager",
            "PuffinDeviceSerialProvider",
            "WhoopDeviceAPIs",
            "BluetoothPairing",
            "BandLink",
            "BleTransport",
            "CommandProcessor",
            "CommandDelegate",
            "HelloPacket",
            "HelloResponse"
        };
        
        int funcCount = 0;
        for (Function func : funcMgr.getFunctions(true)) {
            String name = func.getName();
            
            for (String pattern : classPatterns) {
                if (name.contains(pattern)) {
                    String funcKey = func.getName() + "@" + func.getEntryPoint();
                    if (!seenFunctions.contains(funcKey)) {
                        seenFunctions.add(funcKey);
                        
                        try {
                            var result = decompiler.decompileFunction(func, 30, new ConsoleTaskMonitor());
                            if (result != null && result.decompileCompleted()) {
                                String decompiled = result.getDecompiledFunction().getC();
                                results.add(String.format("FUNCTION: name=%s addr=%s\n%s", 
                                    func.getName(), func.getEntryPoint(), decompiled.substring(0, Math.min(decompiled.length(), 12000))));
                                funcCount++;
                                println("Decompiled: " + func.getName() + " at " + func.getEntryPoint());
                            }
                        } catch (Exception e) {
                            results.add(String.format("FUNCTION: name=%s addr=%s - DECOMPILE ERROR: %s", 
                                func.getName(), func.getEntryPoint(), e.getMessage()));
                        }
                    }
                }
            }
        }
        
        decompiler.dispose();
        println("Decompiled " + funcCount + " functions from key classes");
    }
    
    private void outputResults() {
        String outputPath = "C:/Users/ribhu/kilo-test/whoop-mg-client/docs/research/hello_5802_keyclass_decompile.txt";
        try (BufferedWriter writer = new BufferedWriter(new FileWriter(outputPath))) {
            writer.write("=== BINARY INFO ===\n");
            writer.write("Name: " + currentProgram.getName() + "\n");
            writer.write("SHA256: A82E252BDF11D1AB45C106F26702D1292E301B3FB6AE82D37E15E9F7CE7871B9\n");
            writer.write("Size: 209853712\n");
            writer.write("Architecture: " + currentProgram.getLanguage().toString() + "\n");
            writer.write("Image Base: " + currentProgram.getImageBase() + "\n\n");
            
            writer.write("=== KEY CLASS DECOMPILATIONS ===\n");
            for (String s : results) writer.write(s + "\n\n");
            
            println("Results written to " + outputPath);
        } catch (Exception e) {
            println("Error writing results: " + e.getMessage());
        }
    }
}