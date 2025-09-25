#requires -Version 5.1
# Public functions: Invoke-ConvertApi, Set-ConvertApiToken, Get-ConvertApiToken

$script:ConvertApiToken   = $null
$script:ConvertApiAuthUrl = 'https://www.convertapi.com/a/authentication'

function Get-ConvertApiToken {
<#
.SYNOPSIS
Gets the ConvertAPI API token from memory or environment.

.DESCRIPTION
Returns the in-session token if set, or the CONVERTAPI_API_TOKEN environment variable.

.LINK
https://www.convertapi.com/a/authentication
#>
  [CmdletBinding()]
  param()
  if ($script:ConvertApiToken)   { return $script:ConvertApiToken }
  if ($env:CONVERTAPI_API_TOKEN) { return $env:CONVERTAPI_API_TOKEN }
  return $null
}

function Set-ConvertApiToken {
<#
.SYNOPSIS
Sets the ConvertAPI API token for this session (and optionally persists it).

.EXAMPLE
Set-ConvertApiToken 'YOUR_API_TOKEN' -Persist

.NOTES
Get your API token from: https://www.convertapi.com/a/authentication

.LINK
https://www.convertapi.com/a/authentication
#>
  [CmdletBinding(SupportsShouldProcess)]
  param(
    [Parameter(Mandatory)][string]$Token,
    [switch]$Persist
  )
  $script:ConvertApiToken = $Token
  if ($Persist) {
    if ($PSCmdlet.ShouldProcess("Environment", "Set CONVERTAPI_API_TOKEN (User scope)")) {
      [Environment]::SetEnvironmentVariable("CONVERTAPI_API_TOKEN", $Token, "User")
    }
  }
}

function Invoke-ConvertApi {
<#
.SYNOPSIS
Converts (or merges) files via ConvertAPI v2 REST, supporting multiple files/URLs on PS 5.1.

.DESCRIPTION
- Single local file => uploads raw bytes with Content-Disposition.
- Multiple files/URLs => HttpClient multipart with Files[0], Files[1], ...
- Single URL => passes ?Url=... as a query parameter.
- Extra API params via -Parameters.
- Use -StoreFile to get time-limited URLs for downloading.

.EXAMPLE
Invoke-ConvertApi -From pdf -To merge -File .\a.pdf, .\b.pdf -OutputPath .\out -StoreFile

.LINK
https://www.convertapi.com/a/authentication
#>
  [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'LocalFile')]
  param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_-]+$')] [string]$From,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_-]+$')] [string]$To,

    # Local file(s)
    [Parameter(ParameterSetName='LocalFile', ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [Alias('FullName','Path')] [string[]]$File,

    # Remote URL(s)
    [Parameter(ParameterSetName='RemoteUrl')]
    [string[]]$Url,

    [string]$OutputPath = (Get-Location).Path,
    [hashtable]$Parameters,
    [switch]$StoreFile,          # adds ?StoreFile=true or form field StoreFile=true
    [string]$Token,              # overrides env/module token
    [int]$TimeoutSec = 300,
    [switch]$Overwrite,
    [switch]$PassThru
  )

  begin {
    if (-not $Token) { $Token = Get-ConvertApiToken }
    if (-not $Token) {
      $auth = $script:ConvertApiAuthUrl
      throw ("No API token found. Get your token at: {0}`n" +
             "Then run: Set-ConvertApiToken 'YOUR_API_TOKEN' -Persist`n" +
             "Or set:   $env:CONVERTAPI_API_TOKEN") -f $auth
    }

    if (-not (Test-Path $OutputPath)) {
      New-Item -ItemType Directory -Path $OutputPath | Out-Null
    }

    $headers = @{
      "Authorization" = "Bearer $Token"
      "Accept"        = "application/json"
    }

    # Prefer TLS 1.2 on Windows PowerShell
    if ($PSVersionTable.PSEdition -eq 'Desktop') {
      try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
    }

    function New-ConvertApiUri([string]$From,[string]$To,[hashtable]$Parms){
      $base = "https://v2.convertapi.com/convert/{0}/to/{1}" -f $From, $To
      if (-not $Parms -or $Parms.Count -eq 0) { return $base }
      $qs = ($Parms.GetEnumerator() | ForEach-Object {
        $v = $_.Value; if ($v -is [bool]) { $v = $v.ToString().ToLower() }
        '{0}={1}' -f [uri]::EscapeDataString($_.Key), [uri]::EscapeDataString([string]$v)
      }) -join '&'
      return "$base`?$qs"
    }

    function Save-ConvertApiFiles($response) {
      foreach ($f in $response.Files) {
        $target = Join-Path $OutputPath $f.FileName
        if ((Test-Path $target) -and -not $Overwrite) {
          $target = Join-Path $OutputPath ("{0}-{1}{2}" -f [IO.Path]::GetFileNameWithoutExtension($f.FileName), (Get-Random), [IO.Path]::GetExtension($f.FileName))
        }
        Invoke-WebRequest -Uri $f.Url -OutFile $target | Out-Null
        Write-Verbose "Saved $target"
        if ($PassThru) { Get-Item $target }
      }
    }

    # PS 5.1-safe multipart using HttpClient
    function Invoke-ConvertApiMultipart([string]$Uri, [hashtable]$FilesTable, [hashtable]$UrlsTable, [hashtable]$Fields, [string]$Token, [int]$TimeoutSec){
      Add-Type -AssemblyName System.Net.Http

      $handler = New-Object System.Net.Http.HttpClientHandler
      $client  = New-Object System.Net.Http.HttpClient($handler)
      $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)

      $content = New-Object System.Net.Http.MultipartFormDataContent
      $streams = @()

      try {
        # Add files
        foreach ($kv in $FilesTable.GetEnumerator()){
          $path = $kv.Value
          $stream = [System.IO.File]::OpenRead($path)
          $streams += $stream
          $sc = New-Object System.Net.Http.StreamContent($stream)
          $sc.Headers.ContentDisposition = New-Object System.Net.Http.Headers.ContentDispositionHeaderValue("form-data")
          $sc.Headers.ContentDisposition.Name     = '"' + $kv.Key + '"'
          $sc.Headers.ContentDisposition.FileName = '"' + [IO.Path]::GetFileName($path) + '"'
          $content.Add($sc)
        }

        # Add URLs as string fields (Files[i] = 'https://...')
        foreach ($kv in $UrlsTable.GetEnumerator()){
          $content.Add([System.Net.Http.StringContent]::new($kv.Value), $kv.Key)
        }

        # Add extra fields (StoreFile, Parameters...)
        foreach ($kv in $Fields.GetEnumerator()){
          $content.Add([System.Net.Http.StringContent]::new([string]$kv.Value), $kv.Key)
        }

        $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post, $Uri)
        $req.Content = $content
        $req.Headers.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", $Token)
        $req.Headers.Accept.Add([System.Net.Http.Headers.MediaTypeWithQualityHeaderValue]::new("application/json"))

        $resp = $client.SendAsync($req).Result
        $resp.EnsureSuccessStatusCode() | Out-Null
        $json = $resp.Content.ReadAsStringAsync().Result

        return $json | ConvertFrom-Json
      }
      finally {
        foreach ($s in $streams) { try { $s.Dispose() } catch {} }
        try { $content.Dispose() } catch {}
        try { $client.Dispose() } catch {}
      }
    }

    # Common query/form params
    $common = @{}
    if ($StoreFile.IsPresent) { $common["StoreFile"] = "true" }
    if ($Parameters) { foreach ($k in $Parameters.Keys) { $common[$k] = $Parameters[$k] } }
  }

  process {
    $fileCount = @($File).Count
    $urlCount  = @($Url).Count
    if ($fileCount -eq 0 -and $urlCount -eq 0) {
      throw "Provide at least one -File or -Url."
    }

    # MULTI-INPUT (merge etc.) via HttpClient multipart  —— PS 5.1 safe
    if ($fileCount + $urlCount -gt 1) {
      $uri  = New-ConvertApiUri -From $From -To $To -Parms $null

      # Build Files[i] in order
      $filesTable = [ordered]@{}
      $urlsTable  = [ordered]@{}
      $i = 0
      foreach ($p in $File) {
        if (-not (Test-Path $p)) { throw "Input not found: $p" }
        $resolved = (Resolve-Path $p).Path
        $filesTable["Files[$i]"] = $resolved
        $i++
      }
      foreach ($u in $Url) {
        $urlsTable["Files[$i]"] = $u
        $i++
      }

      # Extra fields
      $fields = [ordered]@{}
      foreach ($k in $common.Keys) {
        $v = $common[$k]; if ($v -is [bool]) { $v = $v.ToString().ToLower() }
        $fields[$k] = [string]$v
      }

      $label = ("{0} item(s)" -f ($fileCount + $urlCount))
      if ($PSCmdlet.ShouldProcess($label, "Convert $From -> $To (multipart)")) {
        $response = Invoke-ConvertApiMultipart -Uri $uri -FilesTable $filesTable -UrlsTable $urlsTable -Fields $fields -Token $Token -TimeoutSec $TimeoutSec
        Save-ConvertApiFiles $response
      }
      return
    }

    # SINGLE URL
    if ($urlCount -eq 1 -and $fileCount -eq 0) {
      $q = $common.Clone(); $q["Url"] = $Url[0]
      $uri = New-ConvertApiUri -From $From -To $To -Parms $q
      if ($PSCmdlet.ShouldProcess($Url[0], "Convert $From -> $To (url)")) {
        $response = Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -TimeoutSec $TimeoutSec
        Save-ConvertApiFiles $response
      }
      return
    }

    # SINGLE LOCAL FILE (octet-stream)
    if ($fileCount -eq 1) {
      $resolved = (Resolve-Path $File[0]).Path
      $name     = [IO.Path]::GetFileName($resolved)
      $bytes    = [IO.File]::ReadAllBytes($resolved)

      $uri = New-ConvertApiUri -From $From -To $To -Parms $common
      $localHeaders = $headers.Clone()
      $localHeaders["Content-Type"]        = "application/octet-stream"
      $localHeaders["Content-Disposition"] = "attachment; filename=`"$name`""

      if ($PSCmdlet.ShouldProcess($name, "Convert $From -> $To (single file)")) {
        $response = Invoke-RestMethod -Uri $uri -Method POST -Headers $localHeaders -Body $bytes -TimeoutSec $TimeoutSec
        Save-ConvertApiFiles $response
      }
      return
    }
  }
}

Export-ModuleMember -Function Invoke-ConvertApi, Set-ConvertApiToken, Get-ConvertApiToken
