# Ghidra script: Filter objc_msgSend calls for HELLO selector pages
# Run with: analyzeHeadless <project> WHOOP_Analysis5 -import <binary> -postScript ghidra_hello_targeted_filter.py -noanalysis

from ghidra.program.model.listing import CodeUnit
from ghidra.program.model.mem import MemoryAccessException
from ghidra.util.task import ConsoleTaskMonitor

# HELLO selector table pages (from __objc_selrefs)
HELLO_SELECTOR_PAGES = {
    0x10b4cb000,  # processCommandDidGetHelloPacket:
    0x10b4cc000,  # processCommandDidGetHelloInfoWithSerial:signature:boardId:
    0x10b396000,  # sendGetHelloPacketWithCompletion:
    0x10aca7000,  # didCallSendGetHelloPacket:
}

OBJC_MSGSEND = 0x10908b704

def get_page(addr):
    return addr & 0xFFFFF000

def find_hello_msgSend_calls():
    """Find objc_msgSend calls that load HELLO selector pages"""
    results = []
    
    # Get all references to _objc_msgSend
    msgSend_func = getFunctionAt(toAddr(OBJC_MSGSEND))
    if not msgSend_func:
        print("ERROR: _objc_msgSend not found at 0x%X" % OBJC_MSGSEND)
        return results
    
    refs = getReferencesTo(toAddr(OBJC_MSGSEND))
    print("Total objc_msgSend references: %d" % len(list(refs)))
    
    for ref in refs:
        call_addr = ref.getFromAddress()
        
        # Look backwards for ADRP instructions loading selector table pages
        # Search up to 20 instructions back
        curr = call_addr
        found_hello_page = False
        selector_addr = None
        
        for i in range(20):
            curr = curr.previous()
            if curr is None:
                break
                
            instr = getInstructionAt(curr)
            if instr is None:
                continue
                
            mnemonic = instr.getMnemonicString()
            if mnemonic == "ADRP":
                # ADRP Xd, page
                ops = instr.getOpObjects(0)
                if ops:
                    page_addr = get_page(ops[0].getOffset())
                    if page_addr in HELLO_SELECTOR_PAGES:
                        found_hello_page = True
                        selector_addr = page_addr
                        break
            elif mnemonic == "LDR" and found_hello_page:
                # LDR Xd, [Xn, #offset] - loading selector from table
                break
        
        if found_hello_page:
            func = getFunctionContaining(call_addr)
            func_name = func.getName() if func else "unknown"
            func_addr = func.getEntryPoint() if func else call_addr
            results.append({
                'call_addr': call_addr,
                'selector_page': hex(selector_addr),
                'func_name': func_name,
                'func_addr': func_addr
            })
    
    return results

def trace_crypto_callers():
    """Find callers of SecKeyCreateSignature and SecKeyVerifySignature"""
    crypto_funcs = {
        'SecKeyCreateSignature': 0x10908a798,
        'SecKeyVerifySignature': 0x10908a7b0,
    }
    
    results = {}
    for name, addr in crypto_funcs.items():
        func = getFunctionAt(toAddr(addr))
        if not func:
            results[name] = {'error': 'Function not found at 0x%X' % addr}
            continue
            
        callers = []
        refs = getReferencesTo(toAddr(addr))
        for ref in refs:
            caller_addr = ref.getFromAddress()
            caller_func = getFunctionContaining(caller_addr)
            if caller_func:
                callers.append({
                    'call_site': caller_addr,
                    'caller_func': caller_func.getName(),
                    'caller_addr': caller_func.getEntryPoint()
                })
        results[name] = {'address': addr, 'callers': callers}
    
    return results

def find_swift_class_metadata():
    """Search for Swift class metadata patterns"""
    # Swift class metadata often has mangled names like $sSo18WHPBLEStrapManagerC
    # Search in __DATA/__objc_classlist or similar sections
    results = []
    
    # Search for known class name patterns in memory
    class_patterns = [
        b'WHPBLEStrapManager',
        b'PuffinDeviceSerialProvider',
        b'WhoopDeviceAPIs',
        b'BluetoothPairingConnectingViewModel',
        b'BluetoothPairingFeature',
        b'WHPBand',
        b'WHPStrap',
    ]
    
    mem = currentProgram.getMemory()
    for block in mem.getBlocks():
        if not block.isExecute() and block.isRead():
            try:
                data = bytearray(block.getSize())
                mem.getBytes(block.getStart(), data)
                
                for pattern in class_patterns:
                    offset = 0
                    while True:
                        idx = data.find(pattern, offset)
                        if idx == -1:
                            break
                        addr = block.getStart().add(idx)
                        results.append({
                            'pattern': pattern.decode('ascii', errors='ignore'),
                            'address': addr,
                            'block': block.getName()
                        })
                        offset = idx + 1
            except MemoryAccessException:
                pass
    
    return results

# Main execution
print("=" * 60)
print("HELLO PROTOCOL TARGETED FILTER ANALYSIS")
print("=" * 60)

# 1. Filter objc_msgSend calls for HELLO selectors
print("\n[1] Filtering objc_msgSend calls for HELLO selector pages...")
hello_calls = find_hello_msgSend_calls()
print("Found %d calls loading HELLO selector pages:" % len(hello_calls))
for r in hello_calls:
    print("  CALL 0x%X -> selector page %s in function %s (0x%X)" % 
          (r['call_addr'], r['selector_page'], r['func_name'], r['func_addr']))

# 2. Trace crypto function callers
print("\n[2] Tracing crypto function callers...")
crypto_results = trace_crypto_callers()
for name, data in crypto_results.items():
    if 'error' in data:
        print("  %s: %s" % (name, data['error']))
    else:
        print("  %s @ 0x%X: %d callers" % (name, data['address'], len(data['callers'])))
        for c in data['callers']:
            print("    CALL from 0x%X in %s (0x%X)" % 
                  (c['call_site'], c['caller_func'], c['caller_addr']))

# 3. Search for Swift class metadata
print("\n[3] Searching for Swift class metadata...")
class_results = find_swift_class_metadata()
print("Found %d class metadata references:" % len(class_results))
for r in class_results[:50]:  # Limit output
    print("  %s at 0x%X in %s" % (r['pattern'], r['address'], r['block']))
if len(class_results) > 50:
    print("  ... and %d more" % (len(class_results) - 50))

# Save results to file
import json
output = {
    'hello_msgSend_calls': [
        {
            'call_addr': hex(r['call_addr']),
            'selector_page': r['selector_page'],
            'func_name': r['func_name'],
            'func_addr': hex(r['func_addr'])
        }
        for r in hello_calls
    ],
    'crypto_callers': crypto_results,
    'class_metadata': [
        {
            'pattern': r['pattern'],
            'address': hex(r['address']),
            'block': r['block']
        }
        for r in class_results
    ]
}

with open('C:/Users/ribhu/kilo-test/whoop-mg-client/docs/research/hello_5802_targeted_filter.json', 'w') as f:
    json.dump(output, f, indent=2)

print("\nResults saved to hello_5802_targeted_filter.json")
print("=" * 60)
print("ANALYSIS COMPLETE")
print("=" * 60)