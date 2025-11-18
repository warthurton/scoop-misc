# Applications List Generator

This repository includes an automated system for generating and maintaining an `APPLICATIONS.md` file that lists all packages in the bucket.

## How It Works

### PowerShell Script

The `bin/generate-applications-list.ps1` script:

-   Scans all JSON manifest files in the `bucket/` directory
-   Extracts package information (name, description, version, homepage, download URL)
-   Generates a markdown table sorted alphabetically
-   Tracks manifests with missing fields
-   Outputs `APPLICATIONS.md` at the repository root

### GitHub Action Workflow

The `.github/workflows/update-applications-list.yml` workflow:

-   Runs automatically when `bucket/*.json` files are modified and pushed to main/master
-   Can be triggered manually from the Actions tab
-   Commits changes to `APPLICATIONS.md` if updated
-   Creates or updates an issue for incomplete manifests
-   Closes the issue when all manifests are complete

## Manual Usage

To generate the applications list manually:

```powershell
# From repository root
.\bin\generate-applications-list.ps1

# With custom paths
.\bin\generate-applications-list.ps1 -BucketPath "path/to/bucket" -OutputFile "path/to/output.md"

# Skip issue tracking
.\bin\generate-applications-list.ps1 -SkipIssueTracking
```

## GitHub Pages Setup

To publish `APPLICATIONS.md` to GitHub Pages:

1. Go to repository **Settings** > **Pages**
2. Under **Source**, select **Deploy from a branch**
3. Choose branch **main** (or **master**) and folder **/ (root)**
4. Click **Save**
5. Wait a few minutes for deployment
6. Access at: `https://<username>.github.io/<repo>/APPLICATIONS`

The `_config.yml` file provides Jekyll configuration for better rendering.

## Incomplete Manifests

The script identifies manifests missing required fields:

-   `description`
-   `homepage`
-   `version` (or invalid version like ".")
-   `url` (download URL)

When incomplete manifests are detected:

1. They're listed in the `APPLICATIONS.md` file
2. An issue is created/updated with label `manifest-incomplete`
3. The issue is automatically closed when all manifests are fixed

## Reuse in Other Buckets

This system is designed to be generic and reusable:

1. Copy files to your bucket repository:

    - `bin/generate-applications-list.ps1`
    - `.github/workflows/update-applications-list.yml`
    - `_config.yml` (optional, for GitHub Pages)

2. No modifications needed! The script automatically:

    - Detects the bucket directory
    - Handles different manifest structures
    - Works with any Scoop bucket

3. Customize if desired:
    - Modify trigger conditions in workflow
    - Adjust issue labels or messages
    - Change output format in PowerShell script
