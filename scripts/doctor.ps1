[CmdletBinding()]
param(
    [Parameter()]
    [string]$Path = (Get-Location).Path
)

# AgentGuard v0.1: Windows-first, strictly read-only diagnostics.
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

    return $EncodingName -match '^(utf-8|utf8)$'
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
    Write-Output 'AgentGuard doctor (strictly read-only)'
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
Test-RepositoryFiles -TargetPath $resolvedPath
Show-Results
