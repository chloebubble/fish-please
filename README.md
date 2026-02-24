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
please --dry-run <request...>
please --help
```

Generated commands are executed in fish via `eval`.

When prompted, choose:
- `Y` (or Enter): run the command (default)
- `n`: skip
- `e`: ask for a more detailed explanation
