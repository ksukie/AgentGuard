<#
.SYNOPSIS
Runs AgentGuard's strictly read-only Windows environment diagnostic.

.DESCRIPTION
Checks repository encoding and line-ending risks by default. The optional
CodexConnectivity mode adds local-only proxy, route, process-connection, and
aggregate Codex retry/fallback checks. It does not change files or settings.

.PARAMETER Path
Directory to inspect for the repository checks. Defaults to the current directory.

.PARAMETER CodexConnectivity
Enables the optional Windows-only Codex connectivity diagnostic.

.PARAMETER SinceHours
Log lookback window for CodexConnectivity, from 1 to 720 hours. Defaults to 24.

.EXAMPLE
pwsh -NoProfile -File .\doctor.ps1 -CodexConnectivity -SinceHours 24
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$Path = (Get-Location).Path,

    [Parameter()]
    [switch]$CodexConnectivity,

    [Parameter()]
    [ValidateRange(1, 720)]
    [int]$SinceHours = 24
)

# AgentGuard v0.3.0: Windows-first, strictly read-only diagnostics.
# This script intentionally does not create, modify, delete, convert, or upload files.

Set-StrictMode -Version 2.0

$script:Results = @()
$script:ExcludedDirectoryNames = @(
    'node_modules', 'vendor', 'third_party', 'dist', 'build', 'out', 'coverage', '.git'
)
$script:BinaryExtensions = @(
    '.7z', '.a', '.avi', '.bmp', '.class', '.db', '.dll', '.dmg', '.doc', '.docx',
    '.eot', '.exe', '.gif', '.gz', '.ico', '.jar', '.jpeg', '.jpg', '.lib', '.mov',
    '.mp3', '.mp4', '.o', '.otf', '.pdf', '.png', '.so', '.tar', '.ttf', '.wasm',
    '.webp', '.woff', '.woff2', '.xls', '.xlsx', '.zip'
)
$script:ScriptExtensions = @('.ps1', '.sh', '.bat', '.cmd')

function Add-Result {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('PASS', 'INFO', 'WARN', 'ACTION')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $script:Results += [PSCustomObject]@{
        Level = $Level
        Message = $Message
    }
}

function Test-Utf8Name {
    param([string]$EncodingName)

    return $EncodingName -match '^(utf-8|utf8|cp65001)$'
}

function Test-ExcludedPath {
    param([string]$RelativePath)

    $segments = $RelativePath -split '[\\/]'
    foreach ($segment in $segments) {
        if ($script:ExcludedDirectoryNames -contains $segment) {
            return $true
        }
    }

    return $false
}

function Test-BinaryPath {
    param([string]$RelativePath)

    $extension = [System.IO.Path]::GetExtension($RelativePath).ToLowerInvariant()
    return $script:BinaryExtensions -contains $extension
}

function Get-BomKind {
    param([byte[]]$Bytes)

    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        return 'UTF-8 BOM'
    }

    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) {
        return 'UTF-16 LE BOM'
    }

    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF) {
        return 'UTF-16 BE BOM'
    }

    return 'none'
}

function Test-ContainsNonAsciiBytes {
    param([byte[]]$Bytes)

    foreach ($byte in $Bytes) {
        if ($byte -gt 0x7F) {
            return $true
        }
    }

    return $false
}

function Get-GitOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = & git @Arguments 2>$null
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        return
    }

    return @($output)
}

function Get-GitAttributeEol {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $output = @(Get-GitOutput -Arguments @('-C', $RepositoryRoot, 'check-attr', 'eol', '--', $RelativePath))
    if ($output.Count -eq 0) {
        return 'unspecified'
    }

    $line = [string]$output[0]
    if ($line -match ': eol: (lf|crlf)$') {
        return $Matches[1]
    }

    return 'unspecified'
}

function Test-IsWindowsHost {
    return [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
}

function Test-LoopbackHost {
    param([string]$HostName)

    if ([string]::IsNullOrWhiteSpace($HostName)) {
        return $false
    }

    $normalizedHost = $HostName.Trim()
    if ($normalizedHost.StartsWith('[') -and $normalizedHost.EndsWith(']')) {
        $normalizedHost = $normalizedHost.Substring(1, $normalizedHost.Length - 2)
    }

    if ($normalizedHost -ieq 'localhost') {
        return $true
    }

    $address = $null
    if ([System.Net.IPAddress]::TryParse($normalizedHost, [ref]$address)) {
        return [System.Net.IPAddress]::IsLoopback($address)
    }

    return $false
}

function Get-ProxyEndpointInfo {
    param(
        [AllowEmptyString()]
        [string]$Value,

        [string]$Source = 'unknown'
    )

    $endpoints = @()
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $endpoints
    }

    foreach ($part in $Value -split ';') {
        $candidate = $part.Trim()
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        $kind = 'proxy'
        if ($candidate -match '^([A-Za-z][A-Za-z0-9+.-]*)=(.+)$') {
            $kind = $Matches[1]
            $candidate = $Matches[2].Trim()
        }

        if ($candidate -notmatch '^[A-Za-z][A-Za-z0-9+.-]*://') {
            $candidate = 'http://' + $candidate
        }

        try {
            $uri = New-Object System.Uri($candidate)
            if ([string]::IsNullOrWhiteSpace($uri.Host)) {
                continue
            }

            $endpoints += [PSCustomObject]@{
                Source = $Source
                Kind = $kind
                Host = $uri.Host
                Port = $uri.Port
                IsLoopback = Test-LoopbackHost -HostName $uri.Host
            }
        }
        catch {
            # A malformed proxy value is reported by the caller without echoing it.
        }
    }

    return $endpoints
}

function Format-ProxyEndpoint {
    param([Parameter(Mandatory = $true)]$Endpoint)

    if ($Endpoint.IsLoopback) {
        return ('{0}:{1}' -f $Endpoint.Host, $Endpoint.Port)
    }

    return ('<remote>:{0}' -f $Endpoint.Port)
}

function Get-SystemProxyState {
    if (-not (Test-IsWindowsHost)) {
        return $null
    }

    try {
        $settings = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        $proxyEnableProperty = $settings.PSObject.Properties['ProxyEnable']
        $proxyServerProperty = $settings.PSObject.Properties['ProxyServer']
        $autoDetectProperty = $settings.PSObject.Properties['AutoDetect']
        $autoConfigUrlProperty = $settings.PSObject.Properties['AutoConfigURL']
        $proxyValue = if ($null -ne $proxyServerProperty) { [string]$proxyServerProperty.Value } else { '' }
        return [PSCustomObject]@{
            Enabled = ($null -ne $proxyEnableProperty -and [int]$proxyEnableProperty.Value -ne 0)
            AutoDetect = ($null -ne $autoDetectProperty -and [int]$autoDetectProperty.Value -ne 0)
            HasAutoConfigUrl = ($null -ne $autoConfigUrlProperty -and -not [string]::IsNullOrWhiteSpace([string]$autoConfigUrlProperty.Value))
            Endpoints = @(Get-ProxyEndpointInfo -Value $proxyValue -Source 'Windows system proxy')
        }
    }
    catch {
        Add-Result -Level 'INFO' -Message '无法读取 Windows 系统代理设置。'
        return $null
    }
}

function Test-ProxyEnvironment {
    $proxyNames = @('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY')
    $names = @($proxyNames + 'NO_PROXY')
    $processEntries = @()
    foreach ($name in $proxyNames) {
        $value = [Environment]::GetEnvironmentVariable($name, 'Process')
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $processEntries += [PSCustomObject]@{
                Name = $name
                Endpoints = @(Get-ProxyEndpointInfo -Value $value -Source ('process environment {0}' -f $name))
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable('NO_PROXY', 'Process'))) {
        Add-Result -Level 'INFO' -Message '当前诊断进程检测到 NO_PROXY（值已省略）。'
    }

    if ($processEntries.Count -eq 0) {
        Add-Result -Level 'INFO' -Message '当前诊断进程未检测到 HTTP_PROXY、HTTPS_PROXY 或 ALL_PROXY。'
    }
    else {
        foreach ($entry in $processEntries) {
            $formatted = @($entry.Endpoints | ForEach-Object { Format-ProxyEndpoint -Endpoint $_ })
            if ($formatted.Count -gt 0) {
                Add-Result -Level 'INFO' -Message ('当前诊断进程检测到 {0}: {1}' -f $entry.Name, ($formatted -join ', '))
            }
            else {
                Add-Result -Level 'WARN' -Message ('当前诊断进程检测到 {0}，但值不是可识别的代理地址。' -f $entry.Name)
            }
        }
    }

    if (-not (Test-IsWindowsHost)) {
        return
    }

    try {
        $userEnvironment = Get-ItemProperty -LiteralPath 'HKCU:\Environment' -ErrorAction Stop
        $persistentNames = @($userEnvironment.PSObject.Properties |
            Where-Object { $names -contains $_.Name.ToUpperInvariant() } |
            Select-Object -ExpandProperty Name)
        if ($persistentNames.Count -eq 0) {
            Add-Result -Level 'INFO' -Message '用户持久环境变量中未检测到标准代理变量。'
        }
        else {
            Add-Result -Level 'INFO' -Message ('用户持久环境变量中检测到: {0}' -f ($persistentNames -join ', '))
        }
    }
    catch {
        Add-Result -Level 'INFO' -Message '无法读取用户持久环境变量。'
    }
}

function Test-SystemProxy {
    param($SystemProxy)

    if ($null -eq $SystemProxy) {
        return
    }

    if (-not $SystemProxy.Enabled) {
        if ($SystemProxy.Endpoints.Count -gt 0) {
            Add-Result -Level 'INFO' -Message 'Windows 系统代理保存了端点，但当前未启用。'
        }
        else {
            Add-Result -Level 'INFO' -Message 'Windows 系统代理未启用。'
        }
        return
    }

    $formatted = @($SystemProxy.Endpoints | ForEach-Object { Format-ProxyEndpoint -Endpoint $_ })
    if ($formatted.Count -eq 0) {
        Add-Result -Level 'WARN' -Message 'Windows 系统代理已启用，但未能解析代理端点。'
    }
    else {
        Add-Result -Level 'PASS' -Message ('Windows 系统代理已启用: {0}' -f ($formatted -join ', '))
    }

    if ($SystemProxy.AutoDetect -or $SystemProxy.HasAutoConfigUrl) {
        Add-Result -Level 'INFO' -Message 'Windows 还启用了代理自动发现或 PAC；实际路由可能不同于静态代理端点。'
    }
}

function Test-LocalProxyListeners {
    param($SystemProxy)

    if ($null -eq $SystemProxy -or -not $SystemProxy.Enabled) {
        return
    }

    $localEndpoints = @($SystemProxy.Endpoints | Where-Object { $_.IsLoopback })
    if ($localEndpoints.Count -eq 0) {
        return
    }

    if ($null -eq (Get-Command -Name 'Get-NetTCPConnection' -ErrorAction SilentlyContinue)) {
        Add-Result -Level 'INFO' -Message '当前 PowerShell 不提供 Get-NetTCPConnection；跳过本地代理监听检查。'
        return
    }

    try {
        $listeners = @(Get-NetTCPConnection -State Listen -ErrorAction Stop)
        foreach ($endpoint in $localEndpoints) {
            $matches = @($listeners | Where-Object {
                $_.LocalPort -eq $endpoint.Port -and
                (Test-LoopbackHost -HostName ([string]$_.LocalAddress) -or $_.LocalAddress -eq '0.0.0.0' -or $_.LocalAddress -eq '::')
            })
            if ($matches.Count -gt 0) {
                Add-Result -Level 'PASS' -Message ('本地代理端口正在监听: {0}' -f (Format-ProxyEndpoint -Endpoint $endpoint))
            }
            else {
                Add-Result -Level 'WARN' -Message ('系统代理指向 {0}，但未发现对应的本地监听端口。' -f (Format-ProxyEndpoint -Endpoint $endpoint))
            }
        }
    }
    catch {
        Add-Result -Level 'INFO' -Message '无法读取本地 TCP 监听状态。'
    }
}

function Get-CodexProcesses {
    $processes = @()
    foreach ($process in @(Get-Process -ErrorAction SilentlyContinue)) {
        $path = ''
        try {
            $path = [string]$process.Path
        }
        catch {
            $path = ''
        }

        $isCodex = $process.ProcessName -ieq 'codex'
        $isChatGpt = $process.ProcessName -ieq 'ChatGPT'
        $isBundledCodex = $path -match '(?i)\\openai\.chatgpt-|\\OpenAI\.Codex_'
        if ($isCodex -or $isChatGpt -or $isBundledCodex) {
            $processes += $process
        }
    }

    return @($processes)
}

function Test-CodexProcessConnections {
    param($SystemProxy)

    $processes = @(Get-CodexProcesses)
    if ($processes.Count -eq 0) {
        Add-Result -Level 'INFO' -Message '未发现正在运行的 Codex 或 ChatGPT Desktop 进程；跳过实时连接归因。'
        return [PSCustomObject]@{
            ProcessCount = 0
            HasConnections = $false
            ViaLocalProxy = $false
        }
    }

    Add-Result -Level 'INFO' -Message ('检测到 {0} 个 Codex 或 ChatGPT Desktop 进程。' -f $processes.Count)
    if ($null -eq (Get-Command -Name 'Get-NetTCPConnection' -ErrorAction SilentlyContinue)) {
        Add-Result -Level 'INFO' -Message '当前 PowerShell 不提供 Get-NetTCPConnection；跳过实时连接归因。'
        return [PSCustomObject]@{
            ProcessCount = $processes.Count
            HasConnections = $false
            ViaLocalProxy = $false
        }
    }

    try {
        $ids = @($processes | Select-Object -ExpandProperty Id)
        $connections = @(Get-NetTCPConnection -State Established -ErrorAction Stop |
            Where-Object { $ids -contains $_.OwningProcess })
        if ($connections.Count -eq 0) {
            Add-Result -Level 'INFO' -Message '未发现 Codex 或 ChatGPT Desktop 的已建立 TCP 连接。'
            return [PSCustomObject]@{
                ProcessCount = $processes.Count
                HasConnections = $false
                ViaLocalProxy = $false
            }
        }

        $localProxyEndpoints = @()
        if ($null -ne $SystemProxy -and $SystemProxy.Enabled) {
            $localProxyEndpoints = @($SystemProxy.Endpoints | Where-Object { $_.IsLoopback })
        }

        $viaLocalProxy = @($connections | Where-Object {
            $connection = $_
            @($localProxyEndpoints | Where-Object {
                $connection.RemotePort -eq $_.Port -and (Test-LoopbackHost -HostName ([string]$connection.RemoteAddress))
            }).Count -gt 0
        })

        if ($viaLocalProxy.Count -gt 0) {
            Add-Result -Level 'PASS' -Message ('检测到 {0} 条 Codex 或 ChatGPT Desktop 连接正在使用声明的本地代理。' -f $viaLocalProxy.Count)
        }
        elseif ($localProxyEndpoints.Count -gt 0) {
            Add-Result -Level 'WARN' -Message '系统代理已指向本地端口，但当前 Codex 或 ChatGPT Desktop 连接未显示为连向该端口。'
        }
        else {
            Add-Result -Level 'INFO' -Message ('检测到 {0} 条 Codex 或 ChatGPT Desktop 已建立连接，但没有可归因的本地代理端点。' -f $connections.Count)
        }

        return [PSCustomObject]@{
            ProcessCount = $processes.Count
            HasConnections = $true
            ViaLocalProxy = ($viaLocalProxy.Count -gt 0)
        }
    }
    catch {
        Add-Result -Level 'INFO' -Message '无法读取 Codex 或 ChatGPT Desktop 的 TCP 连接。'
        return [PSCustomObject]@{
            ProcessCount = $processes.Count
            HasConnections = $false
            ViaLocalProxy = $false
        }
    }
}

function Test-VirtualDefaultRoutes {
    if ($null -eq (Get-Command -Name 'Get-NetAdapter' -ErrorAction SilentlyContinue) -or
        $null -eq (Get-Command -Name 'Get-NetRoute' -ErrorAction SilentlyContinue)) {
        Add-Result -Level 'INFO' -Message '当前 PowerShell 不提供完整网络适配器或路由查询；跳过 TUN 路由检查。'
        return
    }

    try {
        $pattern = '(?i)(tun|tap|wintun|wireguard|vpn|clash|mihomo|meta)'
        $virtualAdapters = @(Get-NetAdapter -ErrorAction Stop | Where-Object {
            (([string]$_.Name + ' ' + [string]$_.InterfaceDescription) -match $pattern)
        })
        if ($virtualAdapters.Count -eq 0) {
            Add-Result -Level 'PASS' -Message '未检测到名称或描述匹配的 TUN、TAP、VPN 或代理虚拟适配器。'
            return
        }

        $defaultRoutes = @(Get-NetRoute -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object { $_.DestinationPrefix -eq '0.0.0.0/0' })
        $routeAdapters = @()
        foreach ($adapter in $virtualAdapters) {
            $matchingRoutes = @($defaultRoutes | Where-Object { $_.InterfaceIndex -eq $adapter.ifIndex })
            if ($matchingRoutes.Count -gt 0) {
                $routeAdapters += $adapter
            }
        }

        if ($routeAdapters.Count -gt 0) {
            Add-Result -Level 'WARN' -Message ('检测到虚拟适配器承载默认路由: {0}。透明路由可能掩盖逐进程代理配置。' -f (($routeAdapters | Select-Object -ExpandProperty Name) -join ', '))
        }
        else {
            Add-Result -Level 'INFO' -Message ('检测到虚拟适配器，但未见其承载 IPv4 默认路由: {0}' -f (($virtualAdapters | Select-Object -ExpandProperty Name) -join ', '))
        }
    }
    catch {
        Add-Result -Level 'INFO' -Message '无法读取虚拟适配器或默认路由。'
    }
}

function Initialize-AgentGuardSqliteReader {
    if ($null -ne ('AgentGuard.SqliteReader' -as [type])) {
        return $true
    }

    $source = @'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace AgentGuard
{
    public static class SqliteReader
    {
        private const int SqliteOk = 0;
        private const int SqliteRow = 100;
        private const int SqliteOpenReadOnly = 1;

        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_open_v2(byte[] filename, out IntPtr db, int flags, IntPtr vfs);

        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_close_v2(IntPtr db);

        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_prepare_v2(IntPtr db, string sql, int bytes, out IntPtr statement, IntPtr tail);

        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_step(IntPtr statement);

        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_finalize(IntPtr statement);

        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_column_count(IntPtr statement);

        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern IntPtr sqlite3_column_text(IntPtr statement, int column);

        private static string ReadText(IntPtr value)
        {
            return value == IntPtr.Zero ? string.Empty : (Marshal.PtrToStringAnsi(value) ?? string.Empty);
        }

        public static string QueryFirstRow(string path, string sql)
        {
            IntPtr db = IntPtr.Zero;
            IntPtr statement = IntPtr.Zero;
            try
            {
                var utf8Path = Encoding.UTF8.GetBytes(path + "\0");
                if (sqlite3_open_v2(utf8Path, out db, SqliteOpenReadOnly, IntPtr.Zero) != SqliteOk)
                {
                    return null;
                }

                if (sqlite3_prepare_v2(db, sql, -1, out statement, IntPtr.Zero) != SqliteOk)
                {
                    return null;
                }

                if (sqlite3_step(statement) != SqliteRow)
                {
                    return null;
                }

                var values = new StringBuilder();
                var count = sqlite3_column_count(statement);
                for (var index = 0; index < count; index++)
                {
                    if (index > 0)
                    {
                        values.Append('\t');
                    }

                    values.Append(ReadText(sqlite3_column_text(statement, index)));
                }

                return values.ToString();
            }
            finally
            {
                if (statement != IntPtr.Zero)
                {
                    sqlite3_finalize(statement);
                }

                if (db != IntPtr.Zero)
                {
                    sqlite3_close_v2(db);
                }
            }
        }
    }
}
'@

    try {
        Add-Type -TypeDefinition $source -Language CSharp -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Get-UnixTimeSeconds {
    $epoch = [DateTime]::SpecifyKind([DateTime]'1970-01-01T00:00:00', [DateTimeKind]::Utc)
    return [Int64][Math]::Floor(([DateTime]::UtcNow - $epoch).TotalSeconds)
}

function Convert-UnixTimeSeconds {
    param([Int64]$Seconds)

    if ($Seconds -le 0) {
        return 'unknown'
    }

    $epoch = [DateTime]::SpecifyKind([DateTime]'1970-01-01T00:00:00', [DateTimeKind]::Utc)
    return $epoch.AddSeconds([double]$Seconds).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss')
}

function Get-CodexLogSummary {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CodexHome,

        [Parameter(Mandatory = $true)]
        [int]$Hours
    )

    $databases = @(Get-ChildItem -LiteralPath $CodexHome -Filter 'logs*.sqlite' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending)
    if ($databases.Count -eq 0) {
        return $null
    }

    if (-not (Test-Path -LiteralPath (Join-Path $env:WINDIR 'System32\winsqlite3.dll'))) {
        Add-Result -Level 'INFO' -Message '未检测到 Windows SQLite 运行库；跳过 Codex 日志聚合。'
        return $null
    }

    if (-not (Initialize-AgentGuardSqliteReader)) {
        Add-Result -Level 'INFO' -Message '无法初始化只读 SQLite 查询；跳过 Codex 日志聚合。'
        return $null
    }

    $since = (Get-UnixTimeSeconds) - ([Int64]$Hours * 3600)
    $sql = @"
SELECT
  COALESCE(SUM(CASE WHEN target = 'codex_core::responses_retry'
    AND instr(COALESCE(feedback_log_body, ''), 'stream disconnected - retrying sampling request') > 0
    THEN 1 ELSE 0 END), 0),
  COALESCE(MAX(CASE WHEN target = 'codex_core::responses_retry'
    AND instr(COALESCE(feedback_log_body, ''), 'stream disconnected - retrying sampling request') > 0
    THEN ts ELSE 0 END), 0),
  COALESCE(SUM(CASE WHEN target = 'codex_core::client'
    AND instr(COALESCE(feedback_log_body, ''), 'falling back to HTTP') > 0
    THEN 1 ELSE 0 END), 0),
  COALESCE(MAX(CASE WHEN target = 'codex_core::client'
    AND instr(COALESCE(feedback_log_body, ''), 'falling back to HTTP') > 0
    THEN ts ELSE 0 END), 0)
FROM logs
WHERE ts >= $since
"@

    $summary = [PSCustomObject]@{
        RetryCount = [Int64]0
        RetryLast = [Int64]0
        FallbackCount = [Int64]0
        FallbackLast = [Int64]0
        DatabaseCount = 0
    }

    foreach ($database in $databases) {
        try {
            $row = [AgentGuard.SqliteReader]::QueryFirstRow($database.FullName, $sql)
            if ([string]::IsNullOrWhiteSpace($row)) {
                continue
            }

            $values = @($row.Split([char]9))
            if ($values.Count -ne 4) {
                continue
            }

            $summary.RetryCount += [Int64]$values[0]
            $summary.RetryLast = [Math]::Max($summary.RetryLast, [Int64]$values[1])
            $summary.FallbackCount += [Int64]$values[2]
            $summary.FallbackLast = [Math]::Max($summary.FallbackLast, [Int64]$values[3])
            $summary.DatabaseCount++
        }
        catch {
            # Keep the diagnostic usable when one rotated log database is unavailable.
        }
    }

    if ($summary.DatabaseCount -eq 0) {
        Add-Result -Level 'INFO' -Message 'Codex 日志数据库不可读或使用了未识别的结构；跳过日志聚合。'
        return $null
    }

    return $summary
}

function Test-CodexConnectivity {
    param([int]$Hours)

    if (-not (Test-IsWindowsHost)) {
        Add-Result -Level 'INFO' -Message 'Codex 连接诊断 v0.2 目前仅实现 Windows 检测；已跳过。'
        return
    }

    Add-Result -Level 'INFO' -Message ('Codex 连接诊断窗口: 最近 {0} 小时。' -f $Hours)
    Test-ProxyEnvironment
    $systemProxy = Get-SystemProxyState
    Test-SystemProxy -SystemProxy $systemProxy
    Test-LocalProxyListeners -SystemProxy $systemProxy
    Test-VirtualDefaultRoutes
    $connectionState = Test-CodexProcessConnections -SystemProxy $systemProxy

    $codexHome = if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
        $env:CODEX_HOME
    }
    else {
        Join-Path $HOME '.codex'
    }

    if (-not (Test-Path -LiteralPath $codexHome -PathType Container)) {
        Add-Result -Level 'INFO' -Message '未找到 CODEX_HOME 或默认 .codex 目录；跳过本地日志聚合。'
        return
    }

    $logSummary = Get-CodexLogSummary -CodexHome $codexHome -Hours $Hours
    if ($null -eq $logSummary) {
        return
    }

    Add-Result -Level 'INFO' -Message ('已对 {0} 个 Codex 日志数据库执行只读聚合。' -f $logSummary.DatabaseCount)

    if ($logSummary.FallbackCount -gt 0) {
        $lastFallback = Convert-UnixTimeSeconds -Seconds $logSummary.FallbackLast
        if ($connectionState.ViaLocalProxy) {
            Add-Result -Level 'ACTION' -Message ('过去 {0} 小时检测到 {1} 条流重试记录和 {2} 次 HTTP 回退记录，最近一次回退 {3}。当前快照显示 Codex 已连向本地代理；请优先复核代理上游和 WebSocket 兼容性。' -f $Hours, $logSummary.RetryCount, $logSummary.FallbackCount, $lastFallback)
        }
        else {
            Add-Result -Level 'ACTION' -Message ('过去 {0} 小时检测到 {1} 条流重试记录和 {2} 次 HTTP 回退记录，最近一次回退 {3}。请结合代理、路由和节点日志复核。' -f $Hours, $logSummary.RetryCount, $logSummary.FallbackCount, $lastFallback)
        }
    }
    elseif ($logSummary.RetryCount -gt 0) {
        $lastRetry = Convert-UnixTimeSeconds -Seconds $logSummary.RetryLast
        Add-Result -Level 'WARN' -Message ('过去 {0} 小时检测到 {1} 条 Codex 流重试记录，最近一次 {2}；未发现可识别的 HTTP 回退记录。' -f $Hours, $logSummary.RetryCount, $lastRetry)
    }
    else {
        Add-Result -Level 'PASS' -Message ('过去 {0} 小时未发现可识别的 Codex 流重试或 HTTP 回退记录。' -f $Hours)
    }
}

function Test-PowerShellEnvironment {
    Add-Result -Level 'INFO' -Message ("当前 PowerShell: {0} {1}" -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion)

    $legacyPowerShell = Get-Command -Name 'powershell.exe' -ErrorAction SilentlyContinue
    if ($null -ne $legacyPowerShell) {
        Add-Result -Level 'INFO' -Message '检测到 Windows PowerShell 5.1 可执行文件。'
    }
    else {
        Add-Result -Level 'INFO' -Message '未检测到 Windows PowerShell 5.1 可执行文件。'
    }

    $pwsh = Get-Command -Name 'pwsh' -ErrorAction SilentlyContinue
    if ($null -ne $pwsh) {
        Add-Result -Level 'PASS' -Message ("检测到 PowerShell 7: {0}" -f $pwsh.Source)
    }
    else {
        Add-Result -Level 'WARN' -Message '未检测到 pwsh。推荐安装 PowerShell 7，以获得更一致的跨平台行为。'
    }

    try {
        $inputName = [Console]::InputEncoding.WebName
        $outputName = [Console]::OutputEncoding.WebName
        $pipelineName = $OutputEncoding.WebName

        Add-Result -Level 'INFO' -Message ("Console 输入编码: {0}; 输出编码: {1}; `$OutputEncoding: {2}" -f $inputName, $outputName, $pipelineName)

        if (-not (Test-Utf8Name -EncodingName $inputName) -or -not (Test-Utf8Name -EncodingName $outputName) -or -not (Test-Utf8Name -EncodingName $pipelineName)) {
            Add-Result -Level 'WARN' -Message '当前编码并非全部 UTF-8。Windows PowerShell 5.1 向原生命令传递非 ASCII 文本时，应显式设置 UTF-8 编码或使用 UTF-8 临时文件。'
        }
        else {
            Add-Result -Level 'PASS' -Message 'Console 输入、Console 输出和 $OutputEncoding 均为 UTF-8。'
        }
    }
    catch {
        Add-Result -Level 'INFO' -Message '无法读取 Console 编码；这通常发生在无交互宿主中。'
    }
}

function Add-PythonEncodingResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PreferredEncoding,

        [Parameter(Mandatory = $true)]
        [string]$FilesystemEncoding,

        [Parameter(Mandatory = $true)]
        [int]$Utf8Mode
    )

    if (Test-Utf8Name -EncodingName $PreferredEncoding) {
        Add-Result -Level 'PASS' -Message ('Python 3 默认文本编码: {0}; UTF-8 Mode: {1}; 文件系统编码: {2}。' -f $PreferredEncoding, $Utf8Mode, $FilesystemEncoding)
        return
    }

    Add-Result -Level 'WARN' -Message ('Python 3 默认文本编码为 {0}（UTF-8 Mode: {1}；文件系统编码: {2}）。未显式指定 encoding 的 open() 或 Path.read_text() 可能无法读取 UTF-8 中文文件；代码应使用 encoding="utf-8"，临时运行第三方工具可设置 PYTHONUTF8=1 或使用 -X utf8。' -f $PreferredEncoding, $Utf8Mode, $FilesystemEncoding)
}

function Test-PythonEnvironment {
    $pythonCommand = Get-Command -Name 'py' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $pythonArguments = @('-3')

    if ($null -eq $pythonCommand) {
        $pythonCommand = Get-Command -Name 'python3' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        $pythonArguments = @()
    }

    if ($null -eq $pythonCommand) {
        $pythonCommand = Get-Command -Name 'python' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        $pythonArguments = @()
    }

    if ($null -eq $pythonCommand) {
        Add-Result -Level 'INFO' -Message '未检测到 Python 3；跳过 Python 默认文本编码检查。'
        return
    }

    $probe = "import json,locale,sys; print(json.dumps({'major':sys.version_info[0],'preferred':locale.getpreferredencoding(False),'filesystem':sys.getfilesystemencoding(),'utf8_mode':sys.flags.utf8_mode}))"
    $pythonArguments += @('-S', '-c', $probe)

    try {
        $executable = $pythonCommand.Source
        $probeOutput = @(& $executable @pythonArguments 2>$null)
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0 -or $probeOutput.Count -eq 0) {
            Add-Result -Level 'INFO' -Message '无法读取 Python 3 默认文本编码；跳过该检查。'
            return
        }

        $info = ([string]$probeOutput[-1]) | ConvertFrom-Json
        $propertyNames = @($info.PSObject.Properties.Name)
        if ($propertyNames -notcontains 'major' -or $propertyNames -notcontains 'preferred' -or $propertyNames -notcontains 'filesystem' -or $propertyNames -notcontains 'utf8_mode' -or [int]$info.major -ne 3) {
            throw 'Unexpected Python encoding probe output.'
        }

        Add-PythonEncodingResult -PreferredEncoding ([string]$info.preferred) -FilesystemEncoding ([string]$info.filesystem) -Utf8Mode ([int]$info.utf8_mode)
    }
    catch {
        Add-Result -Level 'INFO' -Message '无法解析 Python 3 默认文本编码；跳过该检查。'
    }
}

function Test-RepositoryFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    $repoRootOutput = @(Get-GitOutput -Arguments @('-C', $TargetPath, 'rev-parse', '--show-toplevel'))
    if ($repoRootOutput.Count -eq 0) {
        Add-Result -Level 'INFO' -Message '目标路径不在 Git 仓库中；跳过 Git 行尾和已跟踪脚本检查。'
        return
    }

    $repoRoot = [string]$repoRootOutput[0]
    Add-Result -Level 'INFO' -Message ("Git 仓库: {0}" -f $repoRoot)

    foreach ($ruleFile in @('.editorconfig', '.gitattributes', 'AGENTS.md')) {
        $fullPath = Join-Path $repoRoot $ruleFile
        if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
            Add-Result -Level 'PASS' -Message ("检测到 {0}" -f $ruleFile)
        }
        else {
            Add-Result -Level 'INFO' -Message ("未检测到 {0}" -f $ruleFile)
        }
    }

    $autoCrlfOutput = @(Get-GitOutput -Arguments @('-C', $repoRoot, 'config', '--show-origin', '--get', 'core.autocrlf'))
    if ($autoCrlfOutput.Count -eq 0) {
        Add-Result -Level 'INFO' -Message 'Git core.autocrlf 未显式设置；请以仓库的 .gitattributes 为准。'
    }
    else {
        Add-Result -Level 'INFO' -Message ("Git core.autocrlf: {0}" -f ([string]$autoCrlfOutput[0]))
    }

    $trackedFiles = @(Get-GitOutput -Arguments @('-C', $repoRoot, 'ls-files'))
    if ($trackedFiles.Count -eq 0) {
        return
    }

    $eolCandidates = @()
    foreach ($relativePathValue in $trackedFiles) {
        $relativePath = [string]$relativePathValue
        if (-not (Test-ExcludedPath -RelativePath $relativePath) -and -not (Test-BinaryPath -RelativePath $relativePath)) {
            $eolCandidates += $relativePath
        }
    }

    if ($eolCandidates.Count -eq 0) {
        Add-Result -Level 'INFO' -Message '没有可进行行尾检查的已跟踪文本候选文件。'
    }
    else {
        $eolLines = @()
        $batchSize = 100
        for ($start = 0; $start -lt $eolCandidates.Count; $start += $batchSize) {
            $end = [Math]::Min($start + $batchSize - 1, $eolCandidates.Count - 1)
            $batch = @($eolCandidates[$start..$end])
            $gitArguments = @('-C', $repoRoot, 'ls-files', '--eol', '--')
            $gitArguments += $batch
            $eolLines += @(Get-GitOutput -Arguments $gitArguments)
        }

        $mixedCount = 0
        foreach ($line in $eolLines) {
            $text = [string]$line
            if ($text -notmatch '(^|\s)(i|w)/mixed(\s|$)') {
                continue
            }

            $pathMatch = [regex]::Match($text, '\t(.+)$')
            if (-not $pathMatch.Success) {
                Add-Result -Level 'WARN' -Message ("检测到 mixed 行尾，但无法解析路径: {0}" -f $text)
                continue
            }

            $relativePath = $pathMatch.Groups[1].Value
            if (Test-ExcludedPath -RelativePath $relativePath) {
                continue
            }

            $mixedCount++
            $expectedEol = Get-GitAttributeEol -RepositoryRoot $repoRoot -RelativePath $relativePath
            if ($expectedEol -eq 'lf' -or $expectedEol -eq 'crlf') {
                Add-Result -Level 'ACTION' -Message ("{0}: 检测到 mixed 行尾，但 .gitattributes 要求 eol={1}。" -f $relativePath, $expectedEol)
            }
            else {
                Add-Result -Level 'WARN' -Message ("{0}: 检测到 mixed 行尾；请结合 .gitattributes、.editorconfig、生成规则或第三方文件属性复核。" -f $relativePath)
            }
        }

        if ($mixedCount -eq 0) {
            Add-Result -Level 'PASS' -Message '已跟踪且未排除的文件中未检测到 mixed 行尾。'
        }
    }

    foreach ($relativePathValue in $trackedFiles) {
        $relativePath = [string]$relativePathValue
        if (Test-ExcludedPath -RelativePath $relativePath) {
            continue
        }

        $extension = [System.IO.Path]::GetExtension($relativePath).ToLowerInvariant()
        if ($script:ScriptExtensions -notcontains $extension) {
            continue
        }

        $fullPath = Join-Path $repoRoot $relativePath
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            Add-Result -Level 'INFO' -Message ("{0}: 已跟踪但当前工作区不存在，跳过编码检查。" -f $relativePath)
            continue
        }

        $fileInfo = Get-Item -LiteralPath $fullPath -Force
        if ($fileInfo.Length -gt 4MB) {
            Add-Result -Level 'INFO' -Message ("{0}: 文件大于 4 MiB，跳过编码检查。" -f $relativePath)
            continue
        }

        $bytes = [System.IO.File]::ReadAllBytes($fullPath)
        $bomKind = Get-BomKind -Bytes $bytes
        $hasNonAscii = Test-ContainsNonAsciiBytes -Bytes $bytes

        if ($extension -eq '.ps1') {
            if ($bomKind -eq 'UTF-8 BOM') {
                Add-Result -Level 'PASS' -Message ("{0}: PowerShell 脚本使用 UTF-8 BOM。" -f $relativePath)
            }
            elseif ($hasNonAscii -and $bomKind -eq 'none') {
                Add-Result -Level 'WARN' -Message ("{0}: 无 BOM 且包含非 ASCII 字节；若需兼容 Windows PowerShell 5.1，请使用 UTF-8 BOM。" -f $relativePath)
            }
            elseif ($bomKind -match '^UTF-16') {
                Add-Result -Level 'WARN' -Message ("{0}: 使用 {1}；请确认项目确实需要它，UTF-8 BOM 通常更适合兼容 Windows PowerShell 5.1 的含中文脚本。" -f $relativePath, $bomKind)
            }
            else {
                Add-Result -Level 'INFO' -Message ("{0}: 未发现需要 Windows PowerShell 5.1 特别处理的非 ASCII 编码风险。" -f $relativePath)
            }
        }
        elseif (($extension -eq '.bat' -or $extension -eq '.cmd') -and $bomKind -match '^UTF-16') {
            Add-Result -Level 'WARN' -Message ("{0}: 使用 {1}；Cmd 对 UTF-16 批处理文件的兼容性较差。" -f $relativePath, $bomKind)
        }
        elseif ($extension -eq '.sh' -and $bomKind -match '^UTF-16') {
            Add-Result -Level 'WARN' -Message ("{0}: 使用 {1}；POSIX shell 脚本通常应使用 UTF-8 文本。" -f $relativePath, $bomKind)
        }
    }
}

function Show-Results {
    $colorByLevel = @{
        PASS = 'Green'
        INFO = 'Cyan'
        WARN = 'Yellow'
        ACTION = 'Red'
    }

    Write-Output ''
    Write-Output 'AgentGuard doctor v0.3.0 (strictly read-only)'
    Write-Output '========================================'

    foreach ($result in $script:Results) {
        $line = '[{0}] {1}' -f $result.Level, $result.Message
        if ($Host.Name -ne 'ServerRemoteHost') {
            Write-Host $line -ForegroundColor $colorByLevel[$result.Level]
        }
        else {
            Write-Output $line
        }
    }

    $summary = @{}
    foreach ($level in @('PASS', 'INFO', 'WARN', 'ACTION')) {
        $summary[$level] = @($script:Results | Where-Object { $_.Level -eq $level }).Count
    }

    Write-Output ''
    Write-Output ('Summary: PASS={0} INFO={1} WARN={2} ACTION={3}' -f $summary.PASS, $summary.INFO, $summary.WARN, $summary.ACTION)
    Write-Output 'No files or settings were changed.'
}

if ($MyInvocation.InvocationName -eq '.') {
    return
}

$resolvedPath = $null
try {
    $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
}
catch {
    Add-Result -Level 'ACTION' -Message ("无法访问目标路径: {0}" -f $Path)
    Show-Results
    return
}

if (-not (Test-Path -LiteralPath $resolvedPath -PathType Container)) {
    Add-Result -Level 'ACTION' -Message ("目标不是目录: {0}" -f $resolvedPath)
    Show-Results
    return
}

Add-Result -Level 'INFO' -Message ("检查目标: {0}" -f $resolvedPath)
Test-PowerShellEnvironment
Test-PythonEnvironment
Test-RepositoryFiles -TargetPath $resolvedPath
if ($CodexConnectivity) {
    Test-CodexConnectivity -Hours $SinceHours
}
Show-Results
