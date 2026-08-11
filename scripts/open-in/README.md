# open-in Patched Scripts

This directory contains patched versions of `install.bat` and `uninstall.bat` for the open-in application.

## Workflow

1. When a new version of open-in is released, the manifest's autoupdate will fetch new scripts
2. The post_install script compares the hash of upstream scripts with known versions
3. If scripts differ, a warning is displayed asking to create an issue
4. Update this directory with the new scripts and capture changes

## Patches Applied

- Removed `pause` statements to allow unattended installs
- Added error handling (`|| exit /b 0`) to `reg delete` commands to handle missing registry entries gracefully

## Steps to Update When Upstream Changes

1. Download the new version from https://github.com/andy-portmen/native-client/releases
2. Extract and compare the scripts
3. Apply the patches above
4. Update files in this directory
5. Update the hash in open-in.json's post_install section
