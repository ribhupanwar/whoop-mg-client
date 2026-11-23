# Ghidra pre-import script to disable problematic analyzers
# Run with: -preScript disable_analyzers.py

from ghidra.app.plugin.core.analysis import AutoAnalysisManager
from ghidra.program.model.listing import Program

# Get the AutoAnalysisManager for the current program
program = currentProgram
analysisManager = AutoAnalysisManager.getAnalysisManager(program)

# Disable the ObjC Type Metadata Analyzer (causes "Unsupported Objective C type encoding" errors)
analysisManager.disableAnalysis("ObjcTypeMetadataAnalyzer")

# Also disable other Objective-C related analyzers that might cause issues
analysisManager.disableAnalysis("Objc1Analyzer")
analysisManager.disableAnalysis("Objc2Analyzer")

# Disable Swift Type Metadata Analyzer (also slow and may cause issues)
analysisManager.disableAnalysis("SwiftTypeMetadataAnalyzer")

# Disable non-returning functions analyzer (not needed for our search)
analysisManager.disableAnalysis("NonReturningFunctionsAnalyzer")

# Disable the ARM Thunk analyzer (not needed)
analysisManager.disableAnalysis("AARCH64ELFPLTThunkAnalyzer")

print("Disabled problematic analyzers for faster import")