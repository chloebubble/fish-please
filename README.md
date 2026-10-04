# fish-please

Fish function to ask Codex for a shell command, show a short explanation, optionally request a deeper explanation, and confirm before running.

Commands are generated specifically for fish and may use fish builtins/syntax when appropriate.

Each request includes current system facts: OS, kernel, architecture, fish version, working directory, user ID, and local time.
The prompt also lists installed common tools and detects GNU tool versions where available.
Codex uses these facts to select commands and flags for your system.

Generation and explanation use the Codex read-only sandbox.
The prompt permits read-only checks and tells Codex to leave execution to the confirmation step.
The script checks the response format and fish syntax before it shows the command.
These checks cannot prove that a command will produce the correct result. Check the command before you run it.

## Install

Copy `please.fish` to your fish functions path:

```fish
cp please.fish ~/.config/fish/functions/please.fish
```

## Example

https://github.com/user-attachments/assets/b6a63acd-d05a-4d68-9446-82e59da6caca

## Usage

```fish
please <request...>
please --model gpt-5 <request...>
please --reasoning-effort high <request...>
please --defaults show all
please --defaults set model gpt-5
please --defaults set reasoning high
please --defaults clear reasoning
please --dry-run <request...>
please --help
```

Generated commands are executed in fish via `eval`.
When you choose to run one, `please` also appends that exact command to your fish history and saves it immediately.

`--model` and `--reasoning-effort` select values for one run. `--defaults` manages persistent model/reasoning defaults via fish universal variables, so `please` does not create or read a config file.

Default values are printed in an aligned format:

```text
Model:      Codex default (gpt-5.5)
Reasoning:  Codex default (medium)
```

Generated commands are syntax-checked with fish before the run prompt. If Codex returns invalid fish syntax, `please` makes one repair attempt and validates the repaired command before offering to run it.

When prompted, choose:

- `Y` (or Enter): run the command (default)
- `n`: skip
- `e`: ask for a more detailed explanation
