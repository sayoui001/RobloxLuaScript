"""Bundle local Luau modules into one self-contained executor script."""
from pathlib import Path
import argparse
import json

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist" / "AAAutoPlay.lua"
MANIFEST = ROOT / "build.json"

def build() -> bytes:
    config = json.loads(MANIFEST.read_text(encoding="utf-8"))
    modules = config["modules"]
    names = [m["name"] for m in modules]
    if len(names) != len(set(names)):
        raise ValueError("Duplicate module names")
    result = [
        "-- Generated from src. Do not edit.\n",
        "local __factories = {}\nlocal __cache = {}\nlocal __loading = {}\n",
        "local function requireModule(name)\n",
        "    if __cache[name] ~= nil then return __cache[name] end\n",
        "    local factory = __factories[name]\n",
        "    assert(factory, 'Unknown bundled module: '..tostring(name))\n",
        "    assert(not __loading[name], 'Circular dependency: '..name)\n",
        "    __loading[name] = true\n",
        "    local ok, value = pcall(factory)\n",
        "    __loading[name] = nil\n",
        "    if not ok then error(value, 2) end\n",
        "    assert(value ~= nil, 'Module returned nil: '..name)\n",
        "    __cache[name] = value\n",
        "    return value\nend\n",
    ]
    for module in modules:
        name = module["name"]
        filename = module["path"]
        if not name or not isinstance(name, str) or any(c not in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_." for c in name):
            raise ValueError("Invalid module name")
        path = (ROOT / filename).resolve()
        if not path.is_relative_to(ROOT.resolve()):
            raise ValueError("Module outside project")
        contents = path.read_text(encoding="utf-8")
        result.extend([
            "__factories[" + json.dumps(name) + "] = function()\n",
            contents,
            "\nend\n",
        ])
    entry = (ROOT / config["entry"]).resolve()
    if not entry.is_relative_to(ROOT.resolve()):
        raise ValueError("Entry outside project")
    result.append(entry.read_text(encoding="utf-8"))
    return "".join(result).encode("utf-8")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    data = build()
    if args.check:
        if not DIST.is_file() or DIST.read_bytes() != data:
            raise SystemExit("FAIL: dist missing or differs from source")
        print("PASS: deterministic build matches dist")
    else:
        DIST.parent.mkdir(parents=True, exist_ok=True)
        DIST.write_bytes(data)
        print(f"Built {DIST} ({len(data)} bytes)")

if __name__ == "__main__":
    main()
