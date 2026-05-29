# fish-please

Fish function to ask Codex for a shell command, show a short explanation, optionally request a deeper explanation, and confirm before running.

Commands are generated specifically for fish and may use fish builtins/syntax when appropriate.

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
