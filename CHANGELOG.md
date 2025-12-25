# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-12-25

### Added

- Initial release
- **Implicit API** - Process-scoped logging using process dictionary
  - `start/0`, `start_tag/1` - Initialize logging
  - `tag/1` - Set current section tag
  - `log/2`, `log_all/1` - Log key-value pairs
  - `trace/2`, `trace_all/2` - Log and return values (pipe-friendly)
  - `tagged/2` - Execute block with temporary tag
  - `close/0`, `wrap/1` - Finalize and retrieve logs
- **Explicit API** (`DecisionLog.Explicit`) - Functional, stateless logging
  - `new/1` - Create new context
  - `log/3`, `log_all/2` - Log with explicit context
  - `trace/3`, `trace_all/3` - Log and return `{value, context}` tuples
  - `tagged/3` - Execute with temporary tag
  - `close/1`, `wrap/2` - Finalize context
  - `get/1`, `view/1` - Inspect context
- **Decorator API** (`DecisionLog.Decorator`) - Automatic function tagging
  - `@decorate decision_log()` - Use function name as tag
  - `@decorate decision_log(:custom_tag)` - Use custom tag
- **Compression module** (`DecisionLog.Compression`) - PostgreSQL storage support
  - Gzip compression/decompression
  - PostgreSQL setup instructions
  - Ecto integration examples

[0.1.0]: https://github.com/dkuku/decision_log/releases/tag/v0.1.0
