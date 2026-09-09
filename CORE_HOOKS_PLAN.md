# Core hooks: telling the panel which keys are valid

Split out of `TOUCH_PANEL_PLAN.md` on 2026-09-09, from its section 4.6 and
step 3, which now point here. That file still owns the panel itself: the
regions, the pieces, the rose, the tabs, the slot model. This file owns one
thing, the patch to the game core that lets the panel know what the game is
asking for. The two are independent enough to be worked and landed
separately; section 3 below is the seam.

Written to be read cold. Line numbers into `../angbandroid` are pinned at
whatever that checkout is today and are meant as signposts, not as anything
to keep current. Follow the file's conventions: tick boxes in place, and
when something surprising happens add a dated line under the box rather than
editing what is already there.

## 1. Goal

The panel today shows the same keys whatever the game is doing. The game
always knows more than that. At "Drop which item?" only your inventory
letters mean anything. At "Are you sure? [y/n]" only `y` and `n`. In a menu,
only the tags of the rows that can actually be chosen.

The goal is that the core says so, and the panel shows it. Concretely, at an
item prompt the fast-keys strip fills with exactly the letters that will
work; at a confirmation the Enter and Backspace keys relabel to `y` and `n`;
at the character-name prompt the panel switches to its Keys tab.

This is the difference between a touch panel and an on-screen keyboard. It
is also the step where this branch starts diverging from upstream inside the
core rather than only in the frontend, so it is worth doing deliberately and
in a shape that could be offered upstream later.

## 2. Where this comes from

angbandroid (`../angbandroid`) has already solved this. The reusable part is
the C, not the Java.

- `app/src/main/cpp/curses/droid.h`: the API. `Term_control(int what, const
  char *msg)` with kinds `TERM_CONTROL_LIST_KEYS`, `_CONTEXT`,
  `_VISUAL_STATE`, `_SHOW_CURSOR`, `_DEBUG`, `_QUANTITY`; the convenience
  macro `Term_control_keys(msg)`; and the five buffer calls
  `soft_kbd_flash`, `_linger`, `_clear`, `_flush`, `_append`.
- `app/src/main/cpp/curses/droid.c`: the buffer. Small enough to read in one
  sitting; the semantics are in section 4.2 below.
- `app/src/main/cpp/angband/ui-menu.c` `keys_to_ui` (about line 759):
  collects a menu's selectable tags and flashes them. The one hook site that
  is real code rather than a one-liner.
- `app/src/main/cpp/angband/android_changes.txt`: the list of patched core
  files.

Only `LIST_KEYS` is in scope here. `CONTEXT`, `VISUAL_STATE`, `SHOW_CURSOR`
and `QUANTITY` exist in angbandroid for its own UI (it uses `QUANTITY` to
throw up a native number spinner, `VISUAL_STATE` for its tile picker) and are
not wanted. `${quant}` covers the quantity prompt for us as an ordinary key
list.

**Size of the job, measured 2026-09-09.** `TOUCH_PANEL_PLAN.md` section 2.4
says 79 hook sites. That is wrong: `grep -n soft_kbd_ *.c` in
`app/src/main/cpp/angband` gives **42**, all of them calls, spread as

| file | sites | file | sites |
| --- | --- | --- | --- |
| `ui-knowledge.c` | 13 | `ui-display.c` | 2 |
| `ui-input.c` | 9 | `ui-command.c` | 2 |
| `ui-birth.c` | 6 | `ui-player.c` | 1 |
| `ui-options.c` | 3 | `ui-mon-list.c` | 1 |
| `ui-target.c` | 2 | `ui-menu.c` | 1 |
| `player-util.c` | 1 | `game-input.c` | 1 |

Note the last two: `player-util.c` and `game-input.c` are not UI files. The
hook is not purely a UI-layer concern, which matters for how this would be
pitched upstream.

## 3. What this depends on, and what depends on it

From the panel side (`TOUCH_PANEL_PLAN.md`), this work needs:

- The panel exists and draws: done, step 2.
- A place to put the keys. The key stack's wide form already leaves three
  empty rows under the chrome for the fast-keys strip; the Keys tab exists
  and has its letters, symbols and numbers layers.
- A way to send a key: `push_key_event` (keycode plus modifiers) and
  `push_text_event` in `main-sdl2.c`. Panel section 4.7's mention of
  `send_sdl_keylike_event` is stale; that function is gone.

Nothing in the panel plan blocks on this except the fast-keys strip being
useful. Steps 4 (slots and seeding), 6 (iOS), 7 (editing) and 8 (publish)
over there do not need it. Step 4's `panel.txt` and this file's key lists are
independent: slots are commands the player picks, the strip is keys the game
is currently offering.

## 4. Design

### 4.1 The module

New `src/ui-panel.h` and `src/ui-panel.c`:

```c
#define UI_CTRL_LIST_KEYS 1

extern void (*ui_control_hook)(int what, const char *msg);

void ui_panel_keys_flash(const char *keys);
void ui_panel_keys_linger(const char *keys);
void ui_panel_keys_append(const char *keys);
void ui_panel_keys_clear(bool force);
void ui_panel_keys_flush(void);
```

`ui_control_hook` defaults to NULL. Names carry no trace of Android or of
SDL: the core must not know which frontend is listening.

Whether to keep angbandroid's `Term_control`-shaped single entry point with a
`what` argument, or to give the hook one job and drop `what`, is an open
question (section 5).

### 4.2 Buffer semantics

One static string buffer plus a `flashing` flag. Straight from `droid.c`:

- `flash(keys)` — append `keys`, remove duplicate characters, set
  `flashing = true`. These keys are valid until the next keypress.
- `linger(keys)` — the same append, then `flashing = false`. These keys
  survive keypresses; used where the game stays in a mode across several
  keys, as targeting does.
- `clear(force)` — if `flashing` or `force`, empty the buffer, set
  `flashing = true`, and send `${clear}`. So an ordinary clear leaves a
  lingering set alone and a forced clear tears it down.
- `flush()` — if the buffer is not empty, send it. Does not empty it.
- `append(keys)` — append without touching `flashing`.

The asymmetry between `flash` and `linger` is the whole design. Deposits
accumulate on the way to the prompt; `inkey_ex` flushes them just before it
blocks and clears them just after a key arrives, and a lingering set is what
survives that clear.

### 4.3 Token vocabulary

The buffer is mostly literal characters, but a `${...}` token asks the
frontend for a presentation instead of naming keys. The frontend decides what
that means; the core does not know what a button looks like.

| token | meaning | who emits it |
| --- | --- | --- |
| `${clear}` | forget everything, restore the default panel | `clear()` |
| `${yes_no}` | a confirmation: relabel Enter and Backspace to `y` and `n` | `get_check`, `player-util.c` |
| `${quant}` | a number prompt; digits and the usual editing keys | `get_quantity` |
| `${fkeys}` | the function keys F1..F12 | `ui-options.c` keymap entry |
| `${text}` | free text entry: switch to the Keys tab | `askfor_aux`, **new, ours** |

`${text}` does not exist in angbandroid, which has a system keyboard to fall
back on. We do not, so the panel has to take over.

Tokens and literal keys can appear in the same string:
`soft_kbd_linger("${quant}*")` in angbandroid's `get_quantity` means "a
number prompt, and also `*`".

### 4.4 Hook sites

`inkey_ex` in `ui-input.c` is the spine and the only site with real
sequencing: flush right before blocking, clear right after a key arrives.
Everything else just deposits into the buffer on the way there, so the
individual sites are one-liners and can land in batches.

Ordered by how much they are worth:

1. **`ui-input.c`** — `inkey_ex` flush and clear; `get_check` flashes
   `${yes_no}`; `get_char` flashes its own option string; `get_quantity`
   lingers `${quant}*`; `askfor_aux` flashes `${text}`.
2. **`ui-menu.c`** — `keys_to_ui`, called from the menu's input loop. Walks
   the rows, collects the tags of valid ones, and flashes them. This is the
   one that lights up inventory, spell and store prompts, so it earns its
   keep on its own.
3. **`ui-target.c`** — lingers `t*+-rpogmkq?`, force-clears on exit.
4. **The tail** — `ui-knowledge.c` (13 sites, the most of any file),
   `ui-birth.c`, `ui-options.c`, `ui-command.c`, `ui-display.c`,
   `ui-player.c`, `ui-mon-list.c`, `player-util.c`, `game-input.c`.

To find them: `grep -n soft_kbd_ ../angbandroid/app/src/main/cpp/angband/*.c`.
The two repositories' core files have drifted, so the sites transfer by hand,
not by patch.

### 4.5 Frontend consumer

`main-sdl2.c` sets `ui_control_hook` at init and does the work:

- Up to twelve keys go in the fast-keys strip as character-faced buttons.
- A longer list overflows into the top rows of the Keys tab and switches to
  it. (Whether that is the right behaviour is an open question, section 5.)
- `${yes_no}` relabels the Enter and Backspace chrome keys to `y` and `n`,
  as angbandroid's `rebuildTopFixed` does.
- `${text}` switches to the Keys tab.
- `${clear}` restores the strip and the chrome labels to their defaults.

Before any of that, a stderr consumer behind a `-m` subopt or an environment
variable, so the strings can be read at a prompt without the panel being
involved at all. That is what makes the first two boxes of the checklist
testable on their own.

### 4.6 Desktop builds

`ui_control_hook` stays NULL for every frontend but this one, and the
`ui_panel_keys_*` calls become a few instructions into a static buffer and a
NULL check. No behaviour change and no configuration to get wrong. This is
the property that makes the patch defensible; the verification checklist
should keep proving it.

## 5. Decisions and open questions

- [ ] **you decide:** more than twelve keys. Switch to the Keys tab with the
      list filling its top rows, or leave the strip in place and let it
      scroll? Switching is what angbandroid effectively does; scrolling keeps
      the tab you were on. Carried over from `TOUCH_PANEL_PLAN.md` step 3.
- [ ] **you decide:** hook shape. Keep angbandroid's `Term_control(what,
      msg)` with a `what` argument and one kind defined, which leaves room
      for later kinds and matches the reference implementation, or narrow it
      to `void (*ui_panel_keys_hook)(const char *keys)` now, which is honest
      about what it does and easier to defend upstream. (Raised 2026-09-09.)
- [ ] **you decide:** whether the lingering sets are worth their complexity
      for us. Targeting and `ui-command.c`'s repeat prompt are the only two
      that use `linger`. If the panel handles those modes some other way, the
      buffer loses its `flashing` flag and half its surface. Answer this
      after the first sites are in and you have seen it work. (Raised
      2026-09-09.)

## 6. Checklist

Legend as in `TOUCH_PANEL_PLAN.md`: `code` is implementation exercised on the
simulator before hand-off; `you decide` is a question only you can answer;
`you test` is a check by hand; `commit` is a landing point.

### Stage A. The module, with nothing hooked up

- [ ] code: `src/ui-panel.h` and `.c` with the buffer and the five calls,
      `ui_control_hook` defaulting to NULL, added to the build. Done when
      Angband builds and behaves exactly as before with nothing calling in.
- [ ] code: a stderr consumer behind a `-m` subopt or an environment
      variable, so the strings are readable without the panel.
- [ ] commit.

### Stage B. The sites that pay for themselves

- [ ] code: `ui-input.c` — `inkey_ex` flush and clear, `get_check`,
      `get_char`, `get_quantity`, `askfor_aux` `${text}`.
- [ ] code: `ui-menu.c` `keys_to_ui`.
- [ ] you test (simulator): with the stderr consumer on, the expected
      strings appear at an inventory prompt, a yes/no prompt and the
      character-name prompt.
- [ ] commit.

### Stage C. The frontend

- [ ] you decide: the more-than-twelve-keys question (section 5).
- [ ] code: frontend consumer in `main-sdl2.c` — fast-keys strip up to
      twelve, overflow behaviour per your answer, `${yes_no}` relabelling,
      `${text}` switching to Keys, `${clear}` restoring.
- [ ] you test (simulator): inventory letters appear at an item prompt; `y`
      and `n` at a confirmation; the Keys tab appears at the name prompt.
- [ ] commit.

### Stage D. The tail

- [ ] code: `ui-target.c`, `ui-command.c`, `ui-display.c`.
- [ ] code: `ui-knowledge.c`, `ui-birth.c`, `ui-options.c`, `ui-player.c`,
      `ui-mon-list.c`, `player-util.c`, `game-input.c`.
- [ ] you test (device): a session from birth to the first dungeon level
      using only the panel, with the strip watched at each prompt.
- [ ] commit.

### Stage E. The other two variants

- [ ] code: hand-merge the core side into `../NarSil_fork`. Its
      `ui-display.c`, `ui-game.c` and `ui-input.c` differ substantially from
      Angband's, so this is a hand-merge, not a cherry-pick.
- [ ] code: cherry-pick into `../FAangband_fork`, whose core is closer.
- [ ] you test: an item prompt, a confirmation and a text prompt in each.
- [ ] commit.

## 7. Verification

- Desktop and every non-SDL2 frontend: no behaviour change with the hook
  unset. This is the one that must not regress.
- The strip empties on `${clear}` and does not leak keys from the previous
  prompt into the next one.
- A lingering set survives the keypresses it should and is torn down by the
  force-clear that ends the mode; targeting is the case to watch.
- Keys offered by the strip actually work when pressed, under both keysets,
  and under NarSil's four keyset combinations.
- The hardware keyboard still works at every prompt that the panel now
  decorates.

## 8. Notes

- 2026-09-09: file created, from `TOUCH_PANEL_PLAN.md` section 4.6 and step
  3. The site count was corrected from 79 to 42 while writing it (section
  2), the `${text}` token and the stderr consumer were already ours rather
  than angbandroid's, and two design questions were added to section 5 that
  the original step 3 did not ask.
