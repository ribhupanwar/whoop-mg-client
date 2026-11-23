import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.*;
import ghidra.program.model.mem.*;
import ghidra.program.model.address.*;
import ghidra.program.model.symbol.*;
import ghidra.program.model.scalar.Scalar;
import ghidra.util.task.ConsoleTaskMonitor;
import java.io.*;
import java.util.*;

public class HelloProtocolCallTrace extends GhidraScript {

    // HELLO selector table pages
    private static final Set<Long> HELLO_SELECTOR_PAGES = new HashSet<>(Arrays.asList(
        0x10b4cb000L,  // processCommandDidGetHelloPacket:
        0x10b4cc000L,  // processCommandDidGetHelloInfoWithSerial:signature:boardId: and sendGetHelloPacketWithCompletion:
        0x10b396000L,  // didCallSendGetHelloPacket:
        0x10aca7000L   // GetHelloPacket
    ));

    private static final long OBJC_MSGSEND = 0x10908b704L;

    private Set<String> visitedFunctions = new HashSet<>();

    @Override
    protected void run() throws Exception {
        println("=" + "=".repeat(59));
        println("HELLO PROTOCOL CALL TRACE ANALYSIS");
        println("=" + "=".repeat(59));

        // 1. Find HELLO-related objc_msgSend call sites
        println("\n[1] Finding HELLO-related objc_msgSend call sites...");
        List<Map<String, Object>> helloCallSites = findHelloMsgSendCallSites();
        println("Found " + helloCallSites.size() + " HELLO-related call sites:");

        // Group by function
        Map<Long, List<Map<String, Object>>> byFunction = new HashMap<>();
        for (Map<String, Object> site : helloCallSites) {
            Long funcAddr = (Long) site.get("func_addr");
            byFunction.computeIfAbsent(funcAddr, k -> new ArrayList<>()).add(site);
        }

        println("\nHELLO-related functions (" + byFunction.size() + " unique):");
        for (Map.Entry<Long, List<Map<String, Object>>> entry : byFunction.entrySet()) {
            Long funcAddr = entry.getKey();
            List<Map<String, Object>> sites = entry.getValue();
            Function func = getFunctionAt(toAddr(funcAddr));
            String funcName = func != null ? func.getName() : "unknown";
            println(String.format("  %s @ 0x%X: %d call sites", funcName, funcAddr, sites.size()));
            for (Map<String, Object> site : sites) {
                println(String.format("    CALL 0x%X -> selector page %s", 
                    site.get("call_addr"), site.get("selector_page")));
            }
        }

        // 2. Trace callers of these functions
        println("\n[2] Tracing callers of HELLO-related functions...");
        for (Map.Entry<Long, List<Map<String, Object>>> entry : byFunction.entrySet()) {
            Long funcAddr = entry.getKey();
            Function func = getFunctionAt(toAddr(funcAddr));
            if (func != null) {
                traceCallersRecursive(func, 0);
            }
        }

        // 3. Also trace crypto function callers
        println("\n[3] Tracing crypto function callers...");
        traceCryptoCallers();

        println("\n" + "=".repeat(60));
        println("ANALYSIS COMPLETE");
        println("=" + "=".repeat(60));
    }

    private long getPage(long addr) {
        return addr & 0xFFFFF000L;
    }

    private List<Map<String, Object>> findHelloMsgSendCallSites() throws Exception {
        List<Map<String, Object>> results = new ArrayList<>();

        Address msgSendAddr = toAddr(OBJC_MSGSEND);
        ReferenceManager refManager = currentProgram.getReferenceManager();
        ReferenceIterator refIter = refManager.getReferencesTo(msgSendAddr);

        while (refIter.hasNext()) {
            Reference ref = refIter.next();
            if (!ref.getReferenceType().isCall()) continue;

            Address callAddr = ref.getFromAddress();

            // Look backwards for ADRP instructions loading selector table pages
            Address curr = callAddr;
            boolean foundHelloPage = false;
            Long selectorPage = null;

            for (int i = 0; i < 50; i++) {
                Instruction prevInstr = currentProgram.getListing().getInstructionBefore(curr);
                if (prevInstr == null) break;
                curr = prevInstr.getAddress();

                String mnemonic = prevInstr.getMnemonicString();
                if ("ADRP".equals(mnemonic)) {
                    Object[] ops = prevInstr.getOpObjects(0);
                    if (ops != null && ops.length > 0 && ops[0] instanceof Scalar) {
                        long pageAddr = getPage(((Scalar) ops[0]).getValue());
                        if (HELLO_SELECTOR_PAGES.contains(pageAddr)) {
                            foundHelloPage = true;
                            selectorPage = pageAddr;
                            break;
                        }
                    }
                } else if ("LDR".equals(mnemonic) && foundHelloPage) {
                    break;
                }
            }

            if (foundHelloPage) {
                Function func = getFunctionContaining(callAddr);
                String funcName = func != null ? func.getName() : "unknown";
                long funcAddr = func != null ? func.getEntryPoint().getOffset() : callAddr.getOffset();

                Map<String, Object> r = new HashMap<>();
                r.put("call_addr", callAddr.getOffset());
                r.put("selector_page", "0x" + Long.toHexString(selectorPage));
                r.put("func_name", funcName);
                r.put("func_addr", funcAddr);
                results.add(r);
            }
        }

        return results;
    }

    private void traceCallersRecursive(Function func, int depth) {
        if (depth > 5) return;

        String funcKey = func.getEntryPoint().toString();
        if (visitedFunctions.contains(funcKey)) return;
        visitedFunctions.add(funcKey);

        if (depth > 0) {
            println(String.format("  [%d] CALLER: %s @ %s", depth, func.getName(), func.getEntryPoint()));
        }

        ReferenceManager refManager = currentProgram.getReferenceManager();
        ReferenceIterator refIter = refManager.getReferencesTo(func.getEntryPoint());
        while (refIter.hasNext()) {
            Reference ref = refIter.next();
            if (!ref.getReferenceType().isCall()) continue;

            Address callerAddr = ref.getFromAddress();
            Function caller = getFunctionContaining(callerAddr);
            if (caller != null && !caller.equals(func)) {
                traceCallersRecursive(caller, depth + 1);
            }
        }
    }

    private void traceCryptoCallers() throws Exception {
        Map<String, Long> cryptoFuncs = new HashMap<>();
        cryptoFuncs.put("SecKeyCreateSignature", 0x10908a798L);
        cryptoFuncs.put("SecKeyVerifySignature", 0x10908a7b0L);

        ReferenceManager refManager = currentProgram.getReferenceManager();

        for (Map.Entry<String, Long> entry : cryptoFuncs.entrySet()) {
            String name = entry.getKey();
            long addr = entry.getValue();

            Function func = getFunctionAt(toAddr(addr));
            if (func == null) {
                println("  " + name + ": Function not found at 0x" + Long.toHexString(addr));
                continue;
            }

            println("\n  --- " + name + " @ 0x" + Long.toHexString(addr) + " ---");

            ReferenceIterator refIter = refManager.getReferencesTo(toAddr(addr));
            boolean found = false;
            while (refIter.hasNext()) {
                Reference ref = refIter.next();
                if (!ref.getReferenceType().isCall()) continue;

                found = true;
                Address callerAddr = ref.getFromAddress();
                Function caller = getFunctionContaining(callerAddr);
                if (caller != null) {
                    println("    Direct caller: " + caller.getName() + " @ " + caller.getEntryPoint() + " (from " + callerAddr + ")");
                    traceCallersRecursive(caller, 1);
                }
            }

            if (!found) {
                println("    No direct callers found in reference database");
            }
        }
    }
}