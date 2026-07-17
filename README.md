# Machiavelli — Vanilla Engine

A playable, vanilla implementation of Machiavelli (the Italian rummy variant,
mechanically a cousin of Rummikub) in Godot 4.6. This is the base the roguelike
layer (card effects, health/gold, encounters) will be built on.

## Rules implemented

- Two full 52-card decks, no jokers (104 cards); 3 players (you + 2 AI), 13 cards each.
- A valid table group is a **set** (3–4 cards of one rank, all different suits) or a
  **run** (3+ consecutive cards of one suit; ace plays low `A-2-3` or high `Q-K-A`,
  never wrapping).
- On your turn: play **at least one card from your hand**, or draw one card.
  While playing you may freely rearrange *everything* on the table — the signature
  Machiavelli move — as long as every group is valid when you end the turn.
- **Opening rule** (applies to every player, human and AI): until you have laid
  down at least one valid group built *only* from your own hand, you may not add
  cards to other groups or take cards from them. Laying your own valid group
  unlocks the table immediately, even mid-turn.
- First to empty their hand wins. If the stock runs dry and a full round passes,
  fewest cards wins.

## Playing it

Open the project in Godot 4.6 and press Run (`F5`).

You sit at the bottom; opponents sit around the table showing the backs of
their cards — the first enemy directly opposite you, the second on the left,
and a fourth player (when one exists) on the right (max 4 seats). Backs overlap
more as a hand grows, so every seat always fits on screen.

On your turn:

1. **Drag** cards — from your hand and from any group on the table. Drop them on a
   group (or any card in it) to add them there, or on empty felt / the
   **+ New group** zone to start a new group. Dragging a selected card drags the
   whole selection.
2. Clicking works too: click cards to select them (they turn blue), then click a
   group's **+** button or **+ New group**. Groups outline green when valid, red
   when not. Table cards are greyed out until you've opened.
3. Cards you laid down this turn can go back: drag them onto your hand, or select
   them and press **Return to hand**. (Cards that started the turn on the table
   can never enter your hand.)
4. **End turn** validates the table and commits. **Undo action** takes back just
   the last staged move; **Undo turn** puts the whole turn back.
5. **Draw & end turn** if you can't or won't play (this also abandons staged moves).

Enemy turns play out move by move on screen: each card an enemy plays flies from
where it was (their hidden hand or its previous spot on the table) to where it
lands, stays highlighted in gold, and the log narrates each move.

## Layout

- `scripts/card.gd` — `Card` resource: suit, rank + roguelike effect flags (unused by
  the vanilla engine)
- `scripts/rules.gd` — `Rules`: static set/run/meld validation, display ordering
- `scripts/deck.gd` — `Deck`: double deck, seeded Fisher-Yates shuffle, stock
- `scripts/card_set.gd` — `CardSet` resource: one group on the table (+ stubs for
  future Trigger/Sticky effects)
- `scripts/board.gd` — `Board`: the melds on the table, with snapshot/restore so a
  whole turn's rearrangement can be rolled back
- `scripts/player_state.gd` — `PlayerState`: hand (+ roguelike health/gold, unused)
- `scripts/game_manager.gd` — `GameManager`: deal, staged turns, per-move undo,
  the opening rule, commit validation, draw/pass, win detection; emits signals
  the UI listens to
- `scripts/greedy_ai.gd` — `GreedyAI`: baseline opponent — plays complete melds from
  hand, single-card lay-offs, and simple table rearrangements (borrows one card
  from a group, when the leftover group stays valid, to complete a new meld with
  hand cards); respects the opening rule; produces one move at a time so the UI
  can animate enemy turns
- `scripts/main_ui.gd` + `scenes/main.tscn` — drag-and-drop (or click-to-play) UI,
  built in code: styled cards, felt table, per-group validity outlines, opponent
  seats with face-down card backs, flying-card enemy-turn animations,
  return-to-hand for cards staged this turn
- `tests/smoke_test.gd` — headless AI-vs-AI smoke test

## Headless smoke test

```sh
godot --headless --path . --import                              # once, builds class cache
godot --headless --path . --script res://tests/smoke_test.gd    # plays 25 seeded games
```

## Design notes / references

- The turn model is *staged*: moves mutate state immediately, `commit_turn()` is the
  only legality gate, `reset_turn()` rolls the whole turn back. Same as physical play.
- The AI is greedy and only does single-card table rearrangements. A strong AI
  (and a "hint" feature)
  should use the ILP formulation from Den Hertog & Hulshof, *Solving Rummikub
  Problems by Integer Linear Programming* — see
  [cduck/machiavelli](https://github.com/cduck/machiavelli) (MIT) and
  [mjpieters/rummikub-solver](https://github.com/mjpieters/rummikub-solver) for
  reference implementations.

## Roguelike layer (not built yet)

Kept as data stubs so the vanilla engine stays clean: card effect flags on `Card`
(Clear, Sticky, Spiked, Brittle, Bomb, Clone, Trigger, Mirrored), trigger/cluster
stubs on `CardSet`, health/gold on `PlayerState`. Phantom-turn damage, encounters,
and the shared-deck-corruption idea live in the concept doc and git history.
