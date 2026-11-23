import ghidra.app.script.GhidraScript;
import ghidra.program.model.symbol.SymbolTable;
import ghidra.program.model.symbol.Symbol;
import ghidra.program.model.symbol.SymbolType;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionManager;
import ghidra.util.task.ConsoleTaskMonitor;
import java.io.FileWriter;
import java.io.BufferedWriter;
import java.util.ArrayList;
import java.util.List;

public class HelloProtocolTargetedSearchSimple extends GhidraScript {
    
    private List<String> helloSymbols = new ArrayList<>();
    private List<String> rev3Rev4 = new ArrayList<>();
    private List<String> clientHelloFunctions = new ArrayList<>();
    
    @Override
    protected void run() throws Exception {
        collectBinaryInfo();
        searchHelloSymbols();
        searchRev3Rev4();
        findHelloFunctions();
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
    
    private void findHelloFunctions() {
        FunctionManager funcMgr = currentProgram.getFunctionManager();
        
        int funcCount = 0;
        for (Function func : funcMgr.getFunctions(true)) {
            String name = func.getName().toLowerCase();
            if (name.contains("hello") || name.contains("handshake") ||
                name.contains("pair") || name.contains("client") ||
                name.contains("command") || name.contains("write") ||
                name.contains("ble") || name.contains("bluetooth") ||
                name.contains("auth") || name.contains("challenge") ||
                name.contains("signature") || name.contains("serial")) {
                clientHelloFunctions.add(String.format("FUNCTION: name=%s addr=%s", 
                    func.getName(), func.getEntryPoint()));
                funcCount++;
            }
        }
        
        println("Found " + funcCount + " HELLO-related functions");
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
            
            writer.write("=== HELLO-RELATED FUNCTIONS ===\n");
            for (String s : clientHelloFunctions) writer.write(s + "\n");
            writer.write("\n");
            
            println("Results written to " + outputPath);
        } catch (Exception e) {
            println("Error writing results: " + e.getMessage());
        }
    }
}