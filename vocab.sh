#!/bin/bash

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
    echo "Usage: ./vocab_fzf.sh [-d|--deep] <vocab_list.txt>"
    exit 1
fi

OUTPUT_FILE="results.tsv"
> "$OUTPUT_FILE"

# Verify fallbacks exist so ripgrep doesn't throw errors
valid_fallbacks=()
for dir in "${FALLBACK_DIRS[@]}"; do
    [[ -d "$dir" ]] && valid_fallbacks+=("$dir")
done

while IFS= read -r word || [[ -n "$word" ]]; do
    word="${word//[$'\t\r\n ']/}"
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
    base_rg=(rg --color=always --colors 'path:none' --colors 'line:none' -F -n -H --no-heading --glob '!**/old/**' --glob '!**/current/**' "${rg_args[@]}")

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
        --expect=ctrl-c \
        --preview="\"$0\" --preview-helper {1} {2} \"$s\" \"$t\"" \
        --preview-window="right:60%:+{2}-/2:~1:wrap")

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
        sentence=$(echo "$selected" | cut -d':' -f3- | sed 's/\x1b\[[0-9;]*m//g')
        echo -e "${word}\t${sentence}" >> "$OUTPUT_FILE"
    fi

done < "$INPUT_FILE"

echo "Finished! Results saved to $OUTPUT_FILE"
