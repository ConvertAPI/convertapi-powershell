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
- File-typed parameters: any -Parameters key that ends with 'File' is treated as a file input
  when its value is a local path; triggers multipart automatically.

- Use -InputMode to control how inputs are sent:
  * Auto  (default): 1 input -> single-file; 2+ inputs -> Files[i] multipart
  * File               force single-file (exactly 1 input required)
  * Files              force Files[i] multipart (even for 1 input)

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
    [switch]$PassThru,

    [ValidateSet('Auto','File','Files')] [string]$InputMode = 'Auto'
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
        # Add file parts
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

        # Add extra "string" parts (includes Files[i] urls, Url, StoreFile, Parameters, etc.)
        foreach ($kv in $UrlsTable.GetEnumerator()){
          $content.Add([System.Net.Http.StringContent]::new([string]$kv.Value), $kv.Key)
        }
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

    # Common query/form params (cloned later for multipart)
    $common = @{}
    if ($StoreFile.IsPresent) { $common["StoreFile"] = "true" }
    if ($Parameters) { foreach ($k in $Parameters.Keys) { $common[$k] = $Parameters[$k] } }
  }

  process {
    # Safe counts (avoid @($null).Count = 1)
    $fileCount  = if ($PSBoundParameters.ContainsKey('File') -and $null -ne $File) { $File.Count } else { 0 }
    $urlCount   = if ($PSBoundParameters.ContainsKey('Url')  -and $null -ne $Url)  { $Url.Count  } else { 0 }
    $inputTotal = $fileCount + $urlCount
    if ($inputTotal -lt 1 -and -not $Parameters) { throw "Provide at least one -File or -Url." }

    # Detect extra file-typed parameters (keys ending with 'File')
    $fileParamKeys = @()
    if ($Parameters) {
      foreach ($k in $Parameters.Keys) {
        if ($k -match '(?i)File$') { $fileParamKeys += $k }
      }
    }

    # Decide how to send primary inputs
    $useFilesArray = switch ($InputMode) {
      'Files' { $true }                                          # force Files[i]
      'File'  { if ($inputTotal -ne 1) { throw "InputMode 'File' requires exactly one input, but $inputTotal were provided." }; $false }
      default { $inputTotal -ge 2 }                              # Auto: Files[i] only when 2+ inputs
    }

    # Using multipart: we either use Files[i] OR we have any File-typed parameters
    $needsMultipart = $useFilesArray -or ($fileParamKeys.Count -gt 0)

    if ($needsMultipart) {
      $uri        = New-ConvertApiUri -From $From -To $To -Parms $null
      $filesTable = [ordered]@{}
      $stringParts = [ordered]@{}   # Url, Files[i] urls, StoreFile, other non-file params

      # Primary inputs
      if ($useFilesArray) {
        # Files[i] … for local files
        $i = 0
        foreach ($p in ($File | Where-Object { $_ })) {
          if (-not (Test-Path $p)) { throw "Input not found: $p" }
          $filesTable["Files[$i]"] = (Resolve-Path $p).Path
          $i++
        }
        # Files[i] … for url inputs (as strings)
        foreach ($u in ($Url | Where-Object { $_ })) {
          $stringParts["Files[$i]"] = $u
          $i++
        }
      } else {
        # Single primary input carried as 'File' or 'Url' in multipart
        if ($fileCount -eq 1 -and $urlCount -eq 0) {
          if (-not (Test-Path $File[0])) { throw "Input not found: $($File[0])" }
          $filesTable["File"] = (Resolve-Path $File[0]).Path
        } elseif ($urlCount -eq 1 -and $fileCount -eq 0) {
          $stringParts["Url"] = $Url[0]
        }
      }

      # Add file-typed parameters (…File). If value is a local path -> file part; otherwise send as string
      if ($fileParamKeys.Count -gt 0) {
        foreach ($k in $fileParamKeys) {
          $v = $Parameters[$k]
          $vals = @()
          if ($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])) { $vals = @($v) } else { $vals = @($v) }
          $idx = 0
          foreach ($item in $vals) {
            if ($item -and (Test-Path $item)) {
              $partName = if ($idx -eq 0) { $k } else { "$k[$idx]" }
              $filesTable[$partName] = (Resolve-Path $item).Path
              $idx++
            } else {
              # URL or plain string → send as string field
              $partName = if ($idx -eq 0) { $k } else { "$k[$idx]" }
              $stringParts[$partName] = [string]$item
              $idx++
            }
          }
        }
      }

      # Add remaining simple fields (Parameters + StoreFile) except the ones we already promoted to file/string parts above
      $fields = [ordered]@{}
      foreach ($k in $common.Keys) {
        if ($fileParamKeys -contains $k) { continue }  # skip; already added as file/string parts
        $v = $common[$k]; if ($v -is [bool]) { $v = $v.ToString().ToLower() }
        $fields[$k] = [string]$v
      }

      $label = ("{0} item(s)" -f [Math]::Max($inputTotal,1))
      if ($PSCmdlet.ShouldProcess($label, "Convert $From -> $To (multipart)")) {
        $response = Invoke-ConvertApiMultipart -Uri $uri -FilesTable $filesTable -UrlsTable $stringParts -Fields $fields -Token $Token -TimeoutSec $TimeoutSec
        Save-ConvertApiFiles $response
      }
      return
    }

    # ---- Single URL (query string) ----
    if ($urlCount -eq 1 -and $fileCount -eq 0) {
      $q = $common.Clone(); $q["Url"] = $Url[0]
      $uri = New-ConvertApiUri -From $From -To $To -Parms $q
      if ($PSCmdlet.ShouldProcess($Url[0], "Convert $From -> $To (single url)")) {
        $response = Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -TimeoutSec $TimeoutSec
        Save-ConvertApiFiles $response
      }
      return
    }

    # ---- Single local file (octet-stream + Content-Disposition) ----
    if ($fileCount -eq 1 -and $urlCount -eq 0) {
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

    throw "Cannot resolve inputs for the chosen InputMode '$InputMode'."
  }
}

Export-ModuleMember -Function Invoke-ConvertApi, Set-ConvertApiToken, Get-ConvertApiToken
