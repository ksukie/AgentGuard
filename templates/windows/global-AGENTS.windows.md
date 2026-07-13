# AgentGuard Windows enhancement

Merge these Windows-specific defaults with `templates/global-AGENTS.md`; do not use this file to replace project rules or to force Windows commands on non-Windows projects.

## Windows and PowerShell

- Prefer PowerShell 7 (`pwsh`) for new PowerShell automation when it is available.
- Before piping non-ASCII PowerShell text to a native program in Windows PowerShell 5.1, explicitly use UTF-8 for Console InputEncoding, Console OutputEncoding, and `$OutputEncoding`; alternatively, use a UTF-8 temporary file.
- For paths that may contain special characters, use PowerShell `-LiteralPath` where applicable.
- A `.ps1` that must run in Windows PowerShell 5.1 and contains non-ASCII text should use UTF-8 with BOM. Preserve any project convention that differs.
- Do not mix PowerShell syntax with Cmd, Bash, Zsh, or POSIX shell syntax. Use the shell required by the project.
