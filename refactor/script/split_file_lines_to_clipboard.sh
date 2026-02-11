#!/bin/ksh
#
# file_chunks_to_clipboard.sh
# (alternative name: split_file_to_clipboard.sh)
# Split a file into N-line chunks and sequentially copy each chunk to the clipboard.
# Usage: split_file_to_clipboard.sh [--size N|-s N] [--quiet|-q] [--dry-run|-n] <filename>

set -euo pipefail

# Default values
CHUNK_SIZE=400
VERBOSE=1
DRY_RUN=0

# Non-breaking space
NBSP=$(printf "\u00a0")

# Columns for the current terminal
COLS=$(/usr/bin/tput cols)

usage() {
    printf "Usage: %s [--size N|-s N] [--quiet|-q] [--dry-run|-n] <filename>\n" "$1" >&2
    exit 1
}

# Manual option parsing
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--size|-c|--chunk|--chunk-size)
            [[ $# -lt 2 ]] && usage
            CHUNK_SIZE="$2"
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
        --help|-h)
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

# Check for required filename argument
if [[ $# -ne 1 ]]; then
    usage
fi
INPUT_FILE="$1"

# Validate input file early
if [ ! -r "$INPUT_FILE" ]; then
    printf "Input file '%s' does not exist or is not readable.\n" "$INPUT_FILE" | /usr/bin/fold -s -w "$COLS" >&2
    exit 1
fi

if [ "$DRY_RUN" -eq 1 ]; then
    TOTAL_LINES_DRY_RUN=$(/usr/bin/wc -l < "$INPUT_FILE" | /usr/bin/awk '{print $1}')
    if [ "$TOTAL_LINES_DRY_RUN" -eq 0 ]; then
        printf "[DRY RUN] The input file is empty. Nothing to process.\n"
        exit 0
    fi

    # Use ceiling division to account for all lines, including partial chunks.
    TOTAL_CHUNKS_DRY_RUN=$(( (TOTAL_LINES_DRY_RUN + CHUNK_SIZE - 1) / CHUNK_SIZE ))

    case "$CHUNK_SIZE" in
        1) CHUNK_SIZE_GRAMMAR="";;
        *) CHUNK_SIZE_GRAMMAR="s";;
    esac
    case "$TOTAL_CHUNKS_DRY_RUN" in
        1)
            printf "\033[33m[DRY RUN]\033[0m Would split the file into \033[36m%u${NBSP}chunk\033[0m, and copy the chunk to the clipboard.\n" \
            "$TOTAL_CHUNKS_DRY_RUN" |
            /usr/bin/fold -s -w "$COLS"
            ;;
        *)
            TOTAL_CHUNKS_DRY_RUN_GRAMMAR="s"
            printf "\033[33m[DRY RUN]\033[0m Would split the file into \033[36m%u${NBSP}chunk${TOTAL_CHUNKS_DRY_RUN_GRAMMAR}\033[0m, and sequentially copy each chunk to the clipboard.\n" \
            "$TOTAL_CHUNKS_DRY_RUN" |
            /usr/bin/fold -s -w "$COLS"
            ;;
    esac

    printf "%2sTotal lines:  %u\n" "" $TOTAL_LINES_DRY_RUN >&2
    printf "%2sChunk size:   %u${NBSP}line${CHUNK_SIZE_GRAMMAR}\n" "" $CHUNK_SIZE >&2
    printf "%2sTotal chunks: %u\n" "" $TOTAL_CHUNKS_DRY_RUN >&2
    # printf "%2s\033[33mTotal chunks: %u\033[0m\n" "" $TOTAL_CHUNKS_DRY_RUN >&2 # yellow
    # printf "%2s\033[36mTotal chunks: %u\033[0m\n" "" $TOTAL_CHUNKS_DRY_RUN >&2 # cyan
    exit 4
fi

SNAPSHOT_FILE=$(/usr/bin/mktemp "/tmp/${INPUT_FILE##*/}.snapshot.XXXXXX")
CHUNKS_DIR=$(/usr/bin/mktemp -d "/tmp/${INPUT_FILE##*/}.chunks.XXXXXX")

cleanup() {
    printf "\nCleaning up temporary files and exiting...\n" >&2
    /bin/rm -f "$SNAPSHOT_FILE"
    /bin/rm -rf "$CHUNKS_DIR"
}
trap cleanup EXIT INT TERM

# Create a snapshot
/bin/cp -- "$INPUT_FILE" "$SNAPSHOT_FILE"

# Split into chunks
/usr/bin/split -l "$CHUNK_SIZE" -- "$SNAPSHOT_FILE" "$CHUNKS_DIR/chunk_"

TOTAL_LINES=$(/usr/bin/wc -l < "$SNAPSHOT_FILE" | /usr/bin/awk '{print $1}')
# Handle empty files
if [ "$TOTAL_LINES" -eq 0 ]; then
    printf "The input file is empty. Nothing to process.\n" >&2
    exit 0
fi

TOTAL_CHUNKS=$(/usr/bin/find "$CHUNKS_DIR" -type f | /usr/bin/wc -l | /usr/bin/awk '{print $1}')
CHUNK_INDEX=1
CURRENT_LINE=1

for CHUNK in "$CHUNKS_DIR"/chunk_*; do
    LINES_IN_CHUNK=$(/usr/bin/wc -l < "$CHUNK" | /usr/bin/awk '{print $1}')
    END_LINE=$((CURRENT_LINE + LINES_IN_CHUNK - 1))
    PERCENT=$(( 100 * CHUNK_INDEX / TOTAL_CHUNKS ))
    /usr/bin/pbcopy < "$CHUNK"
    if [ "$VERBOSE" -eq 1 ]; then
        printf "Chunk %d of${NBSP}%d (%.0f%%): Lines %d-%d of${NBSP}%d copied to clipboard.\n" \
            "$CHUNK_INDEX" "$TOTAL_CHUNKS" "$PERCENT" "$CURRENT_LINE" "$END_LINE" "$TOTAL_LINES" |
            /usr/bin/fold -s -w "$COLS"
    else
        printf "Chunk %d of${NBSP}%d copied to clipboard.\n" "$CHUNK_INDEX" "$TOTAL_CHUNKS"
    fi
    if [ "$END_LINE" -ge "$TOTAL_LINES" ]; then
        printf "No more lines to process. Clipboard contains the last chunk.\n"
        break
    fi
    printf "Press Enter for the next chunk or Ctrl+C to exit.\n"
    read -r
    CURRENT_LINE=$((END_LINE + 1))
    CHUNK_INDEX=$((CHUNK_INDEX + 1))
done
