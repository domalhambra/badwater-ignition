#!/usr/bin/env python3
"""Generate the Badwater Ignition color asset catalog (light + dark variants).

Run from repo root:  python3 scripts/generate_color_assets.py
Outputs colorsets into App/Shared/BadwaterColors.xcassets/.

The palette lives in App/Shared, not in the app's own catalog, because the
widget extension and the watch targets need the severity ramp too and Color(_:)
resolves against the calling bundle.

Keeping the palette in one script makes the brand system a single source of
truth that the design team can tweak and re-generate.
"""
import json, os, pathlib

# name: (light hex, dark hex).  The Badwater Basin identity:
# teal spring-water accent on salt-flat / basin-night grounds, with the entire
# warm ramp reserved for fire-behavior SEVERITY (never decoration).
PALETTE = {
    # Grounds & surfaces
    "BasinBackground": ("F2F0E9", "0F0E0B"),
    "Surface":         ("FFFFFF", "191712"),
    "SurfaceRaised":   ("FAF9F4", "201D16"),
    "SurfaceSunk":     ("EAE8DF", "14120D"),
    # Text
    "Ink":             ("211E17", "F0ECDF"),
    "Muted":           ("6E6A5D", "9A9484"),
    "Hairline":        ("DDD9CC", "2A2519"),
    # Brand accent — the Badwater pool
    "PoolTeal":        ("1F6E7A", "64B9C3"),
    "PoolTealSunk":    ("165059", "3E8E99"),
    # Caution (used sparingly, never as a severity)
    "SignalAmber":     ("9A6A0B", "E8B84B"),
    # Fire-behavior severity ramp (fills carrying white text)
    "SeverityVeryLow": ("5E7250", "6E8460"),
    "SeverityLow":     ("8A7A2E", "B3A24A"),
    "SeverityMedium":  ("B07A1E", "CE9636"),
    "SeverityHigh":    ("BE5F26", "D9823C"),
    "SeverityVeryHigh":("B0431F", "DD6A30"),
    "SeverityExtreme": ("9E2B1B", "D6402A"),
}

def components(hex6):
    return {
        "red":   f"0x{hex6[0:2].upper()}",
        "green": f"0x{hex6[2:4].upper()}",
        "blue":  f"0x{hex6[4:6].upper()}",
        "alpha": "1.000",
    }

def colorset(light, dark):
    def entry(hex6, appearances=None):
        e = {"idiom": "universal", "color": {"color-space": "srgb", "components": components(hex6)}}
        if appearances:
            e["appearances"] = appearances
        return e
    return {
        "colors": [
            entry(light),
            entry(dark, [{"appearance": "luminosity", "value": "dark"}]),
        ],
        "info": {"author": "xcode", "version": 1},
    }

def main():
    root = pathlib.Path(__file__).resolve().parent.parent
    base = root / "App" / "Shared" / "BadwaterColors.xcassets"
    base.mkdir(parents=True, exist_ok=True)
    # Asset catalog root
    (base / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2))
    for name, (light, dark) in PALETTE.items():
        d = base / f"{name}.colorset"
        d.mkdir(exist_ok=True)
        (d / "Contents.json").write_text(json.dumps(colorset(light, dark), indent=2))
    print(f"Generated {len(PALETTE)} colorsets into {base}")

if __name__ == "__main__":
    main()
