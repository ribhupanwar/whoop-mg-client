import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.address.AddressRange;
import ghidra.program.model.address.AddressRangeImpl;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionManager;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceIterator;
import ghidra.program.model.symbol.ReferenceManager;

public class HelloProtocolCallTraceTargeted extends GhidraScript {

    // Key functions containing HELLO-related objc_msgSend calls
    private static final long[] TARGET_FUNCTIONS = {
        0x10903b618L,  // calls processCommandDidGetHelloPacket:
        0x10903b74cL,  // calls processCommandDidGetHelloPacket:
        0x10904b148L,  // calls processCommandDidGetHelloPacket:
        0x10904aee8L,  // calls processCommandDidGetHelloPacket:
        0x10904af18L,  // calls processCommandDidGetHelloPacket:
        0x1090511c4L,  // calls processCommandDidGetHelloInfoWithSerial:signature:boardId: / sendGetHelloPacketWithCompletion:
        0x1090745a0L,  // calls processCommandDidGetHelloInfoWithSerial:signature:boardId: / sendGetHelloPacketWithCompletion:
        0x1090745b8L,  // calls processCommandDidGetHelloInfoWithSerial:signature:boardId: / sendGetHelloPacketWithCompletion:
    };

    // Selector table pages for HELLO selectors
    private static final long[] HELLO_SELECTOR_PAGES = {
        0x10b4cb000L,  // processCommandDidGetHelloPacket:
        0x10b4cc000L,  // processCommandDidGetHelloInfoWithSerial:signature:boardId: and sendGetHelloPacketWithCompletion:
        0x10b4d8000L,  // sendGetHelloPacketWithCompletion:
        0x10b396000L,  // didCallSendGetHelloPacket:
        0x10aca7000L,  // GetHelloPacket
    };

    // Selector table entry addresses
    private static final long[] SELECTOR_ENTRIES = {
        0x10b4cc260L,  // processCommandDidGetHelloPacket:
        0x10b4cc258L,  // processCommandDidGetHelloInfoWithSerial:signature:boardId:
        0x10b4d8b08L,  // sendGetHelloPacketWithCompletion:
        0x10b396a00L,  // didCallSendGetHelloPacket:
        0x10aca74b8L,  // GetHelloPacket
    };

    @Override
    public void run() throws Exception {
        println("=== TARGETED CALL TRACE FOR HELLO FUNCTIONS ===");
        println("Image base: " + currentProgram.getImageBase());
        
        ReferenceManager refManager = currentProgram.getReferenceManager();
        FunctionManager funcManager = currentProgram.getFunctionManager();

        // 1. Trace callers of target functions
        println("\n=== CALLERS OF TARGET FUNCTIONS ===");
        for (long addr : TARGET_FUNCTIONS) {
            traceCallers(refManager, funcManager, addr);
        }

        // 2. Trace callers of functions that load HELLO selector pages
        println("\n=== FUNCTIONS LOADING HELLO SELECTOR PAGES ===");
        for (long page : HELLO_SELECTOR_PAGES) {
            traceSelectorPageUsers(refManager, funcManager, page);
        }

        // 3. Trace data refs to selector entries
        println("\n=== DATA REFS TO SELECTOR TABLE ENTRIES ===");
        for (long entry : SELECTOR_ENTRIES) {
            traceDataRefs(refManager, funcManager, entry);
        }

        // 4. Search for Swift mangled class names
        println("\n=== SWIFT MANGLED CLASS NAMES ===");
        searchSwiftMangledNames();

        // 5. Trace helloResponse, helloResponseTask, strap_signature, strapSerial, boardId
        println("\n=== KEY STRING USAGE ===");
        traceKeyStrings(refManager, funcManager);
    }

    private void traceCallers(ReferenceManager refManager, FunctionManager funcManager, long addr) {
        Address targetAddr = toAddr(addr);
        Function func = funcManager.getFunctionAt(targetAddr);
        
        if (func == null) {
            println(String.format("0x%X: NO FUNCTION DEFINED", addr));
            return;
        }

        println(String.format("\n0x%X: %s", addr, func.getName()));
        println("  Signature: " + func.getSignature().getPrototypeString());
        
        ReferenceIterator refs = refManager.getReferencesTo(targetAddr);
        int codeRefCount = 0;
        while (refs.hasNext()) {
            Reference ref = refs.next();
            if (ref.getReferenceType().isCall() || ref.getReferenceType().isJump()) {
                Address fromAddr = ref.getFromAddress();
                Function caller = funcManager.getFunctionContaining(fromAddr);
                String callerName = caller != null ? caller.getName() : "UNKNOWN";
                println(String.format("  CALL from 0x%X (%s)", fromAddr.getOffset(), callerName));
                codeRefCount++;
            }
        }
        if (codeRefCount == 0) {
            println("  No code callers found");
        }
    }

    private void traceSelectorPageUsers(ReferenceManager refManager, FunctionManager funcManager, long pageAddr) {
        println(String.format("\n--- Selector page 0x%X ---", pageAddr));
        
        Address start = toAddr(pageAddr);
        Address end = toAddr(pageAddr + 0x1000);
        AddressRange range = new AddressRangeImpl(start, end);
        
        InstructionIterator instrIter = currentProgram.getListing().getInstructions(range, true);
        while (instrIter.hasNext()) {
            Instruction instr = instrIter.next();
            Address[] opRefs = instr.getOperandReferences(0);
            for (Address opRef : opRefs) {
                if (opRef.getOffset() >= pageAddr && opRef.getOffset() < pageAddr + 0x1000) {
                    Function func = funcManager.getFunctionContaining(instr.getAddress());
                    String funcName = func != null ? func.getName() : "NO_FUNC";
                    println(String.format("  0x%X: %s %s (in %s)", 
                        instr.getAddress().getOffset(), instr.getMnemonicString(), 
                        instr.getOpObjects(0).length > 0 ? instr.getOpObjects(0)[0].toString() : "", funcName));
                }
            }
        }
    }

    private void traceDataRefs(ReferenceManager refManager, FunctionManager funcManager, long entryAddr) {
        Address entry = toAddr(entryAddr);
        ReferenceIterator refs = refManager.getReferencesTo(entry);
        println(String.format("\nSelector entry 0x%X:", entryAddr));
        while (refs.hasNext()) {
            Reference ref = refs.next();
            Function func = funcManager.getFunctionContaining(ref.getFromAddress());
            String funcName = func != null ? func.getName() : "NO_FUNC";
            println(String.format("  0x%X (%s) type=%s", ref.getFromAddress().getOffset(), funcName, ref.getReferenceType()));
        }
    }

    private void searchSwiftMangledNames() {
        // Search for Swift mangled names of key classes
        String[] patterns = {
            "$sSo18WHPBLEStrapManagerC",
            "$sSo43PuffinDeviceSerialProviderC",
            "$sSo15WhoopDeviceAPIsC",
            "$sSo40BluetoothPairingConnectingViewModelC",
            "$sSo19BluetoothPairingFeatureC",
            "$sSo8WHPBandC",
            "$sSo8WHPStrapC",
            "WHPBLEStrapManager",
            "PuffinDeviceSerialProvider",
            "WhoopDeviceAPIs",
            "BluetoothPairingConnectingViewModel",
        };

        for (String pattern : patterns) {
            byte[] patternBytes = pattern.getBytes();
            Address addr = findBytes(currentProgram.getMinAddress(), patternBytes);
            if (addr != null) {
                println(String.format("  Found '%s' at 0x%X", pattern, addr.getOffset()));
                // Look for nearby metadata
                for (long offset = -0x200; offset <= 0x200; offset += 8) {
                    Address checkAddr = addr.add(offset);
                    byte[] bytes = new byte[8];
                    if (currentProgram.getMemory().getBytes(checkAddr, bytes) == 8) {
                        // Check if it looks like a vtable pointer
                        long val = 0;
                        for (int i = 0; i < 8; i++) {
                            val |= ((long)(bytes[i] & 0xFF)) << (i * 8);
                        }
                        if (val >= 0x100000000L && val < 0x110000000L) {
                            println(String.format("    Possible vtable pointer at 0x%X -> 0x%X", checkAddr.getOffset(), val));
                        }
                    }
                }
            } else {
                println(String.format("  '%s' NOT FOUND", pattern));
            }
        }
    }

    private void traceKeyStrings(ReferenceManager refManager, FunctionManager funcManager) {
        String[] keyStrings = {
            "helloResponse",
            "helloResponseTask", 
            "strap_signature",
            "strapSerial",
            "boardId",
            "lastConnectedStrapSerial",
            "lastConnectedStrapSignature",
            "setLastConnectedStrapSignature:"
        };

        for (String str : keyStrings) {
            byte[] strBytes = str.getBytes();
            Address addr = findBytes(currentProgram.getMinAddress(), strBytes);
            if (addr != null) {
                println(String.format("\n--- String '%s' at 0x%X ---", str, addr.getOffset()));
                ReferenceIterator refs = refManager.getReferencesTo(addr);
                while (refs.hasNext()) {
                    Reference ref = refs.next();
                    Function func = funcManager.getFunctionContaining(ref.getFromAddress());
                    String funcName = func != null ? func.getName() : "NO_FUNC";
                    println(String.format("  0x%X (%s) type=%s", ref.getFromAddress().getOffset(), funcName, ref.getReferenceType()));
                }
            } else {
                println(String.format("\nString '%s' NOT FOUND", str));
            }
        }
    }
}