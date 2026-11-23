# Ghidra Headless Analysis Script for WHOOP 5.80.2 HELLO Protocol
# Run with: analyzeHeadless.bat <project_dir> <project_name> -import <binary> -scriptPath <script_dir> -postScript <script_name>

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

class HelloProtocolAnalysis(GhidraScript):
    def __init__(self):
        super().__init__()
        self.results = {
            "binary_info": {},
            "hello_functions": [],
            "hello_symbols": [],
            "hello_strings": [],
            "hello_xrefs": [],
            "packet_construction": [],
            "response_parsing": [],
            "rev3_rev4": [],
            "client_hello_writes": [],
        }
    
    def run(self):
        self.collect_binary_info()
        self.search_hello_symbols()
        self.search_hello_strings()
        self.analyze_hello_functions()
        self.trace_client_hello_writes()
        self.search_rev3_rev4()
        self.output_results()
    
    def collect_binary_info(self):
        self.results["binary_info"] = {
            "name": currentProgram.getName(),
            "sha256": "A82E252BDF11D1AB45C106F26702D1292E301B3FB6AE82D37E15E9F7CE7871B9",
            "size": 209853712,
            "architecture": currentProgram.getLanguage().toString(),
            "image_base": str(currentProgram.getImageBase()),
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
        println(f"Found {len(self.results['hello_symbols'])} HELLO-related symbols")
    
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
        println(f"Found {len(self.results['hello_strings'])} HELLO-related strings")
    
    def analyze_hello_functions(self):
        """Decompile and analyze HELLO-related functions"""
        function_manager = currentProgram.getFunctionManager()
        functions = function_manager.getFunctions(True)
        
        target_functions = [
            "processCommandDidGetHelloPacket",
            "processCommandDidGetHelloInfoWithSerial",
        ]
        
        decompiler = DecompInterface()
        decompiler.openProgram(currentProgram)
        options = DecompileOptions()
        decompiler.setOptions(options)
        
        for func in functions:
            name = func.getName()
            for target in target_functions:
                if target in name:
                    println(f"Analyzing function: {name} at {func.getEntryPoint()}")
                    self.decompile_and_analyze(decompiler, func, name, target)
        
        decompiler.dispose()
    
    def decompile_and_analyze(self, decompiler, func, name, target_type):
        """Decompile a function and extract key information"""
        try:
            result = decompiler.decompileFunction(func, 60, ConsoleTaskMonitor())
            if result and result.decompileCompleted():
                decompiled = result.getDecompiledFunction().getC()
                
                # Extract cross-references
                xrefs = []
                for ref in func.getEntryPoint().getReferencesFrom():
                    xrefs.append({
                        "from": str(ref.getFromAddress()),
                        "to": str(ref.getToAddress()),
                        "type": ref.getReferenceType().toString()
                    })
                
                # Extract called functions
                called_funcs = []
                for called in func.getCalledFunctions(ConsoleTaskMonitor()):
                    called_funcs.append({
                        "name": called.getName(),
                        "address": str(called.getEntryPoint())
                    })
                
                # Extract constants
                constants = self.extract_constants(decompiled)
                
                func_info = {
                    "name": name,
                    "address": str(func.getEntryPoint()),
                    "target_type": target_type,
                    "decompiled": decompiled[:10000],  # Limit size
                    "xrefs": xrefs,
                    "called_functions": called_funcs,
                    "constants": constants,
                }
                
                if "processCommandDidGetHelloPacket" in target_type:
                    self.results["response_parsing"].append(func_info)
                elif "processCommandDidGetHelloInfoWithSerial" in target_type:
                    self.results["response_parsing"].append(func_info)
                
        except Exception as e:
            println(f"Error decompiling {name}: {e}")
    
    def extract_constants(self, decompiled_code):
        """Extract numeric constants from decompiled code"""
        import re
        constants = []
        # Look for hex constants
        hex_matches = re.findall(r'0x[0-9a-fA-F]+', decompiled_code)
        for match in hex_matches:
            try:
                val = int(match, 16)
                if val > 0x10:  # Filter out small values
                    constants.append(match)
            except:
                pass
        # Look for decimal constants
        dec_matches = re.findall(r'\b\d{3,}\b', decompiled_code)
        for match in dec_matches:
            constants.append(match)
        return list(set(constants))
    
    def trace_client_hello_writes(self):
        """Find all writes of CLIENT_HELLO (0x91) opcode"""
        search_terms = ["0x91", "145", "CLIENT_HELLO", "clientHello"]
        
        listing = currentProgram.getListing()
        string_iter = listing.getDefinedStrings(True)
        
        # Also search in decompiled code for opcode 0x91
        function_manager = currentProgram.getFunctionManager()
        functions = function_manager.getFunctions(True)
        
        decompiler = DecompInterface()
        decompiler.openProgram(currentProgram)
        options = DecompileOptions()
        decompiler.setOptions(options)
        
        for func in functions:
            try:
                result = decompiler.decompileFunction(func, 30, ConsoleTaskMonitor())
                if result and result.decompileCompleted():
                    decompiled = result.getDecompiledFunction().getC()
                    if "0x91" in decompiled or "145" in decompiled or "CLIENT_HELLO" in decompiled:
                        # Check if this function writes to BLE
                        if any(term in decompiled for term in ["writeValue", "writeCharacteristic", "fd4b0002", "commandTo", "enqueue"]):
                            self.results["client_hello_writes"].append({
                                "function": func.getName(),
                                "address": str(func.getEntryPoint()),
                                "decompiled_excerpt": decompiled[:5000]
                            })
            except:
                pass
        
        decompiler.dispose()
        println(f"Found {len(self.results['client_hello_writes'])} CLIENT_HELLO write sites")
    
    def search_rev3_rev4(self):
        """Search for HelloPacketRev3/Rev4 specifically"""
        search_terms = [
            "HelloPacketRev3", "HelloPacketRev4",
            "HelloResponsePacketRev3", "HelloResponsePacketRev4",
            "HelloPacketRev", "HelloResponsePacketRev",
            "Rev3", "Rev4"
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
    
    def output_results(self):
        """Output results to JSON file"""
        output_path = "C:/Users/ribhu/kilo-test/whoop-mg-client/docs/research/hello_5802_analysis.json"
        with open(output_path, 'w') as f:
            json.dump(self.results, f, indent=2)
        println(f"Results written to {output_path}")

# Run the script
script = HelloProtocolAnalysis()
script.run()