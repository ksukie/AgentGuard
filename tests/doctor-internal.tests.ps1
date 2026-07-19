[CmdletBinding()]
param()

Set-StrictMode -Version 2.0

$doctorPath = Join-Path $PSScriptRoot '..\plugins\agent-policy\skills\agent-policy\scripts\doctor.ps1'
. $doctorPath

$endpoints = @(Get-ProxyEndpointInfo -Value 'http=127.0.0.1:7897;https=[::1]:7898' -Source 'internal-test')
if ($endpoints.Count -ne 2) {
    throw 'Proxy endpoint parser did not return two endpoints.'
}

if (-not $endpoints[0].IsLoopback -or $endpoints[0].Port -ne 7897) {
    throw 'Proxy endpoint parser did not recognize an IPv4 loopback proxy.'
}

if (-not $endpoints[1].IsLoopback -or $endpoints[1].Port -ne 7898) {
    throw 'Proxy endpoint parser did not recognize an IPv6 loopback proxy.'
}

$remote = @(Get-ProxyEndpointInfo -Value 'https://user:secret@example.com:8443' -Source 'internal-test')[0]
if ((Format-ProxyEndpoint -Endpoint $remote) -match 'example\.com|secret|user') {
    throw 'Proxy endpoint formatter exposed a remote host or credential.'
}

$script:Results = @()
Add-PythonEncodingResult -PreferredEncoding 'cp936' -FilesystemEncoding 'utf-8' -Utf8Mode 0
if (@($script:Results | Where-Object { $_.Level -eq 'WARN' -and $_.Message -match 'Path\.read_text\(\)' }).Count -ne 1) {
    throw 'Python locale encoding risk was not reported.'
}

$script:Results = @()
Add-PythonEncodingResult -PreferredEncoding 'utf-8' -FilesystemEncoding 'utf-8' -Utf8Mode 1
if (@($script:Results | Where-Object { $_.Level -eq 'PASS' }).Count -ne 1) {
    throw 'Python UTF-8 mode was not accepted.'
}

$script:Results = @()
Add-PythonEncodingResult -PreferredEncoding 'cp65001' -FilesystemEncoding 'utf-8' -Utf8Mode 0
if (@($script:Results | Where-Object { $_.Level -eq 'PASS' }).Count -ne 1) {
    throw 'Windows UTF-8 code page was not accepted.'
}

Write-Output 'AgentGuard doctor internal tests passed.'
