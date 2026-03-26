#!/usr/bin/env bash
set -euo pipefail

SESSION_DIR="/tmp/netdbg-session"
CMD_PIPE="$SESSION_DIR/cmd_pipe"
OUTPUT_LOG="$SESSION_DIR/output.log"
DBG_PID_FILE="$SESSION_DIR/dbg.pid"
TAIL_PID_FILE="$SESSION_DIR/tail.pid"
READ_OFFSET_FILE="$SESSION_DIR/read_offset"

usage() {
    cat <<'USAGE'
Usage: netdbg.sh <command> [args...]

Commands:
  start <target>        Start a debug session
                        target: path to .dll, or a command like "dotnet run --project ./MyApp"
  attach <pid>          Attach to a running .NET process by PID
  send  "<mi-command>"  Send a GDB/MI command to netcoredbg
  read                  Read new output since last read
  sr "<mi-command>" [wait]  Send a command and read the response (default wait: 0.5s)
  stop                  Stop the debug session and clean up
  status                Check if a debug session is active
USAGE
}

cmd_start() {
    local target="${1:?ERROR: No target specified. Provide a .dll path or a command.}"

    # Clean up any previous session
    if [[ -d "$SESSION_DIR" ]]; then
        echo "Cleaning up previous session..."
        cmd_stop 2>/dev/null || true
    fi

    mkdir -p "$SESSION_DIR"
    mkfifo "$CMD_PIPE"
    : > "$OUTPUT_LOG"
    echo "0" > "$READ_OFFSET_FILE"

    # Determine how to launch netcoredbg based on the target
    if [[ "$target" == *.dll ]]; then
        # Direct DLL — launch via dotnet runtime
        tail -f "$CMD_PIPE" | netcoredbg --interpreter=mi -- dotnet "$target" > "$OUTPUT_LOG" 2>&1 &
        local pipeline_pid=$!
    else
        # Treat as a shell command (e.g., "dotnet run --project ./MyApp")
        # shellcheck disable=SC2086
        tail -f "$CMD_PIPE" | netcoredbg --interpreter=mi -- $target > "$OUTPUT_LOG" 2>&1 &
        local pipeline_pid=$!
    fi

    # Save the pipeline PID (covers both tail and netcoredbg)
    echo "$pipeline_pid" > "$DBG_PID_FILE"

    # Also find and save the tail PID so we can kill it on stop
    # tail is the first process in the pipeline
    local tail_pid
    tail_pid=$(jobs -p 2>/dev/null | head -1)
    if [[ -n "${tail_pid:-}" ]]; then
        echo "$tail_pid" > "$TAIL_PID_FILE"
    fi

    # Wait briefly for netcoredbg to initialize
    sleep 1

    echo "Debug session started. Target: $target"
    echo "Session directory: $SESSION_DIR"
    echo ""
    echo "Use 'netdbg.sh read' to see initial output."
}

cmd_attach() {
    local pid="${1:?ERROR: No PID specified. Provide the process ID to attach to.}"

    # Clean up any previous session
    if [[ -d "$SESSION_DIR" ]]; then
        echo "Cleaning up previous session..."
        cmd_stop 2>/dev/null || true
    fi

    mkdir -p "$SESSION_DIR"
    mkfifo "$CMD_PIPE"
    : > "$OUTPUT_LOG"
    echo "0" > "$READ_OFFSET_FILE"

    # Launch netcoredbg in attach mode
    tail -f "$CMD_PIPE" | netcoredbg --interpreter=mi --attach "$pid" > "$OUTPUT_LOG" 2>&1 &
    local pipeline_pid=$!

    echo "$pipeline_pid" > "$DBG_PID_FILE"

    local tail_pid
    tail_pid=$(jobs -p 2>/dev/null | head -1)
    if [[ -n "${tail_pid:-}" ]]; then
        echo "$tail_pid" > "$TAIL_PID_FILE"
    fi

    sleep 1

    echo "Attached to process $pid."
    echo "Session directory: $SESSION_DIR"
    echo ""
    echo "Use 'netdbg.sh read' to see initial output."
    echo "NOTE: The process is paused. Set breakpoints, then use 'send \"-exec-continue\"' to resume."
}

cmd_send() {
    local mi_cmd="${1:?ERROR: No MI command specified.}"

    if [[ ! -p "$CMD_PIPE" ]]; then
        echo "ERROR: No active debug session. Run 'netdbg.sh start' first."
        return 1
    fi

    # Send the MI command through the FIFO
    echo "$mi_cmd" > "$CMD_PIPE"

    # Brief pause to let netcoredbg process the command
    sleep 0.5

    echo "Sent: $mi_cmd"
}

cmd_sr() {
    local mi_cmd="${1:?ERROR: No MI command specified.}"
    local wait="${2:-1}"

    if [[ ! -p "$CMD_PIPE" ]]; then
        echo "ERROR: No active debug session. Run 'netdbg.sh start' first."
        return 1
    fi

    echo "$mi_cmd" > "$CMD_PIPE"
    sleep "$wait"

    # Poll briefly if no output yet (up to 5 retries, 1s apart)
    local offset
    offset=$(cat "$READ_OFFSET_FILE" 2>/dev/null || echo 0)
    local current_size
    current_size=$(wc -c < "$OUTPUT_LOG")
    local retries=0
    while [[ "$current_size" -le "$offset" && "$retries" -lt 5 ]]; do
        sleep 1
        current_size=$(wc -c < "$OUTPUT_LOG")
        retries=$((retries + 1))
    done

    cmd_read
}

cmd_read() {
    if [[ ! -f "$OUTPUT_LOG" ]]; then
        echo "ERROR: No active debug session. Run 'netdbg.sh start' first."
        return 1
    fi

    local offset
    offset=$(cat "$READ_OFFSET_FILE" 2>/dev/null || echo 0)

    local current_size
    current_size=$(wc -c < "$OUTPUT_LOG")

    if [[ "$current_size" -gt "$offset" ]]; then
        # Show new output since last read
        tail -c +"$((offset + 1))" "$OUTPUT_LOG"
        echo "$current_size" > "$READ_OFFSET_FILE"
    else
        echo "(no new output)"
    fi
}

cmd_stop() {
    local stopped=false

    # Kill the pipeline process group
    if [[ -f "$DBG_PID_FILE" ]]; then
        local dbg_pid
        dbg_pid=$(cat "$DBG_PID_FILE")
        if kill -0 "$dbg_pid" 2>/dev/null; then
            kill "$dbg_pid" 2>/dev/null || true
            wait "$dbg_pid" 2>/dev/null || true
            stopped=true
        fi
    fi

    # Kill tail specifically if still running
    if [[ -f "$TAIL_PID_FILE" ]]; then
        local tail_pid
        tail_pid=$(cat "$TAIL_PID_FILE")
        if kill -0 "$tail_pid" 2>/dev/null; then
            kill "$tail_pid" 2>/dev/null || true
        fi
    fi

    # Also kill any remaining netcoredbg processes from our session
    pkill -f "netcoredbg --interpreter=mi" 2>/dev/null || true

    # Clean up session directory
    if [[ -d "$SESSION_DIR" ]]; then
        rm -rf "$SESSION_DIR"
    fi

    if [[ "$stopped" == true ]]; then
        echo "Debug session stopped and cleaned up."
    else
        echo "No active debug session found. Cleaned up session directory."
    fi
}

cmd_status() {
    if [[ ! -d "$SESSION_DIR" ]]; then
        echo "No active debug session."
        return 1
    fi

    if [[ -f "$DBG_PID_FILE" ]]; then
        local dbg_pid
        dbg_pid=$(cat "$DBG_PID_FILE")
        if kill -0 "$dbg_pid" 2>/dev/null; then
            echo "Debug session is ACTIVE (PID: $dbg_pid)"
            echo "Session directory: $SESSION_DIR"
            echo "Output log size: $(wc -c < "$OUTPUT_LOG") bytes"
            return 0
        fi
    fi

    echo "Debug session exists but process is not running."
    echo "Run 'netdbg.sh stop' to clean up, then 'netdbg.sh start' to restart."
    return 1
}

# Main dispatch
case "${1:-}" in
    start)  shift; cmd_start "$@" ;;
    attach) shift; cmd_attach "$@" ;;
    send)   shift; cmd_send "$@" ;;
    sr)     shift; cmd_sr "$@" ;;
    read)   shift; cmd_read "$@" ;;
    stop)   shift; cmd_stop "$@" ;;
    status) shift; cmd_status "$@" ;;
    -h|--help|help) usage ;;
    *)
        echo "ERROR: Unknown command '${1:-}'"
        usage
        exit 1
        ;;
esac
