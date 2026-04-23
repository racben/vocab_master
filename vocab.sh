#!/bin/bash

# sentence-parsing logic (to capture better than whole line)
extract_sentence_context() {
    local line="$1"
    local needle1="$2"
    local needle2="$3"

    python3 - "$line" "$needle1" "$needle2" <<'PY'
import re
import sys

line = sys.argv[1]
needle1 = sys.argv[2]
needle2 = sys.argv[3]

text = line.strip()
if not text:
    print("")
    sys.exit(0)

# Split on common Chinese sentence-ending punctuation, keeping punctuation attached.
parts = re.split(r'(?<=[。！？!?；;])', text)
parts = [p.strip() for p in parts if p.strip()]

def contains_target(s):
    return needle1 in s or needle2 in s

hits = [s for s in parts if contains_target(s)]

if hits:
    print(''.join(hits).strip())
else:
    print(text)
PY
}

# ==============================================================================
# PREVIEW HELPER (Called recursively by fzf)
# ==============================================================================
if [[ "$1" == "--preview-helper" ]]; then
    raw_file="$2"
    line_num="$3"
    s="$4"
    t="$5"
    
    clean_file=$(printf '%s' "$raw_file" | sed 's/\x1b\[[0-9;]*m//g')
    
    printf "\033[1;33mFile:\033[0m %s\n" "$clean_file"
    
    if [[ "$s" == "$t" ]]; then
        rg_args=(-e "$s")
    else
        rg_args=(-e "$s" -e "$t")
    fi
    
    if command -v bat >/dev/null 2>&1; then
        bat --color=always --style=numbers --highlight-line "$line_num" "$clean_file" 2>/dev/null | \
            rg --passthru --color=always -F "${rg_args[@]}"
    else
        cat "$clean_file" 2>/dev/null | \
            rg --passthru --color=always -F "${rg_args[@]}"
    fi
    exit 0
fi

# ==============================================================================
# MAIN SCRIPT
# ==============================================================================
MAIN_CORPUS="$HOME/Chinese Text Analysis"
# Using $HOME ensures tilde expansion works perfectly in bash scripts
FALLBACK_DIRS=("$HOME/src/TurnBasedGameData" "$HOME/src/AnimeGameData")

DEEP_SEARCH=0
INPUT_FILE=""

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -d|--deep) DEEP_SEARCH=1; shift ;;
        *) INPUT_FILE="$1"; shift ;;
    esac
done

if [[ -z "$INPUT_FILE" ]]; then
    if [ -t 0 ]; then
        echo "Usage: ./vocab_fzf.sh [-d|--deep] <vocab_list.txt>  OR  pipe input via stdin"
        exit 1
    fi
    INPUT_SOURCE="/dev/stdin"
else
    INPUT_SOURCE="$INPUT_FILE"
fi

SOURCE="${BASH_SOURCE[0]}"

while [ -L "$SOURCE" ]; do
    SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ "$SOURCE" != /* ]] && SOURCE="$SCRIPT_DIR/$SOURCE"
done

SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

OUTPUT_DIR="$SCRIPT_DIR/results"
mkdir -p "$OUTPUT_DIR"

timestamp=$(date +"%Y%m%d-%H%M%S")
OUTPUT_FILE="$OUTPUT_DIR/results-${timestamp}-$$.tsv"

# Verify fallbacks exist so ripgrep doesn't throw errors
valid_fallbacks=()
for dir in "${FALLBACK_DIRS[@]}"; do
    [[ -d "$dir" ]] && valid_fallbacks+=("$dir")
done

while IFS= read -r word || [[ -n "$word" ]]; do
    word=$(printf '%s\n' "$word" | awk '{print $1}')
    [[ -z "$word" ]] && continue
    [[ "$word" == \#* ]] && continue

    s=$(printf '%s' "$word" | opencc -c t2s.json 2>/dev/null || printf '%s' "$word")
    t=$(printf '%s' "$word" | opencc -c s2t.json 2>/dev/null || printf '%s' "$word")

    if [[ "$s" == "$t" ]]; then
        rg_args=(-e "$s")
    else
        rg_args=(-e "$s" -e "$t")
    fi

    # Store the base ripgrep command in an array for easy reuse
    base_rg=(rg --color=always --colors 'path:none' --colors 'line:none' -F -n -H --no-heading --glob '!**/old/**' --glob '!**/current/**' --sort=modified "${rg_args[@]}")

    if [[ $DEEP_SEARCH -eq 1 ]]; then
        # Search everything simultaneously if --deep flag is passed
        matches=$("${base_rg[@]}" "$MAIN_CORPUS" "${valid_fallbacks[@]}")
    else
        # Normal search
        matches=$("${base_rg[@]}" "$MAIN_CORPUS")
        
        # Fallback triggered only if matches is empty
        if [[ -z "$matches" && ${#valid_fallbacks[@]} -gt 0 ]]; then
            matches=$("${base_rg[@]}" "${valid_fallbacks[@]}")
        fi
    fi

    if [[ -z "$matches" ]]; then
        echo "Skipping '[$word]' — no matches found in any corpus."
        continue
    fi

    raw_selected=$(echo "$matches" | fzf --prompt="Select sentence for [$word] > " \
        --ansi \
        --delimiter ':' \
        --with-nth '3..' \
        --height=80% \
        --layout=reverse \
        --expect=ctrl-c,alt-enter \
        --preview="\"$0\" --preview-helper {1} {2} \"$s\" \"$t\"" \
        --preview-window="up:60%:+{2}-/2:~1:wrap")

    if [[ -z "$raw_selected" ]]; then
        echo "Skipped '[$word]' — user aborted selection."
        continue
    fi

    key=$(head -n 1 <<< "$raw_selected")
    selected=$(tail -n +2 <<< "$raw_selected")

    if [[ "$key" == "ctrl-c" ]]; then
        echo -e "\nScript aborted by user. Progress so far is saved."
        break
    fi

    if [[ -n "$selected" ]]; then
        line_text=$(echo "$selected" | cut -d':' -f3- | sed 's/\x1b\[[0-9;]*m//g')

        if [[ "$key" == "alt-enter" ]]; then
            sentence=$(extract_sentence_context "$line_text" "$s" "$t")
        else
            sentence="$line_text"
        fi

        echo -e "${word}\t${sentence}" >> "$OUTPUT_FILE"
    fi

done < "$INPUT_SOURCE"

echo "Finished! Results saved to $OUTPUT_FILE"

cat $OUTPUT_FILE
