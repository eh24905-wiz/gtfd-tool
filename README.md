# GTFD Tool - Todo.txt GTD Manager

A command-line task management tool implementing the GTD (Getting Things Done) methodology with the todo.txt format.

## Overview

This shell script provides a simple yet powerful way to manage tasks using the [todo.txt format](http://todotxt.org/). It features an inbox workflow for quick capture, interactive task processing, priority management, and due date tracking.

### Key Features

- **Quick Capture**: Instantly capture thoughts to an inbox for later processing
- **GTD Workflow**: Review and process inbox items into actionable tasks
- **Priority Support**: Assign priorities (A-Z) with validation
- **Projects & Contexts**: Organize with `+Project` and `@context` tags
- **Due Dates**: Track deadlines with natural language support (today, tomorrow, monday, etc.)
- **Color-coded Output**: Visual feedback with automatic detection for piped output
- **Cross-platform**: Works on macOS and Linux
- **Input Validation**: Robust handling of task numbers, priorities, and dates
- **Completed Tasks View**: Review what you've accomplished

## Installation

### Prerequisites

- Bash 4.0 or later
- macOS or Linux

### Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/eh24905-wiz/gtfd-tool.git ~/.todo
   ```

2. Make the script executable:
   ```bash
   chmod +x ~/.todo/todo.sh
   ```

3. Create an alias for easy access (add to `~/.bashrc` or `~/.zshrc`):
   ```bash
   alias t="~/.todo/todo.sh"
   ```

4. (Optional) Copy the example todo file:
   ```bash
   cp ~/.todo/todo.txt.example ~/.todo/todo.txt
   ```

5. Reload your shell:
   ```bash
   source ~/.zshrc  # or ~/.bashrc
   ```

## Usage

### Quick Capture (Inbox)

Capture ideas quickly without interrupting your flow:

```bash
t "Call dentist about appointment"
t "Research vacation destinations"
```

### View Inbox

```bash
t inbox      # or: t i
```

### Process Inbox

Review and organize inbox items into actionable tasks:

```bash
t process    # or: t p
t process 2  # Process specific item
```

During processing, you can:
- **(a)** Make actionable - Add priority, project, context, and due date
- **(d)** Delete - Remove the item
- **(s)** Skip - Move to end of inbox for later
- **(q)** Quit - Exit processing

### List Tasks

```bash
t list           # or: t l     - Show actionable tasks (excludes inbox)
t list all       # or: t la    - Show all including inbox
t list +Project  # Filter by project
t list @context  # Filter by context
```

### Add Tasks Directly

Skip the inbox and add a fully-formed task:

```bash
t add "Call Mom @phone +Family"
t add "(A) Review quarterly report @work +Q4Review due:2024-01-20"
```

### Complete Tasks

```bash
t done 1    # or: t d 1   - Mark task #1 as complete
t done      # or: t d     - View all completed tasks
```

### Delete Tasks

```bash
t xx 1      # Permanently delete task #1 (with confirmation)
```

Note: Use task numbers from `t list all` to delete inbox items.

### Due Date Commands

```bash
t due           # or: t du     - Show all tasks with due dates
t due today     # or: t du t   - Show tasks due today
t due overdue   # or: t du o   - Show overdue tasks
```

### Help

```bash
t help      # or: t h
```

## Configuration

### File Locations

| File | Location | Purpose |
|------|----------|---------|
| Todo file | `~/.todo/todo.txt` | Stores all tasks |

### Customization

Edit the following variables at the top of `todo.sh`:

```bash
TODO_DIR="$HOME/.todo"      # Directory for todo files
TODO_FILE="$TODO_DIR/todo.txt"  # Main todo file
```

### Todo.txt Format

Tasks follow the [todo.txt format](https://github.com/todotxt/todo.txt):

```
(A) 2024-01-15 Call Mom +Family @phone due:2024-01-20
│   │          │       │       │      └── Due date
│   │          │       │       └── Context
│   │          │       └── Project
│   │          └── Task description
│   └── Creation date
└── Priority (A-Z)
```

Completed tasks are prefixed with `x` and completion date:
```
x 2024-01-16 2024-01-15 Call Mom +Family @phone
```

## Examples

### Typical Workflow

```bash
# Quick capture during the day
t "Idea for blog post about productivity"
t "Buy birthday gift for Sarah"
t "Schedule team meeting"

# Review inbox when ready
t process

# Check your task list
t list

# Complete tasks
t done 1
```

### Filter and Focus

```bash
# See all work tasks
t list +Work

# See phone calls to make
t list @phone

# Check what's due today
t due today
```

## Command Reference

| Command | Alias | Description |
|---------|-------|-------------|
| `t "text"` | | Quick capture to inbox |
| `t inbox` | `t i` | View inbox |
| `t process` | `t p` | Interactive inbox review |
| `t process N` | `t p N` | Process specific inbox item |
| `t list` | `t l` | Show actionable tasks |
| `t list all` | `t la` | Show all including inbox |
| `t list +Project` | | Filter by project |
| `t add "task"` | | Add task directly |
| `t done` | `t d` | View completed tasks |
| `t done N` | `t d N` | Mark task #N complete |
| `t xx N` | | Delete task #N |
| `t due` | `t du` | Show tasks with due dates |
| `t due today` | `t du t` | Show tasks due today |
| `t due overdue` | `t du o` | Show overdue tasks |
| `t help` | `t h` | Show help |

## License

MIT License - Feel free to modify and distribute.
