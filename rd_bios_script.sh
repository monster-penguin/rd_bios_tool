#!/bin/bash

# Detect the directory this script lives in (the rd_bios_tool folder)
TOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Initialise source arrays — populated later only if user creates a new zip
DOWNLOAD_SOURCES=()
LOCAL_SOURCES=()

# --- Load config file ---
CONFIG_FILE="$TOOL_DIR/rd_bios_tool.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo ""
    echo "  WARNING: rd_bios_tool.conf not found in $TOOL_DIR"
    echo "  Using built-in defaults. Consider adding the config file."
    echo ""
    # Built-in fallback defaults
    RD_MANIFEST_SOURCE="/var/lib/flatpak/app/net.retrodeck.retrodeck/current/active/files/retrodeck/components"
    RD_LIVE_DIR="$HOME/retrodeck"
    RD_TESTED_VERSION="0.10.6b"
    RD_BIOS_FOLDER="bios"
    RD_SAVES_FOLDER="saves"
    RD_ROMS_FOLDER="roms"
    RD_MANIFEST_OUTPUT="$TOOL_DIR/combined_manifest.json"
    RD_BIOS_ZIP="$TOOL_DIR/rd_bios_set.zip"
    RD_STAGING_DIR="$TOOL_DIR/retrodeck"
    RD_REPORT_DIR="$TOOL_DIR"
    RD_FAILED_HASH_DIR="$TOOL_DIR/failed_hash_checks"
fi


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
echo "  version $RD_TESTED_VERSION."
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
echo "  Step 1 & 2 - RetroDECK Component Manifest Builder"
echo "======================================================="
echo ""

# --- Step 1: Confirm manifest source directory ---
DEFAULT_SOURCE="$RD_MANIFEST_SOURCE"
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

# --- Step 2: Confirm combined_manifest.json output location ---
DEFAULT_OUTPUT="$RD_MANIFEST_OUTPUT"
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

python3 - "$TMPFILE" "$OUTPUT_FILE" "$RD_BIOS_FOLDER" "$RD_SAVES_FOLDER" "$RD_ROMS_FOLDER" << 'PYEOF'
import json
import os
import sys
import re

list_file    = sys.argv[1]
output_file  = sys.argv[2]
bios_folder  = sys.argv[3] if len(sys.argv) > 3 else "bios"
saves_folder = sys.argv[4] if len(sys.argv) > 4 else "saves"
roms_folder  = sys.argv[5] if len(sys.argv) > 5 else "roms"

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
    p = p.replace("$bios_path",  bios_folder)
    p = p.replace("$saves_path", saves_folder)
    p = p.replace("$roms_path",  roms_folder)
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

# --- Step 4: BIOS Set Selection ---
echo ""
echo "======================================================="
echo "  BIOS Set Selection"
echo "======================================================="
echo ""
echo "  Do you have an existing rd_bios_set.zip or would you"
echo "  like to create a new one?"
echo ""
echo "    E - Use existing rd_bios_set.zip"
echo "    C - Create a new rd_bios_set.zip"
echo ""
echo -n "  Your choice (E/C): "
read -r BIOS_SET_CHOICE

if [[ "$BIOS_SET_CHOICE" =~ ^[Ee]$ ]]; then
    echo ""
    echo "  Using existing rd_bios_set.zip. Proceeding to Step 8."

else
    # --- Step 4 sub: Check for existing rd_bios_set.zip ---
    EXISTING_ZIP="$RD_BIOS_ZIP"
    ZIP_MODE="overwrite"

    if [[ -f "$EXISTING_ZIP" ]]; then
        echo ""
        echo "  ****WARNING****"
        echo "  An existing rd_bios_set.zip was found."
        echo ""
        echo "    A - Add new files to the existing archive"
        echo "    O - Overwrite the existing archive"
        echo ""
        echo -n "  Your choice (A/O): "
        read -r ARCHIVE_CHOICE

        if [[ "$ARCHIVE_CHOICE" =~ ^[Aa]$ ]]; then
            ZIP_MODE="append"
        else
            ZIP_MODE="overwrite"
        fi

        echo ""
        echo "  ****WARNING****"
        echo "  This operation cannot be undone."
        echo ""
        echo -n "  Do you wish to proceed? (Y/N): "
        read -r CONFIRM_ARCHIVE_OP
        if [[ ! "$CONFIRM_ARCHIVE_OP" =~ ^[Yy]$ ]]; then
            echo ""
            echo "  Cancelled. rd_bios_set.zip was not modified."
            echo ""
            exit 0
        fi
    fi

    # Staging area for matched files before zipping
    STAGE_DIR=$(mktemp -d /tmp/rd_bios_stage.XXXXXX)
    echo ""
    echo "  Temporary staging directory created."

    # Load manifest filenames into a lookup file
    NAMES_FILE=$(mktemp /tmp/rd_bios_names.XXXXXX)
    python3 - "$OUTPUT_FILE" "$NAMES_FILE" << 'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    manifest = json.load(f)
names = set(e["filename"].lower() for e in manifest)
with open(sys.argv[2], "w") as f:
    for n in names:
        f.write(n + "\n")
print(f"  Manifest contains {len(names)} target filenames.")
PYEOF

    # --- Step 5: Download a BIOS Set from the Internet ---
    echo ""
    echo "======================================================="
    echo "  Step 5: Download a BIOS Set from the Internet"
    echo "======================================================="
    echo ""
    echo -n "  Would you like to download a BIOS set from a URL? (Y/N): "
    read -r CONFIRM_DOWNLOAD

    if [[ "$CONFIRM_DOWNLOAD" =~ ^[Yy]$ ]]; then
        URL_COUNT=0
        MAX_URLS=5

        while [[ $URL_COUNT -lt $MAX_URLS ]]; do
            echo ""
            if [[ $URL_COUNT -eq 0 ]]; then
                echo -n "  Enter URL 1 of up to $MAX_URLS: "
            else
                echo -n "  Enter URL $(( URL_COUNT + 1 )) of up to $MAX_URLS (or press Enter to finish): "
            fi
            read -r DOWNLOAD_URL

            if [[ -z "$DOWNLOAD_URL" ]]; then
                echo "  No URL entered. Moving on."
                break
            fi

            DL_FILENAME="$(basename "$DOWNLOAD_URL")"
            [[ -z "$DL_FILENAME" || "$DL_FILENAME" == "." ]] && DL_FILENAME="downloaded_bios_$(( URL_COUNT + 1 )).zip"
            DL_DEST="$TOOL_DIR/$DL_FILENAME"

            echo ""
            echo "  Downloading: $DOWNLOAD_URL"
            echo "  Saving to:   $DL_DEST"
            echo ""

            if command -v wget &>/dev/null; then
                wget --show-progress -q -O "$DL_DEST" "$DOWNLOAD_URL"
                DL_EXIT=$?
            elif command -v curl &>/dev/null; then
                curl -L --progress-bar -o "$DL_DEST" "$DOWNLOAD_URL"
                DL_EXIT=$?
            else
                echo "  ERROR: Neither wget nor curl is available."
                DL_EXIT=1
            fi

            if [[ $DL_EXIT -eq 0 ]]; then
                echo "  Download complete: $DL_DEST"
                DOWNLOAD_SOURCES+=("$DL_DEST")
                URL_COUNT=$(( URL_COUNT + 1 ))
            else
                echo "  WARNING: Download failed. Skipping."
                [[ -f "$DL_DEST" ]] && rm -f "$DL_DEST"
            fi

            if [[ $URL_COUNT -ge $MAX_URLS ]]; then
                echo ""
                echo "  Maximum of $MAX_URLS URLs reached."
                break
            fi

            echo -n "  Would you like to add another URL? (Y/N): "
            read -r ADD_ANOTHER_URL
            if [[ ! "$ADD_ANOTHER_URL" =~ ^[Yy]$ ]]; then
                break
            fi
        done

        echo ""
        echo "  $URL_COUNT URL(s) queued for processing."
    fi

    # --- Step 6: Scan a Local Directory ---
    echo ""
    echo "======================================================="
    echo "  Step 6: Scan a Local Directory"
    echo "======================================================="
    echo ""
    echo -n "  Would you like to scan a local directory for BIOS files? (Y/N): "
    read -r CONFIRM_LOCAL

    if [[ "$CONFIRM_LOCAL" =~ ^[Yy]$ ]]; then
        DIR_COUNT=0
        MAX_DIRS=5

        while [[ $DIR_COUNT -lt $MAX_DIRS ]]; do
            echo ""
            if [[ $DIR_COUNT -eq 0 ]]; then
                echo -n "  Enter directory path 1 of up to $MAX_DIRS: "
            else
                echo -n "  Enter directory path $(( DIR_COUNT + 1 )) of up to $MAX_DIRS (or press Enter to finish): "
            fi
            read -r LOCAL_DIR

            if [[ -z "$LOCAL_DIR" ]]; then
                echo "  No path entered. Moving on."
                break
            fi

            if [[ -d "$LOCAL_DIR" ]]; then
                LOCAL_SOURCES+=("$LOCAL_DIR")
                echo "  Directory confirmed: $LOCAL_DIR"
                DIR_COUNT=$(( DIR_COUNT + 1 ))
            else
                echo "  WARNING: Directory not found. Skipping."
            fi

            if [[ $DIR_COUNT -ge $MAX_DIRS ]]; then
                echo ""
                echo "  Maximum of $MAX_DIRS directories reached."
                break
            fi

            echo -n "  Would you like to add another directory? (Y/N): "
            read -r ADD_ANOTHER_DIR
            if [[ ! "$ADD_ANOTHER_DIR" =~ ^[Yy]$ ]]; then
                break
            fi
        done

        echo ""
        echo "  $DIR_COUNT director(ies) queued for processing."
    fi

    # --- Step 7: Extract and match files ---
    echo ""
    echo "======================================================="
    echo "  Step 7: Building rd_bios_set.zip"
    echo "======================================================="
    echo ""

    # Check for required extraction tools
    for tool in unzip 7z unar; do
        command -v $tool &>/dev/null && echo "  Found: $tool" || echo "  Not found (optional): $tool"
    done
    echo ""

    python3 - "$NAMES_FILE" "$STAGE_DIR" "$OUTPUT_FILE" "$RD_BIOS_ZIP" "${DOWNLOAD_SOURCES[@]}" "${LOCAL_SOURCES[@]}" << 'PYEOF'
import sys, os, json, hashlib, shutil, zipfile, tarfile, tempfile, subprocess

names_file    = sys.argv[1]
stage_dir     = sys.argv[2]
manifest_path = sys.argv[3]
existing_zip  = sys.argv[4]
sources       = sys.argv[5:]  # mix of files and directories

with open(names_file) as f:
    target_names = set(line.strip().lower() for line in f if line.strip())

def md5_of_bytes(data):
    return hashlib.md5(data).hexdigest()

# ── Load manifest and existing zip contents ONCE up front ────────────────────
try:
    with open(manifest_path) as f:
        _manifest = json.load(f)
    _manifest_lookup = {e["filename"].lower(): e for e in _manifest}
except Exception:
    _manifest_lookup = {}

_zip_passing = set()   # filenames (lowercase) already in zip with a passing hash
if os.path.isfile(existing_zip):
    try:
        with zipfile.ZipFile(existing_zip, "r") as _zf:
            for _m in _zf.infolist():
                _bn = os.path.basename(_m.filename).lower()
                if not _bn or _bn not in _manifest_lookup:
                    continue
                _expected = _manifest_lookup[_bn].get("expected_md5", "")
                if not _expected:
                    continue
                _data   = _zf.read(_m.filename)
                _actual = md5_of_bytes(_data)
                if isinstance(_expected, list):
                    _passes = _actual in _expected
                else:
                    _passes = _actual == _expected
                if _passes:
                    _zip_passing.add(_bn)
    except Exception:
        pass

def existing_entry_passes_hash(filename_lower):
    """Returns True if the file is already in rd_bios_set.zip with a passing hash."""
    return filename_lower in _zip_passing

copied   = 0
skipped  = 0
examined = 0

def try_extract(filepath, extract_to):
    """Attempt extraction using all available tools. Returns True if successful."""
    ext = os.path.splitext(filepath)[1].lower()
    try:
        if ext == ".zip" and zipfile.is_zipfile(filepath):
            with zipfile.ZipFile(filepath, "r") as zf:
                zf.extractall(extract_to)
            return True
    except Exception:
        pass
    for tool, args in [
        ("7z",   ["7z", "x", "-y", f"-o{extract_to}", filepath]),
        ("unar", ["unar", "-o", extract_to, "-f", filepath]),
        ("tar",  ["tar", "-xf", filepath, "-C", extract_to]),
    ]:
        if shutil.which(tool):
            try:
                result = subprocess.run(args, capture_output=True, timeout=120)
                if result.returncode == 0:
                    return True
            except Exception:
                pass
    return False

def process_file(filepath, depth=0):
    """Check if file matches target; if it's an archive, extract and recurse."""
    global copied, skipped, examined
    if depth > 6:
        return
    examined += 1
    basename = os.path.basename(filepath)
    key      = basename.lower()

    if key in target_names:
        dest = os.path.join(stage_dir, basename)

        if os.path.exists(dest):
            # Already staged this session — do not overwrite
            skipped += 1
            print(f"  Skipped (already staged this session): {basename}")
            return

        if existing_entry_passes_hash(key):
            # Already in rd_bios_set.zip with a passing hash — do not overwrite
            skipped += 1
            print(f"  Skipped (existing entry passes hash check): {basename}")
            return

        shutil.copy2(filepath, dest)
        copied += 1
        print(f"  Matched: {basename}")
        return

    # Try to extract as archive
    ext = os.path.splitext(filepath)[1].lower()
    if ext in (".zip", ".7z", ".rar", ".tar", ".gz", ".bz2", ".xz",
               ".tar.gz", ".tar.bz2", ".tar.xz", ".iso", ".cbz"):
        tmpdir = tempfile.mkdtemp()
        try:
            if try_extract(filepath, tmpdir):
                for root, dirs, files in os.walk(tmpdir):
                    for fn in files:
                        process_file(os.path.join(root, fn), depth + 1)
        except Exception as e:
            pass
        finally:
            shutil.rmtree(tmpdir, ignore_errors=True)

# Process all sources
for source in sources:
    if not source:
        continue
    if os.path.isfile(source):
        process_file(source)
    elif os.path.isdir(source):
        for root, dirs, files in os.walk(source):
            for fn in files:
                process_file(os.path.join(root, fn))

print(f"  Examined: {examined} file(s)")
print(f"  Matched:  {copied} file(s) staged for archive")
print(f"  Skipped:  {skipped} file(s) (existing passing entries protected)")
PYEOF

    # --- Step 7 cont: Pack staged files into rd_bios_set.zip ---
    DEST_ZIP="$RD_BIOS_ZIP"

    if [[ "$ZIP_MODE" == "overwrite" && -f "$DEST_ZIP" ]]; then
        rm -f "$DEST_ZIP"
        echo "  Existing archive removed."
    fi

    python3 - "$STAGE_DIR" "$DEST_ZIP" "$ZIP_MODE" "$OUTPUT_FILE" << 'PYEOF'
import sys, os, zipfile, hashlib, json, shutil, tempfile

stage_dir     = sys.argv[1]
dest_zip      = sys.argv[2]
mode          = sys.argv[3]  # "overwrite" or "append"
manifest_path = sys.argv[4]

def md5_of_bytes(data):
    return hashlib.md5(data).hexdigest()

def entry_passes_hash(manifest, filename_lower, data):
    """Check if the provided file data passes the expected hash from the manifest."""
    lookup = {e["filename"].lower(): e for e in manifest}
    if filename_lower not in lookup:
        return False
    expected = lookup[filename_lower].get("expected_md5", "")
    if not expected:
        return False
    actual = md5_of_bytes(data)
    if isinstance(expected, list):
        return actual in expected
    return actual == expected

try:
    with open(manifest_path) as f:
        manifest = json.load(f)
except Exception:
    manifest = []

stage_files = [f for f in os.listdir(stage_dir) if os.path.isfile(os.path.join(stage_dir, f))]

packed   = 0
replaced = 0
skipped  = 0

if mode == "overwrite" or not os.path.isfile(dest_zip):
    # Clean write — no existing entries to protect
    with zipfile.ZipFile(dest_zip, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for fn in stage_files:
            zf.write(os.path.join(stage_dir, fn), arcname=fn)
            packed += 1
else:
    # Append mode — rewrite zip, protecting any existing entries that pass their hash
    tmp_path = dest_zip + ".tmp"

    # Build a set of filenames already in the zip (lowercase) without reading data yet
    with zipfile.ZipFile(dest_zip, "r") as _zin_index:
        existing_members = {
            os.path.basename(m.filename).lower(): m
            for m in _zin_index.infolist()
            if os.path.basename(m.filename)
        }

    stage_lookup = {fn.lower(): fn for fn in stage_files}

    with zipfile.ZipFile(dest_zip, "r") as zin, \
         zipfile.ZipFile(tmp_path, "w", compression=zipfile.ZIP_DEFLATED) as zout:

        # Write existing entries — stream one at a time to avoid loading all into RAM
        for key, member in existing_members.items():
            basename = os.path.basename(member.filename)
            if key in stage_lookup:
                # Read only this one file to check its hash
                data = zin.read(member.filename)
                existing_passes = entry_passes_hash(manifest, key, data)
                if existing_passes:
                    zout.writestr(member, data)
                    skipped += 1
                    print(f"  Protected (existing passes hash): {basename}")
                else:
                    with open(os.path.join(stage_dir, stage_lookup[key]), "rb") as _fh:
                        new_data = _fh.read()
                    zout.writestr(member.filename, new_data)
                    replaced += 1
                    print(f"  Replaced (existing failed hash): {basename}")
            else:
                # Stream directly without loading the whole file at once
                zout.writestr(member, zin.read(member.filename))

        # Add staged files not already in the zip
        for fn in stage_files:
            if fn.lower() not in existing_members:
                zout.write(os.path.join(stage_dir, fn), arcname=fn)
                packed += 1

    shutil.move(tmp_path, dest_zip)

print(f"  Packed {packed} new file(s) into rd_bios_set.zip.")
if replaced:
    print(f"  Replaced {replaced} file(s) (previous entry failed hash check).")
if skipped:
    print(f"  Protected {skipped} file(s) (existing entry already passes hash check).")
print(f"  Archive saved to: {dest_zip}")
PYEOF

    # Cleanup staging
    rm -rf "$STAGE_DIR"
    rm -f "$NAMES_FILE"
    echo ""
    echo "  rd_bios_set.zip is ready."
fi

# --- Step 8: Scan rd_bios_set.zip for actual MD5s ---
echo ""
echo "======================================================="
echo "  Step 8: BIOS Archive Scanner"
echo "======================================================="
echo ""

DEFAULT_ZIP="$RD_BIOS_ZIP"
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

# Reset all actual_md5 fields before scanning so stale results from previous
# runs do not persist for files that may have been removed from the archive.
python3 - "$OUTPUT_FILE" << 'PYEOF'
import json, sys
with open(sys.argv[1], 'r') as f:
    manifest = json.load(f)
for entry in manifest:
    entry["actual_md5"] = ""
with open(sys.argv[1], 'w') as f:
    json.dump(manifest, f, indent=2)
PYEOF

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

# --- Step 9: Copy matched files into retrodeck folder structure ---
echo ""
echo "======================================================="
echo "  Step 9: Build retrodeck/ Folder Structure"
echo "======================================================="
echo ""

DEFAULT_RETRODECK_DIR="$RD_STAGING_DIR"
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
    if not expected:
        return False
    if isinstance(expected, list):
        return actual in expected
    return actual == expected

def has_hash_mismatch(entry):
    """File was found in archive but hash did not match expected."""
    actual   = entry.get("actual_md5", "")
    expected = entry.get("expected_md5", "")
    if not actual or not expected:
        return False
    if isinstance(expected, list):
        return actual not in expected
    return actual != expected

matched_lookup  = {e["filename"].lower(): e for e in manifest if is_match(e)}

copied        = 0
skipped_mismatch  = 0
skipped_no_hash   = 0
skipped_not_found = 0

try:
    with zipfile.ZipFile(zip_path, 'r') as zf:
        members = [m for m in zf.infolist() if not m.filename.endswith('/')]
        for member in members:
            basename = os.path.basename(member.filename)
            if not basename:
                continue
            key = basename.lower()

            # Look up the manifest entry for this file
            manifest_entry = next((e for e in manifest if e["filename"].lower() == key), None)

            if key in matched_lookup:
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
            elif manifest_entry and has_hash_mismatch(manifest_entry):
                skipped_mismatch += 1
            elif manifest_entry and not manifest_entry.get("expected_md5", ""):
                skipped_no_hash += 1
            else:
                skipped_not_found += 1

except zipfile.BadZipFile:
    print(f"  ERROR: {zip_path} is not a valid zip file.")
    sys.exit(1)

print(f"  Copied:  {copied} file(s) into retrodeck/ folder structure.")
if skipped_mismatch:
    print(f"  Skipped: {skipped_mismatch} file(s) — hash mismatch (wrong version or corrupt).")
if skipped_no_hash:
    print(f"  Skipped: {skipped_no_hash} file(s) — no expected MD5 in manifests (cannot verify).")
if skipped_not_found:
    print(f"  Skipped: {skipped_not_found} file(s) — not found in manifest.")

print(f"\n  Folder structure created:")
for root, dirs, files in os.walk(retrodeck_dir):
    dirs.sort()
    rel    = os.path.relpath(root, retrodeck_dir)
    depth  = 0 if rel == "." else rel.count(os.sep) + 1
    indent = "    " + "  " * depth
    folder = "retrodeck/" if rel == "." else os.path.basename(root) + "/"
    print(f"{indent}{folder}  ({len(files)} file(s))")
PYEOF


# --- Step 10: Report and handle failed hash checks ---
echo ""
echo "======================================================="
echo "  Step 10: Failed Hash Check Report"
echo "======================================================="
echo ""

FAILED_HASH_DIR=""

# Single pass: print failures to stderr for the user, capture count via stdout
HASH_FAIL_COUNT=$(python3 - "$OUTPUT_FILE" << 'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    manifest = json.load(f)
failed = []
for entry in manifest:
    actual   = entry.get("actual_md5", "")
    expected = entry.get("expected_md5", "")
    if not actual or not expected:
        continue
    if isinstance(expected, list):
        matched = actual in expected
    else:
        matched = actual == expected
    if not matched:
        failed.append(entry["filename"])
if len(failed) == 0:
    print("  All files with matching filenames passed hash checks.", file=sys.stderr)
else:
    print(f"  {len(failed)} file(s) with a matching filename have failed hash checks:", file=sys.stderr)
    for fn in failed:
        print(f"    - {fn}", file=sys.stderr)
print(len(failed))
PYEOF
)

if [[ "$HASH_FAIL_COUNT" -gt 0 ]]; then
    echo ""
    echo -n "  Would you like to save these files to a separate folder? (Y/N): "
    read -r CONFIRM_SAVE_FAILED

    if [[ "$CONFIRM_SAVE_FAILED" =~ ^[Yy]$ ]]; then
        DEFAULT_FAILED_DIR="$RD_FAILED_HASH_DIR"
        echo ""
        echo "  Confirm destination folder for failed hash check files."
        echo "  Use default: $DEFAULT_FAILED_DIR"
        echo -n "  Y to proceed, N to enter alternate location: "
        read -r CONFIRM_FAILED_DIR

        if [[ "$CONFIRM_FAILED_DIR" =~ ^[Nn]$ ]]; then
            echo -n "  Enter alternate path: "
            read -r FAILED_HASH_DIR
        else
            FAILED_HASH_DIR="$DEFAULT_FAILED_DIR"
        fi

        mkdir -p "$FAILED_HASH_DIR"

        python3 - "$ZIP_FILE" "$OUTPUT_FILE" "$FAILED_HASH_DIR" << 'PYEOF'
import json, os, sys, zipfile, hashlib

zip_path      = sys.argv[1]
manifest_path = sys.argv[2]
output_dir    = sys.argv[3]

def md5_of_bytes(data):
    return hashlib.md5(data).hexdigest()

with open(manifest_path, 'r') as f:
    manifest = json.load(f)

failed_names = set()
for entry in manifest:
    actual   = entry.get("actual_md5", "")
    expected = entry.get("expected_md5", "")
    if not actual or not expected:
        continue
    if isinstance(expected, list):
        matched = actual in expected
    else:
        matched = actual == expected
    if not matched:
        failed_names.add(entry["filename"].lower())

saved = 0
try:
    with zipfile.ZipFile(zip_path, 'r') as zf:
        for member in zf.infolist():
            basename = os.path.basename(member.filename)
            if not basename:
                continue
            if basename.lower() in failed_names:
                data = zf.read(member.filename)
                dest = os.path.join(output_dir, basename)
                with open(dest, 'wb') as out:
                    out.write(data)
                saved += 1
except zipfile.BadZipFile:
    print(f"  ERROR: {zip_path} is not a valid zip file.")
    sys.exit(1)

print(f"  Saved {saved} file(s) to: {output_dir}")
PYEOF

    else
        echo "  Skipping. Failed hash check files were not saved."
    fi
else
    echo "  No failed hash checks to report."
fi


# --- Step 11: Optionally populate live RetroDECK directory ---
echo ""
echo "======================================================="
echo "  Step 11: Populate Live RetroDECK Directory"
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

        DEFAULT_LIVE_DIR="$RD_LIVE_DIR"
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


# --- Step 12: Optional CSV Report ---
echo ""
echo "======================================================="
echo "  Step 12: Generate Report"
echo "======================================================="
echo ""
echo -n "Would you like a CSV report? (Y/N): "
read -r CONFIRM_REPORT

if [[ "$CONFIRM_REPORT" =~ ^[Yy]$ ]]; then

    DEFAULT_REPORT_DIR="$RD_REPORT_DIR"
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


# --- Step 13: Cleanup ---
echo ""
echo "======================================================="
echo "  Step 13: Cleanup"
echo "======================================================="
echo ""
echo "  Choose what to clean up. No files will be deleted until"
echo "  all choices have been made."
echo ""

# ── Collect all choices first ────────────────────────────────────────────────

echo -n "  Delete combined_manifest.json? (Y/N): "
read -r CONFIRM_DEL_MANIFEST

echo -n "  Delete the temporary retrodeck staging folder? (Y/N): "
read -r CONFIRM_DEL_STAGING

echo -n "  Delete rd_bios_set.zip? (Y/N): "
read -r CONFIRM_DEL_ZIP

CONFIRM_SCRUB_ZIP="N"
if [[ ! "$CONFIRM_DEL_ZIP" =~ ^[Yy]$ && "$HASH_FAIL_COUNT" -gt 0 && -f "$ZIP_FILE" ]]; then
    echo ""
    echo "  $HASH_FAIL_COUNT file(s) in rd_bios_set.zip failed hash checks."
    echo "  Would you like to scrub these files from rd_bios_set.zip?"
    echo "  This will remove any file whose filename matched the manifest"
    echo "  but whose MD5 hash did not match the expected value."
    echo ""
    echo -n "  Scrub failed hash check files from rd_bios_set.zip? (Y/N): "
    read -r CONFIRM_SCRUB_ZIP
fi

CONFIRM_DEL_DOWNLOADS="N"
if [[ ${#DOWNLOAD_SOURCES[@]} -gt 0 ]]; then
    echo -n "  Delete files downloaded from the internet this session? (Y/N): "
    read -r CONFIRM_DEL_DOWNLOADS
fi

# ── Execute all deletions ─────────────────────────────────────────────────────

echo ""
echo "  Applying changes..."
echo ""

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

if [[ "$CONFIRM_DEL_STAGING" =~ ^[Yy]$ ]]; then
    STAGING_REAL="$(realpath "$RETRODECK_DIR" 2>/dev/null)"
    LIVE_REAL="$(realpath "$RD_LIVE_DIR" 2>/dev/null)"
    HOME_RD_REAL="$(realpath "$HOME/retrodeck" 2>/dev/null)"
    if [[ "$STAGING_REAL" == "$LIVE_REAL" || "$STAGING_REAL" == "$HOME_RD_REAL" ]]; then
        echo "  SAFETY CHECK: Staging folder resolves to the live RetroDECK directory."
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

if [[ "$CONFIRM_DEL_ZIP" =~ ^[Yy]$ ]]; then
    if [[ -f "$ZIP_FILE" ]]; then
        rm -f "$ZIP_FILE"
        echo "  Deleted: $ZIP_FILE"
    else
        echo "  Not found, skipping: $ZIP_FILE"
    fi
else
    echo "  Keeping: $ZIP_FILE"
    if [[ "$CONFIRM_SCRUB_ZIP" =~ ^[Yy]$ ]]; then
        echo ""
        python3 - "$ZIP_FILE" "$OUTPUT_FILE" << 'PYEOF'
import json, os, sys, zipfile, shutil

zip_path      = sys.argv[1]
manifest_path = sys.argv[2]

with open(manifest_path, 'r') as f:
    manifest = json.load(f)

failed_names = set()
for entry in manifest:
    actual   = entry.get("actual_md5", "")
    expected = entry.get("expected_md5", "")
    if not actual or not expected:
        continue
    if isinstance(expected, list):
        matched = actual in expected
    else:
        matched = actual == expected
    if not matched:
        failed_names.add(entry["filename"].lower())

if not failed_names:
    print("  Nothing to scrub.")
    sys.exit(0)

tmp_path = zip_path + ".tmp"
removed  = 0
kept     = 0

try:
    with zipfile.ZipFile(zip_path, 'r') as zin, \
         zipfile.ZipFile(tmp_path, 'w', compression=zipfile.ZIP_DEFLATED) as zout:
        for member in zin.infolist():
            basename = os.path.basename(member.filename)
            if basename.lower() in failed_names:
                print(f"  Scrubbed: {basename}")
                removed += 1
            else:
                zout.writestr(member, zin.read(member.filename))
                kept += 1
except Exception as e:
    print(f"  ERROR during scrub: {e}")
    if os.path.exists(tmp_path):
        os.remove(tmp_path)
    sys.exit(1)

shutil.move(tmp_path, zip_path)
print(f"  Scrub complete. Removed: {removed} file(s), Kept: {kept} file(s).")
PYEOF
    else
        echo "  Skipping scrub. rd_bios_set.zip was not modified."
    fi
fi

if [[ "$CONFIRM_DEL_DOWNLOADS" =~ ^[Yy]$ ]]; then
    for dl_file in "${DOWNLOAD_SOURCES[@]}"; do
        if [[ -f "$dl_file" ]]; then
            rm -f "$dl_file"
            echo "  Deleted: $dl_file"
        fi
    done
elif [[ ${#DOWNLOAD_SOURCES[@]} -gt 0 ]]; then
    echo "  Keeping downloaded files."
fi

echo ""
echo "======================================================="
echo "  All done. Goodbye!"
echo "======================================================="
echo ""
