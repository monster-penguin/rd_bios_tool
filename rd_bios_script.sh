#!/bin/bash

# Detect the directory this script lives in (the rd_bios_tool folder)
TOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


echo ""
echo "======================================================="
echo "                    ***WARNING***"
echo "======================================================="
echo ""
echo "  This tool was created for the developer's personal"
echo "  use. Accordingly, there are no guarantees that this"
echo "  tool will be compatible with your use case."
echo ""
echo "  Please exercise caution prior to use."
echo ""
echo "  The creator takes no responsibility for any damage"
echo "  caused by the use of this tool."
echo ""
echo "  This tool is not affiliated with RetroDECK in any"
echo "  way whatsoever. Please do not contact RetroDECK"
echo "  for support."
echo ""
echo "======================================================="
echo ""
echo -n "  Do you understand and wish to proceed? (Y/N): "
read -r CONFIRM_DISCLAIMER
if [[ ! "$CONFIRM_DISCLAIMER" =~ ^[Yy]$ ]]; then
    echo ""
    echo "  Exiting. No changes were made."
    echo ""
    exit 0
fi

echo ""
echo "======================================================="
echo "                    ***WARNING***"
echo "======================================================="
echo ""
echo "  This tool was created for use with RetroDECK"
echo "  version 0.10.6b."
echo ""
echo "  There is no guarantee that this tool will work"
echo "  with previous or subsequent versions of RetroDECK."
echo ""
echo "======================================================="
echo ""
echo -n "  Do you wish to proceed? (Y/N): "
read -r CONFIRM_VERSION
if [[ ! "$CONFIRM_VERSION" =~ ^[Yy]$ ]]; then
    echo ""
    echo "  Exiting. No changes were made."
    echo ""
    exit 0
fi

echo ""
echo "======================================================="
echo "  RetroDECK Component Manifest Builder"
echo "======================================================="
echo ""

# --- Step 1: Confirm source directory ---
DEFAULT_SOURCE="/var/lib/flatpak/app/net.retrodeck.retrodeck/current/active/files/retrodeck/components"
echo "Confirm location of component_manifest.json files."
echo "Use default: $DEFAULT_SOURCE"
echo -n "  Y to proceed, N to enter alternate location: "
read -r CONFIRM_SOURCE

if [[ "$CONFIRM_SOURCE" =~ ^[Nn]$ ]]; then
    echo -n "Enter alternate source path: "
    read -r SOURCE_DIR
else
    SOURCE_DIR="$DEFAULT_SOURCE"
fi

echo ""
echo "Scanning: $SOURCE_DIR"

mapfile -t MANIFEST_FILES < <(find "$SOURCE_DIR" -name "component_manifest.json" 2>/dev/null)
MANIFEST_COUNT=${#MANIFEST_FILES[@]}
echo "Found $MANIFEST_COUNT manifest file(s)."

if [[ $MANIFEST_COUNT -eq 0 ]]; then
    echo "No manifest files found. Exiting."
    exit 1
fi

# --- Step 2: Confirm output location ---
DEFAULT_OUTPUT="$TOOL_DIR/combined_manifest.json"
echo ""
echo "Confirm location for output combined_manifest.json."
echo "Use default: $DEFAULT_OUTPUT"
echo -n "  Y to proceed, N to enter alternate location: "
read -r CONFIRM_OUTPUT

if [[ "$CONFIRM_OUTPUT" =~ ^[Nn]$ ]]; then
    echo -n "Enter alternate output path: "
    read -r OUTPUT_FILE
else
    OUTPUT_FILE="$DEFAULT_OUTPUT"
fi

# --- Step 3: Parse manifests and build combined_manifest.json ---
TMPFILE=$(mktemp /tmp/manifest_list.XXXXXX)
printf '%s\n' "${MANIFEST_FILES[@]}" > "$TMPFILE"

python3 - "$TMPFILE" "$OUTPUT_FILE" << 'PYEOF'
import json
import os
import sys
import re

list_file   = sys.argv[1]
output_file = sys.argv[2]

with open(list_file) as lf:
    manifest_files = [line.strip() for line in lf if line.strip()]

def to_str(val):
    if isinstance(val, list):
        return " | ".join(str(v) for v in val if v)
    return str(val) if val else ""

def to_list(val):
    if isinstance(val, list):
        return [str(v).strip() for v in val if v]
    elif val:
        return [str(val).strip()]
    return []

def to_md5_list(val):
    if isinstance(val, list):
        result = []
        for item in val:
            if isinstance(item, list):
                result.extend(str(i).strip() for i in item if i)
            elif item:
                result.append(str(item).strip())
        return [m for m in result if m]
    elif isinstance(val, str) and val.strip():
        return [val.strip()]
    return []

def sanitize_path(p):
    """Fix typos like $saves_paths_path or $saves_paths_paths_path -> $saves_path.
    Replaces the entire $saves_XXXX token so nested repetitions are caught in one pass."""
    p = re.sub(r'\$saves_\w+', '$saves_path', p)
    return p

def resolve_path(p):
    """Resolve RetroDECK path variables to relative folder paths."""
    p = sanitize_path(p)
    p = p.replace("$bios_path",  "bios")
    p = p.replace("$saves_path", "saves")
    p = p.replace("$roms_path",  "roms")
    return p.strip("/")

def extract_bios_list(comp_val):
    """
    Find bios entries in all known locations:
      - top-level 'bios'
      - cores.bios
      - preset_actions.bios
    """
    candidates = []

    if 'bios' in comp_val:
        candidates.append(comp_val['bios'])

    cores = comp_val.get('cores', {})
    if isinstance(cores, dict) and 'bios' in cores:
        candidates.append(cores['bios'])

    preset = comp_val.get('preset_actions', {})
    if isinstance(preset, dict) and 'bios' in preset:
        candidates.append(preset['bios'])

    # Return first valid list found (prefer cores.bios > preset_actions.bios > top-level)
    # Actually merge all of them in case a component defines bios in multiple places
    merged = []
    seen_fn = set()
    for candidate in candidates:
        if not isinstance(candidate, list):
            continue
        for entry in candidate:
            if not isinstance(entry, dict):
                continue
            fn = str(entry.get('filename', '')).strip().lower()
            if fn and fn not in seen_fn:
                merged.append(entry)
                seen_fn.add(fn)
    return merged

# ── Main parse loop ──────────────────────────────────────────
seen = {}
file_count = 0

for mf in manifest_files:
    try:
        with open(mf, 'r') as f:
            data = json.load(f)
        file_count += 1
    except Exception as e:
        print(f"  WARNING: Could not parse {mf}: {e}")
        continue

    for component_key, component_val in data.items():
        if not isinstance(component_val, dict):
            continue

        system_name = to_str(component_val.get("system", component_key))
        bios_list   = extract_bios_list(component_val)

        for entry in bios_list:
            filename = to_str(entry.get("filename", "")).strip()
            if not filename:
                continue

            md5_list    = to_md5_list(entry.get("md5", ""))
            description = to_str(entry.get("description", ""))
            system      = to_str(entry.get("system", system_name))
            required    = to_str(entry.get("required", ""))
            paths_raw   = entry.get("paths")
            paths_list  = to_list(paths_raw) if paths_raw else []

            # Resolve all path variables
            resolved_paths = [resolve_path(p) for p in paths_list] if paths_list else ["bios"]

            filename_lower = filename.lower()

            if filename_lower in seen:
                existing = seen[filename_lower]
                existing_md5s = set(existing["md5"])
                for m in md5_list:
                    if m not in existing_md5s:
                        existing["md5"].append(m)
                        existing_md5s.add(m)
                if system and system not in existing["system"]:
                    existing["system"].append(system)
                for p in resolved_paths:
                    if p not in existing["paths"]:
                        existing["paths"].append(p)
            else:
                seen[filename_lower] = {
                    "filename":    filename,
                    "md5":         md5_list,
                    "system":      [system] if system else [],
                    "description": description,
                    "required":    required,
                    "paths":       resolved_paths
                }

# ── Build output ─────────────────────────────────────────────
output = []
for entry in seen.values():
    md5_val = entry["md5"]
    if len(md5_val) == 1:
        md5_val = md5_val[0]
    elif not md5_val:
        md5_val = ""

    output.append({
        "filename":     entry["filename"],
        "expected_md5": md5_val,
        "actual_md5":   "",
        "system":       " | ".join(entry["system"]) if entry["system"] else "",
        "description":  entry["description"],
        "required":     entry["required"],
        "paths":        entry["paths"]
    })

output.sort(key=lambda x: x["filename"].lower())

out_dir = os.path.dirname(output_file)
if out_dir:
    os.makedirs(out_dir, exist_ok=True)

with open(output_file, 'w') as f:
    json.dump(output, f, indent=2)

print(f"Combined {len(output)} unique BIOS entries from {file_count} manifest(s).")
PYEOF

rm -f "$TMPFILE"

# --- Step 4: Scan rd_bios_set.zip for actual MD5s ---
echo ""
echo "======================================================="
echo "  BIOS Archive Scanner"
echo "======================================================="
echo ""

DEFAULT_ZIP="$TOOL_DIR/rd_bios_set.zip"
echo "Confirm location of rd_bios_set.zip."
echo "Use default: $DEFAULT_ZIP"
echo -n "  Y to proceed, N to enter alternate location: "
read -r CONFIRM_ZIP

if [[ "$CONFIRM_ZIP" =~ ^[Nn]$ ]]; then
    echo -n "Enter alternate path to rd_bios_set.zip: "
    read -r ZIP_FILE
else
    ZIP_FILE="$DEFAULT_ZIP"
fi

if [[ ! -f "$ZIP_FILE" ]]; then
    echo "  ERROR: File not found: $ZIP_FILE"
    echo "  Exiting."
    exit 1
fi

echo ""
echo "Scanning archive: $ZIP_FILE"

python3 - "$ZIP_FILE" "$OUTPUT_FILE" << 'PYEOF'
import json, os, sys, zipfile, hashlib

zip_path      = sys.argv[1]
manifest_path = sys.argv[2]

def md5_of_bytes(data):
    return hashlib.md5(data).hexdigest()

with open(manifest_path, 'r') as f:
    manifest = json.load(f)

lookup = {entry["filename"].lower(): entry for entry in manifest}

matched = 0
scanned = 0

try:
    with zipfile.ZipFile(zip_path, 'r') as zf:
        members = [m for m in zf.infolist() if not m.filename.endswith('/')]
        print(f"  Archive contains {len(members)} file(s).")
        for member in members:
            scanned += 1
            basename = os.path.basename(member.filename)
            if not basename:
                continue
            data = zf.read(member.filename)
            actual = md5_of_bytes(data)
            key = basename.lower()
            if key in lookup:
                lookup[key]["actual_md5"] = actual
                matched += 1
except zipfile.BadZipFile:
    print(f"  ERROR: {zip_path} is not a valid zip file.")
    sys.exit(1)

print(f"  Matched {matched} of {scanned} archive files to manifest entries.")

with open(manifest_path, 'w') as f:
    json.dump(manifest, f, indent=2)

print(f"  Manifest updated with actual MD5s.")
PYEOF

# --- Step 5: Copy matched files into retrodeck folder structure ---
echo ""
echo "======================================================="
echo "  Build retrodeck/ Folder Structure"
echo "======================================================="
echo ""

DEFAULT_RETRODECK_DIR="$TOOL_DIR/retrodeck"
echo "Confirm location for the new retrodeck/ output directory."
echo "Use default: $DEFAULT_RETRODECK_DIR"
echo -n "  Y to proceed, N to enter alternate location: "
read -r CONFIRM_RD_DIR

if [[ "$CONFIRM_RD_DIR" =~ ^[Nn]$ ]]; then
    echo -n "Enter alternate path: "
    read -r RETRODECK_DIR
else
    RETRODECK_DIR="$DEFAULT_RETRODECK_DIR"
fi

echo ""
echo "Building folder structure at: $RETRODECK_DIR"

python3 - "$ZIP_FILE" "$OUTPUT_FILE" "$RETRODECK_DIR" << 'PYEOF'
import json, os, sys, zipfile, hashlib

zip_path      = sys.argv[1]
manifest_path = sys.argv[2]
retrodeck_dir = sys.argv[3]

def md5_of_bytes(data):
    return hashlib.md5(data).hexdigest()

with open(manifest_path, 'r') as f:
    manifest = json.load(f)

def is_match(entry):
    actual   = entry.get("actual_md5", "")
    if not actual:
        return False
    expected = entry.get("expected_md5", "")
    if isinstance(expected, list):
        return actual in expected
    return actual == expected

matched_lookup = {e["filename"].lower(): e for e in manifest if is_match(e)}

copied  = 0
skipped = 0

try:
    with zipfile.ZipFile(zip_path, 'r') as zf:
        members = [m for m in zf.infolist() if not m.filename.endswith('/')]
        for member in members:
            basename = os.path.basename(member.filename)
            if not basename:
                continue
            key = basename.lower()
            if key not in matched_lookup:
                skipped += 1
                continue

            entry     = matched_lookup[key]
            file_data = zf.read(member.filename)
            paths     = entry.get("paths", ["bios"])

            for dest_rel in paths:
                dest_dir  = os.path.join(retrodeck_dir, dest_rel)
                os.makedirs(dest_dir, exist_ok=True)
                dest_path = os.path.join(dest_dir, entry["filename"])
                with open(dest_path, 'wb') as out:
                    out.write(file_data)

            copied += 1

except zipfile.BadZipFile:
    print(f"  ERROR: {zip_path} is not a valid zip file.")
    sys.exit(1)

print(f"  Copied:  {copied} file(s) into retrodeck/ folder structure.")
print(f"  Skipped: {skipped} file(s) (no hash match or not in manifest).")

print(f"\n  Folder structure created:")
for root, dirs, files in os.walk(retrodeck_dir):
    dirs.sort()
    rel    = os.path.relpath(root, retrodeck_dir)
    depth  = 0 if rel == "." else rel.count(os.sep) + 1
    indent = "    " + "  " * depth
    folder = "retrodeck/" if rel == "." else os.path.basename(root) + "/"
    print(f"{indent}{folder}  ({len(files)} file(s))")
PYEOF


# --- Step 6: Optionally populate live RetroDECK directory ---
echo ""
echo "======================================================="
echo "  Populate Live RetroDECK Directory"
echo "======================================================="
echo ""
echo -n "Would you like to populate your existing RetroDECK directory? (Y/N): "
read -r CONFIRM_POPULATE

if [[ "$CONFIRM_POPULATE" =~ ^[Yy]$ ]]; then
    echo ""
    echo "  ****WARNING****"
    echo "  This action will overwrite any existing files that conflict."
    echo "  Compatibility is not guaranteed."
    echo "  You may wish to manually copy the files instead."
    echo ""
    echo -n "  Do you wish to proceed with populating the RetroDECK directory? (Y/N): "
    read -r CONFIRM_OVERWRITE

    if [[ "$CONFIRM_OVERWRITE" =~ ^[Yy]$ ]]; then

        DEFAULT_LIVE_DIR="$HOME/retrodeck"
        echo ""
        echo "Confirm location of your live RetroDECK directory."
        echo "Use default: $DEFAULT_LIVE_DIR"
        echo -n "  Y to proceed, N to enter alternate location: "
        read -r CONFIRM_LIVE_DIR

        if [[ "$CONFIRM_LIVE_DIR" =~ ^[Nn]$ ]]; then
            echo -n "Enter alternate path to RetroDECK directory: "
            read -r LIVE_DIR
        else
            LIVE_DIR="$DEFAULT_LIVE_DIR"
        fi

        if [[ ! -d "$LIVE_DIR" ]]; then
            echo "  ERROR: Directory not found: $LIVE_DIR"
            echo "  Skipping live population."
        else
            echo ""
            echo "Copying files from: $RETRODECK_DIR"
            echo "              into: $LIVE_DIR"
            echo ""

            # rsync: archive mode, overwrite existing, leave non-conflicting files untouched
            # --checksum ensures we only overwrite if content actually differs
            rsync -av --checksum "$RETRODECK_DIR/" "$LIVE_DIR/"
            RSYNC_EXIT=$?

            if [[ $RSYNC_EXIT -eq 0 ]]; then
                echo ""
                echo "  Population complete."
            else
                echo ""
                echo "  WARNING: rsync exited with code $RSYNC_EXIT. Some files may not have copied."
            fi
        fi

    else
        echo "  Cancelled. Live directory was not modified."
    fi
else
    echo "  Skipping live population."
fi


# --- Step 7: Optional CSV Report ---
echo ""
echo "======================================================="
echo "  Generate Report"
echo "======================================================="
echo ""
echo -n "Would you like a CSV report? (Y/N): "
read -r CONFIRM_REPORT

if [[ "$CONFIRM_REPORT" =~ ^[Yy]$ ]]; then

    DEFAULT_REPORT_DIR="$TOOL_DIR"
    echo ""
    echo "Confirm location for the report CSV."
    echo "Use default: $DEFAULT_REPORT_DIR"
    echo -n "  Y to proceed, N to enter alternate location: "
    read -r CONFIRM_REPORT_DIR

    if [[ "$CONFIRM_REPORT_DIR" =~ ^[Nn]$ ]]; then
        echo -n "Enter alternate directory for report: "
        read -r REPORT_DIR
    else
        REPORT_DIR="$DEFAULT_REPORT_DIR"
    fi

    REPORT_FILE="$REPORT_DIR/retrodeck_bios_report.csv"

    python3 - "$OUTPUT_FILE" "$REPORT_FILE" << 'PYEOF'
import json
import csv
import sys
import os

manifest_path = sys.argv[1]
report_path   = sys.argv[2]

with open(manifest_path, 'r') as f:
    manifest = json.load(f)

os.makedirs(os.path.dirname(report_path) if os.path.dirname(report_path) else ".", exist_ok=True)

def fmt(val):
    """Flatten list or string to pipe-separated string."""
    if isinstance(val, list):
        return " | ".join(str(v) for v in val if v)
    return str(val) if val else ""

def present_status(entry):
    actual   = entry.get("actual_md5", "")
    expected = entry.get("expected_md5", "")

    # File was never found in the zip at all
    if not actual:
        return "No"

    # File was found but hash didn't match
    if isinstance(expected, list):
        matched = actual in expected
    else:
        matched = (actual == expected)

    if matched:
        return "Yes"
    else:
        return "Not copied due to checksum mismatch"

def fmt_expected_md5(val):
    """Format expected_md5 for CSV, noting if missing from manifests."""
    if not val or val == "" or val == []:
        return "Missing from RetroDECK manifests"
    if isinstance(val, list):
        return " | ".join(str(v) for v in val if v)
    return str(val)

with open(report_path, 'w', newline='', encoding='utf-8') as csvfile:
    writer = csv.writer(csvfile)
    writer.writerow(["Filename", "System", "Paths", "Required", "Expected MD5", "Actual MD5", "Present"])

    for entry in manifest:
        writer.writerow([
            entry.get("filename", ""),
            fmt(entry.get("system", "")),
            fmt(entry.get("paths", [])),
            entry.get("required", "").strip() or "No",
            fmt_expected_md5(entry.get("expected_md5", "")),
            entry.get("actual_md5", "") or "",
            present_status(entry)
        ])

total    = len(manifest)
yes      = sum(1 for e in manifest if present_status(e) == "Yes")
no       = sum(1 for e in manifest if present_status(e) == "No")
mismatch = sum(1 for e in manifest if present_status(e) == "Not copied due to checksum mismatch")

print(f"  Report saved to: {report_path}")
print(f"  Total entries:   {total}")
print(f"  Present (Yes):   {yes}")
print(f"  Missing (No):    {no}")
print(f"  Checksum mismatch: {mismatch}")
PYEOF

else
    echo "  Skipping report."
fi


# --- Step 8: Cleanup ---
echo ""
echo "======================================================="
echo "  Cleanup"
echo "======================================================="
echo ""

echo -n "Do you wish to delete the combined_manifest.json? (Y/N): "
read -r CONFIRM_DEL_MANIFEST
if [[ "$CONFIRM_DEL_MANIFEST" =~ ^[Yy]$ ]]; then
    if [[ -f "$OUTPUT_FILE" ]]; then
        rm -f "$OUTPUT_FILE"
        echo "  Deleted: $OUTPUT_FILE"
    else
        echo "  Not found, skipping: $OUTPUT_FILE"
    fi
else
    echo "  Keeping: $OUTPUT_FILE"
fi

echo ""
echo -n "Do you wish to delete the temporary retrodeck staging folder? (Y/N): "
read -r CONFIRM_DEL_STAGING
if [[ "$CONFIRM_DEL_STAGING" =~ ^[Yy]$ ]]; then
    # Only delete the staging folder (defaults to Desktop), never the live ~/retrodeck
    if [[ "$RETRODECK_DIR" == "$HOME/retrodeck" ]]; then
        echo "  SAFETY CHECK: Staging folder appears to be the live RetroDECK directory."
        echo "  Refusing to delete: $RETRODECK_DIR"
    elif [[ -d "$RETRODECK_DIR" ]]; then
        rm -rf "$RETRODECK_DIR"
        echo "  Deleted: $RETRODECK_DIR"
    else
        echo "  Not found, skipping: $RETRODECK_DIR"
    fi
else
    echo "  Keeping: $RETRODECK_DIR"
fi

echo ""
echo "======================================================="
echo "  All done. Goodbye!"
echo "======================================================="
echo ""
