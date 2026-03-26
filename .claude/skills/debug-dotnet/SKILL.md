---
name: debug-dotnet
description: Debug .NET applications using netcoredbg in MI (GDB/MI) mode. Use when the user wants to debug a .NET app, set breakpoints, inspect variables, step through code, or diagnose runtime issues.
allowed-tools: Bash, Read, Grep, Glob
argument-hint: [file:line or bug description]
---

# .NET Debugger (netcoredbg MI mode)

Debug .NET applications interactively using netcoredbg's Machine Interface protocol.
The helper script at `${CLAUDE_SKILL_DIR}/scripts/netdbg.sh` manages the debug session.

## Arguments

`$ARGUMENTS` may contain:
- A breakpoint location like `Program.cs:42` or `MyNamespace.MyClass.MyMethod`
- A description of the bug to investigate
- A path to a project directory or DLL

## Workflow

### Step 1: Verify Environment

```bash
which netcoredbg || echo "ERROR: netcoredbg not found"
dotnet --version || echo "ERROR: dotnet not found"
```

If netcoredbg is missing, tell the user to install it from https://github.com/Samsung/netcoredbg/releases.

### Step 2: Find and Build the Project

Locate the .NET project (look for `*.csproj` or `*.sln` files). Build in Debug configuration:

```bash
dotnet build -c Debug
```

Note the output DLL path from build output (e.g., `bin/Debug/net8.0/MyApp.dll`).

### Step 3: Start Debug Session

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh start /path/to/bin/Debug/net8.0/MyApp.dll
```

Then read the initial output to confirm MI mode is active:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh read
```

You should see `=library-loaded` messages confirming netcoredbg started.

### Step 4: Set Breakpoints

Set breakpoints BEFORE running the program:

```bash
# By file and line
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh send "-break-insert /full/path/to/Program.cs:42"
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh read

# By method name
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh send "-break-insert MyNamespace.MyClass.MyMethod"
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh read
```

Verify with `^done,bkpt={number=` in the response. If `^error`, check the path/line.

Use FULL file paths for breakpoints — relative paths may not resolve correctly.

### Step 5: Run the Program

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh send "-exec-run"
sleep 1
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh read
```

Watch for these stop reasons in the output:
- `*stopped,reason="breakpoint-hit"` — breakpoint reached
- `*stopped,reason="exception-received"` — unhandled exception
- `*stopped,reason="exited"` — program finished

If the program needs time to reach the breakpoint (e.g., web server awaiting request), tell the user what to do to trigger the code path, then read again.

### Step 6: Inspect State

When stopped, inspect program state:

```bash
# Call stack
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh send "-stack-list-frames"
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh read

# All local variables in current frame
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh send "-stack-list-variables --all-values"
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh read

# Evaluate a specific expression
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh send '-data-evaluate-expression "variableName"'
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh read

# Inspect object properties
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh send '-data-evaluate-expression "myObj.Property"'
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh read
```

### Step 7: Step Through Code

```bash
# Step over (next line)
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh send "-exec-next"
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh read

# Step into (enter method)
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh send "-exec-step"
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh read

# Step out (finish method)
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh send "-exec-finish"
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh read

# Continue to next breakpoint
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh send "-exec-continue"
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh read
```

After each step, re-inspect variables to observe how state changes.

### Step 8: Diagnose and Report

After gathering debug information:

1. Summarize observations at each breakpoint/step
2. Identify root cause from variable states and control flow
3. Suggest a specific code fix
4. If unclear, set additional breakpoints and repeat

### Step 9: Clean Up

Always clean up when done:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh send "-gdb-exit"
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh stop
```

## MI Response Reference

| Prefix | Meaning |
|--------|---------|
| `^done` | Command succeeded, result data follows |
| `^running` | Target is now running |
| `^error,msg="..."` | Command failed |
| `*stopped,reason="..."` | Target stopped (breakpoint, exception, exit) |
| `=library-loaded` | Assembly loaded |
| `=thread-created` | New thread |
| `~"..."` | Console/debug output |
| `@"..."` | Target program stdout |

## Troubleshooting

- **Breakpoint not hit**: Ensure `-c Debug` build. Check full file path. Verify the code path executes.
- **"Unable to evaluate expression"**: Variable may be optimized away (Release build) or out of scope. Use `-stack-list-variables --all-values` to see what's available.
- **Session hangs on read**: Program may be waiting for input or blocked. Run `bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh stop` and restart.
- **No output from read**: Try `sleep 1` then read again — command may still be processing.
