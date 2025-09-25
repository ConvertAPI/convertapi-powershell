<#
.SYNOPSIS
Batch convert DOCX to PDF using ConvertAPI.

.DESCRIPTION
Converts all .docx files under an input directory to PDF.
Requires CONVERTAPI_API_TOKEN or Set-ConvertApiToken in the session.

.EXAMPLE
.\Convert-DocxToPdf.ps1 -InDir .\docs -OutDir .\out -Verbose -Recurse
#>

[CmdletBinding()]
param(
  [string]$InDir = ".\docs",
  [string]$OutDir = ".\out",
  [switch]$Recurse
)

# Ensure module is loaded
if (-not (Get-Module ConvertApi)) {
  Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'ConvertApi\ConvertApi.psd1') -Force -ErrorAction Stop
}

# Ensure token is present
$token = Get-ConvertApiToken
if (-not $token) {
  throw "No API token found. Get yours at https://www.convertapi.com/a/authentication and run Set-ConvertApiToken 'YOUR_API_TOKEN' -Persist."
}

# Create output folder
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

# Convert all DOCX files
Get-ChildItem -Path $InDir -Filter *.docx -File -Recurse:$Recurse.IsPresent | ForEach-Object {
  Write-Verbose "Converting $($_.FullName)"
  Invoke-ConvertApi -From docx -To pdf -File $_.FullName -OutputPath $OutDir -StoreFile -Verbose
}
