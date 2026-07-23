# Machiavelli — Vanilla Engine

A playable, vanilla implementation of Machiavelli (the Italian rummy variant,
mechanically a cousin of Rummikub) in Godot 4.6: a full rules engine with
staged, undoable turns; a drag-and-drop table UI with animated, tunable AI
opponents; optional jokers with player-chosen stand-ins; and a headless
AI-vs-AI test suite. This is the base the roguelike layer (card effects,
health/gold, encounters) will be built on.

## Rules implemented

- Every player brings their own single 52-card deck (plus 2 jokers each when
  jokers are on); at the start of combat the decks are combined into one stock,
  so you still draw from a shared pile and play is unchanged — a 1v1 rogue round
  is the familiar double deck (104 cards, +4 jokers). Each card remembers which
  deck it came from, which a designed enemy reads to corrupt only its own cards.
  You + 1-3 AI enemies (default 2), 13 cards each.
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
- **Joker locking**: a joker is only a wildcard while it sits in someone's
  hand. The moment it lands in a valid group on the table it locks to the card
  it stands for, and from then on every rule treats it as exactly that card —
  anyone may rearrange it into other groups (or break its group mid-turn), but
  it never changes face and is no longer a wildcard — until a swap sends it
  back to a hand, where it becomes a free joker again.
- **Choosing what a joker stands for**: some groups leave the joker a genuine
  choice — a set of three is missing two suits, and a spare joker on a run could
  extend either end. Right-click the joker to re-point it at any card it could
  stand for; inner run gaps are forced, so those offer no choice. Only the
  player who placed the joker may do this, and only until their turn ends —
  then the choice is final.
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

The top-left corner shows the **round** counter: one round is a full lap of the
table (every player takes one turn), and it ticks up each time play returns to
you. Each opponent's name chip carries an **Info** button — click it for a
pop-up with that opponent's mechanic (in a roguelike round) and the AI brain it
is running.

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
5. **Draw & end turn** if you can't or won't play. A partial or invalid staged
   play is abandoned first, but a *valid* table rearrangement that laid no card
   from your hand is kept — you can rework the felt and still draw.

Jokers on the table show a tooltip with what they stand for; while a joker you
placed this turn still has a choice, right-click it to pick its stand-in (handy
for setting up — or blocking — the swap). Right-clicking anything else — a
card, the felt, your hand — clears the current selection.

The felt is **freeform**: every group sits wherever you put it, not packed into
rows and columns. Each group's panel carries a slim grip (**⠿**) along its top —
grab it and drag to slide the whole group (a crossing or picture cluster moves as
one) anywhere on the table, so a tall vertical run and a wide horizontal one
nestle side by side however you like. A freshly laid group drops into the next
open patch of felt on its own. Each lone group also carries a small **⟳** control
that stands it upright or lays it flat — purely how it sits on the table (the
group itself is untouched).

The table can get crowded, so its header carries **Sort** and **Randomize**
buttons that re-place the groups on the felt (a purely visual reshuffle — the
groups themselves are untouched). **Sort** does as best it can to organize
whatever you have scattered: it lays straights out first — by colour, then by
starting rank — and sets after, by rank, packing them tidily from the top-left;
any group you have broken mid-rearrange stays put at the end. **Randomize** keeps
each group intact but reshuffles where the groups sit, to jog loose a
rearrangement you had not spotted.
The header also carries a row of suit symbols (♥ ♦ ♣ ♠) — the **suit
highlighter**: hover any one to outline every card of that suit *everywhere in
play*, across both the table and your hand at once, and fade the rest, so you can
pick a colour out of the whole board at a glance (jokers count as every suit).
Move the mouse off and everything returns to normal.

Your hand works like Balatro's: it keeps whatever order you give it. Drag a card
onto another hand card to slot it there (left half = before, right half = after),
or drag onto empty hand space to send it to the end. Its header carries two sort
buttons — **Sort: rank** lays the hand out by rank, increasing left to right,
and **Sort: suit** groups it by suit (reds then blacks, rank order within each);
jokers sort last either way. And **hovering a card in your hand shows where it
can play right now with no rearranging**: every group it could lay off onto is
spotlighted green, and a green **✓ New group** cue appears on the felt when the
card completes a brand-new group with other naturals already in your hand. Plays
that would need a joker to close are disregarded, so the cue only lights for
groups you can form without spending a wildcard. Lay-offs only light up once you
have opened; the new-group cue always shows, since that is how you open.

A card that can be played this instant also wears a slim **green cap** across
its top, so you can spot your ready plays without hovering each one. **Double-click
a green-capped card to play it straight away** — no dragging: it lays off onto a
matching group if one exists (the smallest move), otherwise it lays down the
fresh group it completes with other cards in your hand. Cards without the cap
are unaffected — they still drag and click-select as normal.

Enemy turns play out move by move on screen: each card an enemy plays flies from
where it was (their hidden hand or its previous spot on the table) to where it
lands, and the log narrates each move. Every card the enemies touched stays
highlighted in gold — the highlights accumulate across the whole round of enemy
turns and persist through your turn, so you can always see exactly what changed
since you last acted; they clear when the enemies start their next round.

## Settings

The **Settings** button opens a dialog with two tabs — **Vanilla sandbox**
(free-play games only) and **Roguelike run** (the run's own rules, so the
roguelike can be balanced without touching the sandbox). The dialog is built
to always fit fully on screen: each tab is a compact, scrolling column of
single-line rows (each AI dial is one line with its end labels beside the
slider), the longer rule explainers live in tooltips, and the pop-up clamps
itself inside the window.

The **Vanilla sandbox** tab holds:

- **Enemy AI** — three independent 0–1 sliders:
  - **Skill** (weak → strong) — how much of the move space the AI searches. It
    ramps up through single lay-offs, two-card lay-offs, safe joker stand-ins,
    and table rearrangements. At the top (**cutthroat**) it switches from
    grabbing the first legal move to a deck-counting brain that scores every
    legal move and plays the smartest one: it steals exposed jokers off the
    table into its own melds, avoids handing opponents an open end to lay off
    onto, holds cards worth keeping, and drops all of that to race for the
    finish once the endgame is close.
  - **Style** (quick → conservative) — a quick AI dumps everything as soon as
    possible; a conservative one sits on its opening meld until it's big enough
    (unless the endgame forces its hand) and holds cards that still pair up with
    the rest of its hand.
  - **Attention** (oblivious → attentive) — the blunder roll, capped at a 30%
    miss chance when fully oblivious. It only covers the plays that read the
    table — laying off onto an existing group or rearranging the felt — never
    laying a group straight from hand, so an oblivious AI still empties its hand
    into fresh groups reliably but keeps overlooking the table plays (cutting
    its streak short). It is independent of skill — a strong but oblivious AI
    sees the clever plays yet keeps fumbling the obvious ones.
  - **Planning** (short-sighted → expert planner) — how many board-card
    relocations the AI will chain to open up a hand play. Beyond the built-in
    one- and two-card borrows, a planner pulls the table cards a new group needs
    into it alongside its hand cards and then repairs every group left broken —
    relocating the offending cards to a valid home, recursively. A short-sighted
    AI shifts a single card; the middle tier reworks up to three; an expert
    planner reshuffles as much of the table as it needs to lay down what it
    holds (bounded only by internal safety caps). Independent of the other
    dials.

  Applies from the next enemy turn.
- **Enemies** (1-3) — takes effect on the next new game.
- **Cards drawn per turn** (1-3) — applies immediately, to everyone.
- **Starting hand size** (5-21) — how many cards each player is dealt;
  takes effect on the next new game.
- **Max hand size** (none, or 10-20) — applies immediately, to everyone;
  drawing stops at the cap and a draw on a full hand becomes a pass.
- **Include 4 jokers** — takes effect on the next new game.
- **Starting combos** — takes effect on the next new game: every player is
  dealt a random valid three-card group (a set or a run of naturals) straight
  from the stock onto the table, which counts as their opening meld — nobody
  starts locked out of the table on a hand that can't lay a group.
- **Ultimate meter** — every player (you and the enemies) carries a meter that
  charges as they play cards and holds once full, shown as a bar under each
  opponent's name and beside your hand. The bar builds **live** as cards are
  played this turn — the current player's bar previews the charge their staged
  plays will bank — so an ultimate can fire the very turn its meter completes,
  not a turn later. **Meter max** (0 disables it, default 20) is how much it
  holds; **Charge per play** (default 1) is how much each committed hand adds;
  **Charge per card played from hand** switches that from once per hand to once
  per card leaving the hand that turn. Applies from the next new game (the
  meter max also applies live).

The **Roguelike run** tab holds the run's own copies of the same rules —
cards drawn per turn (default 2), starting hand size (default 13), max hand
size (default none), max cards played per turn (default 13), jokers (default
in), starting combos (default on) and the ultimate meter (default max 20,
charge 1 per card played from hand). It also holds an **Enemy AI** section
with the same four sliders (Skill / Style / Attention / Planning) *for each
individual enemy in the roster*, so any single opponent's brain can be retuned
for the run; an enemy left untouched keeps its designed personality (every
designed enemy is an expert planner by default). Every change
applies from the next round; a round in progress keeps the rules it started
under, and each enemy still brings its own designed mechanics.

A **Save settings** button (beside **Done**) writes every setting — both tabs,
including the per-enemy AI overrides — to disk (`user://settings.cfg`), so the
tuning is remembered the next time the game is launched. Changes still apply
live as you make them; Save is only what makes them stick between sessions.

## Layout

The scripts are grouped by architectural layer: `scripts/engine/` (rules and
game state), `scripts/ai/` (opponents and their brains), and `scripts/ui/`
(everything on screen). The engine and AI layers know nothing about the UI.

### Engine — `scripts/engine/`

- `scripts/engine/card.gd` — `Card` resource: suit, rank + roguelike effect flags (unused by
  the vanilla engine)
- `scripts/engine/rules.gd` — `Rules`: static set/run/meld validation (joker-aware),
  joker value assignment (honoring per-joker stand-in preferences), the list of
  alternative stand-ins a joker could take, display ordering
- `scripts/engine/deck.gd` — `Deck`: the players' single decks combined into one
  double deck (optional jokers), each card tagged with its origin deck
  (`Card.deck_owner`), seeded Fisher-Yates shuffle, stock, and a face-up
  discard pile that recycles into the stock when it runs dry (the
  Billionaire's Riichi discards feed it)
- `scripts/engine/tiling.gd` — `Tiling`: the exact "can this pile be laid down
  into valid melds with none left over?" solver (a memoized, in-place
  depth-first search over sets and runs, ace low/high, joker-aware). Run over the
  Billionaire's hand for his Riichi three ways — the wait set (`wait_cards`), the
  tsumo/ron go-out (`can_partition`), and a cheap one-wildcard tenpai gate
  (`can_partition_with_wild`)
- `scripts/engine/card_set.gd` — `CardSet` resource: one group on the table (+ stubs for
  future Trigger/Sticky effects), plus the layout state: an orientation
  (a line group can lie flat or stand upright on the felt), shape cells
  (a "picture" group placing its cards on a small grid, with line-through
  helpers), and the attachment of an extension line — the picture card it
  reads from and its outward direction, its validity being the grid-line
  reading (at least three cards, that anchor counted in)
- `scripts/engine/board.gd` — `Board`: the melds on the table, with snapshot/restore so a
  whole turn's rearrangement can be rolled back (snapshots keep each group's
  orientation and shape). A card may sit in more than one meld at once — an
  intersection, where a vertical group crosses a horizontal one at a shared
  card — via `melds_of` / `intersections`; taking a card off the table
  removes it from every group holding it
- `scripts/engine/board_grid.gd` — `BoardGrid`: the grid math for the layout
  groundwork — lays every connected patch of groups onto a local grid (lines
  along their orientation, crossings aligned at the shared card, pictures by
  their own cells) and answers adjacency queries (`neighbors`), the future
  "cards directly beside each other are a legal play" relation
- `scripts/engine/player_state.gd` — `PlayerState`: hand (+ roguelike health/gold, unused)
- `scripts/engine/game_manager.gd` — `GameManager`: deal, staged turns, per-move undo,
  the opening rule, commit validation, draw/pass, win detection; emits signals
  the UI listens to. Also carries the layout moves: `move_cards_to_new_shape`
  (a new picture group on grid cells — the slime's ultimate plays through
  it), `play_off_picture` (the player's Scrabble-style line off a picture
  card, with the outward-only / one-per-axis / whole-line rules) and
  `stage_cross_meld`, the groundwork move (no card grants it in normal
  play yet) that stages a new group crossing an existing one at a shared
  pivot card — the pivot counts as a member of both groups, both must be
  valid at commit, and both can still take cards

### AI — `scripts/ai/`

- `scripts/ai/greedy_ai.gd` — `GreedyAI`: baseline opponent — plays complete melds from
  hand (with joker fallbacks), single- and two-card lay-offs, and simple table
  rearrangements (borrows one card from a group, when the leftover group stays
  valid, to complete a new meld with hand cards); picks safe joker stand-ins at
  higher skill; respects the opening rule; produces one move at a time so the
  UI can animate enemy turns. At the top skill tier it swaps the greedy search
  for a score-all-candidates "smart brain" that counts the deck, borrows up to
  two table cards at once to reach melds a single borrow can't, steals jokers,
  avoids feeding opponents, holds only cards the deck can still complete (never
  hoarding toward a dead end), and races the endgame. With a planning budget it
  also runs a deep-rearrangement planner: it pulls the table cards a new group
  needs into it alongside its hand cards, then repairs every group left broken
  (relocating the offending cards to a valid home, recursively) up to the
  budget — one board movement when short-sighted, three at the middle tier,
  effectively unlimited for an expert planner. On a glass table the
  counting is glass-aware: it reads only the public information (glass cards
  in hands, a glass stock top) — completions visibly locked in opponents'
  hands are dead ends, visibly held lay-offs are certain feeds, joker
  stand-ins an opponent holds the swap card for are avoided, and a glass next
  draw is worth holding a partner for
- `scripts/ai/ai_profile.gd` — `AIProfile`: the four personality dials GreedyAI
  consults — skill (search depth + the smart brain), style (opening threshold,
  key-card holding), attention (miss chance, capped at 30% and only on
  table-reading plays), planning (how many board relocations the deep planner
  may chain: 1 / 3 / unlimited); unset = strong + quick + attentive + no deep
  planning, and fully deterministic
- `scripts/ai/enemy.gd` — `Enemy`: a designed roguelike opponent — a name, an AI
  profile, an `on_combat_start` hook to plant mechanics, a `mechanic_intro`
  blurb for the game log, a `plan_strategy_move` hook GreedyAI consults once
  ordinary play is spent, and helpers to find its own deck's cards
  (`own_deck_id` / `all_dealt_cards`) so a mechanic corrupts only its own half;
  plus the roster the rogue ladder picks from at random (the Cute Slime and the
  Sadistic Billionaire)
- `scripts/ai/cute_slime.gd` — `CuteSlime`: the first designed enemy (strong,
  oblivious, quick). At combat start she slimes every card in her own deck (the
  Sticky effect) — one copy of each, so of the two copies of any card exactly one
  is sticky, and only her 2 of the 4 jokers; on
  her turns she legally combines slimed cards — oozing them next to the most
  valuable slimed card the player could still lift (weighting by versatility:
  jokers, then the flexible 4-8s), as much as helps while keeping every group
  valid with no leftover cards; she alone moves slimed cards freely. Once her
  ultimate meter fills, she gathers every slimed card she can legally take —
  her hand's, the table's free donations, and cards whose broken groups the
  repair engine can mend — into a heart picture group (14 cards) sealed on the
  felt, and her meter resets
- `scripts/ai/sadistic_billionaire.gd` — `SadisticBillionaire`: the second designed
  enemy (strong, conservative, attentive). At combat start he turns every card in
  his own deck — all 52 naturals and his 2 jokers — to glass (the Clear effect):
  one copy of each, so exactly half the cards in play go see-through from the
  back, visible in any player's hand and on top of the stock, rendered
  transparent. The information cuts both ways — the player reads his hand off his
  card backs, and the smart brain counts every glass card in its planning. His
  ultimate is the **Riichi**: with a full meter and a hand one card from laying
  itself down as its own melds (the `Tiling` solver over his hand alone — a
  self-contained wait the table can't disturb), he weighs the wait — counting
  winnable copies and, with his glass vision, refusing to declare into a wait
  whose copies are all visible in an opponent's hand — then freezes his hand,
  drains his meter, and every turn draws one card: a tsumo win if it completes
  his hand, else a face-up discard. An opponent who plays one of his wait cards
  onto the table hands him the win (ron), through `GameManager.play_interceptor`.
  Other AI opponents read those waits off his glass cards and fold rather than
  feed them (`GreedyAI._feeds_riichi`). To reach a tenpai hand at all he plays a
  hand-shaping strategy (`avoids_play`, consulted by the smart brain): he holds
  his developing melds and partials together, shedding only complete groups and
  floaters, rather than dumping his hand like the baseline AI

### UI — `scripts/ui/` + `scenes/`

- `scripts/ui/main_ui.gd` + `scenes/main.tscn` — `MainUI`, the table controller:
  owns the `GameManager`, builds the layout, drives selection, drag-and-drop and
  click-to-play, the opening-rule locking, the right-click joker menu, and the
  enemy-turn loop. Delegates look, rendering and self-contained regions to the
  helpers below.
- `scripts/ui/table_view.gd` — `TableView`: a passive view that renders the live
  table (opponent seats, the felt of meld panels + "New group" zone, and your
  hand's card buttons) into the controller's containers. Reads the controller's
  state and wires each button back to its handlers; holds no state itself.
- `scripts/ui/enemy_move_animator.gd` — `EnemyMoveAnimator`: flies enemy cards
  from where they were to where they land, so each AI move is visible.
- `scripts/ui/ui_theme.gd` — `UITheme`: shared visual constants (the felt/cards
  palette, card and seat sizes, the suit→colour map). One source of truth for
  how the game looks.
- `scripts/ui/card_renderer.gd` — `CardRenderer`: stateless builders for the
  visual atoms — card/panel styleboxes, card backs, glass faces, the slime
  splotch, the drag preview and the flying-card animation proxy.
- `scripts/ui/game_settings.gd` — `GameSettings`: every tunable rule for both
  modes plus its save/load and the per-enemy AI overrides; the model the
  settings dialog edits and `main_ui` reads at new-game.
- `scripts/ui/menu_screen.gd` + `scenes/ui/menu_screen.tscn` — `MenuScreen`: the
  title menu, emitting an intent signal per button.
- `scripts/ui/settings_dialog.gd` + `scenes/ui/settings_dialog.tscn` —
  `SettingsDialog`: the two-tab (Vanilla / Roguelike) settings pop-up bound to
  the `GameSettings` model.
- `tests/smoke_test.gd` — headless AI-vs-AI smoke test plus unit tests for the
  joker rules, the joker swap, joker stand-in choice, joker locking, the AI's
  safe stand-in picking, the hand cap, the slime's sticky clusters (cluster
  detection, cluster moves, the slime's free movement), the slime setup, her
  joker-guarding strategy, the billionaire's glass setup, and the AI's glass
  counting (visible copies, obtainable copies, glass feed threats, glass-aware
  holding and joker stand-ins) — including full slimed, glass, and
  glass-plus-slimed AI-vs-AI games
- `tests/tiling_check.gd` — headless check of the `Tiling` go-out solver: sets,
  runs (ace low, high and the no-wrap rule), joker fills, multi-meld piles, and
  the wait-set enumeration
- `tests/riichi_check.gd` — headless check of the Billionaire's Riichi: the
  discard-pile reshuffle, the declaration gate (full meter + a live wait, not an
  already-complete hand), dead-wait avoidance off glass information, the tsumo
  win, the face-up draw-and-discard turn, the ron via the commit interceptor, a
  rival folding rather than feeding the ron, and invariant-checked (validity,
  108-card conservation, termination) AI-vs-AI games
- `tests/ui_mode_check.gd` — headless check of the menu modes, the settings
  model, and the roguelike ladder (rules apply from the next round, win/loss
  buttons, starting combos)
- `tests/suit_filter_check.gd` — headless check of the suit highlighter (across
  both the hand and the table) and the table Sort/Randomize ordering
- `tests/play_hint_check.gd` — headless check of the hover-to-play hints: lay-off
  targets on the board, the new-group cue (natural groups only, joker-assisted
  plays disregarded), the opening-rule gate, and that both render their green
  spotlight; plus the double-click auto-play (the group a card completes,
  lay-off preferred over a fresh group, and a green card staying draggable)
- `tests/view_check.gd` — headless check of the table rendering and drag/drop:
  opponent seats, board meld panels, the "New group" zone, card-node
  registration and a new-group drop
- `tests/anim_check.gd` — headless check that an enemy turn drives to
  completion through `EnemyMoveAnimator` with no leaked flying-card proxies
- `tests/riichi_view_check.gd` — headless check that the Riichi UI renders: the
  face-up discard pile beside the stock and the RIICHI seat badge
- `tests/layout_check.gd` — headless check of the board-layout groundwork and
  the slime's ultimate: orientation and shape cells surviving snapshots,
  crossing groups (staging, validity, extending either group, undo, commit,
  shared-card removal), shape groups (the heart template, connectivity,
  line-through), BoardGrid cluster and adjacency math, the meter building live
  as cards are played, the ultimate (fires on a full meter with gatherable
  slime — including the turn the meter completes from that turn's own plays —
  seals a valid heart picture, resets the meter, holds when short, and fires
  inside full seeded AI-vs-AI games with every invariant intact), a picture
  card being movable the turn it is sealed but sealed shut thereafter, the
  Scrabble-style plays off pictures (the grid-line reading and its three-card
  minimum — a lone card is refused, run extension, outward-only and
  one-line-per-axis rules, whole-line tear-down, sealed picture cards, no
  jokers, commit, and the ghost play cells rendering), and the
  vertical/grid rendering paths

## Headless smoke test

```sh
godot --headless --path . --import                              # once, builds class cache
godot --headless --path . --script res://tests/smoke_test.gd    # unit tests + 65 seeded games
godot --headless --path . --script res://tests/ui_mode_check.gd    # menu modes + settings
godot --headless --path . --script res://tests/suit_filter_check.gd # suit highlighter + table sort
godot --headless --path . --script res://tests/play_hint_check.gd  # hover-to-play hints
godot --headless --path . --script res://tests/view_check.gd       # table rendering + drag/drop
godot --headless --path . --script res://tests/anim_check.gd       # enemy-turn animation
godot --headless --path . --script res://tests/layout_check.gd     # board-layout groundwork
godot --headless --path . --script res://tests/tiling_check.gd     # go-out / wait solver
godot --headless --path . --script res://tests/riichi_check.gd     # the Billionaire's Riichi
godot --headless --path . --script res://tests/riichi_view_check.gd # Riichi UI (discard pile, badge)
```

## Headless balance stats

```sh
godot --headless --path . --script res://tests/balance_stats.gd -- --games=50
```

Plays seeded 1v1 games — a simulated strong player against the basic enemy
(with and without jokers), the Cute Slime and the Sadistic Billionaire — and
prints the numbers the roguelike economy needs: game length in player rounds
(distribution + histogram, split into wins and losses) with suggested 3-tier
gold cutoffs from the rounds-to-win terciles, and how often the player plays
a hand vs draws (hands per game, cards per hand) for tuning ultimate-meter
charge rates (`tests/balance_stats.gd`). Add `--combo` to deal every player
a starting combo and measure how much it shortens games.

## Board layout groundwork

The table is growing past "a bag of horizontal lines". The groundwork for the
planned bizarre layouts is in — model, math, rendering and tests — with the
mechanics that will use it still to come:

- **Orientation** — every line group lies flat or stands upright
  (`CardSet.orientation`); vertical groups render as columns, and the ⟳
  control on each group toggles it. Validity never depends on direction.
- **Intersections** — a card can sit in a horizontal AND a vertical group at
  once, where they cross (`GameManager.stage_cross_meld`,
  `Board.melds_of` / `intersections`). Both groups must be valid at commit
  with the shared card counted in both, both can still take lay-offs, moves
  are undoable, and pulling the shared card off the table removes it from
  both. Crossings render as one grid panel. No card grants this in normal
  play yet — a future card mechanic will let its card be used in two
  combinations at the same time.
- **Shape ("picture") groups** — a group can place its cards on a small grid
  instead of in a line (`CardSet.set_shape`), valid when the picture is one
  connected patch. This is what the Cute Slime's ultimate builds (her heart
  template lives on `CuteSlime.ULT_HEART` — `ult_templates()` still walks a
  list so more shapes can be added back later; the engine move is
  `GameManager.move_cards_to_new_shape`). A picture's cards are sealed in
  place — except the turn they are sealed in, when they can still be lifted
  back off like anything else played that turn.
- **Scrabble-style plays off pictures** — any picture card can be played off
  in one direction, horizontal or vertical (`GameManager.play_off_picture`):
  the cards land in a straight line outward from that card, and together
  with it must read as a legal set or run on the grid — spatial order
  matters for runs (`Rules.is_valid_grid_line`), and counting the anchor a
  line is at least three cards, so a single card off a picture is refused
  (you play at least two at once). Lines extend outward
  only (they never hug the silhouette, so the picture always reads as
  drawn), take one line per picture card per axis, hold no jokers, brush a
  neighbouring line only where the touching pair could grow, and tear off
  whole or not at all. Ghost "+" cells around a picture are the drop/click
  targets. A played card connects in ONE direction only — sitting in two
  combinations at once stays reserved for the future layer-mechanic card
  (the crossing groundwork below).
- **Adjacency** — `BoardGrid` lays every connected patch of groups onto a
  local grid and answers `neighbors(card)`: cards directly horizontal or
  vertical to each other, the relation that will eventually make such
  neighbours a legal card play.

## Design notes / references

- The turn model is *staged*: moves mutate state immediately, `commit_turn()` is the
  only legality gate, `reset_turn()` rolls the whole turn back. Same as physical play.
- The AI's table rearrangement is bounded — it borrows at most two cards at a
  time (the top-tier smart brain), not the arbitrary multi-meld shuffles a
  human can do. A truly strong AI (and a "hint" feature)
  should use the ILP formulation from Den Hertog & Hulshof, *Solving Rummikub
  Problems by Integer Linear Programming* — see
  [cduck/machiavelli](https://github.com/cduck/machiavelli) (MIT) and
  [mjpieters/rummikub-solver](https://github.com/mjpieters/rummikub-solver) for
  reference implementations.

## Roguelike layer

Two designed enemies are in; the rogue ladder picks one at random each round
(enemies live in `scripts/ai/enemy.gd` + `cute_slime.gd` +
`sadistic_billionaire.gd`). Because every player brings their own deck and the
decks are only combined into the stock at combat start, each enemy corrupts just
*its own* deck — of the two copies of any card in play, only the enemy's is
touched, so only two of the four jokers ever carry a mechanic.

**The Cute Slime** brings the **Sticky** effect — slimed cards (a green
splotch, top right) stick to *each other*, so a run of them on the table moves
as one lump: dragging any one drags them all, and the leftover has to stay a
valid group. The slime slimes every card in her own deck at combat start — one
copy of each, so all 52 of her cards and her 2 jokers — moves her own slime
freely (`PlayerState.ignores_sticky`),
and runs a "slime strategy" that legally combines slimed cards to guard her
most valuable ones — oozing them next to the most valuable slimed card the
player could still lift, prizing versatility (jokers, then the flexible 4-8s),
as much as helps while keeping every group valid with no leftover cards. The
smart AI understands the slime and never plans a move that would drag a
cluster it didn't mean to.

Her **ultimate** rides the ultimate meter: when it fills and enough slimed
cards can be legally gathered, she squeezes them into a heart picture on the
felt (14 cards) and the meter resets. Because the meter builds live as she
plays, the ultimate can fire the very turn her plays complete the bar — and
she keeps acting afterward (guarding her slime) since the ult is a mechanic,
not the end of her turn. The slime comes from her own hand (naturals first,
her wildcard jokers last) and from the table: free donations whose groups stay
valid without them, plus cards whose broken groups the repair engine can
legally rearrange — mending the leftovers is part of the ultimate, so the
table is whole again when she is done. The picture is all slimed, so it moves
only as one lump nothing can legally absorb: those cards are sealed (only the
turn she squeezes them in can they still be lifted back off), and no planner
(not even hers) ever unpicks a settled picture. Until a picture fits, she
holds the full meter.

A sealed picture isn't dead felt, though — you can play off it,
Scrabble-style: any picture card takes a line of cards outward in one
direction, reading as a legal set or run together with it — at least three
cards counting that picture card, so you play at least two at once and a
lone card is refused. The faint "+" cells around the picture are the
targets; lines extend outward only and come off whole or not at all. See
"Board layout groundwork" for the exact rules.

**The Sadistic Billionaire** brings the **Clear** (glass) effect — glass cards
render transparent and are see-through from the back: everyone can see them
in any player's hand and on top of the stock. He turns every card in his own
deck to glass at combat start — all 52 naturals and his 2 jokers, one copy of
each, so exactly half the cards in play — so his hand shows most of its faces
in his seat, your hand leaks the same way, and a glass stock top telegraphs
the next draw to the whole table. The smart AI uses exactly that public
information — counting glass cards in every hand and reading a glass stock
top — to decide what to play and what to hold back: completions visibly
locked in an opponent's hand are dead ends it stops waiting for, lay-offs an
opponent visibly holds are feeds it avoids, joker stand-ins whose swap card
an opponent visibly holds are never picked, and a card that pairs with a
known upcoming draw is held. Glass is pure information — it never restricts
movement — so a card can be both glass and slimed.

His **ultimate** is the **Riichi**, borrowed from mahjong. When his meter fills
and his hand is *tenpai* — one card away from laying his whole hand down as its
own valid melds, computed by the `Tiling` solver over his hand alone — he may
declare. The wait is **self-contained in his hand**: the winning card completes
his own melds, so nobody rearranging the shared felt can change or break it (a
board-dependent wait would be unstable, and un-mahjong-like). To get there he
**plays for tenpai** instead of racing to empty out like the baseline AI: his
hand-shaping strategy hands his ordinary turn over to a shed policy
(`avoids_play` + `plan_strategy_move`) that keeps a chunk of about a hand-cap's
worth of cards — one he could actually lay down in a turn — trimming only the
excess: complete groups he already holds and lone floaters (cards with no
partner to build a group with), never a developing partial he is growing his
wait on. So a Riichi hand is always small enough to play out. First he weighs
whether declaring is worth it: he enumerates his waits and counts how many live copies
of each are still winnable, and, reading his own glass passive Washizu-style, he
**won't declare into a dead wait** — one whose only remaining copies he can see
locked in an opponent's hand, where he could neither draw it nor expect a smart
rival to feed it. On declaring, his hand **freezes** and his meter drains. From
then on every turn is a single draw: if it completes his hand he wins by
**tsumo**; otherwise he **discards it face up**, out of play until the stock runs
dry and the discard pile is shuffled back in. And if any opponent plays one of
his wait cards onto the table, he claims it and wins on the spot — his **ron**.
Because ron is fed by what opponents lay on the shared table, other AI opponents
play around it: reading his waits off his glass cards, a rival **folds** rather
than lay one (it still plays freely otherwise, and always takes its own winning
turn over folding), so in a multi-opponent game the ron isn't handed over for
free. Because his hand must be structured into near-complete melds, Riichi is —
as in mahjong — a special situation, not something he reaches every game.

Still kept as data stubs so the vanilla engine stays clean: the other card
effect flags on `Card` (Spiked, Brittle, Bomb, Clone, Trigger, Mirrored),
trigger stubs on `CardSet`, health/gold on `PlayerState`. Phantom-turn damage,
encounters, and the shared-deck-corruption idea live in the concept doc and git
history.
