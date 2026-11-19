import zipfile, os

# Mod-Identitaet bleibt FS25_FarmOverview (nicht umbenennen -> Savegame/modSettings
# bleiben gueltig). Interner Projektname ist FruchtfolgeAdvisor.
name = "FS25_FarmOverview.zip"

files = [
    "modDesc.xml",
    "icon_FarmOverview.dds",
    "gui/FarmOverviewPage.xml",
    "gui/helpLine.xml",
    "images/white.dds",
    "images/menuIcon.dds",
    "scripts/FarmOverviewHelp.lua",
    "scripts/CropRotationData.lua",
    "scripts/FieldAnalyzer.lua",
    "scripts/BodengesundheitSyncEvent.lua",
    "scripts/BodengesundheitRequestEvent.lua",
    "scripts/BodengesundheitCfgEvent.lua",
    "scripts/CropSelectionEvent.lua",
    "scripts/FruitMemoryEvent.lua",
    "scripts/Bodengesundheit.lua",
    "scripts/StorageAnalyzer.lua",
    "scripts/AnimalAnalyzer.lua",
    "scripts/ProductionAnalyzer.lua",
    "scripts/RecommendationEngine.lua",
    "scripts/ForesightPlanner.lua",
    "scripts/FruchtfolgeAdvisor.lua",
    "scripts/FruchtfolgeAdvisorDialog.lua",
    "scripts/TaskState.lua",
    "scripts/TaskStateEvent.lua",
    "scripts/TaskAnalyzer.lua",
    "scripts/FinanceBridge.lua",
    "scripts/YieldBridge.lua",
    "scripts/FieldLedger.lua",
    "scripts/FarmOverviewPage.lua",
]

missing = [f for f in files if not os.path.exists(f)]
if missing:
    raise SystemExit("FEHLEND: " + ", ".join(missing))

if os.path.exists(name):
    os.remove(name)

with zipfile.ZipFile(name, "w", zipfile.ZIP_DEFLATED) as z:
    for f in files:
        z.write(f, f)

print("ZIP:", name, round(os.path.getsize(name) / 1024, 1), "KB")
with zipfile.ZipFile(name) as z:
    for i in z.namelist():
        print("  ", i)
