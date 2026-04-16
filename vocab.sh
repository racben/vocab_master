#!/bin/bash

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

    # 1. We keep native ripgrep colors, but disable color on the path and line numbers
    # to ensure fzf can split the columns cleanly.
    matches=$(rg --color=always --colors 'path:none' --colors 'line:none' -F -n -H --no-heading "${rg_args[@]}" "$CORPUS_DIR")

    if [[ -z "$matches" ]]; then
        echo "Skipping '[$word]' — no matches found in corpus."
        continue
    fi

    # 2. In the preview window, we just 'echo' the variables directly to the screen. 
    # {} is the raw ripgrep output line. We use 'cut' to strip the filename and line number,
    # leaving just the highlighted paragraph to wrap natively in the window.
    selected=$(echo "$matches" | fzf --prompt="Select sentence for [$word] > " \
        --ansi \
        --delimiter ':' \
        --with-nth '3..' \
        --height=80% \
        --layout=reverse \
        --preview='echo -e "\033[1;33mFile:\033[0m {1}\n"; echo {} | cut -d: -f3-' \
        --preview-window="right:60%:wrap")

    if [[ -n "$selected" ]]; then
        sentence=$(echo "$selected" | cut -d':' -f3- | sed 's/\x1b\[[0-9;]*m//g')
        echo -e "${word}\t${sentence}" >> "$OUTPUT_FILE"
    else
        echo "Skipped '[$word]' — user aborted."
    fi

done < "$INPUT_FILE"

echo "Finished! Results saved to $OUTPUT_FILE"
