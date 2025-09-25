# ConvertApi (PowerShell)

Thin PowerShell wrapper for the ConvertAPI v2 REST endpoints.  
Supports **single-file conversions**, **URL-based conversions**, and **multi-file merges** (e.g., PDF → merge) with safe downloads.

> **Get your API token:** https://www.convertapi.com/a/authentication

---

## Features

- 🔐 Token-based auth via `CONVERTAPI_API_TOKEN` or `Set-ConvertApiToken`
- 📄 Single local file upload (raw bytes, `Content-Disposition`)
- 🌐 Single URL conversion (query param `Url=…`)
- 📦 Multi-input **multipart/form-data** for merges: `Files[0]`, `Files[1]`, …
- ⚙️ Extra options via `-Parameters @{ Name = 'Value' }`
- 💾 Saves results to disk; preserves API-provided filenames
- 🧪 `-WhatIf`/`-Confirm` safety (SupportsShouldProcess)
- 🖥 Works on Windows PowerShell 5.1 and PowerShell 7+

---

## Install

Place the folder:

```
ConvertApi/
  ConvertApi.psd1
  ConvertApi.psm1
```

into your user modules path:

- Windows PowerShell 5.1 → `~/Documents/WindowsPowerShell/Modules/ConvertApi`
- PowerShell 7+ → `~/Documents/PowerShell/Modules/ConvertApi`

Then:

```powershell
Import-Module ConvertApi -Force
```

---

## Authentication

Set your token once per machine/user (or via CI env var):

```powershell
# Get your token at https://www.convertapi.com/a/authentication
Set-ConvertApiToken 'YOUR_API_TOKEN' -Persist

# or (CI/CD)
$env:CONVERTAPI_API_TOKEN = 'YOUR_API_TOKEN'
```

---

## Quick Start

**Single file (DOCX → PDF):**
```powershell
Invoke-ConvertApi -From docx -To pdf `
  -File .\example.docx `
  -OutputPath .\out -StoreFile -Verbose
```

**URL input (PDF → JPG):**
```powershell
Invoke-ConvertApi -From pdf -To jpg `
  -Url 'https://example.com/sample.pdf' `
  -OutputPath .\out -StoreFile
```

**Batch a folder (pipeline):**
```powershell
Get-ChildItem .\docs -Filter *.docx |
  Invoke-ConvertApi -From docx -To pdf -OutputPath .\out -StoreFile
```

---

## PDF Merge (multiple inputs)

**Local PDFs (order preserved):**
```powershell
Invoke-ConvertApi -From pdf -To merge `
  -File .\a.pdf, .\b.pdf, .\c.pdf `
  -OutputPath .\out -StoreFile
```

**By URLs:**
```powershell
Invoke-ConvertApi -From pdf -To merge `
  -Url 'https://example.com/a.pdf','https://example.com/b.pdf' `
  -OutputPath .\out -StoreFile
```

**Mix local + URL:**
```powershell
Invoke-ConvertApi -From pdf -To merge `
  -File .\local1.pdf `
  -Url  'https://example.com/remote2.pdf' `
  -OutputPath .\out -StoreFile
```

**Merge options (examples):**
```powershell
Invoke-ConvertApi -From pdf -To merge `
  -File .\a.pdf, .\b.pdf `
  -Parameters @{
    PageSize             = 'a4'         # e.g., 'a4', 'letter'
    PageOrientation      = 'portrait'   # 'portrait' | 'landscape'
    BookmarksToc         = 'filename'   # toc from filenames
    RemoveDuplicateFonts = $true
    OpenPage             = 1            # open page number
  } `
  -OutputPath .\out -StoreFile
```

> The module automatically switches to **multipart/form-data** with `Files[0]`, `Files[1]`, … when it detects multiple inputs (files and/or URLs).

---

## Parameters reference (excerpt)

- `-From` / `-To`  
  Route selector → `POST https://v2.convertapi.com/convert/{From}/to/{To}`

- `-File` `[string[]]`  
  One or more local files.  
  - **1 file** → raw bytes upload (octet-stream + Content-Disposition)  
  - **2+ files** → multipart form with `Files[i]`

- `-Url` `[string[]]`  
  One or more remote files.  
  - **1 URL** → sent as `?Url=` query parameter  
  - **2+ URLs** → multipart form with `Files[i]`

- `-Parameters` `[hashtable]`  
  Additional API options (become query params or form fields, as appropriate).

- `-StoreFile` `[switch]`  
  Adds `StoreFile=true` so the API returns downloadable URLs.

- `-OutputPath` `[string]`  
  Directory where results are saved.

- `-Token` `[string]`  
  Overrides the token for the current call.

---

## Troubleshooting

- **“No API token found”**  
  Set the token first:
  ```powershell
  Set-ConvertApiToken 'YOUR_API_TOKEN' -Persist
  ```
  or:
  ```powershell
  $env:CONVERTAPI_API_TOKEN = 'YOUR_API_TOKEN'
  ```
  Token portal: https://www.convertapi.com/a/authentication

- **“Input not found”**  
  Verify paths or use full paths. On merges, any missing file will halt the request.

- **Filename collisions**  
  If a target file exists and `-Overwrite` is not set, the module appends a random suffix.

- **Progress / diagnostics**  
  Add `-Verbose` for download logs and basic tracing.

---

## License

Choose a license appropriate for your distribution (e.g., MIT).


---

## Examples

- `examples/Merge-Pdf.ps1` – Merge multiple PDFs (local files and/or URLs).
- `examples/Convert-DocxToPdf.ps1` – Batch DOCX → PDF for a folder.

Run with:
```powershell
pwsh examples/Merge-Pdf.ps1 -File .\a.pdf,.\b.pdf -OutDir .\out -StoreFile
pwsh examples/Convert-DocxToPdf.ps1 -InDir .\docs -OutDir .\out -Recurse
```

---

## Continuous Integration (GitHub Actions)

A minimal workflow is included at `.github/workflows/ci.yml`:

- Lints the module with **PSScriptAnalyzer**
- Verifies the module can be **imported**

Add your ConvertAPI token as a repository secret later if you introduce integration tests.
