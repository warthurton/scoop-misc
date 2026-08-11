# open-in Patched Scripts

This directory contains patched versions of `install.bat` and `uninstall.bat` for the open-in application.

## Workflow

1. When a new version of open-in is released, GitHub Actions checks for script changes
2. The management script (bin/manage-scripts.ps1) downloads upstream and compares hashes
3. If scripts differ, a GitHub issue is created asking to review and update
4. Update this directory with the new scripts and run the management script

## Patches Applied

- Removed `pause` statements to allow unattended installs
- Added error handling (`|| exit /b 0`) to `reg delete` commands to handle missing registry entries gracefully

## Hash Tracking

Upstream script hashes are tracked in `.github/hashes/open-in.txt` (simple key=value format) to detect when upstream scripts change. Using a text file prevents validation errors from the Scoop test suite.

## Steps to Update When Upstream Changes

1. GitHub Actions detects changes via the excavator workflow and creates an issue
2. Download the new version from https://github.com/andy-portmen/native-client/releases
3. Extract and compare the scripts
4. Apply the patches above if needed
5. Update files in this directory
6. Run: `.\bin\manage-scripts.ps1 -App open-in -Repo andy-portmen/native-client -Version <new-version>`
7. Verify `.github/hashes/open-in.txt` is updated with new hashes
