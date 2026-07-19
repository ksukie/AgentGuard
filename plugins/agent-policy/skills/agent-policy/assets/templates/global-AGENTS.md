# AgentGuard global guidance

Use these as safe personal defaults across repositories. Repository-level `AGENTS.md`, `.editorconfig`, `.gitattributes`, build tooling, and explicit user instructions take precedence when they are more specific.

## Preserve project conventions

- Before changing files, inspect relevant repository instructions and existing conventions. Check encoding, line endings, interpreter requirements, and whether a file is generated or vendored when those details matter.
- Do not make incidental repository-wide encoding or line-ending changes. Preserve established conventions unless the task explicitly requests a migration or normalization.
- For new ordinary source, configuration, and documentation files, default to UTF-8 without a BOM and LF line endings unless the project indicates another convention.
- Keep generated, vendored, binary, and data files unchanged unless the task explicitly includes them. Treat intentionally CRLF files as valid.
- Use paths safely: quote paths that may contain spaces, Chinese characters, emoji, or shell-special characters.

## Cross-platform execution

- Do not rely on operating-system defaults for encoding, locale, line endings, the working directory, or the time zone.
- Use the shell, interpreter, and command syntax required by the project. Do not mix PowerShell, Cmd, Bash, Zsh, or POSIX shell syntax.
- Prefer small, single-purpose commands. Use an existing or purpose-built script for repeatable, multi-step, or heavily quoted work.
