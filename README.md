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
| Energy | Every card played from hand costs its energy (1 unless an instance changes it), shown in a circle in its top-left corner. You start with 3, gain 1 each turn (cap 10). Unspent energy is lost. Rearranging the table is free. |
| Lives | A run starts with 3. Losing a match costs one; at 0 the run is over. |
| Map | Slay the Spire style, three nodes in a line, one enemy each. Win to unlock the next node; lose and you may retry the same node. Beat node 3 to win the run. |
| Enemies | Three plain opponents with no special effects, ramping up in AI skill. |
| Instances | Five random rule cards per match, revealed at the start of rounds 1, 3, 5, 7 and 9, each bringing a random combo to the table. What each does is written in the spreadsheet's Effect column. Mechanics only, no theme yet. |
| Coins | +1 per card you play into a group holding an instance's combo card, plus the Coin Rush instance; banked into the run. Nothing spends them yet. |
| Not yet | Score, combo/streak bonus, card effects, shop. See the design doc. |

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
- **No opening rule.** Classic Machiavelli makes you lay a group built only from
  your own hand before you may touch the rest of the table; here everyone may
  work the whole table from their first turn. The rule is kept as a switch
  (`GameManager.opening_rule`, off) for a future item or enemy to bring back.
- **Starting combos.** A run deals none: its table starts with only the round-1
  instance's combo. The sandbox can deal them (off by default): every player
  begins with a random valid three-card group from their own deck on the table,
  labelled **Your start** / **Rosso's start** until it is changed.
- **Max hand size** (optional): drawing stops at the cap, so a draw on a full
  hand is a pass.
- **Winning a match.** First to empty their hand wins. A player who cannot draw
  (their deck is empty or their hand is at the cap) passes; a full round of
  passes ends the match and the fewest cards wins (a shared tie counts as a win
  for you).

## Instances

Each match draws 5 instances at random from the pool below. One is turned face
up at the start of round 1 and the next at rounds 3, 5, 7 and 9, so at most five
are in play. They stand in a column left of the table: face up once revealed (a
Reveal instance dims after its round), face down with their round until then.

Every instance affects **every player**, not just whoever's turn it is:

- **Reveal** instances act on each player's turn of the round they are revealed
  in — that turn is "this turn" in their text.
- **Ongoing** instances act at the start of every turn, and their rules stay in
  force, for the rest of the match.

Every instance also brings a **combo**: a random valid three-card group (a set or
a run) made of fresh cards from outside both players' decks. It lands on the
table the moment the instance is revealed, flying in from the instance's panel and
lit in gold, and anyone may build on it or borrow from it like any other group.
The instance panel names its combo, and the group's grip strip reads
**<Instance> combo** until it is changed. The round-1 instance is revealed as the
match is dealt, so its combo is the only group on a run's opening table.

**Combo coins.** Every card you play from your hand into a group holding an
instance combo card earns **+1 coin** when you end your turn. Those groups wear
a gold grip strip reading **+1 coin/card**; while your staged turn will earn
coins the hand header says **+N coins on End turn**, and a gold **+N coins**
floats up from the coin count when they land. The rule binds enemies too.

What each instance *does* is its **Effect** in the **Instances** sheet of
`tools/Machiavelli Roguelike.xlsx`: a short list of commands such as
`discard choose 2; draw 2`. Write a new instance's Effect in the sheet,
regenerate, and it is in the game — the commands, picks and filters are listed in
[`data/instances/README.md`](data/instances/README.md). Instances used to be
called locations (and before that events).

| Instance | Type | Description | Effect |
| --- | --- | --- | --- |
| Cycle | Reveal | Choose 2 cards to discard, then draw 2. | `discard choose 2; draw 2` |
| Gift | Reveal | Choose 2 cards to give your opponent. | `give choose 2` |
| Surge | Reveal | +3 energy this turn. | `energy +3` |
| Coin Rush | Reveal | +1 coin per card played this turn. | `coins_per_card 1` |
| Overcharge | Reveal | +2 max energy. | `max_energy +2` |
| Extra Draw | Ongoing | Draw 1 more card whenever you draw. | `draw_bonus 1` |
| Attrition | Ongoing | Discard 1 random card at the start of your turn. | `discard random 1` |
| Open Decks | Ongoing | The top card of every deck is face up. | `open_decks` |
| Wild Card | Reveal | Draw 1 of your Jokers. | `draw_joker 1` |
| Jumble | Reveal | Give 2 random cards random suits and ranks. | `jumble random 2` |
| Jackpot | Ongoing | 7s cost 0 Energy. | `cost rank=7 0` |
| Syphon | Reveal | 2 random cards -1 energy cost, 2 other random cards +2. | `cost random 2 -1; cost random 2 +2` |
| Black Hole | Reveal | Destroy a random Combo on the board. | `destroy combo random` |

**Discard pile.** Discarded and destroyed cards go face up to their owner's
deck's discard pile, which is shuffled back in when that deck runs dry. Yours
sits at the left of your hand showing its count; click it to see every card in
it. A destroyed instance combo card goes to the discard pile of the player whose
turn it is.

When an instance asks you to choose cards, the status line (across the top of
the table) says so and a **Confirm** button appears: click the cards in your
hand, then Confirm. Ending the turn and drawing wait until you do. Enemies pick
the cards they can best spare. To stop instances ending a match by themselves,
discarding and giving never take a player's last card.

**Energy costs.** Each card shows what it costs to play in a circle in its
top-left corner: blue for the usual 1, green when cheaper, red when dearer.
`cost random N ±D` (Syphon) changes a card's cost for good; `cost FILTER V`
(Jackpot) sets it while the instance is in force.

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
header shows your energy (`Energy 2/4` plus a pip per point), each enemy's
name chip shows their energy, and every player's deck sits beside their cards
(yours at the right of your hand, beside **End turn**). The instances stand in a
column left of the felt. The **☰ Menu** in the top-right corner offers
**Settings**, **Restart run** and **Main menu** (which keeps the run; **Resume**
returns to the match, or to the map between matches).

The enemies (`Enemy.roster()`), all plain opponents with standard decks:

| Node | Enemy | AI | Strong simulated player wins* |
| --- | --- | --- | --- |
| 1 | Scrap Drone | capable, quick, distractible, short-sighted | 92% |
| 2 | Rust Raider | strong, quick, attentive, a measured planner | 58% |
| 3 (boss) | Belt Warden | cutthroat, balanced, attentive, an expert planner | 25% |

\* 12 seeded games each from `tests/balance_stats.gd -- --games=12`
under run rules. The simulated player is the AI at full strength, so these are
upper bounds for a human.

The map model (`RunState`) already supports branching: each node links to one
or more nodes in the next row, so a wider map is a different generator, not a
new model.

## Playing it

Open the project in Godot 4.6 and press Run (`F5`). The main menu offers
**Resume** (once a game or run exists), **New run**, **Vanilla sandbox** (a
free-play game against 1–3 AIs with no energy or lives, handy for testing),
**Settings** and **Quit**. In game, the **☰ Menu** in the top-right corner holds
**Settings**, **Restart run** (**New game** in the sandbox) and **Main menu**, which
brings you back here without losing the game in progress.

You sit at the bottom; opponents sit around the table showing the backs of
their cards. The top-left corner shows the **round** counter (one lap of the
table). Each opponent's name chip carries an **Info** button with its
description and AI, and their deck sits beside their card backs with the
cards left (its top card face up when that card is public: glass, Open Decks).
The status line (what to do now) runs across the top of the table in gold. The
**Log** button in the top-left corner lays the game log over the left side of
the screen, above your hand, without moving anything; press it again (or **✕**)
to hide it.

On your turn:

1. **Drag** cards — from your hand and from any group on the table. Drop them on a
   group (or any card in it) to add them there, or on empty felt / the
   **+ New group** zone to start a new group. Dragging a selected card drags the
   whole selection.
2. Clicking works too: click cards to select them (they turn blue), then click a
   group's **+** button or the **+ New group** zone. Valid groups sit quietly on
   the felt; invalid ones outline red.
3. Cards you laid down this turn can go back: drag them onto your hand, or select
   them and press **Return to hand** (this refunds their energy).
4. **End turn** (the big gold button right of your hand) validates the table
   and commits; it lights up once you have played at least one card from your
   hand. **Undo action** takes back just the last staged move; **Undo turn**
   puts the whole turn back.
5. If you can't or won't play, click **your deck** (the **Draw** pile just left
   of End turn) to draw and end your turn. A partial or invalid staged play is
   abandoned first, but a *valid* table rearrangement that laid no card from
   your hand is kept.

Right-clicking anything that isn't a re-pointable joker clears the selection.

The felt is **freeform**: groups start out centered on it (a new group takes
the free spot nearest the middle), and you can drag a group by the grip (**⠿**)
along its top to place it anywhere; **⟳** stands a group upright or lays it flat. The table
header's **Sort** and **Randomize** re-place the groups as a centered block
(purely visual), and the
**suit highlighter** (♥ ♦ ♣ ♠) outlines every card of the hovered suit across
the table and your hand.

Your hand keeps whatever order you give it (drag a card onto another to slot
it before or after), with two small sort buttons at its right edge, by your deck: **A–K** (by rank) and **♥♠** (by
suit). A card you
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
- Include jokers, 2 per deck (on)
- Starting energy (3), energy gained per turn (1), energy cap (10, 0 = none)
- Lives (3)
- Instances per match (5, revealed on rounds 1, 3, 5, 7, 9; 0 turns them off)
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

## Content from the spreadsheet

`tools/Machiavelli Roguelike.xlsx` is upstream of `data/`, the way
`Roguelikes.xlsx` is in Roguelike-like: edit the sheet, run its generator, and
commit the sheet and the regenerated `.tres` together. Never hand-edit a
generated `.tres`, and never save the workbook from a script (openpyxl drops
what it does not understand); generators only read it.

| Sheet | Generator | Output | Schema | Loaded by |
| --- | --- | --- | --- | --- |
| Instances | `tools/generate_instances.py` | `data/instances/*.tres` | `InstanceData` | `Instances` |

```sh
python3 tools/generate_instances.py           # write data/instances/*.tres
python3 tools/generate_instances.py --list    # print what the sheet parses to
python3 tools/generate_instances.py --check   # exit 1 if data/ is out of date
```

**Instances** (`Name | Type | Description | Effect`) are the rule cards
revealed during a match (`MatchInstance`). The sheet decides everything about
one: its name, Type (*Reveal* / *Ongoing*), card text, and Effect — the commands
it runs, read by `InstanceEffect` and run by `GameManager` (see
[`data/instances/README.md`](data/instances/README.md)). So:

- **Rename, reword or retune** an instance: edit the sheet and regenerate.
- **Remove** one from the game: delete its row and regenerate.
- **Add** one: add the row with its Effect and regenerate. A row with no Effect
  yet stays out of the pool, with a warning; an Effect that doesn't read stays
  out with an error naming the problem (the generator already refuses an
  unknown command).
- A brand-new *kind* of command is code (`InstanceEffect` + `GameManager`).

`smoke_test.gd` fails if any row's Effect doesn't read, and plays every
instance in full games.

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
- `match_instance.gd` — `MatchInstance`: an instance's id, kind (Reveal /
  Ongoing), title, rule text and parsed Effect (from the Instances sheet's data),
  its combo, the pool and a random draw
- `instance_effect.gd` — `InstanceEffect`: one Effect command, and the parser
  that reads an Effect cell (or says what is wrong with it). The commands run in
  `GameManager` (`instance_deck`, `instance_rounds`, `revealed_instances`,
  `pending_choice` / `resolve_choice`, `card_cost`, `pending_coins`,
  `draw_count`, `top_is_public`, `reveal_next_instance`)
- `run_state.gd` — `RunState`: one run's lives, coins and map (rows of `MapNode`s,
  each with an enemy and links to the next row); `available_nodes`, `begin`,
  `record_win`, `record_loss`, `is_won`, `is_lost`. `RunState.linear` builds
  the current three-node map
- `rules.gd` — `Rules`: set/run/meld validation (joker-aware), joker
  assignment and stand-in choices, display order, grid-line reading
- `card_set.gd`, `board.gd`, `board_grid.gd` — table groups, the board with
  snapshot/restore, and the grid math for crossings and pictures

### Data — `scripts/resources/` + `data/`

- `instance_data.gd` — `InstanceData`: one row of the Instances sheet (id,
  title, kind, text, effect, sheet order)
- `instances.gd` — `Instances`: loads `data/instances/` once and serves it by
  id (`get_by_id`) or in sheet order (`all`)

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
- `main_ui_builder.gd` — builds the widget tree once (☰ Menu, instances column,
  table, hand with its sort icons, your Draw pile and turn controls, the
  log overlay, map, menu, dialogs)
- `table_view.gd` — renders seats (energy, each opponent's deck pile), the felt
  (centered placement, starting/instance combo labels), the hand and its
  energy pips
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

`smoke_test.gd` covers every instance (the reveal schedule, every sheet row's
Effect reading cleanly, the parser refusing broken Effects, each instance at
work, choices blocking play until resolved, combo coins, card costs, an early
reveal) and ten full games with five random instances each, plus per-player decks (dealing, ownership, draws, custom
decks, deck-out passes), energy (start, growth, cap, no carry-over, refunds,
free rearranging, energy off in sandbox), the AI staying inside its energy
(including trimming a long meld), the run map (lives, retry, unlock, win, loss),
the joker rules, and full AI-vs-AI games — including six 1v1 games under run
rules that check every single AI move against the mover's energy.
`ui_mode_check.gd` walks a whole run through the UI: map, locked nodes, the
instances row, an instance choice through the Confirm button, coins banking into the
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
