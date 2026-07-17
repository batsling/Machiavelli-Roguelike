# Machiavelli — Vanilla Engine

A playable, vanilla implementation of Machiavelli (the Italian rummy variant,
mechanically a cousin of Rummikub) in Godot 4.6: a full rules engine with
staged, undoable turns; a drag-and-drop table UI with animated, tunable AI
opponents; optional jokers with player-chosen stand-ins; and a headless
AI-vs-AI test suite. This is the base the roguelike layer (card effects,
health/gold, encounters) will be built on.

## Rules implemented

- Two full 52-card decks (104 cards); you + 1-3 AI enemies (default 2), 13 cards
  each. Optional: 4 jokers in the deck (settings).
- A valid table group is a **set** (3–4 cards of one rank, all different suits) or a
  **run** (3+ consecutive cards of one suit; ace plays low `A-2-3` or high `Q-K-A`,
  never wrapping).
- On your turn: play **at least one card from your hand**, or draw (1-3 cards,
  set in settings; default 1).
  While playing you may freely rearrange *everything* on the table — the signature
  Machiavelli move — as long as every group is valid when you end the turn.
- **Jokers** (optional, ★): count as any card, but a group needs at least one real
  card to anchor them. A joker in a valid group shows the card it stands for
  (e.g. `★7♥`); a player holding that exact card may drop it on the joker to swap
  it out and take the wildcard into their hand. The real card leaves your hand
  for the table, so the swap counts as playing a card — a swap alone lets you
  end your turn.
- **Choosing what a joker stands for**: some groups leave the joker a genuine
  choice — a set of three is missing two suits, and a spare joker on a run could
  extend either end. Right-click the joker to pick from the valid options;
  inner run gaps are forced, so those offer no choice. The choice is open only
  while the joker is freshly placed — until the turn that played it is
  committed.
- **Joker locking**: when the turn that placed a joker ends, the joker locks to
  the card it was placed as. From then on every rule treats it as exactly that
  card — anyone may rearrange it into other groups, but it is no longer a
  wildcard — until the swap sends it back to a hand, where it becomes a free
  joker again.
- **Max hand size** (optional, settings: none or 10-20): drawing stops at the
  cap, so trying to draw on a full hand is a pass. A full round of passes ends
  the game as usual, fewest cards winning.
- **Opening rule** (applies to every player, human and AI): until you have laid
  down at least one valid group built *only* from your own hand, you may not add
  cards to other groups or take cards from them. Laying your own valid group
  unlocks the table immediately, even mid-turn.
- First to empty their hand wins. If the stock runs dry and a full round passes,
  fewest cards wins.

## Playing it

Open the project in Godot 4.6 and press Run (`F5`). You land on the main
menu: **Play vanilla** deals a fresh game, **Resume** (shown once a game
exists) returns to the table, **Settings** opens the options below, **Quit**
exits. In game, the **Menu** button brings you back here without losing the
game in progress.

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
   group's **+** button or the **+ New group** zone — both appear only while you
   have cards selected, keeping the table clean. Valid groups sit quietly on the
   felt; invalid ones outline red. Table cards are greyed out until you've
   opened.
3. Cards you laid down this turn can go back: drag them onto your hand, or select
   them and press **Return to hand**. (Cards that started the turn on the table
   can never enter your hand.)
4. **End turn** validates the table and commits. **Undo action** takes back just
   the last staged move; **Undo turn** puts the whole turn back.
5. **Draw & end turn** if you can't or won't play (this also abandons staged moves).

Jokers on the table show a tooltip with what they stand for; when the group
leaves them a choice, right-click one to pick its stand-in (handy for setting
up — or blocking — the swap).

Your hand works like Balatro's: it keeps whatever order you give it. Drag a card
onto another hand card to slot it there (left half = before, right half = after),
drag onto empty hand space to send it to the end, or use the **Sort: rank** /
**Sort: suit** buttons.

Enemy turns play out move by move on screen: each card an enemy plays flies from
where it was (their hidden hand or its previous spot on the table) to where it
lands, and the log narrates each move. Every card the enemies touched stays
highlighted in gold — the highlights accumulate across the whole round of enemy
turns and persist through your turn, so you can always see exactly what changed
since you last acted; they clear when the enemies start their next round.

## Settings

The **Settings** button opens a dialog with:

- **Enemy AI graph** — click to place the marker. Vertical axis is skill
  (top = strong, bottom = weak), horizontal is style (left = quick,
  right = conservative). A weak AI regularly misses plays it could have made; a
  strong one sees single- and two-card lay-offs plus table rearrangements, and
  points the jokers it plays at safe stand-ins — cards whose copies are mostly
  already visible on the table (or in its own hand), so the other players are
  unlikely to hold the exact card needed to swap-claim the joker. A quick AI
  dumps everything as soon as possible; a conservative one sits on its opening
  meld until it's big enough (unless the endgame forces its hand) and holds
  cards that still pair up with the rest of its hand. Applies from the next
  enemy turn.
- **Enemies** (1-3) — takes effect on the next new game.
- **Cards drawn per turn** (1-3) — applies immediately, to everyone.
- **Max hand size** (none, or 10-20) — applies immediately, to everyone;
  drawing stops at the cap and a draw on a full hand becomes a pass.
- **Include 4 jokers** — takes effect on the next new game.

## Layout

- `scripts/card.gd` — `Card` resource: suit, rank + roguelike effect flags (unused by
  the vanilla engine)
- `scripts/rules.gd` — `Rules`: static set/run/meld validation (joker-aware),
  joker value assignment (honoring per-joker stand-in preferences), the list of
  alternative stand-ins a joker could take, display ordering
- `scripts/deck.gd` — `Deck`: double deck (optional jokers), seeded Fisher-Yates
  shuffle, stock
- `scripts/card_set.gd` — `CardSet` resource: one group on the table (+ stubs for
  future Trigger/Sticky effects)
- `scripts/board.gd` — `Board`: the melds on the table, with snapshot/restore so a
  whole turn's rearrangement can be rolled back
- `scripts/player_state.gd` — `PlayerState`: hand (+ roguelike health/gold, unused)
- `scripts/game_manager.gd` — `GameManager`: deal, staged turns, per-move undo,
  the opening rule, commit validation, draw/pass, win detection; emits signals
  the UI listens to
- `scripts/greedy_ai.gd` — `GreedyAI`: baseline opponent — plays complete melds from
  hand (with joker fallbacks), single- and two-card lay-offs, and simple table
  rearrangements (borrows one card from a group, when the leftover group stays
  valid, to complete a new meld with hand cards); picks safe joker stand-ins at
  higher skill; respects the opening rule; produces one move at a time so the
  UI can animate enemy turns
- `scripts/ai_profile.gd` — `AIProfile`: the skill/style knobs GreedyAI consults
  (miss chance, search depth, opening threshold, key-card holding); unset =
  strong + quick and fully deterministic
- `scripts/ai_graph.gd` — `AIGraph`: the clickable 2D skill/style picker in the
  settings dialog
- `scripts/main_ui.gd` + `scenes/main.tscn` — main menu plus the drag-and-drop
  (or click-to-play) UI, built in code: styled cards, felt table, per-group
  validity outlines, opponent seats with face-down card backs, flying-card
  enemy-turn animations with round-long gold highlights, the right-click joker
  menu, Balatro-style hand ordering, return-to-hand for cards staged this
  turn, the settings dialog
- `tests/smoke_test.gd` — headless AI-vs-AI smoke test plus unit tests for the
  joker rules, the joker swap, joker stand-in choice, joker locking, the AI's
  safe stand-in picking, and the hand cap

## Headless smoke test

```sh
godot --headless --path . --import                              # once, builds class cache
godot --headless --path . --script res://tests/smoke_test.gd    # unit tests + 65 seeded games
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
