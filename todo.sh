#!/usr/bin/env bash
# GTD-style Todo.txt Manager with Inbox Workflow

set -o pipefail

# Configuration
# Priority: Environment variable > Config file > Default
readonly CONFIG_DIR="$HOME/.todo"
readonly CONFIG_FILE="$CONFIG_DIR/config"

# Default values
DEFAULT_TODO_FILE="$HOME/.todo/todo.txt"

# Load config file if it exists
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# Set TODO_FILE: env var takes priority, then config file, then default
TODO_FILE="${TODO_FILE:-$DEFAULT_TODO_FILE}"

# Derive TODO_DIR and LOCK_FILE from TODO_FILE location
TODO_DIR="$(dirname "$TODO_FILE")"
LOCK_FILE="$TODO_DIR/.todo.lock"

# Export for potential child processes
export TODO_FILE TODO_DIR

# UI Constants
readonly SEPARATOR="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
readonly INBOX_MARKER="status:inbox"

# Color support detection: disable colors when output isn't a terminal
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; NC=''
fi

# Initialize todo directory and file with error handling
if ! mkdir -p "$TODO_DIR"; then
    echo "Error: Cannot create directory $TODO_DIR" >&2
    exit 1
fi

if ! touch "$TODO_FILE"; then
    echo "Error: Cannot create file $TODO_FILE" >&2
    exit 1
fi

today() { date +%Y-%m-%d; }

# Validation helper: check if argument is a positive integer
is_positive_integer() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

# Validation helper: check if priority is valid (single letter A-Z)
# Uses tr for Bash 3.2 compatibility (macOS default)
is_valid_priority() {
    [[ "$1" =~ ^[A-Za-z]$ ]]
}

# Convert to uppercase (Bash 3.2 compatible)
to_upper() {
    echo "$1" | tr '[:lower:]' '[:upper:]'
}

# Cross-platform sed in-place edit
sed_inplace() {
    if sed --version 2>&1 | grep -q GNU; then
        sed -i "$@"
    else
        sed -i '' "$@"
    fi
}

# File locking wrapper for safe concurrent access
with_lock() {
    local lock_fd=200
    exec 200>"$LOCK_FILE"
    flock -x $lock_fd
    "$@"
    local result=$?
    exec 200>&-
    return $result
}

inbox_count() {
    local c
    c=$(grep -c "$INBOX_MARKER" "$TODO_FILE" 2>/dev/null)
    echo "${c:-0}"
}

get_inbox_line() { grep -n "$INBOX_MARKER" "$TODO_FILE" | sed -n "${1}p" | cut -d: -f1; }

# Get task line number matching the DISPLAY order (priority sorted first, then other)
# Caches file content in a single read for efficiency
# Usage: get_task_line <task_num> [include_inbox]
#   include_inbox: if "all", includes inbox items (matches 't la' behavior)
get_task_line() {
    local task_num="$1"
    local include_inbox="$2"

    # Validate input is a positive integer
    if ! is_positive_integer "$task_num"; then
        return 1
    fi

    # Read file content once to avoid multiple file reads
    local file_content
    file_content=$(cat "$TODO_FILE" 2>/dev/null) || return 1

    local tasks priority other combined_tasks

    # Get tasks excluding completed (and optionally inbox)
    if [[ "$include_inbox" == "all" ]]; then
        tasks=$(echo "$file_content" | grep -v "^x ")
    else
        tasks=$(echo "$file_content" | grep -v "^x " | grep -v "$INBOX_MARKER")
    fi
    priority=$(echo "$tasks" | grep "^([A-Z])" | sort)
    other=$(echo "$tasks" | grep -v "^([A-Z])")

    # Combine in display order
    combined_tasks=""
    [[ -n "$priority" ]] && combined_tasks="$priority"
    if [[ -n "$other" ]]; then
        [[ -n "$combined_tasks" ]] && combined_tasks="$combined_tasks"$'\n'"$other" || combined_tasks="$other"
    fi

    # Get the Nth task from combined list
    local target_task
    target_task=$(echo "$combined_tasks" | sed -n "${task_num}p")
    [[ -z "$target_task" ]] && return

    # Find this exact task's line number using fixed-string matching (handles special chars)
    echo "$file_content" | grep -nF "$target_task" | head -1 | cut -d: -f1
}

format_project() {
    local input="$1"
    [[ -z "$input" ]] && return
    [[ "$input" == +* ]] && echo "$input" || echo "+$input"
}

format_context() {
    local input="$1"
    [[ -z "$input" ]] && return
    [[ "$input" == @* ]] && echo "$input" || echo "@$input"
}

parse_due_date() {
    local input="$1"
    [[ -z "$input" ]] && return

    # Check for YYYY-MM-DD format
    if [[ "$input" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        # Validate it's a real date (macOS date validation)
        if date -j -f "%Y-%m-%d" "$input" >/dev/null 2>&1; then
            echo "$input"
        else
            printf "${YELLOW}Warning: Invalid date '%s', ignoring${NC}\n" "$input" >&2
        fi
        return
    fi

    local day_input=$(echo "$input" | tr '[:upper:]' '[:lower:]')
    local target_day=""

    case "$day_input" in
        sun|sunday)    target_day=0 ;;
        mon|monday)    target_day=1 ;;
        tue|tuesday)   target_day=2 ;;
        wed|wednesday) target_day=3 ;;
        thu|thursday)  target_day=4 ;;
        fri|friday)    target_day=5 ;;
        sat|saturday)  target_day=6 ;;
        today|tod)     echo "$(today)"; return ;;
        tomorrow|tom)  date -v+1d +%Y-%m-%d; return ;;
        *)
            printf "${YELLOW}Warning: Unrecognized date '%s', ignoring${NC}\n" "$input" >&2
            return
            ;;
    esac

    local today_dow=$(date +%w)
    local days_ahead=$(( (target_day - today_dow + 7) % 7 ))
    [[ $days_ahead -eq 0 ]] && days_ahead=7

    date -v+${days_ahead}d +%Y-%m-%d
}

# Prompts user for task metadata and builds a formatted task string
# Sets the BUILD_TASK variable with the result
# Returns 0 on success, 1 if user cancelled
prompt_and_build_task() {
    local task_text="$1"
    local priority project context due

    read -r -p "  Priority (A-Z or Enter to skip): " priority

    # Validate priority if provided
    if [[ -n "$priority" ]] && ! is_valid_priority "$priority"; then
        printf "${YELLOW}  Warning: Invalid priority '%s' (must be A-Z), ignoring${NC}\n" "$priority"
        priority=""
    fi

    read -r -p "  Project (e.g., Health): " project
    read -r -p "  Context (e.g., phone): " context
    read -r -p "  Due date (YYYY-MM-DD or day name or today/tomorrow): " due

    project=$(format_project "$project")
    context=$(format_context "$context")
    due=$(parse_due_date "$due")

    BUILD_TASK="$(today) $task_text"
    [[ -n "$priority" ]] && BUILD_TASK="($(to_upper "$priority")) $BUILD_TASK"
    [[ -n "$project" ]] && BUILD_TASK="$BUILD_TASK $project"
    [[ -n "$context" ]] && BUILD_TASK="$BUILD_TASK $context"
    [[ -n "$due" ]] && BUILD_TASK="$BUILD_TASK due:$due"
}

cmd_inbox() {
    if [[ -z "$1" ]]; then
        local count
        count=$(inbox_count)
        if [[ "$count" -eq 0 ]]; then
            printf "${YELLOW}Inbox is empty${NC}\n"
            echo "Use 't \"your idea\"' to capture something."
            return 0
        fi
        printf "${CYAN}Inbox (%s items)${NC}\n" "$count"
        echo "$SEPARATOR"
        grep "$INBOX_MARKER" "$TODO_FILE" | sed "s/ *${INBOX_MARKER}//g" | sed 's/^[0-9-]* //' | nl -w2 -s'. '
        printf "\nRun ${BOLD}t process${NC} to review these items.\n"
    else
        echo "$(today) $* $INBOX_MARKER" >> "$TODO_FILE"
        printf "${GREEN}* Added to inbox:${NC} %s\n" "$*"
    fi
    return 0
}

cmd_list() {
    local show_all=false filter=""
    [[ "$1" == "all" ]] && show_all=true && shift
    filter="$1"

    printf "${CYAN}Todo List${NC}\n"
    echo "$SEPARATOR"

    # Handle empty file
    if [[ ! -s "$TODO_FILE" ]]; then
        printf "${YELLOW}No tasks yet. Add one with 't \"your task\"'${NC}\n"
        return
    fi

    local tasks
    if $show_all; then
        tasks=$(grep -v "^x " "$TODO_FILE" 2>/dev/null)
    else
        tasks=$(grep -v "^x " "$TODO_FILE" 2>/dev/null | grep -v "$INBOX_MARKER")
    fi
    [[ -n "$filter" ]] && tasks=$(echo "$tasks" | grep -i "$filter")

    if [[ -z "$tasks" ]]; then
        printf "${YELLOW}No tasks found.${NC}\n"
    else
        local priority=$(echo "$tasks" | grep "^([A-Z])" | sort)
        local other=$(echo "$tasks" | grep -v "^([A-Z])")
        local num=1
        local today_date
        today_date=$(today)

        if [[ -n "$priority" ]]; then
            printf "\n${BOLD}Priority Tasks:${NC}\n"
            while IFS= read -r line; do
                if [[ -n "$line" ]]; then
                    # Color-code due dates based on urgency
                    local display_line="$line"
                    if [[ "$line" =~ due:([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
                        local due_date="${BASH_REMATCH[1]}"
                        if [[ "$due_date" < "$today_date" ]]; then
                            display_line="${RED}${line}${NC} ! OVERDUE"
                        elif [[ "$due_date" == "$today_date" ]]; then
                            display_line="${YELLOW}${line}${NC} [TODAY]"
                        fi
                    fi
                    printf "%2d. %b\n" "$num" "$display_line"
                    ((num++))
                fi
            done <<< "$priority"
        fi

        if [[ -n "$other" ]]; then
            printf "\n${BOLD}Other Tasks:${NC}\n"
            while IFS= read -r line; do
                if [[ -n "$line" ]]; then
                    # Color-code due dates based on urgency
                    local display_line="$line"
                    if [[ "$line" =~ due:([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
                        local due_date="${BASH_REMATCH[1]}"
                        if [[ "$due_date" < "$today_date" ]]; then
                            display_line="${RED}${line}${NC} ! OVERDUE"
                        elif [[ "$due_date" == "$today_date" ]]; then
                            display_line="${YELLOW}${line}${NC} [TODAY]"
                        fi
                    fi
                    printf "%2d. %b\n" "$num" "$display_line"
                    ((num++))
                fi
            done <<< "$other"
        fi

        # Show task count summary
        printf "\n${CYAN}Total: %d task(s)${NC}\n" "$((num - 1))"
    fi

    local icount
    icount=$(inbox_count)
    if [[ "$icount" -gt 0 ]] && [ "$show_all" = "false" ]; then
        printf "${YELLOW}%s item(s) in inbox awaiting processing${NC}\n" "$icount"
    fi
    return 0
}

cmd_done() {
    # No arguments: show completed tasks
    if [[ -z "$1" ]]; then
        printf "${CYAN}Completed Tasks${NC}\n"
        echo "$SEPARATOR"

        local completed_tasks
        completed_tasks=$(grep "^x " "$TODO_FILE" 2>/dev/null | sort -r)

        if [[ -z "$completed_tasks" ]]; then
            printf "${YELLOW}No completed tasks yet.${NC}\n"
            return 0
        fi

        local num=1
        while IFS= read -r line; do
            # Format: x YYYY-MM-DD [optional-creation-date] task text
            # Extract completion date (first date after 'x ')
            local display_line="${line#x }"
            printf "%2d. [x] %s\n" "$num" "$display_line"
            ((num++))
        done <<< "$completed_tasks"

        printf "\n${CYAN}Total: %d completed${NC}\n" "$((num - 1))"
        return 0
    fi

    # With argument: mark task as complete
    if ! is_positive_integer "$1"; then
        printf "${RED}Usage: t done <task_number> (must be a positive number)${NC}\n"
        printf "${CYAN}Or run 't done' with no arguments to see completed tasks.${NC}\n"
        return 1
    fi

    local line_num
    line_num=$(get_task_line "$1")
    if [[ -z "$line_num" ]]; then
        printf "${RED}Task #%s not found. Run 't list' to see available tasks.${NC}\n" "$1"
        return 1
    fi
    local task completed
    task=$(sed -n "${line_num}p" "$TODO_FILE")
    completed="x $(today) $(echo "$task" | sed 's/^([A-Z]) //')"
    sed_inplace "${line_num}s|.*|${completed}|" "$TODO_FILE"
    printf "${GREEN}[x] Completed:${NC} %s\n" "$task"
    return 0
}

cmd_delete() {
    if [[ -z "$1" ]] || ! is_positive_integer "$1"; then
        printf "${RED}Usage: t xx <task_number> (must be a positive number)${NC}\n"
        return 1
    fi
    local line_num
    # Use "all" to include inbox items (matches 't la' numbering)
    line_num=$(get_task_line "$1" "all")
    if [[ -z "$line_num" ]]; then
        printf "${RED}Task #%s not found. Run 't list all' to see all tasks.${NC}\n" "$1"
        return 1
    fi
    local task confirm
    task=$(sed -n "${line_num}p" "$TODO_FILE")

    # Confirm deletion
    printf "${YELLOW}Delete:${NC} %s\n" "$task"
    read -r -p "Are you sure? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        printf "${BLUE}Cancelled.${NC}\n"
        return 0
    fi

    sed_inplace "${line_num}d" "$TODO_FILE"
    printf "${RED}✗ Deleted:${NC} %s\n" "$task"
    return 0
}

cmd_add() {
    if [[ -z "$1" ]]; then
        printf "${RED}Usage: t add \"task\" [@context] [+project]${NC}\n"; return 1
    fi
    echo "$(today) $*" >> "$TODO_FILE"
    printf "${GREEN}* Added:${NC} $(today) %s\n" "$*"
    return 0
}

cmd_process() {
    local specific_item="$1"
    [[ -n "$specific_item" ]] && { process_single_item "$specific_item"; return; }
    
    local count
    count=$(inbox_count)
    if [[ "$count" -eq 0 ]]; then
        printf "${GREEN}Inbox is empty! Nothing to process.${NC}\n"; return
    fi

    printf "${CYAN}Processing Inbox (%s items)${NC}\n" "$count"
    echo "$SEPARATOR"
    
    local processed=0 deleted=0 skipped=0 item_num=1
    
    while true; do
        local line_num
        line_num=$(get_inbox_line 1)
        [[ -z "$line_num" ]] && break

        local task
        task=$(sed -n "${line_num}p" "$TODO_FILE" | sed "s/ *${INBOX_MARKER}//" | sed 's/^[0-9-]* //')

        printf "\n${BOLD}[%s]${NC} %s\n\n" "$item_num" "$task"
        echo "  (a) Make actionable    (d) Delete    (s) Skip    (q) Quit"
        read -r -p "Choice: " choice
        
        case "$choice" in
            a|A)
                prompt_and_build_task "$task"
                sed_inplace "${line_num}d" "$TODO_FILE"
                echo "$BUILD_TASK" >> "$TODO_FILE"
                printf "${GREEN}* Updated:${NC} %s\n" "$BUILD_TASK"
                ((processed++))
                ;;
            d|D)
                sed_inplace "${line_num}d" "$TODO_FILE"
                printf "${YELLOW}* Deleted:${NC} %s\n" "$task"
                ((deleted++))
                ;;
            s|S)
                sed_inplace "${line_num}d" "$TODO_FILE"
                echo "$(today) $task $INBOX_MARKER" >> "$TODO_FILE"
                printf "${BLUE}-> Skipped (moved to end)${NC}\n"
                ((skipped++)); ((item_num++))
                ;;
            q|Q) printf "\n${YELLOW}Quit.${NC}\n"; break ;;
            *) printf "${RED}Invalid choice.${NC}\n" ;;
        esac
    done
    
    echo "$SEPARATOR"
    printf "${GREEN}Done!${NC} %s actionable, %s deleted, %s skipped\n" "$processed" "$deleted" "$skipped"
    return 0
}

process_single_item() {
    local line_num
    line_num=$(get_inbox_line "$1")
    if [[ -z "$line_num" ]]; then
        printf "${RED}Inbox item #%s not found.${NC}\n" "$1"; return 1
    fi
    local task
    task=$(sed -n "${line_num}p" "$TODO_FILE" | sed "s/ *${INBOX_MARKER}//" | sed 's/^[0-9-]* //')

    printf "${CYAN}Processing Inbox Item${NC}\n"
    echo "$SEPARATOR"
    printf "\n${BOLD}[%s]${NC} %s\n\n" "$1" "$task"
    echo "  (a) Make actionable    (d) Delete    (s) Skip"
    read -r -p "Choice: " choice
    
    case "$choice" in
        a|A)
            prompt_and_build_task "$task"
            sed_inplace "${line_num}d" "$TODO_FILE"
            echo "$BUILD_TASK" >> "$TODO_FILE"
            echo "$SEPARATOR"
            printf "${GREEN}* Updated:${NC} %s\n" "$BUILD_TASK"
            ;;
        d|D)
            sed_inplace "${line_num}d" "$TODO_FILE"
            echo "$SEPARATOR"
            printf "${YELLOW}* Deleted:${NC} %s\n" "$task"
            ;;
        *)
            echo "$SEPARATOR"
            printf "${BLUE}-> Skipped${NC}\n"
            ;;
    esac
    return 0
}

cmd_due() {
    local today_date
    today_date=$(today)
    printf "${CYAN}Tasks by Due Date${NC}\n"
    echo "$SEPARATOR"

    case "$1" in
        today|t)
            printf "\n${BOLD}Due Today (%s):${NC}\n" "$today_date"
            grep -v "^x " "$TODO_FILE" | grep "due:$today_date" | nl -w2 -s'. ' || echo "  (none)"
            ;;
        overdue|o)
            printf "\n${BOLD}Overdue:${NC}\n"
            local overdue_tasks
            overdue_tasks=$(grep -v "^x " "$TODO_FILE" | grep -E "due:[0-9]{4}-[0-9]{2}-[0-9]{2}" | while read -r line; do
                due=$(echo "$line" | grep -oE "due:[0-9-]+" | cut -d: -f2)
                [[ "$due" < "$today_date" ]] && echo "$line"
            done)
            if [[ -n "$overdue_tasks" ]]; then
                echo "$overdue_tasks" | nl -w2 -s'. '
            else
                echo "  (none)"
            fi
            ;;
        *) printf "\n${BOLD}All with due dates:${NC}\n"
           grep -v "^x " "$TODO_FILE" | grep "due:" | nl -w2 -s'. ' || echo "  (none)" ;;
    esac
    return 0
}

cmd_help() {
    printf "${BOLD}Todo.txt GTD Manager${NC}\n\n"
    printf "${CYAN}Command              Description${NC}\n"
    echo "─────────────────────────────────────────────────────"
    echo "t \"idea\"             Quick capture to inbox (default)"
    echo "t add \"task\"         Add task directly (skip inbox)"
    echo "t inbox / t i        List inbox items"
    echo "t process / t p      Interactive inbox review"
    echo "t process 2          Process specific inbox item"
    echo "t list / t l         Show actionable tasks (excludes inbox)"
    echo "t list all / t la    Show all including inbox"
    echo "t list +Project      Filter by project"
    echo "t done / t d         Show completed tasks"
    echo "t done N / t d N     Mark task #N as complete"
    echo "t xx N               Delete task #N permanently"
    echo "t due / t du         Show tasks with due dates"
    echo "t due today / t du t Show tasks due today"
    echo "t due overdue / t du o  Show overdue tasks"
    echo "t help / t h         Show this help"
}

# Main router - capture exit code to ensure clean exit
main_exit=0
case "$1" in
    inbox)       shift; cmd_inbox "$@" || main_exit=$? ;;
    i)           shift; cmd_inbox "$@" || main_exit=$? ;;
    list|ls)     shift; cmd_list "$@" || main_exit=$? ;;
    l)           shift; cmd_list "$@" || main_exit=$? ;;
    la)          shift; cmd_list all "$@" || main_exit=$? ;;
    process)     shift; cmd_process "$@" || main_exit=$? ;;
    p)           shift; cmd_process "$@" || main_exit=$? ;;
    done|do)     shift; cmd_done "$@" || main_exit=$? ;;
    d)           shift; cmd_done "$@" || main_exit=$? ;;
    xx)          shift; cmd_delete "$@" || main_exit=$? ;;
    add)         shift; cmd_add "$@" || main_exit=$? ;;
    due)         shift; cmd_due "$@" || main_exit=$? ;;
    du)          shift; cmd_due "$@" || main_exit=$? ;;
    help|-h|--help|h) cmd_help ;;
    "")          cmd_list || main_exit=$? ;;
    *)           cmd_inbox "$@" || main_exit=$? ;;
esac

exit $main_exit
