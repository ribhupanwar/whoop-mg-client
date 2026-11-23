import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.*;
import ghidra.program.model.mem.*;
import ghidra.program.model.address.*;
import ghidra.program.model.symbol.*;
import ghidra.program.model.scalar.Scalar;
import ghidra.util.task.ConsoleTaskMonitor;
import java.io.*;
import java.util.*;

public class HelloProtocolTargetedFilter extends GhidraScript {

    // HELLO selector table pages (from __objc_selrefs)
    private static final Set<Long> HELLO_SELECTOR_PAGES = new HashSet<>(Arrays.asList(
        0x10b4cb000L,  // processCommandDidGetHelloPacket:
        0x10b4cc000L,  // processCommandDidGetHelloInfoWithSerial:signature:boardId:
        0x10b396000L,  // sendGetHelloPacketWithCompletion:
        0x10aca7000L   // didCallSendGetHelloPacket:
    ));

    private static final long OBJC_MSGSEND = 0x10908b704L;

    @Override
    protected void run() throws Exception {
        println("=" + "=".repeat(59));
        println("HELLO PROTOCOL TARGETED FILTER ANALYSIS");
        println("=" + "=".repeat(59));

        // 1. Filter objc_msgSend calls for HELLO selectors
        println("\n[1] Filtering objc_msgSend calls for HELLO selector pages...");
        List<Map<String, Object>> helloCalls = findHelloMsgSendCalls();
        println("Found " + helloCalls.size() + " calls loading HELLO selector pages:");
        for (Map<String, Object> r : helloCalls) {
            println(String.format("  CALL 0x%X -> selector page %s in function %s (0x%X)",
                r.get("call_addr"), r.get("selector_page"), r.get("func_name"), r.get("func_addr")));
        }

        // 2. Trace crypto function callers
        println("\n[2] Tracing crypto function callers...");
        Map<String, Object> cryptoResults = traceCryptoCallers();
        for (Map.Entry<String, Object> entry : cryptoResults.entrySet()) {
            String name = entry.getKey();
            @SuppressWarnings("unchecked")
            Map<String, Object> data = (Map<String, Object>) entry.getValue();
            if (data.containsKey("error")) {
                println("  " + name + ": " + data.get("error"));
            } else {
                @SuppressWarnings("unchecked")
                List<Map<String, Object>> callers = (List<Map<String, Object>>) data.get("callers");
                println("  " + name + " @ 0x" + Long.toHexString((Long)data.get("address")) + ": " + callers.size() + " callers");
                for (Map<String, Object> c : callers) {
                    println(String.format("    CALL from 0x%X in %s (0x%X)",
                        c.get("call_site"), c.get("caller_func"), c.get("caller_addr")));
                }
            }
        }

        // 3. Search for Swift class metadata
        println("\n[3] Searching for Swift class metadata...");
        List<Map<String, Object>> classResults = findSwiftClassMetadata();
        println("Found " + classResults.size() + " class metadata references:");
        int limit = Math.min(50, classResults.size());
        for (int i = 0; i < limit; i++) {
            Map<String, Object> r = classResults.get(i);
            println("  " + r.get("pattern") + " at 0x" + r.get("address") + " in " + r.get("block"));
        }
        if (classResults.size() > 50) {
            println("  ... and " + (classResults.size() - 50) + " more");
        }

        // Save results to file
        saveResults(helloCalls, cryptoResults, classResults);

        println("\n" + "=".repeat(60));
        println("ANALYSIS COMPLETE");
        println("=" + "=".repeat(60));
    }

    private long getPage(long addr) {
        return addr & 0xFFFFF000L;
    }

    private List<Map<String, Object>> findHelloMsgSendCalls() throws Exception {
        List<Map<String, Object>> results = new ArrayList<>();

        Function msgSendFunc = getFunctionAt(toAddr(OBJC_MSGSEND));
        if (msgSendFunc == null) {
            println("ERROR: _objc_msgSend not found at 0x" + Long.toHexString(OBJC_MSGSEND));
            return results;
        }

        Reference[] refs = getReferencesTo(toAddr(OBJC_MSGSEND));
        println("Total objc_msgSend references: " + refs.length);

        for (Reference ref : refs) {
            Address callAddr = ref.getFromAddress();

            // Look backwards for ADRP instructions loading selector table pages
            Address curr = callAddr;
            boolean foundHelloPage = false;
            Long selectorPage = null;

            for (int i = 0; i < 20; i++) {
                curr = curr.previous();
                if (curr == null) break;

                Instruction instr = getInstructionAt(curr);
                if (instr == null) continue;

                String mnemonic = instr.getMnemonicString();
                if ("ADRP".equals(mnemonic)) {
                    Object[] ops = instr.getOpObjects(0);
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

    private Map<String, Object> traceCryptoCallers() throws Exception {
        Map<String, Object> results = new HashMap<>();

        Map<String, Long> cryptoFuncs = new HashMap<>();
        cryptoFuncs.put("SecKeyCreateSignature", 0x10908a798L);
        cryptoFuncs.put("SecKeyVerifySignature", 0x10908a7b0L);

        for (Map.Entry<String, Long> entry : cryptoFuncs.entrySet()) {
            String name = entry.getKey();
            long addr = entry.getValue();

            Function func = getFunctionAt(toAddr(addr));
            if (func == null) {
                Map<String, Object> errorData = new HashMap<>();
                errorData.put("error", "Function not found at 0x" + Long.toHexString(addr));
                results.put(name, errorData);
                continue;
            }

            List<Map<String, Object>> callers = new ArrayList<>();
            Reference[] refs = getReferencesTo(toAddr(addr));
            for (Reference ref : refs) {
                Address callerAddr = ref.getFromAddress();
                Function callerFunc = getFunctionContaining(callerAddr);
                if (callerFunc != null) {
                    Map<String, Object> c = new HashMap<>();
                    c.put("call_site", callerAddr.getOffset());
                    c.put("caller_func", callerFunc.getName());
                    c.put("caller_addr", callerFunc.getEntryPoint().getOffset());
                    callers.add(c);
                }
            }

            Map<String, Object> data = new HashMap<>();
            data.put("address", addr);
            data.put("callers", callers);
            results.put(name, data);
        }

        return results;
    }

    private List<Map<String, Object>> findSwiftClassMetadata() throws Exception {
        List<Map<String, Object>> results = new ArrayList<>();

        String[] classPatterns = {
            "WHPBLEStrapManager",
            "PuffinDeviceSerialProvider",
            "WhoopDeviceAPIs",
            "BluetoothPairingConnectingViewModel",
            "BluetoothPairingFeature",
            "WHPBand",
            "WHPStrap"
        };

        Memory mem = currentProgram.getMemory();
        for (MemoryBlock block : mem.getBlocks()) {
            if (!block.isExecute() && block.isRead()) {
                try {
                    byte[] data = new byte[(int) block.getSize()];
                    mem.getBytes(block.getStart(), data);

                    for (String pattern : classPatterns) {
                        byte[] patternBytes = pattern.getBytes("UTF-8");
                        int offset = 0;
                        while (true) {
                            int idx = indexOf(data, patternBytes, offset);
                            if (idx == -1) break;
                            Address addr = block.getStart().add(idx);
                            Map<String, Object> r = new HashMap<>();
                            r.put("pattern", pattern);
                            r.put("address", addr.getOffset());
                            r.put("block", block.getName());
                            results.add(r);
                            offset = idx + 1;
                        }
                    }
                } catch (MemoryAccessException e) {
                    // Skip unreadable blocks
                }
            }
        }

        return results;
    }

    private int indexOf(byte[] data, byte[] pattern, int start) {
        for (int i = start; i <= data.length - pattern.length; i++) {
            boolean match = true;
            for (int j = 0; j < pattern.length; j++) {
                if (data[i + j] != pattern[j]) {
                    match = false;
                    break;
                }
            }
            if (match) return i;
        }
        return -1;
    }

    private void saveResults(List<Map<String, Object>> helloCalls,
                             Map<String, Object> cryptoResults,
                             List<Map<String, Object>> classResults) throws IOException {
        String outputPath = "C:/Users/ribhu/kilo-test/whoop-mg-client/docs/research/hello_5802_targeted_filter.json";

        StringBuilder json = new StringBuilder();
        json.append("{\n");
        json.append("  \"hello_msgSend_calls\": [\n");
        for (int i = 0; i < helloCalls.size(); i++) {
            Map<String, Object> r = helloCalls.get(i);
            json.append("    {\n");
            json.append("      \"call_addr\": \"0x").append(Long.toHexString((Long)r.get("call_addr"))).append("\",\n");
            json.append("      \"selector_page\": \"").append(r.get("selector_page")).append("\",\n");
            json.append("      \"func_name\": \"").append(r.get("func_name")).append("\",\n");
            json.append("      \"func_addr\": \"0x").append(Long.toHexString((Long)r.get("func_addr"))).append("\"\n");
            json.append("    }");
            if (i < helloCalls.size() - 1) json.append(",");
            json.append("\n");
        }
        json.append("  ],\n");
        json.append("  \"crypto_callers\": {\n");
        int cryptoCount = 0;
        for (Map.Entry<String, Object> entry : cryptoResults.entrySet()) {
            String name = entry.getKey();
            @SuppressWarnings("unchecked")
            Map<String, Object> data = (Map<String, Object>) entry.getValue();
            json.append("    \"").append(name).append("\": ");
            if (data.containsKey("error")) {
                json.append("{\"error\": \"").append(data.get("error")).append("\"}");
            } else {
                @SuppressWarnings("unchecked")
                List<Map<String, Object>> callers = (List<Map<String, Object>>) data.get("callers");
                json.append("{\"address\": \"0x").append(Long.toHexString((Long)data.get("address"))).append("\", \"callers\": [\n");
                for (int i = 0; i < callers.size(); i++) {
                    Map<String, Object> c = callers.get(i);
                    json.append("      {\n");
                    json.append("        \"call_site\": \"0x").append(Long.toHexString((Long)c.get("call_site"))).append("\",\n");
                    json.append("        \"caller_func\": \"").append(c.get("caller_func")).append("\",\n");
                    json.append("        \"caller_addr\": \"0x").append(Long.toHexString((Long)c.get("caller_addr"))).append("\"\n");
                    json.append("      }");
                    if (i < callers.size() - 1) json.append(",");
                    json.append("\n");
                }
                json.append("    ]}");
            }
            cryptoCount++;
            if (cryptoCount < cryptoResults.size()) json.append(",");
            json.append("\n");
        }
        json.append("  },\n");
        json.append("  \"class_metadata\": [\n");
        for (int i = 0; i < classResults.size(); i++) {
            Map<String, Object> r = classResults.get(i);
            json.append("    {\n");
            json.append("      \"pattern\": \"").append(r.get("pattern")).append("\",\n");
            json.append("      \"address\": \"0x").append(Long.toHexString((Long)r.get("address"))).append("\",\n");
            json.append("      \"block\": \"").append(r.get("block")).append("\"\n");
            json.append("    }");
            if (i < classResults.size() - 1) json.append(",");
            json.append("\n");
        }
        json.append("  ]\n");
        json.append("}\n");

        try (FileWriter fw = new FileWriter(outputPath)) {
            fw.write(json.toString());
        }
        println("Results saved to hello_5802_targeted_filter.json");
    }
}