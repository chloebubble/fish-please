function please --description 'Generate and optionally run a shell command via Codex'
    set -l opts \
        h/help \
        'm/model=' \
        'reasoning-effort=' \
        defaults \
        n/dry-run
    argparse --name=please $opts -- $argv
    or return 2

    if set -q _flag_help
        printf "%s\n" \
            "Usage: please [OPTIONS] <request...>" \
            "Generate one shell command with Codex, show a short why, then ask before running (default: yes)." \
            "" \
            "Options:" \
            "  -m, --model MODEL           Codex model to use for this run" \
            "      --reasoning-effort LEVEL  Reasoning effort to use for this run" \
            "      --defaults              Manage defaults via subcommands" \
            "  -n, --dry-run               Only show the generated command and explanation" \
            "  -h, --help                  Show this help" \
            "" \
            "Defaults subcommands:" \
            "  please --defaults show [model|reasoning|all]" \
            "  please --defaults set model MODEL" \
            "  please --defaults set reasoning LEVEL" \
            "  please --defaults clear [model|reasoning|all]" \
            "" \
            "Examples:" \
            "  please find all .log files bigger than 50MB" \
            "  please --dry-run show disk usage by top 10 folders" \
            "  please --defaults set model gpt-5" \
            "  please --defaults set reasoning high" \
            "  please --defaults show all" \
            "" \
            "Run prompt choices: [Y/n/e=explain]"
        return 0
    end

    set -l default_model_var __please_default_model
    set -l default_reasoning_effort_var __please_default_reasoning_effort
    set -l codex_config_file "$HOME/.codex/config.toml"
    set -l codex_default_model unknown
    set -l codex_default_reasoning_effort unknown

    if test -r "$codex_config_file"
        set -l configured_model_line (string match -r '^model[[:space:]]*=.*$' -- (cat "$codex_config_file"))
        set -l configured_model (string trim -- (string replace -r '^[^"]*"([^"]+)".*$' '$1' -- "$configured_model_line"))
        if test -n "$configured_model"
            set codex_default_model "$configured_model"
        end

        set -l configured_reasoning_line (string match -r '^model_reasoning_effort[[:space:]]*=.*$' -- (cat "$codex_config_file"))
        set -l configured_reasoning (string trim -- (string replace -r '^[^"]*"([^"]+)".*$' '$1' -- "$configured_reasoning_line"))
        if test -n "$configured_reasoning"
            set codex_default_reasoning_effort "$configured_reasoning"
        end
    end

    if set -q _flag_defaults
        if set -q _flag_model; or set -q _flag_reasoning_effort; or set -q _flag_dry_run
            echo "please: --defaults cannot be combined with run options" >&2
            return 2
        end

        if test (count $argv) -eq 0
            echo "please: missing defaults subcommand (show/set/clear)" >&2
            return 2
        end

        set -l defaults_cmd (string lower -- "$argv[1]")
        set -l defaults_scope all
        set -l defaults_value

        switch $defaults_cmd
            case show clear
                if test (count $argv) -ge 2
                    set defaults_scope (string lower -- "$argv[2]")
                end
                if test (count $argv) -gt 2
                    echo "please: too many arguments for --defaults $defaults_cmd" >&2
                    return 2
                end
            case set
                if test (count $argv) -ne 3
                    echo "please: usage: please --defaults set [model|reasoning] VALUE" >&2
                    return 2
                end
                set defaults_scope (string lower -- "$argv[2]")
                set defaults_value (string trim -- "$argv[3]")
            case '*'
                echo "please: invalid defaults subcommand: $defaults_cmd" >&2
                return 2
        end

        switch $defaults_scope
            case model reasoning reasoning-effort all
            case '*'
                echo "please: invalid defaults target: $defaults_scope" >&2
                return 2
        end

        switch $defaults_cmd
            case show
                set -l label_width 12
                if test "$defaults_scope" = model -o "$defaults_scope" = all
                    if set -q $default_model_var
                        printf "%-*s%s\n" $label_width "Model:" "$$default_model_var"
                    else
                        printf "%-*s%s\n" $label_width "Model:" "Codex default ($codex_default_model)"
                    end
                end
                if test "$defaults_scope" = reasoning -o "$defaults_scope" = reasoning-effort -o "$defaults_scope" = all
                    if set -q $default_reasoning_effort_var
                        printf "%-*s%s\n" $label_width "Reasoning:" "$$default_reasoning_effort_var"
                    else
                        printf "%-*s%s\n" $label_width "Reasoning:" "Codex default ($codex_default_reasoning_effort)"
                    end
                end
                return 0
            case clear
                if test "$defaults_scope" = model -o "$defaults_scope" = all
                    set --erase --universal $default_model_var
                end
                if test "$defaults_scope" = reasoning -o "$defaults_scope" = reasoning-effort -o "$defaults_scope" = all
                    set --erase --universal $default_reasoning_effort_var
                end
                printf "%s\n" cleared
                return 0
            case set
                if test -z "$defaults_value"
                    echo "please: defaults set value cannot be empty" >&2
                    return 2
                end

                if test "$defaults_scope" = model
                    set --universal $default_model_var "$defaults_value"
                    printf "%-*s%s\n" 12 "Model:" "$defaults_value"
                    return 0
                end

                if test "$defaults_scope" = reasoning -o "$defaults_scope" = reasoning-effort
                    if not string match -qr '^(low|medium|high|xhigh)$' -- "$defaults_value"
                        echo "please: reasoning effort must be low, medium, high, or xhigh" >&2
                        return 2
                    end
                    set --universal $default_reasoning_effort_var "$defaults_value"
                    printf "%-*s%s\n" 12 "Reasoning:" "$defaults_value"
                    return 0
                end
        end
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
        "Execution shell is fish; this command will be run with fish eval." \
        "Use fish-specific builtins or syntax when they are the best fit." \
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
    else if set -q $default_model_var
        set -a codex_args --model "$$default_model_var"
    end
    if set -q _flag_reasoning_effort
        if not string match -qr '^(low|medium|high|xhigh)$' -- "$_flag_reasoning_effort"
            echo "please: --reasoning-effort must be low, medium, high, or xhigh" >&2
            return 2
        end
        set -a codex_args -c "model_reasoning_effort=$_flag_reasoning_effort"
    else if set -q $default_reasoning_effort_var
        set -a codex_args -c "model_reasoning_effort=$$default_reasoning_effort_var"
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

    # Validate generated command syntax before displaying/running it.
    if not fish --no-execute -c "$command_line" >/dev/null 2>/dev/null
        set -l repair_prompt (string join "\n" \
            "Fix this fish command so it is valid fish syntax and still satisfies the request." \
            "Return exactly two lines and nothing else:" \
            "COMMAND: <single shell command>" \
            "WHY: <brief explanation, max 120 chars>" \
            "Original request: $user_request" \
            "Broken command: $command_line")

        set -l repair_out_file (mktemp -t please.codex.repair.out.XXXXXX)
        or begin
            echo "please: generated command failed fish syntax validation" >&2
            return 1
        end
        set -l repair_err_file (mktemp -t please.codex.repair.err.XXXXXX)
        or begin
            command rm -f "$repair_out_file"
            echo "please: generated command failed fish syntax validation" >&2
            return 1
        end

        set -l repair_codex_args exec --skip-git-repo-check --color never -o "$repair_out_file"
        if set -q _flag_model
            set -a repair_codex_args --model "$_flag_model"
        else if set -q $default_model_var
            set -a repair_codex_args --model "$$default_model_var"
        end
        if set -q _flag_reasoning_effort
            set -a repair_codex_args -c "model_reasoning_effort=$_flag_reasoning_effort"
        else if set -q $default_reasoning_effort_var
            set -a repair_codex_args -c "model_reasoning_effort=$$default_reasoning_effort_var"
        end

        codex $repair_codex_args -- "$repair_prompt" >/dev/null 2>"$repair_err_file"
        set -l repair_status $status
        if test $repair_status -ne 0
            echo "please: generated command failed fish syntax validation" >&2
            if test -s "$repair_err_file"
                cat "$repair_err_file" >&2
            end
            command rm -f "$repair_out_file" "$repair_err_file"
            return 1
        end

        set -l repair_response (string trim -- (cat "$repair_out_file"))
        command rm -f "$repair_out_file" "$repair_err_file"

        set -l repaired_command
        set -l repaired_why
        for line in (string split "\n" -- $repair_response)
            if string match -q 'COMMAND:*' -- "$line"
                set repaired_command (string trim -- (string replace -r '^COMMAND:[[:space:]]*' '' -- "$line"))
            else if string match -q 'WHY:*' -- "$line"
                set repaired_why (string trim -- (string replace -r '^WHY:[[:space:]]*' '' -- "$line"))
            end
        end

        if test -z "$repaired_command" -o -z "$repaired_why"
            echo "please: generated command failed fish syntax validation and could not be repaired" >&2
            return 1
        end

        if not fish --no-execute -c "$repaired_command" >/dev/null 2>/dev/null
            echo "please: generated command failed fish syntax validation and repair attempt" >&2
            return 1
        end

        set command_line "$repaired_command"
        set why_line "$repaired_why"
    end

    printf "%s\n" "Command: $command_line"
    printf "%s\n" "Why: $why_line"

    if set -q _flag_dry_run
        return 0
    end

    while true
        read --local --prompt-str "Run this command? [Y/n/e=explain] " confirm
        switch (string lower -- (string trim -- "$confirm"))
            case '' y yes
                history append -- "$command_line"
                history save
                eval "$command_line"
                return $status
            case e explain
                set -l explain_prompt (string join "\n" \
                    "Explain this fish command in detail for the original request." \
                    "Return plain text only, max 8 lines." \
                    "Request: $user_request" \
                    "Command: $command_line")

                set -l explain_out_file (mktemp -t please.codex.explain.out.XXXXXX)
                or begin
                    echo "please: failed to create temporary output file" >&2
                    return 1
                end
                set -l explain_err_file (mktemp -t please.codex.explain.err.XXXXXX)
                or begin
                    command rm -f "$explain_out_file"
                    echo "please: failed to create temporary error file" >&2
                    return 1
                end

                set -l explain_codex_args exec --skip-git-repo-check --color never -o "$explain_out_file"
                if set -q _flag_model
                    set -a explain_codex_args --model "$_flag_model"
                else if set -q $default_model_var
                    set -a explain_codex_args --model "$$default_model_var"
                end
                if set -q _flag_reasoning_effort
                    if not string match -qr '^(low|medium|high|xhigh)$' -- "$_flag_reasoning_effort"
                        echo "please: --reasoning-effort must be low, medium, high, or xhigh" >&2
                        return 2
                    end
                    set -a explain_codex_args -c "model_reasoning_effort=$_flag_reasoning_effort"
                else if set -q $default_reasoning_effort_var
                    set -a explain_codex_args -c "model_reasoning_effort=$$default_reasoning_effort_var"
                end

                codex $explain_codex_args -- "$explain_prompt" >/dev/null 2>"$explain_err_file"
                set -l explain_status $status
                if test $explain_status -ne 0
                    echo "please: codex failed to explain command" >&2
                    if test -s "$explain_err_file"
                        cat "$explain_err_file" >&2
                    end
                    command rm -f "$explain_out_file" "$explain_err_file"
                    return 1
                end

                printf "\n%s\n%s\n\n" "Detailed explanation:" (string trim -- (cat "$explain_out_file"))
                command rm -f "$explain_out_file" "$explain_err_file"
            case n no
                printf "%s\n" "Skipped."
                return 0
            case '*'
                printf "%s\n" "Please enter Y, n, or e."
        end
    end
end
