# Ghidra Headless Analysis Script for WHOOP 5.80.2 HELLO Protocol - Targeted Search
# Run with: analyzeHeadless.bat <project_dir> <project_name> -import <binary> -scriptPath <script_dir> -postScript <script_name> -noanalysis

from ghidra.app.script import GhidraScript
from ghidra.program.model.symbol import SymbolType
from ghidra.program.model.address import Address
from ghidra.program.model.listing import Function
from ghidra.util.task import ConsoleTaskMonitor
from ghidra.app.decompiler import DecompInterface
from ghidra.app.decompiler import DecompileOptions
from ghidra.program.model.mem import MemoryAccessException
import json
import os

class HelloProtocolTargetedSearch(GhidraScript):
    def __init__(self):
        super().__init__()
        self.results = {
            "binary_info": {},
            "hello_symbols": [],
            "hello_strings": [],
            "hello_functions": [],
            "rev3_rev4": [],
            "client_hello_writes": [],
            "decompile_errors": [],
        }
    
    def run(self):
        self.collect_binary_info()
        self.search_hello_symbols()
        self.search_hello_strings()
        self.search_rev3_rev4()
        self.find_client_hello_opcode()
        self.output_results()
    
    def collect_binary_info(self):
        self.results["binary_info"] = {
            "name": currentProgram.getName(),
            "sha256": "A82E252BDF11D1AB45C106F26702D1292E301B3FB6AE82D37E15E9F7CE7871B9",
            "size": 209853712,
            "architecture": currentProgram.getLanguage().toString(),
            "image_base": str(currentProgram.getImageBase()),
            "entry_point": str(currentProgram.getEntryPoint()) if currentProgram.getEntryPoint() else "N/A",
        }
        println("Binary info collected")
    
    def search_hello_symbols(self):
        """Search for HELLO-related symbols in the symbol table"""
        symbol_table = currentProgram.getSymbolTable()
        search_terms = [
            "HelloPacket", "helloPacket", "HelloRev", "helloRev",
            "processCommandDidGetHelloPacket",
            "processCommandDidGetHelloInfoWithSerial",
            "sendGetHelloPacket", "getHelloPacket",
            "HelloSending", "CLIENT_HELLO", "clientHello",
            "handshake", "challenge", "signature", "boardId", "serial"
        ]
        
        count = 0
        for symbol in symbol_table.getAllSymbols(True):
            name = symbol.getName()
            for term in search_terms:
                if term.lower() in name.lower():
                    self.results["hello_symbols"].append({
                        "name": name,
                        "address": str(symbol.getAddress()),
                        "type": symbol.getSymbolType().toString(),
                        "matched_term": term
                    })
                    count += 1
        println(f"Found {count} HELLO-related symbols")
    
    def search_hello_strings(self):
        """Search for HELLO-related strings in the string table"""
        search_terms = [
            "HelloPacket", "helloPacket", "HelloRev", "helloRev",
            "CLIENT_HELLO", "clientHello", "handshake",
            "challenge", "signature", "boardId", "serial",
            "pairing", "HelloSending", "sendGetHelloPacket"
        ]
        
        listing = currentProgram.getListing()
        string_iter = listing.getDefinedStrings(True)
        
        count = 0
        for string in string_iter:
            value = string.getValue()
            for term in search_terms:
                if term.lower() in value.lower():
                    self.results["hello_strings"].append({
                        "value": value,
                        "address": str(string.getAddress()),
                        "length": string.getLength(),
                        "matched_term": term
                    })
                    count += 1
        println(f"Found {count} HELLO-related strings")
    
    def search_rev3_rev4(self):
        """Search for HelloPacketRev3/Rev4 specifically"""
        search_terms = [
            "HelloPacketRev3", "HelloPacketRev4",
            "HelloResponsePacketRev3", "HelloResponsePacketRev4",
            "HelloPacketRev", "HelloResponsePacketRev",
        ]
        
        # Search symbols
        symbol_table = currentProgram.getSymbolTable()
        for symbol in symbol_table.getAllSymbols(True):
            name = symbol.getName()
            for term in search_terms:
                if term.lower() in name.lower():
                    self.results["rev3_rev4"].append({
                        "type": "symbol",
                        "name": name,
                        "address": str(symbol.getAddress()),
                        "matched_term": term
                    })
        
        # Search strings
        listing = currentProgram.getListing()
        string_iter = listing.getDefinedStrings(True)
        for string in string_iter:
            value = string.getValue()
            for term in search_terms:
                if term.lower() in value.lower():
                    self.results["rev3_rev4"].append({
                        "type": "string",
                        "value": value,
                        "address": str(string.getAddress()),
                        "matched_term": term
                    })
        
        # Search in function names
        function_manager = currentProgram.getFunctionManager()
        functions = function_manager.getFunctions(True)
        for func in functions:
            name = func.getName()
            for term in search_terms:
                if term.lower() in name.lower():
                    self.results["rev3_rev4"].append({
                        "type": "function",
                        "name": name,
                        "address": str(func.getEntryPoint()),
                        "matched_term": term
                    })
        
        println(f"Found {len(self.results['rev3_rev4'])} Rev3/Rev4 references")
    
    def find_client_hello_opcode(self):
        """Search for CLIENT_HELLO opcode 0x91 in the binary"""
        # Search for the byte pattern 0x91 in instructions
        byte_pattern = [0x91]
        
        # Also search for "0x91" in strings and decompiled code
        search_terms = ["0x91", "145", "CLIENT_HELLO", "clientHello", "0x91"]
        
        # Search in strings
        listing = currentProgram.getListing()
        string_iter = listing.getDefinedStrings(True)
        for string in string_iter:
            value = string.getValue()
            for term in search_terms:
                if term in value:
                    self.results["client_hello_writes"].append({
                        "type": "string",
                        "value": value,
                        "address": str(string.getAddress()),
                        "matched_term": term
                    })
        
        # Search in function names and decompiled code
        function_manager = currentProgram.getFunctionManager()
        functions = function_manager.getFunctions(True)
        
        decompiler = DecompInterface()
        decompiler.openProgram(currentProgram)
        options = DecompileOptions()
        decompiler.setOptions(options)
        
        func_count = 0
        for func in functions:
            try:
                name = func.getName()
                # Quick filter by function name
                if any(term.lower() in name.lower() for term in ["hello", "handshake", "pair", "client", "command", "write", "ble", "bluetooth"]):
                    result = decompiler.decompileFunction(func, 30, ConsoleTaskMonitor())
                    if result and result.decompileCompleted():
                        decompiled = result.getDecompiledFunction().getC()
                        if any(term in decompiled for term in ["0x91", "145", "CLIENT_HELLO", "clientHello"]):
                            self.results["client_hello_writes"].append({
                                "type": "function",
                                "name": name,
                                "address": str(func.getEntryPoint()),
                                "decompiled_excerpt": decompiled[:5000]
                            })
                            func_count += 1
            except Exception as e:
                self.results["decompile_errors"].append({
                    "function": func.getName() if 'func' in locals() else "unknown",
                    "error": str(e)
                })
        
        decompiler.dispose()
        println(f"Found {func_count} functions with CLIENT_HELLO references")
    
    def output_results(self):
        """Output results to JSON file"""
        output_path = "C:/Users/ribhu/kilo-test/whoop-mg-client/docs/research/hello_5802_analysis.json"
        with open(output_path, 'w') as f:
            json.dump(self.results, f, indent=2)
        println(f"Results written to {output_path}")

# Run the script
script = HelloProtocolTargetedSearch()
script.run()