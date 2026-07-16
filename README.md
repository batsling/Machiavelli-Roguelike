# Machiavelli — Prototype Scaffold

This is a starting skeleton, not a working game yet. It exists so Claude Code has
real code to build on instead of an empty project.

## What's here

- `project.godot` — Godot 4.3 project file (Forward+ renderer)
- `scripts/card.gd` — `Card` resource: suit, rank, owner, and a list of effect flags
  (Clear, Sticky, Spiked, Brittle, Bomb, Clone, Trigger, Mirrored)
- `scripts/card_set.gd` — `CardSet` resource: a run of cards on the board; has stubs
  for trigger resolution and Sticky-cluster adjacency walking
- `scripts/player_state.gd` — `PlayerState` resource: hand, health, gold, finished flag
- `scripts/game_manager.gd` — `GameManager` node: minimal turn loop with a
  phantom-turn-damage stub

## What's deliberately NOT here yet

- No scenes/UI — no board rendering, no card sprites, no input handling
- No actual damage/heal numbers tuned — placeholders only
- No AI/opponent decision-making
- Shared-deck-with-corruption idea is not implemented — it's flagged as a structural
  candidate in the concept doc, not yet a settled design
- Mirrored/4-sided card has a flag on `Card` but no dual-set membership logic

## Suggested first milestone for Claude Code

1. Open this folder in Godot to confirm it loads (or `godot --headless --path .`
   to sanity-check from the CLI).
2. Build a minimal scene: one board, one human player, two opponents, all with
   starter hands — enough to click through a full turn cycle in-editor.
3. Wire `GameManager._take_real_turn()` to real input: play a card from hand, or
   reposition a card already on the board.
4. Get phantom-turn damage actually firing and visible (health bar/log), even with
   placeholder numbers.
5. Only after that loop feels right, start layering in the card effects one at a
   time (Sticky before Bomb/Spiked, since those two key off Sticky's clustering).

See `machiavelli_concept.md` (same output folder) for the full design doc, including
the running list of open questions this scaffold leaves unresolved on purpose.
