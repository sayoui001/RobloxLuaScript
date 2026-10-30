import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from build import build

class BuildTests(unittest.TestCase):
    def test_deterministic(self):
        self.assertEqual(build(), build())

    def test_dist_matches_source(self):
        self.assertEqual((ROOT / "dist/AAAutoPlay.lua").read_bytes(), build())

    def test_extracted_road_logic_preserved(self):
        # Same source functions moved intact from production (only indentation/wrapper changed).
        original = (ROOT / "AAAutoPlay.lua").read_text(encoding="utf-8")
        first = original.index("local function lanePoints()")
        last = original.index("local function pathMidpoint(percentOverride)")
        old = original[first:last]
        module = (ROOT / "src/Core/RoadDetector.luau").read_text(encoding="utf-8")
        self.assertIn(old, module)

    def test_module_binding(self):
        entry = (ROOT / "src/Main.luau").read_text(encoding="utf-8")
        self.assertIn('requireModule("Core.RoadDetector")(WS)', entry)
        self.assertEqual(entry.count("local function lanePoints()"), 0)
        bundled = build().decode("utf-8")
        self.assertIn('local function requireModule(name)', bundled)
        self.assertIn('__factories["Core.RoadDetector"]', bundled)


    def test_extracted_placement_logic_preserved(self):
        original = (ROOT / "AAAutoPlay.lua").read_text(encoding="utf-8")
        first = original.index("local function offsets()")
        last = original.index("function app:ClearPreview()")
        module = (ROOT / "src/Core/PlacementEngine.luau").read_text(encoding="utf-8")
        self.assertIn(original[first:last], module)

    def test_placement_bindings(self):
        entry = (ROOT / "src/Main.luau").read_text(encoding="utf-8")
        self.assertIn('requireModule("Core.PlacementEngine")', entry)
        self.assertNotIn("local function findGround(", entry)
        self.assertIn('__factories["Core.PlacementEngine"]', build().decode("utf-8"))


    def test_verifier_extraction_preserves_logic(self):
        original = (ROOT / "AAAutoPlay.lua").read_text(encoding="utf-8")
        first = original.index("local function ownedSnapshot(")
        last = original.index("function app:InspectRoad()")
        module = (ROOT / "src/Core/PlacementVerifier.luau").read_text(encoding="utf-8")
        self.assertIn(original[first:last], module)

    def test_verifier_binding_and_timeout(self):
        entry = (ROOT / "src/Main.luau").read_text(encoding="utf-8")
        self.assertIn('requireModule("Core.PlacementVerifier")(cfg,player)', entry)
        self.assertIn('local timeout=1', entry)
        self.assertIn('task.wait(0.1)', entry)
        self.assertIn('matchingNewUnit(folder,before,uuid,pos)', entry)
        self.assertIn('__factories["Core.PlacementVerifier"]', build().decode("utf-8"))


    def test_auto_upgrade_extracted_unchanged(self):
        baseline = (ROOT / "AAAutoPlay.lua").read_text(encoding="utf-8")
        start = baseline.index("-- Embedded Auto Upgrade (kept in its own lexical scope)")
        end = baseline.index("-- Embedded Auto Skill | per-slot support")
        module = (ROOT / "src/Features/AutoUpgrade.luau").read_text(encoding="utf-8")
        self.assertIn(baseline[start:end], module)

    def test_auto_upgrade_binding(self):
        entry = (ROOT / "src/Main.luau").read_text(encoding="utf-8")
        self.assertIn('requireModule("Features.AutoUpgrade")()', entry)
        self.assertIn('__factories["Features.AutoUpgrade"]', build().decode("utf-8"))


    def test_auto_skill_extraction_preserves_logic(self):
        baseline = (ROOT / "AAAutoPlay.lua").read_text(encoding="utf-8")
        start = baseline.index("-- Embedded Auto Skill | per-slot support")
        end = baseline.index("local function upgradeApp()")
        module = (ROOT / "src/Features/AutoSkill.luau").read_text(encoding="utf-8")
        self.assertIn(baseline[start:end], module)

    def test_auto_skill_binding(self):
        entry = (ROOT / "src/Main.luau").read_text(encoding="utf-8")
        self.assertIn('requireModule("Features.AutoSkill")(cfg)', entry)
        self.assertIn('__factories["Features.AutoSkill"]', build().decode("utf-8"))


    def test_ui_settings_extracted(self):
        entry = (ROOT / "src/Main.luau").read_text(encoding="utf-8")
        baseline = (ROOT / "AAAutoPlay.lua").read_text(encoding="utf-8")
        ui = (ROOT / "src/UI/MainWindow.luau").read_text(encoding="utf-8")
        reader = (ROOT / "src/Core/Settings.luau").read_text(encoding="utf-8")
        writer = (ROOT / "src/Core/SettingsPersistence.luau").read_text(encoding="utf-8")
        self.assertIn("local function buildWindUI()", ui)
        self.assertIn("placement:Toggle({Title=\"Road Preview\"", ui)
        self.assertIn("app:RefreshRoadPreview()", ui)
        self.assertIn("sk.Enabled=isAutoPlayRunning() and", ui)
        self.assertNotIn("Title=\"Toggle Road Preview\"", ui)
        self.assertIn("local function readSettings()", reader)
        self.assertIn("safe.AutoBuffEnabled[kind]=data.AutoBuffEnabled[kind]==true", reader)
        self.assertIn("safe.MapPlacementAnchors", reader)
        self.assertIn("safe.MapPlacementSides", reader)
        self.assertIn("safe.MapPathPercents", reader)
        self.assertIn(baseline[baseline.index("function app:SaveSettings()"):baseline.index("local function statusText(msg)")], writer)
        for module in ("UI.MainWindow", "Core.Settings", "Core.SettingsPersistence"):
            self.assertIn('requireModule("'+module+'")', entry)
            self.assertIn('__factories["'+module+'"]', build().decode("utf-8"))
        self.assertIn("isAutoPlayRunning=function() return autoPlayRunning end",entry)


    def test_auto_buff_v3_rotation_and_integration(self):
        original = (ROOT / "AABuffV3.lua").read_text(encoding="utf-8")
        buff = (ROOT / "src/Features/AutoBuff.luau").read_text(encoding="utf-8")
        main = (ROOT / "src/Main.luau").read_text(encoding="utf-8")
        ui = (ROOT / "src/UI/MainWindow.luau").read_text(encoding="utf-8")
        reader = (ROOT / "src/Core/Settings.luau").read_text(encoding="utf-8")
        for phrase in ("highestCooldown / REQUIRED_UNITS", "DELAY_MARGIN = 0.15", "REQUIRED_UNITS = 4", 'FindFirstChild("use_active_attack")', "controller.SetEnabled(kind, enabled)"):
            self.assertIn(phrase, original)
            self.assertIn(phrase, buff)
        self.assertIn('requireModule("Features.AutoBuff")', main)
        self.assertIn("syncAutoBuff(true)", main)
        self.assertIn("syncAutoBuff(false)", main)
        self.assertIn('Title="Auto Buff"', ui)
        self.assertIn('AutoBuffEnabled', reader)
        self.assertIn('__factories["Features.AutoBuff"]', build().decode("utf-8"))


    def test_slow_preview_toggle_and_cleanup(self):
        main=(ROOT / "src/Main.luau").read_text(encoding="utf-8")
        ui=(ROOT / "src/UI/MainWindow.luau").read_text(encoding="utf-8")
        for phrase in ('ShowSlowPreview=false', '"ShowSlowPreview","CenterMode"', 'function app:RefreshSlowPreview()', 'function app:ClearSlowPreview()', 'self:ClearSlowPreview()', 'unitPlacementCandidates("Slow",0,target,center,offsetsList)'):
            self.assertIn(phrase, main)
        self.assertIn('Title="Slow Placement Preview"', ui)
        self.assertIn('Title="Refresh Slow Preview"', ui)
        self.assertIn('cfg.ShowSlowPreview=enabled==true', ui)

    def test_window_size_recovers_from_minimized_viewport(self):
        ui=(ROOT / "src/UI/MainWindow.luau").read_text(encoding="utf-8")
        self.assertIn('local startedSmall=', ui)
        self.assertIn('viewport.X>=720 and viewport.Y>=550', ui)
        self.assertIn('window:SetSize(UDim2.fromOffset(585,470))', ui)
        self.assertIn('app.WindUIWindow==window and env.AAAutoPlace==app', ui)

if __name__ == "__main__":
    unittest.main()
