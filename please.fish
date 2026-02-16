function please --description 'Generate and optionally run a shell command via Codex'
    set -l opts \
        h/help \
        'm/model=' \
        n/dry-run
    argparse --name=please $opts -- $argv
    or return 2

    if set -q _flag_help
        printf "%s\n" \
            "Usage: please [OPTIONS] <request...>" \
            "Generate one shell command with Codex, show a short why, then ask before running." \
            "" \
            "Options:" \
            "  -m, --model MODEL  Codex model to use (optional)" \
            "  -n, --dry-run      Only show the generated command and explanation" \
            "  -h, --help         Show this help" \
            "" \
            "Examples:" \
            "  please find all .log files bigger than 50MB" \
            "  please --dry-run show disk usage by top 10 folders"
        return 0
    end

    if not command -sq codex
        echo "please: missing dependency: codex" >&2
        return 127
    end

    if test (count $argv) -eq 0
        echo "please: missing request (see --help)" >&2
        return 2
    end

    set -l user_request (string join ' ' -- $argv)
    set -l codex_prompt (string join "\n" \
        "Generate exactly one fish-compatible shell command for this request." \
        "Return exactly two lines and nothing else:" \
        "COMMAND: <single shell command>" \
        "WHY: <brief explanation, max 120 chars>" \
        "Do not include code fences, numbering, or extra text." \
        "Request: $user_request")

    set -l output_file (mktemp -t please.codex.out.XXXXXX)
    or begin
        echo "please: failed to create temporary output file" >&2
        return 1
    end

    set -l err_file (mktemp -t please.codex.err.XXXXXX)
    or begin
        command rm -f "$output_file"
        echo "please: failed to create temporary error file" >&2
        return 1
    end

    set -l codex_args exec --skip-git-repo-check --color never -o "$output_file"
    if set -q _flag_model
        set -a codex_args --model "$_flag_model"
    end

    codex $codex_args -- "$codex_prompt" >/dev/null 2>"$err_file"
    set -l codex_status $status

    if test $codex_status -ne 0
        echo "please: codex failed" >&2
        if test -s "$err_file"
            cat "$err_file" >&2
        end
        command rm -f "$output_file" "$err_file"
        return 1
    end

    set -l response (string trim -- (cat "$output_file"))
    command rm -f "$output_file" "$err_file"

    set -l command_line
    set -l why_line
    for line in (string split "\n" -- $response)
        if string match -q 'COMMAND:*' -- "$line"
            set command_line (string trim -- (string replace -r '^COMMAND:[[:space:]]*' '' -- "$line"))
        else if string match -q 'WHY:*' -- "$line"
            set why_line (string trim -- (string replace -r '^WHY:[[:space:]]*' '' -- "$line"))
        end
    end

    if test -z "$command_line" -o -z "$why_line"
        echo "please: unexpected codex response format" >&2
        printf "%s\n" "$response" >&2
        return 1
    end

    printf "%s\n" "Command: $command_line"
    printf "%s\n" "Why: $why_line"

    if set -q _flag_dry_run
        return 0
    end

    read --local --prompt-str "Run this command? [y/N] " confirm
    switch (string lower -- "$confirm")
        case y yes
            eval "$command_line"
            return $status
        case '*'
            printf "%s\n" "Skipped."
            return 0
    end
end
