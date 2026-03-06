
  rd_bios_tool - README


--------------------------------------------------------------------------------
  FOLDER STRUCTURE
--------------------------------------------------------------------------------

  The rd_bios_tool folder should contain the following files before running:

    rd_bios_tool/
      rd_bios_script.sh       <- The script (this tool)
      rd_bios_set.zip         <- Your BIOS archive to be scanned
      readme.txt              <- This file

  The following files and folders will be created by the script when it runs:

    rd_bios_tool/
      combined_manifest.json  <- Generated BIOS database from RetroDECK manifests
      retrodeck/              <- Staging folder containing sorted BIOS files
        bios/                 <- Files destined for the RetroDECK bios directory
          dc/                 <- Example subfolder (Dreamcast)
          pico-8/             <- Example subfolder (PICO-8)
          ...
        saves/                <- Files destined for the RetroDECK saves directory
          gc/
            dolphin/
              EU/
              US/
              JP/
        roms/                 <- Files destined for the RetroDECK roms directory
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
  - rsync (required for the live directory population step)
  - RetroDECK must be installed on the system


--------------------------------------------------------------------------------
  HOW TO RUN THE SCRIPT
--------------------------------------------------------------------------------

  1. Place the rd_bios_tool folder on your Desktop:

       ~/Desktop/rd_bios_tool/

  2. Place your rd_bios_set.zip inside the rd_bios_tool folder if you have
     previously moved it, otherwise it should already be there by default.

  3. Open a terminal and make the script executable (first time only):

       chmod +x ~/Desktop/rd_bios_tool/rd_bios_script.sh

  4. Run the script:

       ~/Desktop/rd_bios_tool/rd_bios_script.sh

  5. The script will guide you through each step with prompts.
     All default paths point to the rd_bios_tool folder automatically.
     Simply press Y at each confirmation prompt to accept the defaults,
     or N to enter a custom path.


--------------------------------------------------------------------------------
  STEPS PERFORMED BY THE SCRIPT
--------------------------------------------------------------------------------

  Step 1  - Locates the RetroDECK component_manifest.json files on your system
            and parses them to build a combined BIOS database.

  Step 2  - Confirms where to save the combined_manifest.json file.

  Step 3  - Builds the combined_manifest.json from all discovered manifests.

  Step 4  - Scans rd_bios_set.zip and computes MD5 hashes for all files inside,
            then matches them against the expected hashes in the manifest.

  Step 5  - Creates the retrodeck/ staging folder and copies all files whose
            hashes match into the correct subfolder structure.

  Step 6  - (Optional) Copies the staged files into your live RetroDECK
            directory. A stern warning is displayed before any files are
            written. This step uses rsync and will overwrite conflicting
            files while leaving unrelated files untouched.

  Step 7  - (Optional) Generates a CSV report summarising every BIOS entry,
            including filename, system, paths, required status, expected MD5,
            actual MD5, and whether the file was present, missing, or skipped
            due to a checksum mismatch.

  Step 8  - (Optional) Cleanup. Offers to delete the combined_manifest.json
            and/or the retrodeck/ staging folder. The live RetroDECK directory
            is protected and will never be deleted by this step.


--------------------------------------------------------------------------------
  CSV REPORT COLUMNS
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
                      Yes                              - File matched and copied.
                      No                               - File not in the archive.
                      Not copied due to checksum mismatch - File found but hash
                                                         did not match.


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
