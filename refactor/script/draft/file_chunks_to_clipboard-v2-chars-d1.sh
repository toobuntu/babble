#!/bin/ksh
#
# split_file_to_clipboard.sh
# Split a file into character-based chunks while preserving line boundaries
# Usage: split_file_to_clipboard.sh [--size N|-s N] [--quiet|-q] [--dry-run|-n] <filename>

set -euo pipefail

# Default values (10,240 characters = 10KB)
CHUNK_SIZE=10240
VERBOSE=1
DRY_RUN=0

# Formatting constants
NBSP=$(printf "\u00a0")
COLS=$(/usr/bin/tput cols)
YELLOW='\033[33m'
CYAN='\033[36m'
RESET='\033[0m'

usage() {
    printf "Usage: %s [--size N|-s N] [--quiet|-q] [--dry-run|-n] <filename>\n" "$1" >&2
    exit 1
}

# Option parsing
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--size) CHUNK_SIZE="$2"; shift 2 ;;
        -q|--quiet) VERBOSE=0; shift ;;
        -n|--dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage ;;
        --) shift; break ;;
        -*) printf "Unknown option: %s\n" "$1" >&2; usage ;;
        *) break ;;
    esac
done

[[ $# -ne 1 ]] && usage
INPUT_FILE="$1"

# Validation
if [ ! -r "$INPUT_FILE" ]; then
    printf "Input file '%s' does not exist or is not readable.\n" "$INPUT_FILE" | fold -s -w "$COLS" >&2
    exit 1
fi

# Dry-run simulation
if [ "$DRY_RUN" -eq 1 ]; then
    TOTAL_LINES=$(wc -l < "$INPUT_FILE" | awk '{print $1}')
    TOTAL_CHARS=$(wc -m < "$INPUT_FILE" | awk '{print $1}')

    # Simulate chunking
    current_chars=0 chunk_count=0 line_count=0
    while IFS= read -r line; do
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
        "$chunk_count" "$chunk_grammar" "$CHUNK_SIZE" "$size_grammar" | fold -s -w "$COLS"

    printf "  ${CYAN}Total lines:${RESET}    %9d${NBSP}line%s\n" "$TOTAL_LINES" "$line_grammar"
    printf "  ${CYAN}Total chars:${RESET}    %9d\n" "$TOTAL_CHARS"
    printf "  ${CYAN}Chunk size:${RESET}     %9d${NBSP}char%s\n" "$CHUNK_SIZE" "$size_grammar"
    printf "  ${CYAN}Total chunks:${RESET}   %9d\n" "$chunk_count"
    exit 4
fi

# Temporary resources
SNAPSHOT_FILE=$(mktemp "/tmp/${INPUT_FILE##*/}.snapshot.XXXXXX")
CHUNKS_DIR=$(mktemp -d "/tmp/${INPUT_FILE##*/}.chunks.XXXXXX")
LINE_RANGES="$CHUNKS_DIR/line_ranges"

cleanup() {
    printf "\nCleaning temporary files...\n" >&2
    rm -rf "$SNAPSHOT_FILE" "$CHUNKS_DIR"
}
trap cleanup EXIT INT TERM

# Create snapshot and chunk tracking
cp -- "$INPUT_FILE" "$SNAPSHOT_FILE"
> "$LINE_RANGES"

# Character-based chunking with line tracking
{
    current_chars=0 chunk_num=1 start_line=1 line_num=0
    current_lines=()

    while IFS= read -r line; do
        line_num=$((line_num + 1))
        line_chars=$((${#line} + 1))  # Include newline

        if (( current_chars + line_chars > CHUNK_SIZE )); then
            if (( ${#current_lines[@]} == 0 )); then
                # Single-line chunk exceeding size
                printf "%s\n" "$line" > "$CHUNKS_DIR/chunk_$chunk_num"
                echo "$start_line $line_num" >> "$LINE_RANGES"
                chunk_num=$((chunk_num + 1))
                start_line=$((line_num + 1))
            else
                # Write accumulated chunk
                printf "%s\n" "${current_lines[@]}" > "$CHUNKS_DIR/chunk_$chunk_num"
                echo "$start_line $((line_num - 1))" >> "$LINE_RANGES"
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
        echo "$start_line $line_num" >> "$LINE_RANGES"
    fi
} < "$SNAPSHOT_FILE"

# Process chunks
TOTAL_CHUNKS=$(find "$CHUNKS_DIR" -name 'chunk_*' | wc -l | awk '{print $1}')
TOTAL_LINES=$(wc -l < "$SNAPSHOT_FILE" | awk '{print $1}')
CHUNK_INDEX=1

while read -r start end; do
    chunk_file="$CHUNKS_DIR/chunk_$CHUNK_INDEX"
    chars_in_chunk=$(wc -m < "$chunk_file" | awk '{print $1}')
    percent=$((100 * CHUNK_INDEX / TOTAL_CHUNKS))

    /usr/bin/pbcopy < "$chunk_file"

    if [ "$VERBOSE" -eq 1 ]; then
        printf "Chunk %d/${NBSP}%d (${CYAN}%.0f%%${RESET}): " "$CHUNK_INDEX" "$TOTAL_CHUNKS" "$percent"
        if [ "$start" -eq "$end" ]; then
            printf "Line ${CYAN}%d${RESET} of${NBSP}%d, " "$start" "$TOTAL_LINES"
        else
            printf "Lines ${CYAN}%d-%d${RESET} of${NBSP}%d, " "$start" "$end" "$TOTAL_LINES"
        fi
        printf "${CYAN}%d${RESET} characters\n" "$chars_in_chunk" | fold -s -w "$COLS"
    else
        printf "Chunk %d/${NBSP}%d copied\n" "$CHUNK_INDEX" "$TOTAL_CHUNKS"
    fi

    if (( CHUNK_INDEX < TOTAL_CHUNKS )); then
        printf "Press Enter for next chunk or Ctrl+C to exit..."
        read -r
    fi

    CHUNK_INDEX=$((CHUNK_INDEX + 1))
done < "$LINE_RANGES"

printf "Clipboard contains final chunk.${NBSP}Processing complete.\n"
