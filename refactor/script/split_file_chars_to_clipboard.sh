#!/bin/ksh
#
# split_file_to_clipboard.sh
# Split a file into character-based chunks, supporting IEC/SI size units.
# Usage: split_file_to_clipboard.sh [--size N|-s N] [--quiet|-q] [--dry-run|-n] <filename>

set -euo pipefail

# Default values (10 KiB = 10,240 chars)
CHUNK_SIZE=10240
VERBOSE=1
DRY_RUN=0

# Formatting constants
NBSP=$(printf "\u00a0")
COLS=$(/usr/bin/tput cols)
YELLOW='\033[33m'
CYAN='\033[36m'
RESET='\033[0m'

# Detect platform for command path logic
case "$(uname -s)" in
    Darwin)
        # macOS: use absolute paths for core tools
        AWK="/usr/bin/awk"
        CP="/bin/cp"
        FIND="/usr/bin/find"
        FOLD="/usr/bin/fold"
        MKTEMP="/usr/bin/mktemp"
        RM="/bin/rm"
        SED="/usr/bin/sed"
        TR="/usr/bin/tr"
        WC="/usr/bin/wc"

        # macOS: use absolute path for pbcopy
        CLIPBOARD_COPY="/usr/bin/pbcopy"
        ;;
    *)
        # Other: sanitize PATH, use command names
        export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
        AWK="awk"
        CP="cp"
        FIND="find"
        FOLD="fold"
        MKTEMP="mktemp"
        RM="rm"
        SED="sed"
        TR="tr"
        WC="wc"

        # Linux/BSD: detect xclip or xsel
        if command -v xclip >/dev/null 2>&1; then
            CLIPBOARD_COPY="xclip -selection clipboard -in"
        elif command -v xsel >/dev/null 2>&1; then
            CLIPBOARD_COPY="xsel --clipboard --input"
        else
            usage_note=1
            printf "\033[31mERROR: Install xclip or xsel for clipboard support\033[0m\n" >&2
            printf "  Ubuntu/Debian: sudo apt install xclip\n" >&2
            printf "  FreeBSD:       pkg install xclip\n" >&2
            printf "\n" >&2
            usage
        fi
        ;;
esac

usage() {
    printf "Usage: %s [--size N|-s N] [--quiet|-q] [--dry-run|-n] <filename>\n" "$1" >&2
    printf "  SIZE: Integer character count or unit suffix (e.g. 10K, 5MiB, 2.5MB)\n" >&2
    if usage_note=1; then
        printf "  NOTE:  On Linux/BSD, xclip or xsel required for clipboard\n" >&2
        exit 127
    fi
    exit 1
}

# Parse human-friendly size strings (e.g. 10K, 10KiB, 10KB, 2.5M, 1.5MB, etc.)
parse_size() {
    # Accepts a string like 10K, 8KiB, 5MB, 2.5M, 10000, etc.
    # Outputs the integer character count

    set -f  # Disable globbing

    str="$1"
    # Extract numeric part (may have decimal), and suffix
    num_part=$(printf '%s\n' "$str" | "$SED" -En 's/^([0-9.]+).*/\1/p')
    suffix_part=$(printf '%s\n' "$str" | "$SED" -En 's/^[0-9.]+(.*)/\1/p' | "$TR" '[:upper:]' '[:lower:]')

    # Handle unitless values
    [ -z "$suffix_part" ] && { printf "%.0f\n" "$num_part"; return; }

    # Determine multiplier
    case "$suffix_part" in
        # IEC binary units (1024ⁿ)
        k|ki|kib)   mult=1024 ;;
        m|mi|mib)   mult=$((1024**2)) ;;
        g|gi|gib)   mult=$((1024**3)) ;;
        t|ti|tib)   mult=$((1024**4)) ;;
        p|pi|pib)   mult=$((1024**5)) ;;

        # SI decimal units (1000ⁿ)
        kb)         mult=1000 ;;
        mb)         mult=$((1000**2)) ;;
        gb)         mult=$((1000**3)) ;;
        tb)         mult=$((1000**4)) ;;
        pb)         mult=$((1000**5)) ;;

        *)          printf "Invalid size suffix: %s\n" "$suffix_part" >&2; exit 1 ;;
    esac

    # Calculate and print result
    "$AWK" "BEGIN {printf \"%.0f\", $num_part * $mult}"
}

# Manual option parsing
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--size|-c|--chunk|--chunks|--chunk-size)
            [[ $# -lt 2 ]] && usage
            CHUNK_SIZE_RAW="$2"
            CHUNK_SIZE=$(parse_size "$CHUNK_SIZE_RAW")
            shift 2
            ;;
        -q|--quiet)
            VERBOSE=0
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            usage
            ;;
        --)
            shift
            break
            ;;
        -*)
            printf "Unknown option: %s\n" "$1" >&2
            usage
            ;;
        *)
            break
            ;;
    esac
done

[[ $# -ne 1 ]] && usage
INPUT_FILE="$1"

# Validation
if [ ! -r "$INPUT_FILE" ]; then
    printf "Input file '%s' does not exist or is not readable.\n" "$INPUT_FILE" | "$FOLD" -s -w "$COLS" >&2
    exit 1
fi

# Dry-run simulation
if [ "$DRY_RUN" -eq 1 ]; then
    TOTAL_LINES=$("$WC" -l < "$INPUT_FILE" | "$AWK" '{print $1}')
    TOTAL_CHARS=$("$WC" -m < "$INPUT_FILE" | "$AWK" '{print $1}')
    
    # Simulate chunking
    current_chars=0 chunk_count=0 line_count=0
    while IFS= read -r line || [ -n "$line" ]; do
        line_count=$((line_count + 1))
        line_chars=$((${#line} + 1))
        if (( current_chars + line_chars > CHUNK_SIZE )); then
            chunk_count=$((chunk_count + 1))
            current_chars=$line_chars
        else
            current_chars=$((current_chars + line_chars))
        fi
    done < "$INPUT_FILE"
    (( current_chars > 0 )) && chunk_count=$((chunk_count + 1))

    # Grammar handling
    chunk_grammar=$([ "$chunk_count" -eq 1 ] && echo "" || echo "s")
    size_grammar=$([ "$CHUNK_SIZE" -eq 1 ] && echo "" || echo "s")
    line_grammar=$([ "$TOTAL_LINES" -eq 1 ] && echo "" || echo "s")

    printf "${YELLOW}[DRY RUN]${RESET} Would split into ${CYAN}%d${NBSP}chunk%s${RESET} (≤%d character%s)\n" \
        "$chunk_count" "$chunk_grammar" "$CHUNK_SIZE" "$size_grammar" | "$FOLD" -s -w "$COLS"
    
    printf "  ${CYAN}Total lines:${RESET}    %9d${NBSP}line%s\n" "$TOTAL_LINES" "$line_grammar"
    printf "  ${CYAN}Total chars:${RESET}    %9d\n" "$TOTAL_CHARS"
    printf "  ${CYAN}Chunk size:${RESET}     %9d${NBSP}char%s\n" "$CHUNK_SIZE" "$size_grammar"
    printf "  ${CYAN}Total chunks:${RESET}   %9d\n" "$chunk_count"
    exit 4
fi

# Temporary resources
SNAPSHOT_FILE=$("$MKTEMP" "/tmp/${INPUT_FILE##*/}.snapshot.XXXXXX")
CHUNKS_DIR=$("$MKTEMP" -d "/tmp/${INPUT_FILE##*/}.chunks.XXXXXX")
LINE_RANGES="$CHUNKS_DIR/line_ranges"

cleanup() {
    printf "\nCleaning temporary files...\n" >&2
    "$RM" -rf "$SNAPSHOT_FILE" "$CHUNKS_DIR"
}
trap cleanup EXIT INT TERM

# Create snapshot and chunk tracking
"$CP" -- "$INPUT_FILE" "$SNAPSHOT_FILE"
> "$LINE_RANGES"

# Character-based chunking with line tracking
{
    current_chars=0 chunk_num=1 start_line=1 line_num=0
    current_lines=()
    
    while IFS= read -r line || [ -n "$line" ]; do
        line_num=$((line_num + 1))
        line_chars=$((${#line} + 1))  # Include newline
        
        if (( current_chars + line_chars > CHUNK_SIZE )); then
            if (( ${#current_lines[@]} == 0 )); then
                # Single-line chunk exceeding size
                printf "%s\n" "$line" > "$CHUNKS_DIR/chunk_$chunk_num"
                printf "%s %s\n" "$start_line" "$line_num" >> "$LINE_RANGES"
                chunk_num=$((chunk_num + 1))
                start_line=$((line_num + 1))
                current_chars=0
                current_lines=()
            else
                # Write accumulated chunk
                printf "%s\n" "${current_lines[@]}" > "$CHUNKS_DIR/chunk_$chunk_num"
                printf "%s %s\n" "$start_line" "$((line_num - 1))" >> "$LINE_RANGES"
                chunk_num=$((chunk_num + 1))
                current_lines=("$line")
                current_chars=$line_chars
                start_line=$line_num
            fi
        else
            current_lines+=("$line")
            current_chars=$((current_chars + line_chars))
        fi
    done
    
    # Final chunk
    if (( ${#current_lines[@]} > 0 )); then
        printf "%s\n" "${current_lines[@]}" > "$CHUNKS_DIR/chunk_$chunk_num"
        printf "%s %s\n" "$start_line" "$line_num" >> "$LINE_RANGES"
    fi
} < "$SNAPSHOT_FILE"

# Process chunks
TOTAL_CHUNKS=$("$FIND" "$CHUNKS_DIR" -name 'chunk_*' | "$WC" -l | "$AWK" '{print $1}')
TOTAL_LINES=$("$WC" -l < "$SNAPSHOT_FILE" | "$AWK" '{print $1}')
CHUNK_INDEX=1

# Header message
if [ "$VERBOSE" -eq 1 ]; then
    size_grammar=$([ "$CHUNK_SIZE" -eq 1 ] && echo "" || echo "s")
    printf "\n${CYAN}== Processing %s ==${RESET}\n" "$INPUT_FILE" | "$FOLD" -s -w "$COLS"
    printf "Chunk size: ${CYAN}%d${NBSP}character%s${RESET}\n" "$CHUNK_SIZE" "$size_grammar"
    printf "Total size: ${CYAN}%d${NBSP}characters${RESET}\n" "$(wc -m < "$SNAPSHOT_FILE")"
    printf "${CYAN}====================${RESET}\n\n"
fi

while read -r start end; do
    chunk_file="$CHUNKS_DIR/chunk_$CHUNK_INDEX"
    chars_in_chunk=$("$WC" -m < "$chunk_file" | "$AWK" '{print $1}')
    percent=$((100 * CHUNK_INDEX / TOTAL_CHUNKS))

    # Do not quote $CLIPBOARD_COPY so it splits into command and args.
    # shellcheck disable=SC2086
    $CLIPBOARD_COPY < "$chunk_file"

    if [ "$VERBOSE" -eq 1 ]; then
        printf "Chunk %d of${NBSP}%d (${CYAN}%.0f%%${RESET}): " "$CHUNK_INDEX" "$TOTAL_CHUNKS" "$percent"
        if [ "$start" -eq "$end" ]; then
            printf "Line ${CYAN}%d${RESET} of${NBSP}%d, " "$start" "$TOTAL_LINES"
        else
            printf "Lines ${CYAN}%d-%d${RESET} of${NBSP}%d, " "$start" "$end" "$TOTAL_LINES"
        fi
        printf "${CYAN}%d${RESET} characters copied to clipboard.\n" "$chars_in_chunk" | "$FOLD" -s -w "$COLS"
    else
        printf "Chunk %d of${NBSP}%d copied to clipboard.\n" "$CHUNK_INDEX" "$TOTAL_CHUNKS"
    fi

    if (( CHUNK_INDEX < TOTAL_CHUNKS )); then
        printf "Press Enter for the next chunk or Ctrl+C to exit.\n" >&2
        read -r </dev/tty
    fi

    CHUNK_INDEX=$((CHUNK_INDEX + 1))
done < "$LINE_RANGES"

printf "No more lines to process. Clipboard contains the last chunk.\n"
