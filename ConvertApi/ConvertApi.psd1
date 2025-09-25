@{
  RootModule           = 'ConvertApi.psm1'
  ModuleVersion        = '1.0.0'
  GUID                 = '8f28c2d0-0f4d-4d64-9f65-2a0a8e0e9b10'
  Author               = 'Your Name or Company'
  CompanyName          = 'Your Company'
  Description          = 'Thin PowerShell wrapper for ConvertAPI v2 REST using CONVERTAPI_API_TOKEN; file/URL input, extra params, safe downloads.'
  PowerShellVersion    = '5.1'
  CompatiblePSEditions = @('Desktop','Core')
  FunctionsToExport    = @('Invoke-ConvertApi','Set-ConvertApiToken','Get-ConvertApiToken')
  CmdletsToExport      = @()
  VariablesToExport    = @()
  AliasesToExport      = @()
  PrivateData = @{
    PSData = @{
      Tags = @('convertapi','conversion','pdf','docx','automation','powershell','token')
    }
  }
}
