# rd_bios_tool

A personal utility for finding, verifying, and installing BIOS files for [RetroDECK](https://retrodeck.net/).

> **Disclaimer:** This tool was created for the developer's personal use. It is not affiliated with RetroDECK in any way. Do not contact RetroDECK for support regarding this tool. The creator takes no responsibility for any damage caused by its use.

---

## Contents

- [Folder Structure](#folder-structure)
- [Requirements](#requirements)
- [Configuration](#configuration)
- [Getting Started](#getting-started)
- [How to Run — Linux](#how-to-run--linux)
- [Script Steps](#script-steps)
- [CSV Report Columns](#csv-report-columns)
- [Notes](#notes)

---

## Folder Structure

Place the following files in a folder before running:

```
rd_bios_tool/
├── rd_bios_script.sh        ← The script
├── rd_bios_tool.conf        ← Configuration file
└── README.md                ← This file
```

The script will create the following during a run:

```
rd_bios_tool/
├── combined_manifest.json      ← Generated BIOS database from RetroDECK manifests
├── rd_bios_set.zip             ← Your BIOS archive (built or supplied during the run)
├── <downloaded_file>.zip       ← Any file downloaded from the internet (Step 5)
├── retrodeck/                  ← Staging folder with sorted BIOS files
│   ├── bios/
│   │   ├── dc/
│   │   ├── pico-8/
│   │   └── ...
│   ├── saves/
│   │   └── gc/
│   │       └── dolphin/
│   │           ├── EU/
│   │           ├── US/
│   │           └── JP/
│   └── roms/
│       ├── neogeo/
│       ├── arcade/
│       └── ...
├── retrodeck_bios_report.csv   ← Summary report of all BIOS files
└── failed_hash_checks/         ← Files that failed MD5 verification (optional)
```

---

## Requirements

### All Platforms

| Requirement | Notes |
|---|---|
| RetroDECK | Must be installed on the system |
| python3 | Standard |
| unzip | Recommended for archive scanning |
| 7z | Optional — adds `.7z` and additional format support |
| unar | Optional — adds `.rar` and additional format support |
| rsync | Required for Step 11 (live directory population) only |
| wget or curl | Required for Step 5 (URL download) only |

### Linux

| Requirement | Notes |
|---|---|
| bash | Standard |

---

## Configuration

The script reads `rd_bios_tool.conf` at startup. This file must be in the same folder as the script. If it is missing, the script falls back to built-in defaults and displays a warning — it will still run normally.

### Section 1 — RetroDECK Installation Paths

| Variable | Description | Default |
|---|---|---|
| `RD_MANIFEST_SOURCE` | Where the script looks for RetroDECK's `component_manifest.json` files | Standard flatpak path |
| `RD_LIVE_DIR` | Your live RetroDECK user data directory. Used in Step 11 and by the Step 13 safety check to prevent accidental deletion of the live directory | `~/retrodeck` |
| `RD_TESTED_VERSION` | The RetroDECK version this tool was built against. Displayed in the startup warning | `0.10.6b` |

### Section 2 — RetroDECK Internal Path Variables

These define how path tokens in the manifests map to folders inside the `retrodeck/` staging directory.

| Variable | Maps from | Default |
|---|---|---|
| `RD_BIOS_FOLDER` | `$bios_path` | `bios` |
| `RD_SAVES_FOLDER` | `$saves_path` | `saves` |
| `RD_ROMS_FOLDER` | `$roms_path` | `roms` |

**Example:** a manifest entry with `$bios_path/dc` will be placed at `retrodeck/bios/dc/`.

Only change these if RetroDECK has renamed its internal folder structure.

### Section 3 — Tool Output Paths

All paths default to the `rd_bios_tool/` folder (`$TOOL_DIR`).

| Variable | Description |
|---|---|
| `RD_MANIFEST_OUTPUT` | Where `combined_manifest.json` is saved |
| `RD_BIOS_ZIP` | Path and filename for `rd_bios_set.zip` |
| `RD_STAGING_DIR` | Where the `retrodeck/` staging folder is created |
| `RD_REPORT_DIR` | Directory where the CSV report is saved |
| `RD_FAILED_HASH_DIR` | Folder where files that failed MD5 checks are saved (Step 10) |

If RetroDECK ever changes its folder structure or installation path, update only the relevant lines in `rd_bios_tool.conf` — no changes to the script are required.

---

## Getting Started

You do not need anything other than the script and config file. `rd_bios_set.zip` is **not** a prerequisite — it is built during the run, or you can supply an existing one when prompted.

The basic workflow:

1. Run the script.
2. The script reads your RetroDECK installation to build a manifest of all expected BIOS files.
3. Supply your BIOS files by downloading from a URL (Step 5), scanning a local folder (Step 6), or both.
4. The script packages matched files into `rd_bios_set.zip`, verifies them by MD5 hash, and sorts them into the correct RetroDECK folder structure.
5. Optionally copy the result directly into your live RetroDECK directory.

On subsequent runs you can use your existing `rd_bios_set.zip` and add to it incrementally as you find more files.

The script will guide you through each step with prompts. Press `Y` at each confirmation to accept the default path, or `N` to enter a custom one.

---

## How to Run — Linux

**First time only** — make the script executable:

```bash
chmod +x ~/Desktop/rd_bios_tool/rd_bios_script.sh
```

**Run the script:**

```bash
~/Desktop/rd_bios_tool/rd_bios_script.sh
```

**Or combined:**

```bash
chmod +x ~/Desktop/rd_bios_tool/rd_bios_script.sh && ~/Desktop/rd_bios_tool/rd_bios_script.sh
```

---

## Script Steps

| Step | Description |
|---|---|
| **1** | Confirm the location of your RetroDECK `component_manifest.json` files |
| **2** | Confirm where to save `combined_manifest.json` |
| **3** | Parse all discovered manifests and build `combined_manifest.json` — a unified BIOS database with filenames, MD5 hashes, systems, paths, and required status |
| **4** | BIOS Set Selection — choose `E` to use an existing `rd_bios_set.zip` as-is (skips to Step 8), `A` to add new files to an existing archive (runs Steps 5–7 in append mode), or `C` to create a new archive (Steps 5–7) |
| **5** | *(Optional)* Download up to 5 BIOS sets from URLs. Requires `wget` or `curl` |
| **6** | *(Optional)* Scan up to 5 local directories recursively. Supports `.zip`, `.7z`, `.rar`, `.tar`, `.gz`, and more, up to 6 levels deep |
| **7** | Match found files against the manifest, stage them, and pack into `rd_bios_set.zip` |
| **8** | Scan `rd_bios_set.zip`, compute MD5 hashes, and update the manifest |
| **9** | Build the `retrodeck/` staging folder — copy all hash-verified files into the correct subfolder structure |
| **10** | Failed Hash Check Report — list files with matching filenames but wrong MD5s, with an option to save them to `failed_hash_checks/` |
| **11** | *(Optional)* Copy the staged files into your live RetroDECK directory using `rsync` |
| **12** | *(Optional)* Generate a CSV report summarising every BIOS entry |
| **13** | *(Optional)* Cleanup |

### Step 4 — BIOS Set Selection

Three options are available:

| Choice | Behaviour |
|---|---|
| `E` — Use existing | Uses `rd_bios_set.zip` exactly as it is and skips straight to Step 8. No files are added or changed. |
| `A` — Add to existing | Runs Steps 5–7 in append mode. New files are added; files already present with a passing hash are protected. |
| `C` — Create new | Runs Steps 5–7. If a zip already exists, you will be asked whether to append or overwrite before proceeding. |

### Step 7 — Overwrite Protection

Overwrite protection is applied at two levels when adding to an existing `rd_bios_set.zip`:

- A new file will **not** replace an existing entry if that entry already passes its MD5 hash check.
- A new file **will** replace an existing entry if that entry is present but has a failing or unverifiable hash.

This ensures a good file already in your archive can never be accidentally overwritten by a bad copy from a new source.

### Step 8 — Stale Hash Clearing

Before scanning, all previously recorded `actual_md5` values are cleared. This ensures results from a prior run never persist for files that have since been removed from the archive.

### Step 9 — Copy and Skip Categories

Files copied into `retrodeck/` are reported in two categories:

| Category | Meaning |
|---|---|
| Copied (verified) | File found in archive and MD5 matched the expected hash from the RetroDECK manifests |
| Copied (unverified) | File found in archive and filename matched the manifest, but RetroDECK has no expected MD5 to verify against. Most likely valid — copied by default so nothing is withheld unnecessarily. If RetroDECK later publishes an expected MD5 for this file, re-running the tool will verify it automatically |

Files not copied into `retrodeck/` are reported in two skip categories:

| Category | Meaning |
|---|---|
| Hash mismatch | File found in archive but MD5 does not match expected (wrong version or corrupt) |
| Not in manifest | File present in archive but not recognised by any RetroDECK manifest |

### Step 13 — Cleanup

All Y/N choices are collected first. No files are deleted until every question has been answered. Items are executed in this order:

1. `retrodeck/` staging folder *(safety check: refuses to delete if the path resolves to your live RetroDECK directory)*
2. `rd_bios_set.zip` *(if keeping, two optional scrub prompts are offered)*
   - **Failed hash files** — appears if any files failed hash checks. Removes files whose MD5 did not match the expected value
   - **Unverified files** — appears if any files were copied without hash verification. Advanced option for users who want the zip to contain only fully verified files. Most users should skip this
3. Downloaded files
4. `combined_manifest.json` *(always last — the scrub above depends on it)*

---

## CSV Report Columns

| Column | Description |
|---|---|
| `Filename` | The BIOS filename as listed in the RetroDECK manifests |
| `System` | The emulated system(s) that use this file (`\|` separated) |
| `Paths` | Destination path(s) within `retrodeck/` (`\|` separated) |
| `Required` | Whether the file is required, optional, or not specified |
| `Expected MD5` | The MD5 hash(es) from the manifests, or `Missing from RetroDECK manifests` if none listed |
| `Actual MD5` | The MD5 computed from the file in `rd_bios_set.zip`. Blank if not found |
| `Present` | `Yes` / `Yes (unverified — no expected MD5 in RetroDECK manifests)` / `No` / `Not copied due to checksum mismatch` |

**Present column values explained:**

| Value | Meaning |
|---|---|
| `Yes` | RetroDECK wants it, you have it, hash check passed |
| `Yes (unverified — no expected MD5 in RetroDECK manifests)` | RetroDECK wants it, you have it, no hash available to check against |
| `Not copied due to checksum mismatch` | RetroDECK wants it, you have it, hash check failed |
| `No` | RetroDECK wants it, you don't have it |

---

## Notes

- Files are matched by **filename** in Step 7 and verified by **MD5 hash** in Step 9. Both checks must pass for a file to be placed into the `retrodeck/` folder structure.

- A file with no expected MD5 in the RetroDECK manifests will appear as `Missing from RetroDECK manifests` in the CSV report and will be listed under the "Copied (unverified)" category in Step 9. It is copied to staging by default since the filename matched a manifest entry RetroDECK declared it wants. If RetroDECK later adds an expected MD5 for the file, re-running the tool will verify it automatically on the next run.

- Each time Step 8 runs it clears all previously recorded MD5 results before scanning. This ensures that if a file is removed from `rd_bios_set.zip` between runs, it will not continue to show as present in the report or affect Step 9.

- Steps 5 and 6 are both optional and independent. Each accepts up to 5 entries — mix and match URLs and directories as needed in a single run.

- `rd_bios_set.zip` is your personal BIOS collection archive. It persists between runs and can be added to incrementally.

- A file with a matching filename but wrong MD5 will be reported in Step 10. It will **not** be copied into `retrodeck/`. Saving it to `failed_hash_checks/` lets you identify which files need to be sourced from elsewhere.

- The `retrodeck/` staging folder is safe to delete after Step 11.
