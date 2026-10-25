# Machiavelli Roguelike — new baseline

A roguelike built on Machiavelli (the Italian rummy variant, mechanically a
cousin of Rummikub) in Godot 4.6. This is the **baseline of the new design**:
a short run across a three-node map, 3 lives, every player drawing from their
own deck, and every card costing 1 energy. The full Machiavelli rules engine,
drag-and-drop table UI, animated AI opponents and headless test suite carry
over from the first version.

The first version (the endless ladder with the Cute Slime and the Sadistic
Billionaire, the shared double-deck stock, ultimates, Riichi) is kept intact in
[`legacy/v1-vanilla-engine/`](legacy/v1-vanilla-engine/) — open that folder as
its own Godot project to play it. A `.gdignore` in `legacy/` keeps it out of
this project.

## What the baseline has

| System | Baseline rule |
| --- | --- |
| Decks | The player and each enemy bring their own deck (52 cards + 2 jokers) and draw only from it. The table is shared. |
| Energy | Every card played from hand costs 1. You start with 3, gain 1 each turn (cap 10). Unspent energy is lost. Rearranging the table is free. |
| Lives | A run starts with 3. Losing a match costs one; at 0 the run is over. |
| Map | Slay the Spire style, three nodes in a line, one enemy each. Win to unlock the next node; lose and you may retry the same node. Beat node 3 to win the run. |
| Enemies | Three plain opponents with no special effects, ramping up in AI skill. |
| Events | Three random rule cards per match, revealed at the start of rounds 1, 3 and 5. Mechanics only, no theme yet. |
| Coins | Earned only from the Coin Rush event for now; banked into the run. Nothing spends them yet. |
| Not yet | Score, combo/streak bonus, combo objectives on events, card effects, shop. See the design doc. |

## Rules

- **Own decks.** Every player is dealt a starting hand (13 by default) from
  their own deck and only ever draws from it. Each card remembers its owner
  (`Card.deck_owner`) wherever it ends up on the table.
- **Groups.** A valid table group is a **set** (3–4 cards of one rank, all
  different suits) or a **run** (3+ consecutive cards of one suit; ace plays
  low `A-2-3` or high `Q-K-A`, never wrapping).
- **Your turn.** Play **at least one card from your hand**, or draw (2 cards in
  a run, 1–3 in settings). While playing you may freely rearrange *everything*
  on the table — the signature Machiavelli move — as long as every group is
  valid when you end the turn.
- **Energy** (runs only). Each card leaving your hand costs its energy cost
  (1 for every card for now). Your ceiling is 3 on your first turn and +1 each
  turn after, capped at 10; it refills to the ceiling every turn, so unspent
  energy never carries over. Taking a card back to your hand, or undoing,
  refunds it. A joker swap plays a real card, so it costs 1. Moving cards
  already on the table is always free.
- **Jokers** (★): count as any card, but a group needs at least one real card
  to anchor them. A joker in a valid group shows the card it stands for (e.g.
  `★7♥`); a player holding that exact card may drop it on the joker to swap it
  out and take the wildcard into their hand. The swap counts as playing a card.
- **Joker locking.** A joker is only a wildcard while it sits in a hand. The
  moment it lands in a valid group it locks to the card it stands for and every
  rule treats it as exactly that card until a swap sends it back to a hand.
  While a joker you placed this turn still has a choice (a set of three missing
  two suits, a spare joker on either end of a run), right-click it to re-point
  it; the choice is final when your turn ends.
- **Opening rule** (everyone, human and AI): until you have laid down at least
  one valid group built *only* from your own hand, you may not add cards to
  other groups or take cards from them. Runs deal **starting combos** by default:
  every player begins with a random valid three-card group from their own deck
  on the table, which counts as opening.
- **Max hand size** (optional): drawing stops at the cap, so a draw on a full
  hand is a pass.
- **Winning a match.** First to empty their hand wins. A player who cannot draw
  (their deck is empty or their hand is at the cap) passes; a full round of
  passes ends the match and the fewest cards wins (a shared tie counts as a win
  for you).

## Events

Each match draws 3 events at random from the pool below. One is turned face up
at the start of round 1, the next at round 3, the last at round 5, so at most
three are in play. They show in a row above the table: face up once revealed
(an on-reveal event dims after its round), face down with their round until
then.

Every event affects **every player**, not just whoever's turn it is:

- **On reveal** events act once on each player's turn of the round they are
  revealed in — that turn is "this turn" in their text.
- **Ongoing** events stay in force for the rest of the match.

| Event | Kind | Rule |
| --- | --- | --- |
| Cycle | On reveal | Choose 2 cards to discard, then draw 2. |
| Gift | On reveal | Choose 2 cards to give to your opponent. |
| Surge | On reveal | Gain +3 energy this turn (may go past the cap). |
| Coin Rush | On reveal | This turn, each card played gives +1 coin. |
| Overcharge | Ongoing | +1 max energy (may go past the cap). |
| Extra Draw | Ongoing | Draw 1 more card whenever you draw. |
| Attrition | Ongoing | Discard 1 random card at the start of your turn. |
| Open Decks | Ongoing | The top card of every deck is face up. |

Discards go face up to the owner's deck's discard pile, which is shuffled
back in when that deck runs dry. When an event asks you to choose cards, the
status line says so and a **Confirm** button appears: click the cards in your
hand, then Confirm. Ending the turn and drawing wait until you do. Enemies pick
the cards they can best spare. To stop events ending a match by themselves,
Gift never takes your last card and Attrition skips a one-card hand.

## The run

**New run** on the main menu opens the **Star chart**: three nodes from the
bottom (where you start) to the top (the boss), joined by a path. The node you
can fight now is lit gold, cleared nodes are green and checked, the rest are
locked. Hover a node for its enemy's description and AI. Your lives sit in the
header.

Click the lit node to play a 1v1 match against its enemy. When the match ends:

- **Win** — the node is cleared and the next one unlocks. Press **Back to map**.
- **Lose** — you lose a life and the node stays open to retry. Press **Back to map**.
- **Last node cleared** — the run is won. **Out of lives** — the run is lost.
  Either way the button becomes **New run**.

During a match the top bar shows your lives and which node you are on, the hand
header shows your energy (`Energy 2/4` plus a pip per point), and each enemy's
name chip shows their deck size and energy. Mid-match the action row offers
**Restart run**; **Menu** keeps the run, and **Resume** returns to the match,
or to the map between matches.

The enemies (`Enemy.roster()`), all plain opponents with standard decks:

| Node | Enemy | AI | Strong simulated player wins* |
| --- | --- | --- | --- |
| 1 | Scrap Drone | capable, quick, distractible, short-sighted | 100% |
| 2 | Rust Raider | strong, quick, attentive, a measured planner | 83% |
| 3 (boss) | Belt Warden | cutthroat, balanced, attentive, an expert planner | 33% |

\* 12 seeded games each from `tests/balance_stats.gd -- --games=12 --combo`
under run rules. The simulated player is the AI at full strength, so these are
upper bounds for a human.

The map model (`RunState`) already supports branching: each node links to one
or more nodes in the next row, so a wider map is a different generator, not a
new model.

## Playing it

Open the project in Godot 4.6 and press Run (`F5`). The main menu offers
**Resume** (once a game or run exists), **New run**, **Vanilla sandbox** (a
free-play game against 1–3 AIs with no energy or lives, handy for testing),
**Settings** and **Quit**. In game, the **Menu** button brings you back here
without losing the game in progress.

You sit at the bottom; opponents sit around the table showing the backs of
their cards. The top-left corner shows the **round** counter (one lap of the
table). Each opponent's name chip carries an **Info** button with its
description and AI.

On your turn:

1. **Drag** cards — from your hand and from any group on the table. Drop them on a
   group (or any card in it) to add them there, or on empty felt / the
   **+ New group** zone to start a new group. Dragging a selected card drags the
   whole selection.
2. Clicking works too: click cards to select them (they turn blue), then click a
   group's **+** button or the **+ New group** zone. Valid groups sit quietly on
   the felt; invalid ones outline red. Table cards are greyed out until you've
   opened.
3. Cards you laid down this turn can go back: drag them onto your hand, or select
   them and press **Return to hand** (this refunds their energy).
4. **End turn** validates the table and commits. **Undo action** takes back just
   the last staged move; **Undo turn** puts the whole turn back.
5. **Draw & end turn** if you can't or won't play. A partial or invalid staged
   play is abandoned first, but a *valid* table rearrangement that laid no card
   from your hand is kept.

Right-clicking anything that isn't a re-pointable joker clears the selection.

The felt is **freeform**: drag a group by the grip (**⠿**) along its top to
place it anywhere; **⟳** stands a group upright or lays it flat. The table
header's **Sort** and **Randomize** re-place the groups (purely visual), and the
**suit highlighter** (♥ ♦ ♣ ♠) outlines every card of the hovered suit across
the table and your hand.

Your hand keeps whatever order you give it (drag a card onto another to slot
it before or after), with **Sort: rank** and **Sort: suit** buttons. A card you
can play this instant, with no rearranging and within your energy, wears a
slim **green cap**; hovering it spotlights where it goes, and **double-clicking**
it plays it there (a lay-off if one exists, otherwise the fresh group it
completes with cards in your hand, trimmed to what your energy can pay for).

Enemy turns play out move by move: each card flies from where it was to where
it lands, the log narrates each move, and every card the enemies touched stays
highlighted in gold through your turn.

## Settings

The **Settings** dialog has two tabs. Changes apply live; **Save settings**
writes them to `user://settings.cfg` so they survive a restart.

**Roguelike run** (applies from the next match; lives from the next run):

- Cards drawn per turn (default 2), starting hand size (13), max hand size (none)
- Include jokers, 2 per deck (on); starting combos (on)
- Starting energy (3), energy gained per turn (1), energy cap (10, 0 = none)
- Lives (3)
- Events per match (3, revealed on rounds 1, 3, 5; 0 turns them off)
- **Enemy AI** — the four dials below for each enemy on the map; an enemy left
  untouched keeps its designed personality

**Vanilla sandbox** (sandbox games only): the four AI dials, enemy count (1–3),
cards drawn per turn, starting hand size, max hand size, max cards played per
turn, jokers, starting combos, and the ultimate meter (a sandbox-only leftover
from v1 that no current enemy uses).

The four AI dials:

- **Skill** (weak → strong) — how much of the move space the AI searches: single
  lay-offs, two-card lay-offs, safe joker stand-ins, table rearrangements. At the
  top (**cutthroat**) it scores every legal move with a card-counting brain that
  steals exposed jokers, avoids feeding opponents, holds useful cards and races
  the endgame.
- **Style** (quick → conservative) — a conservative AI sits on a small opening
  meld and holds cards that still pair up.
- **Attention** (oblivious → attentive) — a miss chance (up to 30%) on plays that
  read the table; laying a group from hand is never fumbled.
- **Planning** (short-sighted → expert planner) — how many board relocations the
  AI chains to open up a hand play: 1, 3, or as many as it needs.

## Layout

Scripts are grouped by layer: `scripts/engine/` (rules and game state, no UI),
`scripts/ai/` (opponents) and `scripts/ui/` (everything on screen).

### Engine — `scripts/engine/`

- `card.gd` — `Card`: suit, rank, owner deck, energy `cost` (1 for now), joker
  state, and effect flags (Sticky, Clear and others, dormant in the baseline)
- `deck.gd` — `Deck`: one player's deck — a standard 52 (+2 jokers) tagged with
  its owner, seeded shuffle, draw, and a discard pile that recycles when the
  deck runs dry
- `player_state.gd` — `PlayerState`: hand, own deck, energy ceiling and turns
  taken, opened flag
- `game_manager.gd` — `GameManager`: deals each player from their own deck
  (or a custom deck passed to `setup`), staged turns with per-move undo, the
  opening rule, energy (`energy_on`, `energy_left`, `energy_spent`,
  `play_budget`, `upcoming_energy`), commit validation, draw/pass, win
  detection; emits the signals the UI listens to. Also the layout moves
  (pictures, plays off pictures, crossings) kept from v1
- `match_event.gd` — `MatchEvent`: an event's id, kind (on reveal / ongoing),
  title and rule text, the pool and a random draw. The rules themselves live in
  `GameManager` (`event_deck`, `event_rounds`, `revealed_events`,
  `is_event_active`, `pending_choice` / `resolve_choice`, `draw_count`,
  `top_is_public`, `reveal_next_event`)
- `run_state.gd` — `RunState`: one run's lives, coins and map (rows of `MapNode`s,
  each with an enemy and links to the next row); `available_nodes`, `begin`,
  `record_win`, `record_loss`, `is_won`, `is_lost`. `RunState.linear` builds
  the current three-node map
- `rules.gd` — `Rules`: set/run/meld validation (joker-aware), joker
  assignment and stand-in choices, display order, grid-line reading
- `card_set.gd`, `board.gd`, `board_grid.gd` — table groups, the board with
  snapshot/restore, and the grid math for crossings and pictures

### AI — `scripts/ai/`

- `greedy_ai.gd` — `GreedyAI`: plays complete melds, lay-offs and table
  rearrangements one move at a time; the smart brain and deep planner at the
  top tiers. Plans inside the turn's `play_budget` (energy), and trims a meld it
  can't fully afford to the largest valid part that fits (`_fit_meld`), so an
  energy-limited turn still lays down what it can. Card counting reads
  `GameManager.copies_in_play`, since copies now depend on who brought what
- `ai_profile.gd` — `AIProfile`: the four personality dials
- `enemy.gd` — `Enemy`: an opponent's name, description, AI dials, and hooks for
  later (`build_deck` for an authored deck, `on_combat_start`,
  `plan_strategy_move`, `wants_control`/`run_controlled_turn`, `avoids_play`).
  `Enemy.roster()` is the three map enemies

### UI — `scripts/ui/` + `scenes/`

- `main_ui.gd` + `scenes/main.tscn` — `MainUI`: the controller — menu, map and
  match flow, selection, drag-and-drop, the enemy-turn loop, game-over handling
  for the run
- `map_screen.gd` — `MapScreen`: the run map, built in code; emits
  `node_chosen` and `menu_requested`
- `main_ui_builder.gd` — builds the widget tree once (table, hand, action row,
  lives label, energy slot, map, menu, dialogs)
- `table_view.gd` — renders seats (deck size, energy), the felt, the hand and
  its energy pips
- `play_advisor.gd` — "what can this hand card do right now": hover hints, the
  green cap and double-click play, all energy-aware
- `menu_screen.gd`, `settings_dialog.gd`, `game_settings.gd`, `card_renderer.gd`,
  `enemy_move_animator.gd`, `ui_theme.gd` — menu, settings dialog and model,
  card visuals, enemy-move animation, shared constants

## Tests

```sh
godot --headless --path . --import                                   # once, builds class cache
godot --headless --path . --script res://tests/smoke_test.gd         # unit tests + seeded AI games
godot --headless --path . --script res://tests/ui_mode_check.gd      # run flow, map, lives, energy, sandbox
godot --headless --path . --script res://tests/suit_filter_check.gd  # suit highlighter + table sort
godot --headless --path . --script res://tests/play_hint_check.gd    # hover-to-play hints
godot --headless --path . --script res://tests/view_check.gd         # table rendering + drag/drop
godot --headless --path . --script res://tests/anim_check.gd         # enemy-turn animation
godot --headless --path . --script res://tests/layout_check.gd       # crossings, pictures, grid lines
godot --headless --path . --script res://tests/opponent_view_check.gd # glass/slime reveal, green cap
```

`smoke_test.gd` covers every event (the reveal schedule, each rule, choices
blocking play until resolved, an early reveal) and ten full games with three
random events each, plus per-player decks (dealing, ownership, draws, custom
decks, deck-out passes), energy (start, growth, cap, no carry-over, refunds,
free rearranging, energy off in sandbox), the AI staying inside its energy
(including trimming a long meld), the run map (lives, retry, unlock, win, loss),
the joker rules, and full AI-vs-AI games — including six 1v1 games under run
rules that check every single AI move against the mover's energy.
`ui_mode_check.gd` walks a whole run through the UI: map, locked nodes, the
events row, an event choice through the Confirm button, coins banking into the
run, the
first match's rules, the energy display and green-cap gating, win → next node
under changed settings, loss → life lost and retry, out of lives → new run,
and a won run.

### Balance stats

```sh
godot --headless --path . --script res://tests/balance_stats.gd -- --games=50 --combo
```

Plays seeded 1v1 games under run rules — a simulated strong player against
each map enemy — and prints game length in player rounds, win rates, how often
the player plays vs draws, and cards per played hand. `--no-energy` turns
energy off; `--hand=N` changes the starting hand.

## Dormant systems kept from v1

These stay in the engine, tested, for the design ahead; nothing in the baseline
run uses them:

- **Card effects** — Sticky (slimed cards move as one lump) and Clear (glass,
  visible from the back), with the AI's glass-aware counting. Planned as the
  first buyable augments.
- **Pictures and crossings** — shape groups on a grid, Scrabble-style plays off
  them, and groups crossing at a shared card (`GameManager.move_cards_to_new_shape`,
  `play_off_picture`, `stage_cross_meld`). Good material for board objectives.
- **Ultimate meter** — still in the sandbox settings; off in runs.
- **Enemy hooks** — everything a designed enemy needs to plant a mechanic or
  author its deck.

## References

- The turn model is *staged*: moves mutate state immediately, `commit_turn()` is
  the only legality gate, `reset_turn()` rolls the whole turn back.
- A stronger AI (and a hint feature) could use the ILP formulation from Den
  Hertog & Hulshof, *Solving Rummikub Problems by Integer Linear Programming* —
  see [cduck/machiavelli](https://github.com/cduck/machiavelli) (MIT) and
  [mjpieters/rummikub-solver](https://github.com/mjpieters/rummikub-solver).
