import ghidra.app.script.GhidraScript;
import ghidra.program.model.symbol.SymbolTable;
import ghidra.program.model.symbol.Symbol;
import ghidra.program.model.symbol.SymbolType;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionManager;
import ghidra.program.model.listing.Listing;
import ghidra.util.task.ConsoleTaskMonitor;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileOptions;
import java.io.FileWriter;
import java.io.BufferedWriter;
import java.util.ArrayList;
import java.util.List;

public class HelloProtocolTargetedSearch extends GhidraScript {
    
    private List<String> helloSymbols = new ArrayList<>();
    private List<String> rev3Rev4 = new ArrayList<>();
    private List<String> clientHelloWrites = new ArrayList<>();
    private List<String> decompileErrors = new ArrayList<>();
    
    @Override
    protected void run() throws Exception {
        collectBinaryInfo();
        searchHelloSymbols();
        searchRev3Rev4();
        findClientHelloOpcode();
        outputResults();
    }
    
    private void collectBinaryInfo() {
        println("Binary: " + currentProgram.getName());
        println("SHA256: A82E252BDF11D1AB45C106F26702D1292E301B3FB6AE82D37E15E9F7CE7871B9");
        println("Size: 209853712");
        println("Architecture: " + currentProgram.getLanguage().toString());
        println("Image Base: " + currentProgram.getImageBase());
    }
    
    private void searchHelloSymbols() {
        SymbolTable symbolTable = currentProgram.getSymbolTable();
        String[] searchTerms = {
            "HelloPacket", "helloPacket", "HelloRev", "helloRev",
            "processCommandDidGetHelloPacket",
            "processCommandDidGetHelloInfoWithSerial",
            "sendGetHelloPacket", "getHelloPacket",
            "HelloSending", "CLIENT_HELLO", "clientHello",
            "handshake", "challenge", "signature", "boardId", "serial"
        };
        
        int count = 0;
        for (Symbol symbol : symbolTable.getAllSymbols(true)) {
            String name = symbol.getName();
            for (String term : searchTerms) {
                if (name.toLowerCase().contains(term.toLowerCase())) {
                    helloSymbols.add(String.format("SYMBOL: name=%s addr=%s type=%s match=%s", 
                        name, symbol.getAddress(), symbol.getSymbolType(), term));
                    count++;
                }
            }
        }
        println("Found " + count + " HELLO-related symbols");
    }
    
    private void searchRev3Rev4() {
        String[] searchTerms = {
            "HelloPacketRev3", "HelloPacketRev4",
            "HelloResponsePacketRev3", "HelloResponsePacketRev4",
            "HelloPacketRev", "HelloResponsePacketRev",
        };
        
        // Search symbols
        SymbolTable symbolTable = currentProgram.getSymbolTable();
        for (Symbol symbol : symbolTable.getAllSymbols(true)) {
            String name = symbol.getName();
            for (String term : searchTerms) {
                if (name.toLowerCase().contains(term.toLowerCase())) {
                    rev3Rev4.add(String.format("SYMBOL: name=%s addr=%s match=%s", 
                        name, symbol.getAddress(), term));
                }
            }
        }
        
        // Search in function names
        FunctionManager funcMgr = currentProgram.getFunctionManager();
        for (Function func : funcMgr.getFunctions(true)) {
            String name = func.getName();
            for (String term : searchTerms) {
                if (name.toLowerCase().contains(term.toLowerCase())) {
                    rev3Rev4.add(String.format("FUNCTION: name=%s addr=%s match=%s", 
                        name, func.getEntryPoint(), term));
                }
            }
        }
        
        println("Found " + rev3Rev4.size() + " Rev3/Rev4 references");
    }
    
    private void findClientHelloOpcode() {
        String[] searchTerms = {"0x91", "145", "CLIENT_HELLO", "clientHello"};
        
        // Search in function names and decompiled code
        FunctionManager funcMgr = currentProgram.getFunctionManager();
        DecompInterface decompiler = new DecompInterface();
        decompiler.openProgram(currentProgram);
        DecompileOptions options = new DecompileOptions();
        decompiler.setOptions(options);
        
        int funcCount = 0;
        for (Function func : funcMgr.getFunctions(true)) {
            String name = func.getName();
            if (name.toLowerCase().contains("hello") || name.toLowerCase().contains("handshake") ||
                name.toLowerCase().contains("pair") || name.toLowerCase().contains("client") ||
                name.toLowerCase().contains("command") || name.toLowerCase().contains("write") ||
                name.toLowerCase().contains("ble") || name.toLowerCase().contains("bluetooth")) {
                try {
                    var result = decompiler.decompileFunction(func, 30, new ConsoleTaskMonitor());
                    if (result != null && result.decompileCompleted()) {
                        String decompiled = result.getDecompiledFunction().getC();
                        for (String term : searchTerms) {
                            if (decompiled.contains(term)) {
                                clientHelloWrites.add(String.format("FUNCTION: name=%s addr=%s\ndecompiled:\n%s", 
                                    name, func.getEntryPoint(), decompiled.substring(0, Math.min(decompiled.length(), 5000))));
                                funcCount++;
                                break;
                            }
                        }
                    }
                } catch (Exception e) {
                    decompileErrors.add(name + ": " + e.getMessage());
                }
            }
        }
        
        decompiler.dispose();
        println("Found " + funcCount + " functions with CLIENT_HELLO references");
    }
    
    private void outputResults() {
        String outputPath = "C:/Users/ribhu/kilo-test/whoop-mg-client/docs/research/hello_5802_analysis.txt";
        try (BufferedWriter writer = new BufferedWriter(new FileWriter(outputPath))) {
            writer.write("=== BINARY INFO ===\n");
            writer.write("Name: " + currentProgram.getName() + "\n");
            writer.write("SHA256: A82E252BDF11D1AB45C106F26702D1292E301B3FB6AE82D37E15E9F7CE7871B9\n");
            writer.write("Size: 209853712\n");
            writer.write("Architecture: " + currentProgram.getLanguage().toString() + "\n");
            writer.write("Image Base: " + currentProgram.getImageBase() + "\n\n");
            
            writer.write("=== HELLO SYMBOLS ===\n");
            for (String s : helloSymbols) writer.write(s + "\n");
            writer.write("\n");
            
            writer.write("=== REV3/REV4 ===\n");
            for (String s : rev3Rev4) writer.write(s + "\n");
            writer.write("\n");
            
            writer.write("=== CLIENT_HELLO (0x91) WRITES ===\n");
            for (String s : clientHelloWrites) writer.write(s + "\n\n");
            writer.write("\n");
            
            writer.write("=== DECOMPILE ERRORS ===\n");
            for (String s : decompileErrors) writer.write(s + "\n");
            
            println("Results written to " + outputPath);
        } catch (Exception e) {
            println("Error writing results: " + e.getMessage());
        }
    }
}