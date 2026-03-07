# ra_bios_tool

A personal utility for finding, verifying, and installing BIOS files for [RetroARCH](https://www.retroarch.com/).

> **Disclaimer:** This tool was created for the developer's personal use. It is not affiliated with RetroARCH in any way. Do not contact RetroARCH for support regarding this tool. The creator takes no responsibility for any damage caused by its use.

> **Version note:** Built and tested against **RetroARCH 1.22.2** (flatpak) on **Bazzite Linux**. There is no guarantee it will work with other versions.

---

## Contents

- [Folder Structure](#folder-structure)
- [Requirements](#requirements)
- [Configuration](#configuration)
- [Getting Started](#getting-started)
- [How to Run](#how-to-run)
- [Script Steps](#script-steps)
- [CSV Report Columns](#csv-report-columns)
- [Notes](#notes)

---

## Folder Structure

Place the following files in a folder before running:

```
ra_bios_tool/
├── ra_bios_script.sh        ← The script
├── ra_bios_tool.conf        ← Configuration file
└── README.md                ← This file
```

The script will create the following during a run:

```
ra_bios_tool/
├── combined_manifest.json      ← Generated BIOS database from RetroARCH .info files
├── ra_bios_set.zip             ← Your BIOS archive (built or supplied during the run)
├── <downloaded_file>.zip       ← Any file downloaded from the internet (Step 5)
├── retroarch/                  ← Staging folder with sorted BIOS files
│   └── system/                 ← Mirrors RetroARCH's system/ directory
│       ├── dc/
│       ├── PPSSPP/
│       └── ...
├── retroarch_bios_report.csv   ← Summary report of all BIOS files
└── failed_hash_checks/         ← Files that failed MD5 verification (optional)
```

The `retroarch/` staging folder mirrors the structure of RetroARCH's live config directory. Step 11 uses `rsync` to copy it directly into your live RetroARCH config directory with no additional renaming required.

---

## Requirements

| Requirement | Notes |
|---|---|
| Linux | Tested on Bazzite |
| bash | Standard |
| python3 | Standard |
| RetroARCH | Must be installed on the system (flatpak or standalone) |
| unzip | Recommended for archive scanning |
| 7z | Optional — adds `.7z` and additional format support |
| unar | Optional — adds `.rar` and additional format support |
| rsync | Required for Step 11 (live directory population) only |
| wget or curl | Required for Step 5 (URL download) only |

---

## Configuration

The script reads `ra_bios_tool.conf` at startup. This file must be in the same folder as the script. If it is missing, the script falls back to built-in defaults and displays a warning — it will still run normally.

### Section 1 — RetroARCH Installation Paths

| Variable | Description | Default |
|---|---|---|
| `RA_MANIFEST_SOURCE` | Where the script looks for RetroARCH's `.info` firmware files | Standard flatpak path |
| `RA_LIVE_DIR` | Your live RetroARCH config directory (the parent of `system/`, `saves/`, etc.). Used in Step 11 and by the Step 13 safety check to prevent accidental deletion of the live directory | `~/.var/app/org.libretro.RetroArch/config/retroarch` |
| `RA_TESTED_VERSION` | The RetroARCH version this tool was built against. Displayed in the startup warning | `1.22.2` |

### Section 2 — RetroARCH Internal Folder Names

These define the folder names used inside the `retroarch/` staging directory. They are deliberately chosen to match RetroARCH's own directory structure so that `rsync` (Step 11) maps the staging folder directly onto the live config directory.

| Variable | Folder name | RetroARCH directory |
|---|---|---|
| `RA_BIOS_FOLDER` | `system` | `retroarch/system/` — all firmware and BIOS files |
| `RA_SAVES_FOLDER` | `saves` | `retroarch/saves/` |
| `RA_ROMS_FOLDER` | `roms` | `retroarch/roms/` |

**How paths work:** RetroARCH `.info` files store firmware paths relative to the `system/` directory. For example, a `.info` entry with `firmware0_path = "dc/dc_boot.bin"` will be placed at `retroarch/system/dc/dc_boot.bin`, which maps directly to `~/.var/app/org.libretro.RetroArch/config/retroarch/system/dc/dc_boot.bin` in the live installation.

Only change these values if RetroARCH has renamed its internal folder structure.

### Section 3 — Tool Output Paths

All paths default to the `ra_bios_tool/` folder (`$TOOL_DIR`).

| Variable | Description |
|---|---|
| `RA_MANIFEST_OUTPUT` | Where `combined_manifest.json` is saved |
| `RA_BIOS_ZIP` | Path and filename for `ra_bios_set.zip` |
| `RA_STAGING_DIR` | Where the `retroarch/` staging folder is created |
| `RA_REPORT_DIR` | Directory where the CSV report is saved |
| `RA_FAILED_HASH_DIR` | Folder where files that failed MD5 checks are saved (Step 10) |

If RetroARCH ever changes its folder structure or installation path, update only the relevant lines in `ra_bios_tool.conf` — no changes to the script are required.

---

## Getting Started

You do not need anything other than the script and config file. `ra_bios_set.zip` is **not** a prerequisite — it is built during the run, or you can supply an existing one when prompted.

The basic workflow:

1. Run the script.
2. The script reads RetroARCH's `.info` core files to build a manifest of all expected BIOS and firmware files, along with their MD5 hashes and destination paths.
3. Supply your BIOS files by downloading from a URL (Step 5), scanning a local folder (Step 6), or both.
4. The script packages matched files into `ra_bios_set.zip`, verifies them by MD5 hash, and sorts them into the correct RetroARCH folder structure under `retroarch/system/`.
5. Optionally copy the result directly into your live RetroARCH config directory.

On subsequent runs you can use your existing `ra_bios_set.zip` and add to it incrementally as you find more files.

---

## How to Run

**First time only** — make the script executable:

```bash
chmod +x ~/Desktop/ra_bios_tool/ra_bios_script.sh
```

**Run the script:**

```bash
~/Desktop/ra_bios_tool/ra_bios_script.sh
```

**Or combined:**

```bash
chmod +x ~/Desktop/ra_bios_tool/ra_bios_script.sh && ~/Desktop/ra_bios_tool/ra_bios_script.sh
```

The script will guide you through each step with prompts. Press `Y` at each confirmation to accept the default path, or `N` to enter a custom one.

---

## Script Steps

| Step | Description |
|---|---|
| **1** | Confirm the location of your RetroARCH `.info` firmware files |
| **2** | Confirm where to save `combined_manifest.json` |
| **3** | Parse all discovered `.info` files and build `combined_manifest.json` — a unified BIOS database with filenames, MD5 hashes, systems, destination paths, and required status |
| **4** | BIOS Set Selection — choose `E` to use an existing `ra_bios_set.zip` as-is (skips to Step 8), `A` to add new files to an existing archive (runs Steps 5–7 in append mode), or `C` to create a new archive (Steps 5–7) |
| **5** | *(Optional)* Download up to 5 BIOS sets from URLs. Requires `wget` or `curl` |
| **6** | *(Optional)* Scan up to 5 local directories recursively. Supports `.zip`, `.7z`, `.rar`, `.tar`, `.gz`, and more, up to 6 levels deep |
| **7** | Match found files against the manifest, stage them, and pack into `ra_bios_set.zip` |
| **8** | Scan `ra_bios_set.zip`, compute MD5 hashes, and update the manifest |
| **9** | Build the `retroarch/` staging folder — copy all hash-verified files into the correct subfolder structure under `retroarch/system/` |
| **10** | Failed Hash Check Report — list files with matching filenames but wrong MD5s, with an option to save them to `failed_hash_checks/` |
| **11** | *(Optional)* Copy the staged files into your live RetroARCH config directory using `rsync` |
| **12** | *(Optional)* Generate a CSV report summarising every BIOS entry |
| **13** | *(Optional)* Cleanup |

### Step 4 — BIOS Set Selection

Three options are available:

| Choice | Behaviour |
|---|---|
| `E` — Use existing | Uses `ra_bios_set.zip` exactly as it is and skips straight to Step 8. No files are added or changed. |
| `A` — Add to existing | Runs Steps 5–7 in append mode. New files are added; files already present with a passing hash are protected. |
| `C` — Create new | Runs Steps 5–7. If a zip already exists, you will be asked whether to append or overwrite before proceeding. |

### How .info Files Are Parsed (Step 3)

RetroARCH distributes one `.info` file per core. Each file uses an INI-like `key = "value"` format. The script extracts:

- `firmware_count` — how many firmware entries the core declares
- `firmwareN_path` — path of the firmware file, relative to RetroARCH's `system/` directory
- `firmwareN_opt` — `"true"` if optional, `"false"` (or absent) if required
- `firmwareN_desc` — human-readable description
- MD5 hashes embedded in the `notes` field in the form `(!) filename.ext (md5): hexhash`

Where multiple cores list the same firmware file, entries are merged and all associated system names and MD5 hashes are combined.

### Step 7 — Overwrite Protection

Overwrite protection is applied at two levels when adding to an existing `ra_bios_set.zip`:

- A new file will **not** replace an existing entry if that entry already passes its MD5 hash check.
- A new file **will** replace an existing entry if that entry is present but has a failing or unverifiable hash.

This ensures a good file already in your archive can never be accidentally overwritten by a bad copy from a new source.

### Step 8 — Stale Hash Clearing

Before scanning, all previously recorded `actual_md5` values are cleared. This ensures results from a prior run never persist for files that have since been removed from the archive.

### Step 9 — Skip Categories

Files not copied into `retroarch/` are reported in three distinct categories:

| Category | Meaning |
|---|---|
| Hash mismatch | File found in archive but MD5 does not match expected (wrong version or corrupt) |
| No expected MD5 | File found but the `.info` files contain no hash to verify against |
| Not in manifest | File present in archive but not recognised |

### Step 13 — Cleanup

All Y/N choices are collected first. No files are deleted until every question has been answered. Items are executed in this order:

1. `retroarch/` staging folder *(safety check: refuses to delete if the path resolves to your live RetroARCH config directory)*
2. `ra_bios_set.zip` *(if keeping, and hash failures were detected, you will be offered a scrub option to remove only the failed files from the archive)*
3. Downloaded files
4. `combined_manifest.json` *(always last — the scrub above depends on it)*

---

## CSV Report Columns

| Column | Description |
|---|---|
| `Filename` | The BIOS filename as listed in the RetroARCH `.info` files |
| `System` | The emulated system(s) that use this file (`\|` separated) |
| `Paths` | Destination path(s) within `retroarch/` (`\|` separated) |
| `Required` | Whether the file is required or optional, as declared in the `.info` file |
| `Expected MD5` | The MD5 hash(es) from the `.info` files, or `Missing from RetroARCH .info files` if none listed |
| `Actual MD5` | The MD5 computed from the file in `ra_bios_set.zip`. Blank if not found |
| `Present` | `Yes` / `No` / `Not copied due to checksum mismatch` |

---

## Notes

- Files are matched by **filename** in Step 7 and verified by **MD5 hash** in Step 9. Both checks must pass for a file to be placed into the `retroarch/` folder structure.

- Not all `.info` files include MD5 hashes in their `notes` field. A file with no expected MD5 will appear as `Missing from RetroARCH .info files` in the CSV report and will be listed under a separate skip category in Step 9. It cannot be verified or copied regardless of whether it is present in the archive.

- Some cores (e.g. ScummVM) list many theme or asset files as firmware entries. These will appear in the manifest and report, but typically have no MD5 hashes. They will be matched by filename if found in a scanned directory.

- Each time Step 8 runs it clears all previously recorded MD5 results before scanning. This ensures that if a file is removed from `ra_bios_set.zip` between runs, it will not continue to show as present in the report or affect Step 9.

- Steps 5 and 6 are both optional and independent. Each accepts up to 5 entries — mix and match URLs and directories as needed in a single run.

- `ra_bios_set.zip` is your personal BIOS collection archive. It persists between runs and can be added to incrementally.

- A file with a matching filename but wrong MD5 will be reported in Step 10. It will **not** be copied into `retroarch/`. Saving it to `failed_hash_checks/` lets you identify which files need to be sourced from elsewhere.

- The `retroarch/` staging folder is safe to delete after Step 11 — it is only a copy of what was placed into your live RetroARCH config directory.

- If `ra_bios_tool.conf` is missing, the script will run using built-in fallback defaults and display a warning. It is recommended to keep the config file alongside the script at all times.

- **Standalone vs. flatpak:** The default paths assume the RetroARCH flatpak installation. If you use standalone RetroARCH, update `RA_MANIFEST_SOURCE` and `RA_LIVE_DIR` in `ra_bios_tool.conf` to match your installation paths.
