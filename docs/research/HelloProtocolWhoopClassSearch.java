import ghidra.app.script.GhidraScript;
import ghidra.program.model.symbol.SymbolTable;
import ghidra.program.model.symbol.Symbol;
import ghidra.program.model.symbol.SymbolType;
import ghidra.util.task.ConsoleTaskMonitor;
import java.io.FileWriter;
import java.io.BufferedWriter;
import java.util.ArrayList;
import java.util.List;

public class HelloProtocolWhoopClassSearch extends GhidraScript {
    
    private List<String> results = new ArrayList<>();
    
    @Override
    protected void run() throws Exception {
        collectBinaryInfo();
        searchWhoopClasses();
        outputResults();
    }
    
    private void collectBinaryInfo() {
        println("Binary: " + currentProgram.getName());
        println("SHA256: A82E252BDF11D1AB45C106F26702D1292E301B3FB6AE82D37E15E9F7CE7871B9");
        println("Size: 209853712");
        println("Architecture: " + currentProgram.getLanguage().toString());
        println("Image Base: " + currentProgram.getImageBase());
    }
    
    private void searchWhoopClasses() {
        SymbolTable symTab = currentProgram.getSymbolTable();
        
        // Search for WHOOP-specific class names (from STRAP and 5.78.0 analysis)
        String[] classPatterns = {
            "WhoopBand", "WhoopDevice", "WhoopPeripheral", "WhoopManager",
            "BandLink", "BandManager", "BandConnection", "BandCommunicator",
            "PuffinDevice", "PuffinManager", "PuffinPeripheral",
            "StrapDevice", "StrapManager", "StrapPeripheral",
            "HelloPacket", "HelloResponse", "HelloRequest",
            "CommandProcessor", "CommandHandler", "CommandDelegate",
            "BleTransport", "BleCommunicator", "BleSession",
            "FirmwareUpdater", "FirmwareManager",
            "DeviceSerial", "DeviceSignature", "BoardId",
            "Rev3", "Rev4", "HelloRev",
            "ClientHello", "ServerHello",
            "Pairing", "pairing", "Handshake", "handshake",
            "Authentication", "authentication", "Challenge", "challenge"
        };
        
        for (Symbol sym : symTab.getAllSymbols(true)) {
            String name = sym.getName();
            String lowerName = name.toLowerCase();
            
            for (String pattern : classPatterns) {
                if (lowerName.contains(pattern.toLowerCase())) {
                    results.add(String.format("SYMBOL: name=%s addr=%s type=%s match=%s", 
                        name, sym.getAddress(), sym.getSymbolType(), pattern));
                }
            }
        }
        
        println("Found " + results.size() + " WHOOP class/symbol matches");
    }
    
    private void outputResults() {
        String outputPath = "C:/Users/ribhu/kilo-test/whoop-mg-client/docs/research/hello_5802_whoop_class_search.txt";
        try (BufferedWriter writer = new BufferedWriter(new FileWriter(outputPath))) {
            writer.write("=== BINARY INFO ===\n");
            writer.write("Name: " + currentProgram.getName() + "\n");
            writer.write("SHA256: A82E252BDF11D1AB45C106F26702D1292E301B3FB6AE82D37E15E9F7CE7871B9\n");
            writer.write("Size: 209853712\n");
            writer.write("Architecture: " + currentProgram.getLanguage().toString() + "\n");
            writer.write("Image Base: " + currentProgram.getImageBase() + "\n\n");
            
            writer.write("=== WHOOP CLASS/SYMBOL SEARCH ===\n");
            for (String s : results) writer.write(s + "\n");
            
            println("Results written to " + outputPath);
        } catch (Exception e) {
            println("Error writing results: " + e.getMessage());
        }
    }
}