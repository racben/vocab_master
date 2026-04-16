#!/bin/bash

# ==============================================================================
# PREVIEW HELPER (Called recursively by fzf)
# ==============================================================================
if [[ "$1" == "--preview-helper" ]]; then
    raw_file="$2"
    line_num="$3"
    
    # Safely strip any invisible ANSI codes
    clean_file=$(printf '%s' "$raw_file" | sed 's/\x1b\[[0-9;]*m//g')
    
    # Print exactly ONE clean header line. This is what we will pin.
    printf "\033[1;33mFile:\033[0m %s\n" "$clean_file"
    
    # Run bat without its native header (just line numbers), or fallback to cat
    if command -v bat >/dev/null 2>&1; then
        bat --color=always --style=numbers --highlight-line "$line_num" "$clean_file" 2>/dev/null
    else
        cat "$clean_file" 2>/dev/null
    fi
    exit 0
fi

# ==============================================================================
# MAIN SCRIPT
# ==============================================================================
CORPUS_DIR="/Users/ben/Documents/Chinese Text Analysis"
INPUT_FILE="$1"
OUTPUT_FILE="results.tsv"

if [[ -z "$INPUT_FILE" ]]; then
    echo "Usage: ./vocab_fzf.sh <vocab_list.txt>"
    exit 1
fi

> "$OUTPUT_FILE"

while IFS= read -r word || [[ -n "$word" ]]; do
    word="${word//[$'\t\r\n ']/}"
    [[ -z "$word" ]] && continue

    s=$(printf '%s' "$word" | opencc -c t2s.json 2>/dev/null || printf '%s' "$word")
    t=$(printf '%s' "$word" | opencc -c s2t.json 2>/dev/null || printf '%s' "$word")

    if [[ "$s" == "$t" ]]; then
        rg_args=(-e "$s")
    else
        rg_args=(-e "$s" -e "$t")
    fi

    # Run ripgrep with native color highlighting, keeping path and line uncolored
    matches=$(rg --color=always --colors 'path:none' --colors 'line:none' -F -n -H --no-heading "${rg_args[@]}" "$CORPUS_DIR")

    if [[ -z "$matches" ]]; then
        echo "Skipping '[$word]' — no matches found in corpus."
        continue
    fi

    selected=$(echo "$matches" | fzf --prompt="Select sentence for [$word] > " \
        --ansi \
        --delimiter ':' \
        --with-nth '3..' \
        --height=80% \
        --layout=reverse \
        --preview="\"$0\" --preview-helper {1} {2}" \
        --preview-window="right:60%:+{2}-/2:~1:wrap")

    if [[ -n "$selected" ]]; then
        sentence=$(echo "$selected" | cut -d':' -f3- | sed 's/\x1b\[[0-9;]*m//g')
        echo -e "${word}\t${sentence}" >> "$OUTPUT_FILE"
    else
        echo "Skipped '[$word]' — user aborted."
    fi

done < "$INPUT_FILE"

echo "Finished! Results saved to $OUTPUT_FILE"
