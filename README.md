# ConvertApi (PowerShell)

Thin PowerShell wrapper for the ConvertAPI v2 REST endpoints.  
Supports **single-file conversions**, **URL-based conversions**, and **multi-file multi-part uploads** (e.g., PDF → merge) with safe downloads.

> **Get your API token:** https://www.convertapi.com/a/authentication

---

## Features

- 🔐 Token-based auth via `CONVERTAPI_API_TOKEN` or `Set-ConvertApiToken`
- 📄 Single local file upload (raw bytes, `Content-Disposition`)
- 🌐 Single URL conversion (query param `Url=…`)
- 📦 Multi-input **multipart/form-data** (`Files[0]`, `Files[1]`, …) when you pass multiple inputs
- 📎 **Extra file parameters**: any parameter whose name ends with `File` (e.g., `OverlayFile`, `BackgroundFile`) is detected and uploaded as a file part automatically
- ⚙️ Extra options via `-Parameters @{ Name = 'Value' }`
- 💾 Saves results to disk; preserves API‑provided filenames
- 🧪 `-WhatIf`/`-Confirm` safety (SupportsShouldProcess)
- 🖥 Works on Windows PowerShell 5.1 and PowerShell 7+

---

## Install

### Option A — PowerShell Gallery (recommended)
Once published to the Gallery, end users can install with:
```powershell
Install-Module ConvertApi -Scope CurrentUser
Import-Module ConvertApi -Force
# later updates
Update-Module ConvertApi
```
> Notes: First-time installs may prompt to trust the PSGallery repo and to install the NuGet provider—this is normal.

### Option B — Manual install from source
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

> If you downloaded a ZIP in a browser, Windows may mark files as “downloaded from internet.”  
> Run once to unblock (not needed when installing via **PowerShell Gallery** or **git clone**):
> ```powershell
> Set-ExecutionPolicy -Scope Process Bypass -Force
> Unblock-File -Path '<repo>\*' -Recurse
> ```

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

> When you pass multiple inputs (files and/or URLs), the module automatically uses **multipart/form‑data** and sends them as `Files[0]`, `Files[1]`, …

---

## Watermark / Overlay (extra file parameter)

Some converters accept **additional files** as parameters. Any parameter whose name ends with `File` is treated as a file part when the value is a local path.

**PDF → watermark-overlay (overlay from local PDF):**
```powershell
Invoke-ConvertApi -From pdf -To watermark-overlay `
  -File .\a.pdf `
  -Parameters @{ OverlayFile = '.\b.pdf'; Opacity = 0.6 } `
  -OutputPath .\out -StoreFile -Verbose
```

**Overlay from a URL:**
```powershell
Invoke-ConvertApi -From pdf -To watermark-overlay `
  -File .\a.pdf `
  -Parameters @{ OverlayFile = 'https://example.com/b.pdf' } `
  -OutputPath .\out -StoreFile
```

---

## Parameters reference (excerpt)

- `-From` / `-To`  
  Route selector → `POST https://v2.convertapi.com/convert/{From}/to/{To}`

- `-File` `[string[]]`  
  One or more local files.  
  - **1 file** → raw bytes upload (octet‑stream + Content‑Disposition)  
  - **2+ files** → multipart form with `Files[i]`

- `-Url` `[string[]]`  
  One or more remote files.  
  - **1 URL** → sent as `?Url=` query parameter  
  - **2+ URLs** → multipart form with `Files[i]`

- `-Parameters` `[hashtable]`  
  Additional API options (become query params or form fields).  
  **Special rule:** keys that end with **`File`** and point to a local path are uploaded as **file parts**; URL strings remain as string fields.

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

- **Execution policy / blocked scripts**  
  Not an issue when installing via **PowerShell Gallery** or **git clone**.  
  Only needed for ZIP downloads from the browser:
  ```powershell
  Set-ExecutionPolicy -Scope Process Bypass -Force
  Unblock-File -Path '<repo>\*' -Recurse
  ```

- **AllSigned environments**  
  Your org may require Authenticode‑signed scripts. Sign the module or ask your admin to trust your code‑signing certificate.

- **Launching a new process with multiple `-File` values**  
  Repeat the flag:
  ```powershell
  pwsh -NoProfile -File .\examples\Convert-PdfToMerge.ps1 -File .\a.pdf -File .\b.pdf -OutDir .\out
  ```

- **Filename collisions**  
  If a target file exists and `-Overwrite` is not set, the module appends a random suffix.

- **Progress / diagnostics**  
  Add `-Verbose` for download logs and basic tracing.

---

## License

Choose a license appropriate for your distribution (e.g., MIT).

---

## Examples

- `examples/Convert-PdfToMerge.ps1` – Merge multiple PDFs (local files and/or URLs).
- `examples/Convert-DocxToPdf.ps1` – Batch DOCX → PDF for a folder.
- `examples/Watermark-Overlay.ps1` – Apply a PDF overlay using `OverlayFile`.

Run with:
```powershell
# PowerShell 7
pwsh .\examples\Convert-PdfToMerge.ps1 -File .\a.pdf,.\b.pdf -OutDir .\out -StoreFile

# Windows PowerShell 5.1
powershell -File .\examples\Convert-DocxToPdf.ps1 -InDir .\docs -OutDir .\out -Recurse
```

---

## Continuous Integration (GitHub Actions)

A minimal workflow is included at `.github/workflows/ci.yml`:

- Lints the module with **PSScriptAnalyzer**
- Verifies the module can be **imported**

Add your ConvertAPI token as a repository secret later if you introduce integration tests.
