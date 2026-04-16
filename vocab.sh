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

    # 1. Added -H and --no-heading to guarantee file:line:text format
    # 2. Added --colors flags to keep the match red, but strip color from the path/line
    matches=$(rg --color=always --colors 'path:none' --colors 'line:none' -H --no-heading -F -n "${rg_args[@]}" "$CORPUS_DIR")

    if [[ -z "$matches" ]]; then
        echo "Skipping '[$word]' — no matches found in corpus."
        continue
    fi

    # The fzf command remains the same, but now {1} and {2} are guaranteed 
    # to be plain text and correctly mapped!
    selected=$(echo "$matches" | fzf --prompt="Select sentence for [$word] > " \
        --ansi \
        --delimiter ':' \
        --with-nth '3..' \
        --height=80% \
        --layout=reverse \
        --preview='bat --color=always --style=header,numbers --highlight-line {2} "{1}" 2>/dev/null || { echo "File: {1}"; cat "{1}"; }' \
        --preview-window="right:60%:+{2}-/2:wrap")

    if [[ -n "$selected" ]]; then
        sentence=$(echo "$selected" | cut -d':' -f3- | sed 's/\x1b\[[0-9;]*m//g')
        echo -e "${word}\t${sentence}" >> "$OUTPUT_FILE"
    else
        echo "Skipped '[$word]' — user aborted."
    fi

done < "$INPUT_FILE"

echo "Finished! Results saved to $OUTPUT_FILE"
