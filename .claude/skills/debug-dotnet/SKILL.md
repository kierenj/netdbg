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

If either tool is missing, install them before proceeding (see the Dependencies section below).

### Step 2: Find and Build the Project

Locate the .NET project (look for `*.csproj` or `*.sln` files). Build in Debug configuration:

```bash
dotnet build -c Debug
```

Note the output DLL path from build output (e.g., `bin/Debug/net8.0/MyApp.dll`).

For multi-project solutions, identify the entry point project (the one with `<OutputType>Exe</OutputType>`) and build that. Breakpoints can be set in any project's source files as long as the DLLs were built with Debug symbols.

### Step 3: Start Debug Session

**Launch a new process:**
```bash
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh start /path/to/bin/Debug/net8.0/MyApp.dll
```

**Or attach to a running process:**
```bash
# Find the PID first
ps aux | grep dotnet
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh attach <pid>
```

When attaching, the process is paused immediately. Set breakpoints, then send `-exec-continue` to resume.

Then read the initial output to confirm MI mode is active:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh read
```

You should see `=library-loaded` messages and `(gdb)` confirming netcoredbg started.

### Step 4: Set Breakpoints

Set breakpoints BEFORE running the program:

```bash
# By file and line (use FULL paths — relative paths may not resolve)
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh send "-break-insert /full/path/to/Program.cs:42"
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh read

# By method name
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh send "-break-insert MyNamespace.MyClass.MyMethod"
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh read
```

Verify with `^done,bkpt={number=` in the response. If `^error`, check the path/line.

#### Conditional Breakpoints

Stop only when a condition is true:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh send '-break-insert -c "i==100" /full/path/to/File.cs:33'
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh read
```

The condition is a C# expression evaluated at the breakpoint location.

NOTE: The `-i` flag (ignore count / skip first N hits) is NOT functional in netcoredbg — use a conditional breakpoint with a counter variable instead.

#### Exception Breakpoints

Break when exceptions are thrown (not just unhandled):

```bash
# Break on ALL thrown exceptions
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh send '-break-exception-insert throw+user-unhandled *'
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh read

# Break on a specific exception type only
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh send '-break-exception-insert throw+user-unhandled System.NullReferenceException'
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh read
```

When an exception breakpoint fires, the stop reason will be `*stopped,reason="exception-received"` with `exception-stage="throw"`. The `$exception` variable will be available for inspection.

### Step 5: Run the Program

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh send "-exec-run"
sleep 1
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh read
```

netcoredbg stops at the entry point first (`*stopped,reason="entry-point-hit"`).
Send `-exec-continue` to proceed to your breakpoints.

Watch for these stop reasons in the output:
- `*stopped,reason="entry-point-hit"` — paused at program entry, send `-exec-continue`
- `*stopped,reason="breakpoint-hit"` — breakpoint reached
- `*stopped,reason="exception-received"` — exception thrown (check `exception-stage` and `$exception` variable)
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
```

#### Inspecting Complex Objects and Collections

NOTE: `-data-evaluate-expression` is NOT supported by netcoredbg. Use the `-var-*` commands instead.

To inspect objects, collections, and nested properties, use this three-step pattern:

```bash
# 1. Create a variable handle for the object
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh send '-var-create myvar * "variableName"'
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh read
# Response shows: numchild (number of properties/fields)

# 2. List its children (properties, fields)
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh send '-var-list-children myvar'
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh read
# Response shows child names like var2, var3... with their exp (property name) and type

# 3. Get the value of a specific child
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh send '-var-evaluate-expression var2'
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh read
# Response: ^done,value="the value"
```

**List/Array items:** Create a var for the list, list children to find `_items` (the backing array), then list children of `_items` to see `[0]`, `[1]`, etc. Use `-var-evaluate-expression` on each element to get the value.

**Dictionary entries:** Create a var for the dictionary and drill into its internal structure via `-var-list-children`.

**Nested objects:** List children of an object to find its properties. If a child has `numchild > 0`, it's a complex type — create or list its children to drill deeper.

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

# Interrupt a running/blocked program
bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh send "-exec-interrupt"
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

## Process I/O (stdout, stderr, stdin)

**stdout and stderr:** Both appear as `=message,text="...",send-to="output-window"` in the MI output. They are NOT distinguishable from each other — both use the same format. Look for these in `read` output to see what the program printed.

**stdin:** The process's stdin is NOT directly accessible through MI commands. The FIFO pipe feeds netcoredbg's MI command interpreter, not the debugged program. If the program calls `Console.ReadLine()` or similar, it will block indefinitely. Use `-exec-interrupt` to regain control if this happens.

**Writing to stdin via /proc (Linux only):** On Linux, you can send input to the debugged process by writing to netcoredbg's fd 4, which is piped to the child's stdin:

```bash
# Find netcoredbg's PID
pgrep -f "netcoredbg --interpreter=mi"
# Write to its fd 4 to deliver stdin to the debugged process
echo "input text" > /proc/<netcoredbg-pid>/fd/4
```

**Other workarounds for stdin-dependent programs:**
- Modify the code to read from a file or environment variable instead during debugging
- Use the attach approach: start the program normally (with stdin available), then attach the debugger

## Async/Await Debugging

When debugging `async` methods, be aware of these quirks:

**Stack frames:** Async methods show as compiler-generated state machine names in the call stack:
- `MyClass.<MyMethod>d__1.MoveNext()` instead of `MyClass.MyMethod()`
- The `<MethodName>` in angle brackets is the original method name
- The stack will include framework frames like `AsyncStateMachineBox`, `ExecutionContext.RunInternal`, `ThreadPoolWorkQueue.Dispatch`

**Variables:** Despite the mangled stack frames, local variables are usually accessible with their original names via `-stack-list-variables --all-values`.

**Threads:** After an `await`, execution may resume on a different thread (thread pool). The `thread-id` in stop messages may change between steps. This is normal.

**Stepping:** Stepping over an `await` will stop after the awaited task completes. If the task takes time (e.g., `Task.Delay`, HTTP call), add a longer `sleep` before reading output.

## MI Response Reference

| Prefix | Meaning |
|--------|---------|
| `^done` | Command succeeded, result data follows |
| `^running` | Target is now running |
| `^error,msg="..."` | Command failed |
| `*stopped,reason="..."` | Target stopped (breakpoint, exception, exit, interrupt) |
| `=library-loaded` | Assembly loaded |
| `=thread-created` | New thread |
| `=message,text="...",send-to="output-window"` | Program stdout/stderr output |

## Troubleshooting

- **Breakpoint not hit**: Ensure `-c Debug` build. Check full file path. Verify the code path executes.
- **Program blocked on stdin**: Use `-exec-interrupt` to pause, then either skip past the ReadLine with stepping or stop and use the attach workflow instead.
- **Session hangs on read**: Program may be waiting for input or blocked. Use `-exec-interrupt` to regain control, or `bash ${CLAUDE_SKILL_DIR}/scripts/netdbg.sh stop` to force-stop.
- **No output from read**: Try `sleep 1` then read again — command may still be processing.
- **`libdbgshim.so` not found**: All files from the netcoredbg release tarball must be installed together (see Dependencies below).
- **Async stack is confusing**: Look for the original method name in angle brackets: `<MethodName>d__N.MoveNext()` means you're in `MethodName`. Ignore the framework frames below it.
- **Thread ID changed after await**: Normal for async code — execution resumed on a thread pool thread.
- **`-data-evaluate-expression` returns "Unknown command"**: This command is not supported by netcoredbg. Use `-var-create`, `-var-list-children`, and `-var-evaluate-expression` instead.

## Dependencies

This skill requires the .NET SDK and netcoredbg. The .NET SDK is assumed to be already installed. If netcoredbg is missing, install it using the steps below.

### netcoredbg

The Samsung .NET debugger. Must be installed with ALL companion files from the release archive (the binary alone is not enough — it needs `libdbgshim.so` and several `.dll` files).

**Linux (amd64):**
```bash
curl -sSL https://github.com/Samsung/netcoredbg/releases/latest/download/netcoredbg-linux-amd64.tar.gz -o /tmp/netcoredbg.tar.gz
tar xzf /tmp/netcoredbg.tar.gz -C /tmp
cp /tmp/netcoredbg/* /usr/local/bin/
```

**macOS (arm64):**
```bash
curl -sSL https://github.com/Samsung/netcoredbg/releases/latest/download/netcoredbg-osx-arm64.tar.gz -o /tmp/netcoredbg.tar.gz
tar xzf /tmp/netcoredbg.tar.gz -C /tmp
cp /tmp/netcoredbg/* /usr/local/bin/
```

**macOS (amd64):**
```bash
curl -sSL https://github.com/Samsung/netcoredbg/releases/latest/download/netcoredbg-osx-amd64.tar.gz -o /tmp/netcoredbg.tar.gz
tar xzf /tmp/netcoredbg.tar.gz -C /tmp
cp /tmp/netcoredbg/* /usr/local/bin/
```

**Windows:**
Download https://github.com/Samsung/netcoredbg/releases/latest/download/netcoredbg-win64.zip, extract it, and add the extracted directory to your PATH.

For other platforms, download the correct archive from https://github.com/Samsung/netcoredbg/releases.

IMPORTANT: Keep ALL files from the extracted archive together in the same directory, not just the `netcoredbg` binary. The debugger requires `libdbgshim.so` (Linux), `libdbgshim.dylib` (macOS), or `dbgshim.dll` (Windows) and several managed `.dll` files (`ManagedPart.dll`, `Microsoft.CodeAnalysis.*.dll`) to function.

Verify with: `netcoredbg --version`
