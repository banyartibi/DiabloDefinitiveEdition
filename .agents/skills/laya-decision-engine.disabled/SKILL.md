---
name: laya-decision-engine
description: "MANDATORY local routing layer running on CPU: evaluate mutating/risky shell commands, triage C++/build errors, and make architectural decisions using Laya System 1 MCP tools to ensure zero token waste and 100% sound decisions."
---

# Laya System 1 Decision Engine — Mandatory Routing Layer

This skill establishes a **required routing and decision layer** to conserve LLM tokens, avoid trial-and-error overhead, and guarantee 100% sound, deterministic actions.
The engine runs locally on CPU via the `laya-decision-engine` MCP server (`call_mcp_tool`), consuming **0 GPU VRAM and 0 cloud API tokens**.

## Core Tools & Triggers

### 1. `evaluate_shell_command`
- **Trigger:** ANY shell command that mutates state: deleting/moving/overwriting files, building/compiling code, git commits/pushes/resets, package or service management, or touching system resources.
- **Exemptions:** Simple read-only inspection commands (`cat`, `ls`, `head`, `tail`, `grep`, `pwd`) are exempt to prevent unnecessary latency.
- **Parameters:**
  - `command`: exact command string.
  - `environment`: `"development"` (default).
  - `working_directory`: `/home/biti/antigravity/magical-bell` (or target directory).
- **Execution Rules:**
  - `decision: "allow"` → Proceed with command execution.
  - `decision: "warn"` → State the risk concisely, then proceed if safe.
  - `decision: "block"` → Do NOT execute. Provide a safe alternative or ask user confirmation.

### 2. `triage_build_error`
- **Trigger:** Any C++, CMake, Godot GDExtension, SCons, or linker error during builds or module compilation.
- **Parameters:**
  - `error_message`: the exact build error log snippet.
  - `context`: build system, target file, language.
- **Execution Rules:**
  - Follow Laya's `error_category` and suggested `mechanical_fix` immediately.
  - Avoid burning speculative LLM tokens when a deterministic fix is identified.

### 3. `make_decision`
- **Trigger:** Multi-option architectural forks, pipeline routing choices, or ambiguous implementation paths where choosing incorrectly would waste time and tokens.
- **Parameters:**
  - `state`: concise description of current context.
  - `question`: the specific choice to make.
  - `options`: array of candidate options.
- **Execution Rules:**
  - Adopt the option recommended by Laya.
  - If confidence is low, note the trade-off briefly before proceeding.

## Invariant Rules
1. Never bypass `evaluate_shell_command` on mutating or potentially destructive shell commands.
2. Keep Laya routing concise: state the tool call result in one sentence before acting, without verbose fluff.
