<#
.SYNOPSIS
Merge multiple PDFs using ConvertAPI from PowerShell.

.DESCRIPTION
Accepts local files and/or URLs. Order is preserved (files first, then URLs).
Requires CONVERTAPI_API_TOKEN environment variable or Set-ConvertApiToken.

.EXAMPLE
.\Merge-Pdf.ps1 -File .\a.pdf,.\b.pdf -OutDir .\out -StoreFile

.EXAMPLE
.\Merge-Pdf.ps1 -Url 'https://ex.com/a.pdf','https://ex.com/b.pdf' -OutDir .\out -StoreFile

.LINK
Get token: https://www.convertapi.com/a/authentication
#>

[CmdletBinding(DefaultParameterSetName='Local')]
param(
  [Parameter(Mandatory=$true, ParameterSetName='Local')]
  [string[]]$File,

  [Parameter(Mandatory=$true, ParameterSetName='Remote')]
  [string[]]$Url,

  [string]$OutDir = ".\out",
  [switch]$StoreFile,
  [hashtable]$Parameters
)

# Import module by repo-relative path (works from anywhere)
# Ensure module is loaded
if (-not (Get-Module ConvertApi)) {
  Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'ConvertApi\ConvertApi.psd1') -Force -ErrorAction Stop
}

# Ensure token is present
$token = Get-ConvertApiToken
if (-not $token) {
  throw "No API token found. Get yours at https://www.convertapi.com/a/authentication and run Set-ConvertApiToken 'YOUR_API_TOKEN' -Persist."
}

# Ensure output folder
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

switch ($PSCmdlet.ParameterSetName) {
  'Local' {
    Invoke-ConvertApi -From pdf -To merge -File $File -OutputPath $OutDir -StoreFile:$StoreFile.IsPresent -Parameters $Parameters -Verbose
  }
  'Remote' {
    Invoke-ConvertApi -From pdf -To merge -Url  $Url  -OutputPath $OutDir -StoreFile:$StoreFile.IsPresent -Parameters $Parameters -Verbose
  }
}
