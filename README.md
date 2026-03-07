================================================================================
  rd_bios_tool - README
================================================================================

--------------------------------------------------------------------------------
  FOLDER STRUCTURE
--------------------------------------------------------------------------------

  The rd_bios_tool folder should contain the following files before running:

    rd_bios_tool/
      rd_bios_script.sh       <- The script (this tool)
      rd_bios_tool.conf       <- Configuration file (paths and settings)
      readme.txt              <- This file

  The following files and folders will be created by the script when it runs:

    rd_bios_tool/
      combined_manifest.json     <- Generated BIOS database from RetroDECK manifests
      rd_bios_set.zip            <- Your BIOS archive (built or supplied during the run)
      <downloaded_file>.zip      <- Any file downloaded from the internet (Step 5)
      retrodeck/                 <- Staging folder containing sorted BIOS files
        bios/                   <- Files destined for the RetroDECK bios directory
          dc/                   <- Example subfolder (Dreamcast)
          pico-8/               <- Example subfolder (PICO-8)
          ...
        saves/                  <- Files destined for the RetroDECK saves directory
          gc/
            dolphin/
              EU/
              US/
              JP/
        roms/                   <- Files destined for the RetroDECK roms directory
          neogeo/
          arcade/
          ...
      retrodeck_bios_report.csv  <- Summary report of all BIOS files


--------------------------------------------------------------------------------
  REQUIREMENTS
--------------------------------------------------------------------------------

  - Linux (tested on Bazzite with RetroDECK 0.10.6b)
  - bash
  - python3
  - RetroDECK must be installed on the system

  The following are optional but recommended:
  - unzip     (recommended for archive scanning)
  - 7z        (optional, adds support for .7z and additional formats)
  - unar      (optional, adds support for .rar and additional formats)
  - rsync     (required for Step 11 - live directory population only)
  - wget or curl (required for Step 5 - URL download only)


--------------------------------------------------------------------------------
  CONFIGURATION  (rd_bios_tool.conf)
--------------------------------------------------------------------------------

  The script reads rd_bios_tool.conf at startup to determine all default paths
  and settings. This file must be in the same folder as rd_bios_script.sh.

  If the config file is missing, the script will fall back to built-in defaults
  and display a warning. The tool will still run normally in this case.

  The config file is divided into four sections:

  1. RETRODECK INSTALLATION PATHS
       RD_MANIFEST_SOURCE   - Where the script looks for RetroDECK's
                              component_manifest.json files. Default is the
                              standard RetroDECK flatpak installation path.

       RD_LIVE_DIR          - Your live RetroDECK user data directory.
                              Used in Step 11 when populating your installation,
                              and by the Step 13 cleanup safety check to prevent
                              the staging folder from being mistakenly deleted.
                              Default: ~/retrodeck

       RD_TESTED_VERSION    - The RetroDECK version this tool was built against.
                              Displayed in the version warning at startup.
                              Update this when re-testing against a new version.

  2. RETRODECK INTERNAL PATH VARIABLES
       These define how RetroDECK path tokens in the manifests map to folders
       inside the retrodeck/ staging directory.

       RD_BIOS_FOLDER       - Maps $bios_path  -> default: "bios"
       RD_SAVES_FOLDER      - Maps $saves_path -> default: "saves"
       RD_ROMS_FOLDER       - Maps $roms_path  -> default: "roms"

       Example: a manifest entry with "$bios_path/dc" will be placed at
       retrodeck/bios/dc/ using the default values.

       Only change these if RetroDECK has renamed its internal folder structure.

  3. TOOL OUTPUT PATHS
       RD_MANIFEST_OUTPUT   - Where combined_manifest.json is saved.
       RD_BIOS_ZIP          - Path and filename for rd_bios_set.zip.
       RD_STAGING_DIR       - Where the retrodeck/ staging folder is created.
       RD_REPORT_DIR        - Directory where the CSV report is saved.
       RD_FAILED_HASH_DIR   - Folder where files that failed MD5 hash checks
                              are saved if you elect to keep them (Step 10).
                              Default: rd_bios_tool/failed_hash_checks/

       All of these default to the rd_bios_tool folder ($TOOL_DIR).

  If RetroDECK ever changes its folder structure or installation path, you
  only need to update the relevant lines in rd_bios_tool.conf — no changes
  to the script itself are required.


--------------------------------------------------------------------------------
  GETTING STARTED
--------------------------------------------------------------------------------

  You do not need anything other than the script and config file to get started.
  rd_bios_set.zip is NOT a prerequisite - it is built by the script during
  the run, or you can supply an existing one when prompted.

  The basic workflow is:

    1. Run the script.
    2. The script reads your RetroDECK installation to build a manifest of
       all expected BIOS files.
    3. You supply your BIOS files by downloading from a URL (Step 5),
       scanning a local folder (Step 6), or both.
    4. The script packages your matched files into rd_bios_set.zip,
       verifies them by MD5 hash, and sorts them into the correct
       RetroDECK folder structure.
    5. Optionally copy the result directly into your live RetroDECK directory.

  On subsequent runs you can choose to use your existing rd_bios_set.zip
  and add to it incrementally as you find more files.


--------------------------------------------------------------------------------
  HOW TO RUN THE SCRIPT
--------------------------------------------------------------------------------

  1. Place the rd_bios_tool folder on your Desktop:

       ~/Desktop/rd_bios_tool/

  2. Open a terminal and make the script executable (first time only):

       chmod +x ~/Desktop/rd_bios_tool/rd_bios_script.sh

  3. Run the script:

       ~/Desktop/rd_bios_tool/rd_bios_script.sh

     Or combined into one command:

       chmod +x ~/Desktop/rd_bios_tool/rd_bios_script.sh && ~/Desktop/rd_bios_tool/rd_bios_script.sh

  4. The script will guide you through each step with prompts.
     All default paths are loaded from rd_bios_tool.conf automatically.
     Press Y at each confirmation prompt to accept the defaults,
     or N to enter a custom path.


--------------------------------------------------------------------------------
  STEPS PERFORMED BY THE SCRIPT
--------------------------------------------------------------------------------

  Step 1  - Confirm the location of your RetroDECK component_manifest.json
            files. Default is loaded from RD_MANIFEST_SOURCE in the config.

  Step 2  - Confirm where to save the combined_manifest.json output file.
            Default is loaded from RD_MANIFEST_OUTPUT in the config.

  Step 3  - Parses all discovered manifests and builds combined_manifest.json,
            a unified BIOS database containing filenames, MD5 hashes, systems,
            paths, and required status for every known BIOS entry.

  Step 4  - BIOS Set Selection. Choose to use an existing rd_bios_set.zip
            (skips to Step 8), or build a new one (proceeds through Steps 5-7).
            If an existing rd_bios_set.zip is found, you will be prompted to
            either add to it or overwrite it.

  Step 5  - (Optional) Download up to 5 BIOS sets from URLs. For each URL,
            the file is saved to the rd_bios_tool folder and scanned
            automatically. After each successful download you will be asked
            if you want to add another. Press Enter at the URL prompt to stop
            early at any time. Requires wget or curl.

  Step 6  - (Optional) Scan up to 5 local directories recursively for BIOS
            files. The script walks all subfolders and opens any archives it
            finds, searching for matching filenames up to 6 levels deep.
            Supports .zip, .7z, .rar, .tar, .gz, and more. After each valid
            directory you will be asked if you want to add another. Press
            Enter at the path prompt to stop early at any time.
            You do not need to extract anything manually.

  Step 7  - Matches all files found in Steps 5 and 6 against the manifest
            by filename, stages the matches, and packs them into
            rd_bios_set.zip. Reports how many files were examined, matched,
            and skipped.

            Overwrite protection is applied at two levels:
              - A new file will NOT replace an existing entry in rd_bios_set.zip
                if that entry already passes its MD5 hash check.
              - A new file WILL replace an existing entry if that entry is
                present but has a failing or unverifiable hash.
            This ensures that a good file already in your archive can never
            be accidentally overwritten by a bad copy found in a new source.

  Step 8  - Scans rd_bios_set.zip and computes MD5 hashes for every file
            inside, then compares them against the expected hashes in the
            manifest. Before scanning, all previously recorded actual_md5
            values are cleared so that results from a prior run never persist
            for files that have since been removed from the archive.
            Updates combined_manifest.json with the fresh results.

  Step 9  - Creates the retrodeck/ staging folder and copies all files whose
            MD5 hashes match into the correct subfolder structure, ready to
            be dropped into your RetroDECK installation. Files that are not
            copied are reported in three distinct categories:
              - Hash mismatch: file found but MD5 does not match expected
                (wrong version or corrupt).
              - No expected MD5: file found but the manifests contain no hash
                to verify against.
              - Not in manifest: file present in archive but not recognised.

  Step 10 - Failed Hash Check Report. Reports how many files in rd_bios_set.zip
            had a matching filename in the manifest but failed MD5 verification.
            Lists each offending filename. Offers to save these files to a
            separate folder so you can inspect or replace them. Default
            destination is a subfolder called failed_hash_checks/ inside the
            rd_bios_tool folder. You will be prompted for an alternate location
            if preferred.

  Step 11 - (Optional) Copies the staged files into your live RetroDECK
            directory. A warning is displayed before any files are written.
            Uses rsync to overwrite conflicting files while leaving all
            other files untouched. Default live path loaded from RD_LIVE_DIR
            in the config. Requires rsync.

  Step 12 - (Optional) Generates a CSV report summarising every BIOS entry,
            including filename, system, paths, required status, expected MD5,
            actual MD5, and whether the file was present, missing, or skipped
            due to a checksum mismatch. Report location loaded from
            RD_REPORT_DIR in the config.

  Step 13 - (Optional) Cleanup. All Y/N choices are collected first and no
            files are deleted until every question has been answered.
            Items are presented and deleted in the following order:
              - Any files downloaded from the internet during this session
              - retrodeck/ staging folder
                  Before deleting, the script resolves the real path of the
                  staging folder and compares it against RD_LIVE_DIR and
                  ~/retrodeck. If they match for any reason (including
                  symlinks), deletion is refused as a safety measure.
              - rd_bios_set.zip
                  If you choose to KEEP rd_bios_set.zip and hash failures were
                  detected this session, you will be offered an additional option
                  to scrub the failed files directly from the archive. This
                  removes only the files whose MD5 did not match, leaving all
                  other files in the archive untouched.
              - combined_manifest.json (always asked last, as the scrub
                  operation above depends on it being present)


--------------------------------------------------------------------------------
  CSV REPORT COLUMNS  (Step 12)
--------------------------------------------------------------------------------

  Filename        - The BIOS filename as listed in the RetroDECK manifests.
  System          - The emulated system(s) that use this file (| separated).
  Paths           - The destination path(s) within retrodeck/ (| separated).
  Required        - Whether the file is required, optional, or not specified.
  Expected MD5    - The MD5 hash(es) listed in the RetroDECK manifests,
                    or "Missing from RetroDECK manifests" if none is listed.
  Actual MD5      - The MD5 hash computed from the file in rd_bios_set.zip.
                    Blank if the file was not found in the archive.
  Present         - One of:
                      Yes                                - File matched and copied.
                      No                                 - File not in the archive.
                      Not copied due to checksum mismatch - File found but hash
                                                           did not match.


--------------------------------------------------------------------------------
  NOTES
--------------------------------------------------------------------------------

  - Files are matched by filename in Step 7, and verified by MD5 hash in
    Step 9. A file must pass both checks to be placed into the retrodeck/
    folder structure. Step 9 reports skipped files in three separate
    categories so you know exactly why each file was not copied.

  - If a BIOS file has no expected MD5 in the RetroDECK manifests, it will
    appear as "Missing from RetroDECK manifests" in the CSV report and will
    be reported as a separate skip category in Step 9. It cannot be verified
    or copied regardless of whether it is present in the archive.

  - Each time Step 8 runs it clears all previously recorded MD5 results
    before scanning. This ensures that if a file is removed from
    rd_bios_set.zip between runs, it will not continue to show as present
    in the report or affect Step 9.

  - Steps 5 and 6 are both optional and independent. You can use one, both,
    or neither (if using an existing rd_bios_set.zip from a previous run).
    Each step accepts up to 5 entries — mix and match as many URLs and
    directories as you need in a single run.

  - rd_bios_set.zip is your personal BIOS collection archive. It persists
    between runs and can be added to incrementally.

  - A file that appears in rd_bios_set.zip with a matching filename but a
    wrong MD5 hash will be reported in Step 10. It will NOT be copied into
    the retrodeck/ folder structure. Saving it to failed_hash_checks/ lets
    you identify which files need to be sourced from elsewhere.

  - The retrodeck/ staging folder is safe to delete after Step 11 as it is
    only a copy of what was placed into your live RetroDECK directory.

  - If rd_bios_tool.conf is missing, the script will run using built-in
    fallback defaults and display a warning. It is recommended to keep the
    config file alongside the script at all times.


--------------------------------------------------------------------------------
  DISCLAIMERS
--------------------------------------------------------------------------------

  - This tool was created for the developer's personal use. There are no
    guarantees it will be compatible with your system or use case.

  - This tool was built and tested against RetroDECK version 0.10.6b.
    There is no guarantee it will work with previous or subsequent versions.

  - The creator takes no responsibility for any damage caused by the use
    of this tool.

  - This tool is not affiliated with RetroDECK in any way whatsoever.
    Please do not contact RetroDECK for support regarding this tool.

================================================================================
