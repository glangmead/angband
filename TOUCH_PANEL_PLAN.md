# Touch panel for the SDL2 frontend (iPad first)

Plan written 2026-09-08 from a design session, then revised the same day after
a review of the three repositories (sections 2.5, 2.6, 4.9, 5, 6, 7 and 8).
It is meant to be read cold by a new session working in this repository. Line
numbers refer to `sdl2-term-touch-keyboard` at commit `c1d4bb4c7` and are
pinned there on purpose: read them with `git show c1d4bb4c7:src/main-sdl2.c`
and do not update them as the branch moves. Step 0 was carried out the same
day; its results are in sections 2.6, 4.9, 5 and 7. The same plan applies
afterwards to `../FAangband_fork` and `../NarSil_fork`, which carry the same
branch and the same current keyboard hack.

## 1. Goal

The whole screen stays SDL. Term windows are laid out from fractional
"regions" that differ per orientation. One region is not a term: it is a
**panel** drawn by `main-sdl2.c` with its own toolkit, containing a compass
rose, a few fixed keys, and five tabs of buttons. The game core is patched to
tell the panel which keys are valid at the current prompt. No UIKit views, no
frameworks, one app per variant.

This replaces the current approach, where a term subwindow displays a grid of
characters that acts as a keyboard.

## 2. What exists today

### 2.1 This branch's iOS work

- Build: `CMakeLists.txt` IOS block, `src/cmake/toolchain/ios.toolchain.cmake`,
  `.github/workflows/ios.yaml`. SDL2, SDL_ttf, SDL_image come from FetchContent
  in `src/cmake/macros/SDL2_Frontend.cmake`. `src/main-uikit-sdl2.c` provides
  `SDL_UIKitRunApp`.
- Paths: on `__APPLE__` the user dir is `~/Documents` (`src/main.c`), and a
  new `ANGBAND_DIR_PLATFORM` (`src/init.c`) lets `lib/ios/` supply defaults:
  `sdl2init.txt`, `window.prf`, `customized_interface_options.txt`.
- Layout: `lib/ios/sdl2init.txt` holds absolute pixel rects tuned for the
  11 inch iPad Pro in landscape at 2x (2420 by 1668). Map on the left at 36
  point, keyboard term column on the right, two half-width subterms under the
  map, one full-width subterm at the bottom.
- HiDPI: `handle_last_resize_event` doubles the reported size when
  `SDL_WINDOW_ALLOW_HIGHDPI` is set; `start_window` sets that flag on Apple
  and calls `SDL_RenderSetLogicalSize` with the renderer output size.
- Keyboard hack to be removed once the panel works: `PW_TOUCH_KEYBOARD` in
  `src/ui-term.h`, `update_touch_keyboard_subwindow` in `src/ui-display.c`,
  `display_touch_keyboard` in `src/ui-input.c`, defaults in `src/ui-init.c`,
  `lib/help/keyboard_horiz.txt` and `keyboard_vert.txt`, and the term 1 flag in
  `lib/ios/window.prf`. Clicks on that term become synthetic SDL events in
  `send_sdl_keylike_event` (`src/main-sdl2.c:5861`). That function is reused
  by the panel.
  2026-09-09: removed, in the step 2d follow-up below. The panel does not
  in fact use `send_sdl_keylike_event`; it pushes events itself, so that
  function went too, along with `send_char_clicked_as_keystroke` on
  `struct term`, which existed only to feed it.
- Font: JuliaMono, which already has glyphs for Esc, Backspace, Space, Return,
  Tab and arrows.

### 2.2 Facts about `src/main-sdl2.c`

These facts hold for Angband and FAangband. NarSil's frontend predates the
toolkit; see section 2.5.

- Widget toolkit under `src/sdl2/` (`pui-ctrl.c`, `pui-dlg.c`, `pui-misc.c`,
  about 6,400 lines). Dialogs have a `pinned` flag (`pui-dlg.h:211`) meaning
  never auto-remove. Each control carries a function table with `render`,
  `handle_mouseclick`, `handle_mousemove` (`pui-ctrl.h:75`). New control types
  are registered at runtime with `sdlpui_register_code`. Built-in controls:
  image, label, push button, menu button, menu toggle, ranged int.
- Compositing: `render_all` (`:877`) draws subwindows, then the status bar,
  then dialogs. Mouse events are offered to dialogs first in
  `handle_mousebutton` (comment "Have a menu or dialog handle the event").
- Event loop: `get_event` (`:4591`) polls `SDL_PollEvent`; only `wait_anykey`
  uses `SDL_WaitEvent`. `TERM_XTRA_EVENT` handling is at `:4762`.
- Finger events are disabled at init (`:7193`), so touches arrive as mouse
  events. `SDL_StartTextInput` is called at `:7199`.
- Resize: `resize_window` (`:6057`) recomputes the status bar and inner rect,
  then only clamps each subwindow with `fit_subwindow_in_window` (`:6041`).
  Nothing re-lays out. `adjust_subwindow_geometry` (`:5689`) derives cols and
  rows from the font glyph size. Minimums: `MIN_COLS_MAIN 80`,
  `MIN_ROWS_MAIN 24`, others 12 by 3 (`:139`).
- Fonts: `load_font` (`:5546`), `reload_font(subwindow, ...)` (`:5516`),
  `make_font_cache` (`:5432`).
- Config: `parser_reg` calls near `:7999` define `window-*` and `subwindow-*`
  keys; value types are int, uint, sym, str (no float). `dump_config_file`
  near `:6400` writes them back on exit.
- There is an existing shortcut editor dialog (`SHORTCUT_EDITOR_CODE`). Check
  it before writing a new editor for panel slots.
- Redraw timing uses `window->next_redraw` and `SDL_GetTicks` (`:1011`).
  There is no key-repeat machinery.

### 2.3 Core command tables

`src/ui-game.c` defines `cmds_all` with groups `Items`, `Action commands`,
`Manage items`, `Information`, `Utility`, `Hidden`, plus debug groups. Each
`struct cmd_info` has a description, a key array, and a command or hook.

- Angband and FAangband: `key[2]`, index `OPT(player, rogue_like_commands)`
  (`ui-game.c:522`).
- NarSil: `key[4]`, index built from `angband_keyset` and roguelike options
  (`../NarSil_fork/src/ui-game.c:520`). Mirror whatever `textui_process_key`
  does there.

Where the variants differ (this is why slots reference commands, not keys):

| Command | Angband, FAangband | NarSil |
|---|---|---|
| Options | `=` | `O` (Sil keyset), `=` (Angband keyset) |
| Character sheet | `C` | `@` |
| Rest | `R` | `Z` |
| Fire at nearest | `h`, Tab in roguelike | `m` |
| Throw | `v` | `t` |
| Take off | `t` | `r` |
| Stand still | space | `z` |
| Alter | `+` | `/` |
| Center map | Ctrl-L | `C` |
| Tab | fire at nearest | abilities list |

NarSil-only commands: change song, toggle stealth, blow horn, smith, exchange
places, bash door. FAangband-only: change shape, move house, time of day.
Shift-Tab is bound to nothing in all three. Tab has no menu role in any of
them.

### 2.4 Reference implementations

- **angbandroid** (`../angbandroid`), the Android port. The reusable part is
  the core patch, not the Java:
  - `app/src/main/cpp/curses/droid.h`, `droid.c`: the `soft_kbd_*` buffer
    (flash, linger, clear, flush, append) and `Term_control` message kinds.
  - `app/src/main/cpp/angband/android_changes.txt`: list of patched core
    files. `grep -n soft_kbd_ app/src/main/cpp/angband/*.c` gives the 79 hook
    sites.
  - `app/src/main/cpp/angband/ui-menu.c` `keys_to_ui` (about line 780):
    collects a menu's valid tags and flashes them.
  - `app/src/main/cpp/angband/ui-input.c:1749` `feed_keymap`: turns a string
    into an `inkey_next` buffer so a multi-key button behaves like a keymap.
  - `app/src/main/cpp/common/angdroid.c` `process_special_command`: how the
    Java side sends `macro:` strings and how they reach `feed_keymap`.
  - Java, for UI ideas only: `ButtonRibbon.java` `setCommandMode` (default
    ribbon string `.iUmhfvngdR+ewb,azul[]C~LM=?`), `rebuildTopFixed` (Esc,
    Enter, Backspace become Esc, n, y in yes/no mode), `AdvKeyboard.java`
    `createPage0`/`createPage1`, `KeyBuffer.java` `addDirection`,
    `GameActivity.java` `setFastKeys`.
- **pocketzot** (`../pocketzot`), a DCSS touch client:
  - `src/game/input/control-sets.ts`: fixed chrome plus three swappable
    tabs; slot is literal text (1 to 3 chars) or a special key token;
    human-readable export format with `{Esc}` style tokens.
  - `src/game/input/touch.ts`: `DPAD_LAYOUT` with plain, shifted and
    ctrl variants per direction; `REPEAT_DELAY_MS 350`,
    `REPEAT_INTERVAL_MS 85`; sticky Shift (tap once, double tap locks, tap
    from lock clears), one-shot Ctrl.
- **Brogue** (`~/Downloads/brogue.png`, iBrogueCE on iPad): the compass rose
  model. Eight petals, four long on the cardinals and four short on the
  diagonals, faint outline, rounded-square center with a rest glyph, lifted
  well above the bottom edge. Bottom bar uses words, not letters. Copy the
  image into the repo if it should outlive Downloads.

### 2.5 The three variants' SDL2 frontends (checked 2026-09-08)

- Angband rewrote `main-sdl2.c` around the `sdlpui` toolkit in commit
  `d68863680` (2023-12-23, "SDL2: refactor event handling and change drawing
  for menu items"), four months after the 4.2.5 tag (2023-08-19).
- FAangband upstream took that rewrite. `../FAangband_fork/src/main-sdl2.c`
  differs from this repository's copy by about 155 diff lines and has the
  same `src/sdl2/` directory, plus an extra `SDL_uikit_main.c`. Porting to
  FAangband is a cherry-pick.
- NarSil upstream (`NickMcConnell/NarSil`) never took the rewrite. It has no
  `src/sdl2/` directory, and its `main-sdl2.c` is the 4.2.5-era file, within
  about 260 diff lines of Angband 4.2.5, with small fixes cherry-picked since,
  mostly by Eric Branlund. It uses the older `button_bank` and `menu_panel`
  structures. Nothing in that file is NarSil-specific.
- The `sdl2-term-touch-keyboard` branch in `../NarSil_fork` carries the same
  kind of changes as the other two: seven commits, about 140 lines in
  `main-sdl2.c`, the `lib/ios/` files, `main-uikit-sdl2.c`, the CMake and
  toolchain files. The difference between the variants is the base file, not
  that work.
- `../NarSil_fork` `main` is 124 commits behind upstream `main` (fetched
  2026-09-08). None of them touch `main-sdl2.c`. NarSil upstream did pick up
  Angband's CMake modernisation (Angband #6415 and #6420, December 2025), but
  those edit the SDL1 and GCU macros, not `SDL2_Frontend.cmake`, so they do
  not collide with the iOS changes.
- Static probe of Angband's toolkit frontend (`main-sdl2.c` plus
  `src/sdl2/*.c`) against NarSil's headers: every core header it includes
  exists in NarSil; of about 500 functions it calls, only `is_sound_inited`
  (`src/sound.h:87`, implemented at `src/sound-core.c:423` here) is
  undeclared in NarSil. `angband_term`, `ANGBAND_TERM_MAX`,
  `ANGBAND_DIR_PLATFORM`, the `graphics_modes` API, `Term_keypress`,
  `Term_mousepress`, `KTRL`, `KC_MOD_KEYPAD`, `KC_MOD_SHIFT`,
  `KC_MOD_CONTROL`, `inkey_next`, `PW_MAX_FLAGS` and `window_flag_desc` all
  exist in both. Struct field differences are the one thing a probe cannot
  see; a compile settles it.
- Conclusion: unify NarSil's frontend with Angband's before the panel reaches
  it, rather than writing the panel to work without the toolkit. Recipe in
  section 7. Decision 1 stands as written.
- Core-side divergence matters for the hooks step, not for the frontend:
  NarSil's `ui-display.c` differs from Angband's by about 1,700 diff lines,
  `ui-game.c` by about 400, `ui-input.c` by about 140. FAangband's differ by
  about 100, 30 and 40.

### 2.6 Build and repository state (2026-09-08, after step 0)

- All three variants build for macOS today, but those are Cocoa builds
  (`main-cocoa.m`). The panel is SDL2 code. Step 0 decided against a macOS
  SDL2 build in favour of the iPad simulator (section 4.9): the load-bearing
  questions are touch, HiDPI and orientation, and Homebrew's SDL2 is
  `sdl2-compat` over SDL3 rather than the SDL2 the iOS build fetches.
- Simulator builds work for Angband and NarSil with the existing toolchain
  using `PLATFORM=SIMULATORARM64`. `DEPLOYMENT_TARGET` must be passed on the
  configure command line for simulator builds: when it is undefined the
  toolchain excludes arm64 for the simulator SDK (`ios.toolchain.cmake:194`).
  The `set(DEPLOYMENT_TARGET ... CACHE)` line in the `if(IOS)` block of
  `CMakeLists.txt` is dead code, because the toolchain has already stored its
  own value as an INTERNAL cache entry by the time that line runs; the device
  build uses the toolchain default of 18.0 whatever the line says. The
  line has been deleted in Angband and NarSil; FAangband still has it.
- Bugs found and fixed in this repository during step 0 (committed):
  - `src/init.c` declared and freed `ANGBAND_DIR_PLATFORM` but never built
    it, so it was NULL and `lib/ios/sdl2init.txt`, `window.prf` and
    `customized_interface_options.txt` were never found. FAangband and
    NarSil have the `BUILD_DIRECTORY_PATH` line; Angband lost it in commit
    `4ffda767b`. The `.ipa` built from `sdl2-term-touch-keyboard` has this
    bug: the tuned layout only appears if a copy of `sdl2init.txt` already
    sits in the app's Documents folder.
  - `src/cmake/macros/SDL2_Frontend.cmake` had a stray
    `PKG_SEARCH_MODULE(SDL2 sdl2)` line inside the `FetchContent_Declare`
    for SDL_image, also from `4ffda767b`. CMake tolerated it silently.
    Removed.
- Bug observed, not fixed: the status bar's Menu dropdown is open when the
  app comes up, on every launch, in both Angband and NarSil. A tap anywhere
  closes it. Probably a spurious mouse-down at the origin during SDL's iOS
  startup. Confirmed on the iPad too (Angband, landscape, first launch), so
  it is real. Find and fix it in step 2a, where mouse routing gets
  attention anyway. 2026-09-09: fixed in step 2a (a spurious mouse
  motion to the origin, not a mouse-down; see the step 2a notes).
- iPadOS 26 orientation behaviour, seen on the simulator: an app that
  restricts itself to landscape is not rotated. With landscape-only
  `Info.plist` orientations (NarSil today) the landscape canvas is drawn
  scaled down and letterboxed inside the portrait screen; touches are
  transformed correctly. With the SDL orientation hint restricting to
  landscape at runtime (tested through the `SDL_IOS_ORIENTATIONS`
  environment variable) the app opens as a floating, resizable window. So
  the app must accept every orientation and lay out for whatever size it is
  given, which is what regions do. Treat the window size as arbitrary, not
  as one of two device sizes. On hardware (iPad Pro 11-inch M4, 2026-09-08)
  Angband, which now allows portrait, does rotate and receives a resize
  event. What it then draws is wrong for two reasons that step 1 fixes: the
  renderer's logical size is set once in `start_window` and never
  refreshed, so the old 2420 by 1668 logical space is scaled into a 1668 by
  1150 band in the middle of the portrait screen; and inside that space the
  absolute rects are only clamped. Screenshot:
  `~/Downloads/andband_rotated.png`.
- GitHub issues are disabled on `glangmead/angband`. Work is tracked in this
  file.
- Step 0 is committed on `sdl2-touch-panel` in this repository and in
  `../NarSil_fork` (2026-09-08): the fixes above, the `Info.plist` portrait
  change (a step 6 item done early), the workflow trigger, `gregsim.sh`,
  and this file; in NarSil the unified frontend (section 7).

## 3. Decisions (locked)

1. Whole screen is SDL. Panel drawn by `main-sdl2.c` with `sdlpui`.
2. Layout is fractional rects per orientation, resolved on start and resize.
3. Panel = fixed chrome + five tabs, four by four.
4. Chrome: compass rose, Escape, Enter, Backspace, Space, sticky Shift,
   sticky Ctrl, tab strip, fast-keys strip.
5. Rose: Brogue-style petals, cardinals larger, bottom-left, lifted 140
   points, fixed position for now. 2026-09-09: after seeing it, half the
   size (120 points across), petals drawn as 10 point outlines rather
   than fills, shaped as in Brogue (a cone from an apex near the centre
   to a semicircular cap); position by two-finger drag (step 2d).
6. Tabs: Act, Items, Info (seeded from `cmds_all`), Mine (user macros),
   Keys (full keyboard).
7. Slots reference commands by description, resolved to a key at press time
   for the active keyset. Literal text and special-key slots also exist.
8. Faces: words on the four themed tabs, characters on the Keys tab and in
   the fast-keys strip.
9. Modifier rule from pocketzot: tap once, double tap locks, tap from lock
   clears.
10. Repeat: 350 ms then every 85 ms, for the rose, arrows and Backspace.
    Commands fire once. 2026-09-09: 450 ms then every 120 ms, after the
    device test.
11. Tab and Shift-Tab are not chrome. Tab is an ordinary command that
    seeding places per variant.

## 4. Design

### 4.1 Layout regions

Config lines, values in per-mille of the window inner rect (below the status
bar), because the parser has no float type:

```
region:<name>:<orient>:<x>:<y>:<w>:<h>
```

`name` is `map` (subwindow 0), `sub1` to `sub7` (subwindow index), or
`panel`. `orient` is `portrait`, `landscape`, or `any`. If any region line
matches the current orientation, regions win over `subwindow-full-rect`.

Resolver `resolve_layout(window)`:

- Called from `start_window` once the inner rect is known, and from
  `handle_last_resize_event` instead of the clamp-only path.
- Orientation is `w > h`.
- For each region: set `subwindow->full_rect`, then
  `adjust_subwindow_geometry`.
- Map font fits: try sizes from `subwindow-font-max` down to
  `subwindow-font-min` with `reload_font` until cols >= 80 and rows >= 24.
  Other subterms use their fixed `subwindow-font`.
- Panel rect is stored on the window for section 4.2.
- `dump_config_file` writes region lines back.
- Compute `ui_scale = renderer_output_w / window_w` once in `start_window`.
  On iOS it is 2. Point values like the 140 point lift and 44 point minimum
  touch targets are multiplied by it.

Proposed defaults for `lib/ios/sdl2init.txt`, derived from the current tuned
landscape file (inner rect excludes the 42 px status bar):

```
region:map:landscape:0:0:760:645
region:sub2:landscape:0:645:380:178
region:sub3:landscape:380:645:380:178
region:sub4:landscape:0:823:760:177
region:panel:landscape:760:0:240:1000

region:map:portrait:0:0:1000:520
region:sub2:portrait:0:520:500:160
region:sub3:portrait:500:520:500:160
region:panel:portrait:0:680:1000:320
```

Portrait on the 11 inch gives a map font around 32 point at 80 columns.
Whether `sub4` (messages) fits in portrait is a tuning question; it can take
a slice of the map region if wanted.

### 4.2 Panel structure

- One pinned `sdlpui` dialog sized to the panel region, no border, alpha from
  a `panel-alpha` config line. Rendered by the existing dialog pass in
  `render_all`. Mouse reaches it through the existing dialog branch in
  `handle_mousebutton`. `get_subwindow_by_xy` must not claim the panel area.
- Chrome, always visible:
  - Compass rose (section 4.5) at bottom-left of the panel region, its bottom
    edge lifted 140 points.
  - Escape, Enter, Backspace, Space.
  - Shift, Ctrl: sticky per decision 9. Shift affects the rose (run), letters
    on the Keys tab, and shifted symbols. Ctrl affects the rose (alter) and
    letters (KTRL).
  - Tab strip with five labels.
  - Fast-keys strip fed by the core hook (section 4.6). When the core signals
    a yes/no prompt, the Enter and Backspace slots show `y` and `n` instead,
    as angbandroid does.
- Tabs: Act, Items, Info, Mine are four by four grids of word-faced buttons.
  Keys is a denser character grid: letters layer and symbols layer toggled by
  a button, plus arrows and F1 to F12.
- Landscape: the panel is a column. Rose at the bottom, tabs above it.
  Portrait: the panel is a band. Rose at the left, tabs to its right.
- A new control type `panel_key` (label, action, repeat flag, pressed state,
  face font) and a `panel_rose` type. Register both with
  `sdlpui_register_code`.
- Repeat: record press time in the control's mouse-down handler; the main
  loop calls a `panel_tick` that re-fires held repeatable controls on the
  350/85 ms schedule using `SDL_GetTicks`. Release or focus loss cancels.

### 4.3 Slot model and `panel.txt`

Per variant: shipped default `lib/customize/panel.txt`, user override
`<user dir>/panel.txt` searched first (same lookup order as the current
`keyboard_*.txt` files).

```
panel-version:1
tab:Act
row:[Rest for a while]  [Look around]  [Fire at nearest target]  [Throw an item]
row:[Dig a tunnel]  [Alter a grid]  [Disarm a trap or lock a door]  [Open a door or a chest]
row:[Close a door]  [Go up staircase]  [Go down staircase]  [Pick up objects]
row:[Drop an item]  [Walk into a trap]  [Stand still]  [Repeat previous command]
tab:Mine
row:"za."=Zap  {}  {}  {}
```

Token grammar, whitespace separated within a `row:` line:

- `[Description]`: command reference. Matched against `cmd_info.desc` across
  the non-hidden groups. Resolved to a key for the active keyset at press
  time. Unknown descriptions render as a disabled slot rather than failing.
- `"text"`: literal text, one to three characters, sent through
  `feed_keymap`.
- `{Esc}` `{Ent}` `{BS}` `{Sp}` `{Tab}` `{Up}` `{Down}` `{Left}` `{Right}`
  `{F1}` to `{F12}` `{^A}` to `{^Z}`: special keys.
- `{}`: empty slot.
- Optional `=Face` suffix overrides the face on any token.

Faces: the face table in section 4.4, else the `=Face` override, else the
first word of the description. The Keys tab and the fast-keys strip always
show characters.

### 4.4 Seeding from the command table

Run once when no `panel.txt` exists in either location, and on demand from
a menu item. Output is a complete `panel.txt` the user can edit.

- Walk `cmds_all`, skip `Hidden` and debug groups, skip commands whose key is
  zero for every keyset.
- Group to tab: `Action commands` to Act; `Items` and `Manage items` to
  Items; `Information` and `Utility` to Info.
- The first 16 in table order fill the grid. The rest are written as
  commented rows so the user can swap them in.
- Mine starts empty. Keys is not seeded; it is fixed.
- Face table, keyed by description, shared across variants. Initial entries:
  Rest, Look, Fire, Throw, Tunnel, Alter, Disarm, Open, Close, Up, Down,
  Pickup, Drop, Trap, Run, Explore, Stay, Repeat, Inven, Equip, Quiver,
  Wield, TakeOff, Quaff, Read, Eat, Fuel, Cast, Aim, Use, Zap, Activate,
  Browse, Study, Inscribe, Uninscr, Ignore, Examine, Map, Locate, Monsters,
  Items, Char, Know, Feeling, Msgs, Options, Help, Symbol, Notes, Retire,
  Save. NarSil additions: Song, Stealth, Horn, Smith, Swap, Bash, Abilities.
  Unknown descriptions fall back to the first word.
- Because resolution happens at press time, changing keyset options never
  requires re-seeding.

### 4.5 Compass rose

- Geometry, radius R from the panel's short side: cardinal petals reach 1.0 R
  and own a 54 degree window; diagonal petals reach 0.7 R and own a 36 degree
  window; center is a rounded square of side 0.45 R, hit within 0.3 R.
- Rendering: `SDL_RenderGeometry` for petal fills, or a pre-rendered texture
  per state. Ghosted outline at low alpha; the pressed petal fills solid.
  Center shows the face of its command.
- Behaviour: tap steps; hold repeats; sliding while held changes the active
  petal without lifting (SDL delivers motion during a press). Shift makes it
  run, Ctrl makes it alter. Center runs the `Stand still` command by
  reference. Long press on center is reserved for a run-mode toggle later.
- Emission: send what a physical keypad sends, a digit keycode with
  `KC_MOD_KEYPAD`, plus `KC_MOD_SHIFT` for run or `KC_MOD_CONTROL` for alter.
  Verify in `textui_process_key` that keypad digits with those modifiers map
  to run and alter in all three variants; otherwise fall back to the
  variant's run and alter command prefixes.
- Position: bottom-left of the panel region, bottom edge lifted 140 points
  times `ui_scale`. Fixed for now; a preference later.

### 4.6 Core to panel hooks

Port the angbandroid patch, renamed so nothing says Android:

- New `src/ui-panel.h` and `src/ui-panel.c`: the `soft_kbd_*` buffer from
  `droid.c`, and `extern void (*ui_control_hook)(int what, const char *msg)`
  defaulting to NULL. Message kinds: `UI_CTRL_LIST_KEYS` with a key string or
  `${clear}`, and tokens `${yes_no}`, `${quant}`, `${fkeys}`, plus a new
  `${text}` emitted by `askfor_aux` so the panel can switch to the Keys tab
  during string entry.
- Hook sites: follow `grep -n soft_kbd_ ../angbandroid/app/src/main/cpp/angband/*.c`.
  The important ones: `inkey_ex` flushes right before blocking and clears
  after a key; `get_check` flashes `${yes_no}`; `get_char` flashes its
  options; `get_quantity` lingers `${quant}*`; `ui-menu.c` gets
  `keys_to_ui`; targeting lingers `t*+-rpogmkq?`; birth, knowledge, options,
  player sheet, monster list and command menus flash their keys.
- Frontend implementation of the hook: update the fast-keys strip (up to
  twelve character buttons; longer lists fill the top rows of the Keys tab and
  switch to it), relabel Enter and Backspace for `${yes_no}`, switch to Keys
  for `${text}`, restore on `${clear}`.
- Desktop builds without the panel leave the pointer NULL and compile
  unchanged.

### 4.7 Panel to core input path

- Special keys and single characters: `send_sdl_keylike_event`, extended to
  carry modifiers.
- Command references: resolve, then the same path.
- Literal multi-character text: port `feed_keymap` from angbandroid
  `ui-input.c:1749`, then push one harmless event so the poll loop wakes.
  This preserves the core's more-prompt handling for keymaps.
- Rose: keypad digit events with modifiers, per section 4.5.

### 4.8 iOS specifics

- Call `SDL_SetHint(SDL_HINT_ENABLE_SCREEN_KEYBOARD, "0")` before
  `SDL_StartTextInput` at `:7199` on iOS, or UIKit shows the system keyboard.
- Remove the `PW_TOUCH_KEYBOARD` hack listed in section 2.1 once the panel
  can play a full turn. Term 1 becomes free for messages.
- Replace the pixel rects in `lib/ios/sdl2init.txt` with region lines.
- `os/ios/Info.plist`: allow both orientations on iPad.
- Minimum touch target 44 points times `ui_scale`.

### 4.9 Simulator development loop

Decided in step 0: no macOS SDL2 build. The panel is developed on the iPad
simulator, where touches arrive as mouse events exactly as on the device.

- Simulator: iPad Pro 11-inch (M5), iOS 26.5, udid
  `1EF4F5CD-E295-4DB7-9427-00B9B0A3913C`; a 13-inch M5 on the same runtime
  exists for the second size. Screen is 1668 by 2420 pixels, 834 by 1210
  points, scale 2.
- Hardware: "Greg's iPad", an iPad Pro 11-inch (M4) with the same screen,
  listed by `xcrun devicectl list devices` when paired. Install path:
  `bash ./gregcmake2.sh`, then `cd build && cpack -G ZIP -C RelWithDebInfo`,
  then drag `build/Angband.ipa` onto Sideloadly. The GitHub workflow builds
  the same `.ipa` as an artifact. After an Xcode update, delete
  `build/CMakeCache.txt` and `build/CMakeFiles` first, because the toolchain
  caches the SDK path; keep `build/_deps`, which the simulator builds reuse.
  For a clean-install test, delete the app or remove `sdl2init.txt` from its
  Documents folder in Files, or the layout comes from that file.
- `./gregsim.sh` in each repository configures (first run), builds, installs
  and launches; `./gregsim.sh shot out.png` screenshots. It reads the app
  name from `CMakeLists.txt` and reuses the SDL sources already fetched into
  `../angband/build/_deps`. Configure takes about four minutes the first
  time (SDL's feature checks); an incremental rebuild after a one-file change
  takes well under a minute.
- Input from the command line: `idb ui tap X Y --udid ...` in points, and
  `idb ui key <HID code>` for hardware keys (Return 40, Escape 41, Right 79,
  Left 80, Down 81, Up 82). Both reach the game; a turn was played this way
  in both variants. `idb ui text` types strings.
- Rotation: `simctl` cannot rotate. `./gregsim.sh rotate` clicks the
  Simulator's Device menu through System Events, which needs Accessibility
  permission for the process running the script. claude.app has it as of
  2026-09-08 and the click works. Once, a `simctl io screenshot` issued right
  after a rotation hung until killed, so wait a few seconds after rotating.
- Console: `xcrun simctl launch --console` streams stdout and stderr. The
  frontend is silent about config loading, so add a `plog` when debugging
  paths.
- A `panel` config line still makes sense so the panel can be turned off;
  the desktop-only toggle from the first draft is no longer needed.
- Learned during step 1 (2026-09-08):
  - The user config is `Documents/Angband/sdl2init.txt` inside the app's
    data container (`PRIVATE_USER_PATH` makes the user dir
    `Documents/<VERSION_NAME>`), not `Documents/`. A file there overrides
    the bundled one, so it is the quickest way to try a layout without a
    rebuild. `xcrun simctl get_app_container <udid> org.rephial.Angband
    data` gives the container, and the path changes on every
    `simctl install`, so query it after installing.
  - On the simulator the app bundle is writable, so a normal quit writes
    the config into the bundle's own `lib/ios/sdl2init.txt` (the first
    path tried) instead of `Documents/Angband/`. `simctl install`
    replaces it. `simctl terminate` kills without writing.
  - The Menu dropdown that is open at launch has keyboard focus: `idb ui
    key` presses go into it (a run of Returns changed the map font).
    Tap once anywhere first to close it, then send keys.
  - Simulator rotation: from portrait, "Rotate Left" gives landscape;
    from that landscape, "Rotate Right" gives portrait and "Rotate Left"
    gives upside-down portrait, which the app does not support.
    `./gregsim.sh rotate right` exists now. The menu click sometimes does
    nothing; check the screenshot size (`sips -g pixelWidth`) and retry.
  - Twice, rotating to landscape after a portrait launch put the app in
    an iPadOS 26 floating window: SDL still reported 2420 by 1626 and the
    canvas was drawn scaled down inside the window. A third run of the
    same sequence stayed full screen. Portrait was always full screen.
    `UIRequiresFullScreen` in `Info.plist` is the likely lever if this
    matters; see the step 1 "you test" box.
  - The frontend logs every layout with `SDL_Log` (window size and
    scale, each subwindow's rect, font size and cells), visible with
    `xcrun simctl launch --console`.
  - Rotation and keystrokes through System Events need the Mac unlocked:
    with the screen locked (`CGSSessionScreenIsLocked` in
    `CGSessionCopyCurrentDictionary()`), the Simulator's menu items are
    disabled and the clicks do nothing, while `simctl` and `idb` keep
    working. A headless stand-in for a rotation is the status bar's Size
    button plus `idb ui swipe` on a term: it takes the same
    `resize_subwindow` path. With a crash that the game's own handler
    catches ("Exiting on signal 11"), no report is written; attach
    `lldb -p <pid> --batch -o "process continue" -o "bt 30"` before
    reproducing to get a backtrace.
  - Learned during step 2a (2026-09-09):
    - A few `SDL_Log` lines in `get_event`, printing each event's type,
      coordinates and device for the first minute, show exactly what the
      simulator delivers; that is how the Menu bug was found. A touch
      arrives as a motion, a button down and a button up, all with
      `which` set to the touch id (4294967295).
    - Once, before the panel existed, a tap on the map with the Menu
      dropdown open was followed by an `SDL_TEXTINPUT` of a single
      space. Not seen since. If it recurs, suspect SDL's hidden text
      field on iOS; the step 6 screen keyboard hint is the place to look.
    - CMake bakes `os/ios/Info.plist` into the Xcode project at
      configure time; after editing it run `cmake build-sim` before
      `cmake --build`, or the bundle keeps the old plist.
    - The Mac stayed locked all session, so every check used `idb`
      taps and the console; no scripted rotation was possible.

## 5. Implementation steps

Rewritten 2026-09-08 (evening) as a checklist. Legend for each box:

- `code`: implementation, exercised on the simulator with `idb` before
  hand-off.
- `you decide`: a question only you can answer; items after it that depend
  on the answer wait for it.
- `you test`: a check by hand, on the simulator or the device.
- `commit`: a landing point.

Tick boxes in place. When something surprising happens, add a dated line
under the step rather than editing history. Each step still ends in a state
that runs on the simulator. Step numbers match the rest of this file.

**Status 2026-09-09:** step 0 complete. Step 1 done, tested on the
simulator and the iPad, committed in this repository and cherry-picked to
NarSil and FAangband; the portrait split decision is deferred until the
panel exists. Step 2a and 2b done and tested by you. Step 2c (repeat)
and the step 5 rose code done, tested on the simulator and the iPad,
and committed here. You have asked for movable panel pieces (two-finger
drag, as in Brogue) before any layout or size decision: step 2d, with
the design in section 8. Step 2d: the split into pieces and the piece
regions are done and tested on the simulator; the two-finger drag is
built and waits for your hand test (`idb` has one finger). Nothing from
2d is committed yet; its commit box follows your test and decision.
Next: your 2d test, then step 3.
2026-09-09, evening: your 2d tests passed (third round: drag
performance on the iPad "great"); you chose candidate 2 for the strip
layout. Nothing from 2d is committed yet. The session ended with a
list of to-dos and questions under step 2d ("Next session") and two
TBD discussion items in section 8. Committed 2026-09-09.
2026-09-09, later: the three code boxes of that list are done --
candidate 2 is the shipped default, the rose is 156 points with a 9
point outline, and the touch keyboard hack is gone from Angband. Both
orientations were exercised on the simulator and a saved game plays in
portrait. What is left before step 3 is yours: the blank-term question
and the device test.

### Step 0. Prerequisites

- [x] code: branch `sdl2-touch-panel` in this repository and `../NarSil_fork`.
- [x] code: simulator configure and build for Angband; `gregsim.sh`.
- [x] code: `init.c` `ANGBAND_DIR_PLATFORM` fix; stray cmake line removed.
- [x] code: NarSil frontend unified (section 7); simulator build.
- [x] test: a turn played in both from `idb` taps and keys.
- [x] you decide: delete the dead `DEPLOYMENT_TARGET` line in
      `CMakeLists.txt`, or leave it. Deleted, in Angband and NarSil.
- [x] you decide: grant Accessibility permission to the terminal so scripts
      can rotate the simulator, or rotate by hand for the rest of the
      project. Granted to claude.app; scripted rotation works (section 4.9).
- [x] you test: run `./gregsim.sh` in both repositories from your own shell
      once, so the loop is known to work outside this session (idb
      companion, simulator boot). Both built and launched.
- [x] commit (angband): `init.c` and cmake macro fixes; `gregsim.sh` and
      this file; `Info.plist` orientations. The dead `DEPLOYMENT_TARGET`
      line went with the cmake fixes.
- [x] commit (NarSil): the unification as one commit.
- [x] code: point `.github/workflows/ios.yaml` at `sdl2-touch-panel` (it
      still triggers on `sdl2-term-touch-keyboard`), or add the branch.
      Added in Angband and NarSil; FAangband when it gets the branch
      (done 2026-09-09 with the step 1 port).
- [x] you test (device; optional now, required before step 6): install the
      fixed Angband build on the iPad; confirm the tuned layout appears on
      a clean install; note whether the Menu dropdown is open at launch on
      hardware. Done on the iPad Pro 11-inch (M4): landscape layout correct
      (`~/Downloads/angband_landscape.png`); NarSil plays a turn by touch
      and its toolkit Menu works; the Menu dropdown is open at first launch
      on hardware as well.
      Rotating to portrait redrew the terms in the wrong places
      (`~/Downloads/andband_rotated.png`, filename sic); see section 2.6 and
      the logical-size item in step 1.

### Step 1. Regions

- [x] code: `region:<name>:<orient>:<x>:<y>:<w>:<h>` parser line
      (per-mille), stored on the window config as a small array; unknown
      names rejected with a parse error like the other keys. Done when a
      file with region lines loads without complaint and nothing else
      changes. 2026-09-08: regions bind to window 0 and need its
      `window-display` line first; the C struct is `layout_region` because
      `ui-output.h` already owns `struct region`. Verified on the
      simulator: the landscape layout is unchanged with region lines
      present, a region line before the window header reports "missing
      record header", `region:bogus:...` reports "invalid value". The
      user config on iOS lives in `Documents/Angband/sdl2init.txt`
      (`PRIVATE_USER_PATH`), not `Documents/`.
- [x] code: `resolve_layout(window)`: pick the regions for the current
      orientation (`w > h`), set each named subwindow's `full_rect`, call
      `adjust_subwindow_geometry`, store the panel rect. Called from
      `start_window` and from `handle_last_resize_event` in place of the
      clamp-only path. Subwindows with no region keep today's behaviour.
      While there, fix the `|` that should be `&` on the HiDPI check in
      `handle_last_resize_event`. Done when a portrait launch shows a
      portrait layout. 2026-09-08: done. `resolve_layout` serves the
      resize path (`resize_window`); at start-up `load_subwindow` applies
      the region itself because the term does not exist yet, and
      `start_window` only resolves the panel rect. `start_window` now also
      takes the window size from the renderer instead of the config, which
      is what made a portrait launch lay out as 2420 wide before. A region
      too small for its subwindow's minimum grows to the minimum and shows
      the error border instead of aborting (`ensure_minimum_rect`); the
      first portrait launch hit that abort. The HiDPI flag test is gone
      rather than fixed: the resize path now asks the renderer for its
      output size, which is right with or without HiDPI. The keyboard term
      only redrew on `EVENT_INITSTATUS`, so after a rotation it kept its
      old layout; it is now also registered on `EVENT_INPUT_FLUSH`, which
      `do_cmd_redraw` signals when the core sees the main term's resize.
      Layout is logged with `SDL_Log` for `simctl launch --console`.
- [x] code: on resize, refresh `SDL_RenderSetLogicalSize` to the new
      renderer output size (or drop the logical size and use the output
      size directly) before re-laying out. Today it is set once in
      `start_window`; the rotated-device screenshot in section 2.6 shows the
      consequence. Done when a rotation on the device fills the screen.
      2026-09-08: refreshed in `handle_last_resize_event`; on the simulator
      a rotation fills the screen in both directions. The device check is
      in the "you test (device)" box below.
- [x] code: map font fit: new `subwindow-font-max` and `subwindow-font-min`
      keys; try sizes downward with `reload_font` until cols >= 80 and rows
      >= 24. Done when the portrait map is 80 by 24 at the largest size that
      fits and landscape is unchanged. 2026-09-08: done, but not with
      `reload_font`, which needs a live term and resizes the rect to the
      font; `fit_font_size` measures candidate sizes with `TTF_OpenFont`
      alone (no glyph cache) and the chosen size goes through the normal
      font load. With `48` and `16` on the 11 inch: landscape stays at 36
      (82 by 24), portrait fits at 34 (82 by 30).
- [x] code: `dump_config_file` writes region lines and the font range back;
      a relaunch reproduces the layout. 2026-09-08: verified by quitting
      from the status bar Menu in portrait and relaunching. Note for
      simulator work: the app bundle is writable there, so the dump goes
      into the bundle's own `lib/ios/sdl2init.txt` (the first path
      `init_globals` tries) rather than `Documents/Angband/`; each
      `simctl install` replaces it. On a device the bundle is read-only
      and the fallback path is used.
- [x] code: `ui_scale` computed once in `start_window`. 2026-09-08: stored
      on the window (`window->ui_scale`), 2.00 on the simulator.
- [x] code: `lib/ios/sdl2init.txt` for Angband rewritten with the section
      4.1 region defaults, keeping the keyboard term as `sub1` for now so
      the game stays playable by touch until step 6. 2026-09-08: done,
      with comments (the parser skips `#` lines). `sub1` takes the
      panel's region in both orientations and the `panel` lines are there
      too, so the panel rect is already resolved for step 2. The absolute
      `subwindow-full-rect` lines stay as fallbacks. Both orientations
      launch and rotate on the simulator; in portrait `sub4` (monster
      recall, not messages: see `window.prf`) has no region in the 4.1
      defaults and sits at its clamped landscape rect with the error
      border, which is the next box's question.
- [ ] you decide: the portrait split. Does `sub4` (messages) get a slice of
      the map region? What fraction goes to the panel band? Two candidate
      files can be prepared for you to compare on the simulator.
      2026-09-08: `sub4` is monster recall today (`window.prf`), not
      messages; messages get a term in step 6. Two complete config files
      sit untracked in the repository root, differing only in their
      portrait lines; screenshots of both at the birth screen, with term
      borders turned on for the comparison, are
      `~/Downloads/step1_portrait_A.png` and `step1_portrait_B.png`
      (`step1_portrait_default.png` shows the 4.1 defaults with `sub4`
      left at its landscape rect; `step1_landscape_borders.png` the
      landscape layout). Scripted birth through `idb` dropped keys, so
      in-town shots are quicker by hand:
      - `sdl2init.portraitA.txt`: recall takes a slice of the map. Map
        `0:0:1000:420` (24 rows at 34 point), recall `0:420:1000:100`
        (6 rows), monsters and items `0:520:500:160` and `500:520:500:160`
        (10 rows, 45 columns), panel band `0:680:1000:320` (761 px).
      - `sdl2init.portraitB.txt`: map keeps `0:0:1000:520` (30 rows);
        monsters, items and recall share a taller band as three columns
        `0:520:333:200`, `333:520:334:200`, `667:520:333:200` (12 rows,
        30 columns each); panel band `0:720:1000:280` (666 px, still 9
        rows of the 59 point keyboard).
      To try one: copy it over `lib/ios/sdl2init.txt` and `./gregsim.sh`,
      or drop it into the app's `Documents/Angband/` (section 4.9). The
      chosen file replaces the portrait lines in `lib/ios/sdl2init.txt`
      before the commit. 2026-09-09: deferred. The layout decision waits
      until the panel exists; the 4.1 defaults stay in
      `lib/ios/sdl2init.txt` and the two candidate files stay untracked.
- [x] you test (simulator): rotate by hand while the game runs; both
      orientations re-lay out without a restart; the keyboard term is
      visible in both; the map never drops below 80 by 24. Also try the
      iPadOS 26 floating window if the simulator offers it, and resize it.
      Passed 2026-09-09; the keyboard redraw fix below confirmed by hand.
      2026-09-08 notes: scripted rotation passes in both directions (map
      82 by 24 landscape, 82 by 30 portrait). The keyboard term redraws
      its layout after a rotation only once the game processes input
      (`EVENT_INPUT_FLUSH`), so on the splash screen it shows the old
      layout until a key is pressed. The floating window appeared twice
      out of three portrait-launch-then-landscape runs (section 4.9): the
      app is drawn scaled inside it and SDL still reports the full
      screen, so nothing re-lays out. Decide whether to drop
      `UIRequiresFullScreen` from `os/ios/Info.plist` so iPadOS resizes
      the window instead of scaling it; regions would then apply.
      2026-09-09, by hand: rotation worked, mouse and hardware keyboard
      both worked. The keyboard term kept its old layout after a rotation
      until something in the game redrew it. Fixed: `refresh_angband_terms`
      (called after every term resize) now signals `EVENT_REFRESH` in any
      state after init, and the keyboard term listens to it, redrawing
      only when its size changed and clearing first (the original NarSil
      commit used `EVENT_INPUT_FLUSH`, which only fires in play).
      Exercised on the simulator through the status bar's Size button and
      an `idb ui swipe`, which takes the same `resize_subwindow` path as a
      rotation: the term redrew at once with the layout for its new size.
      That test also caught a crash in the hack itself:
      `display_touch_keyboard` queued every line of the layout file with
      no bounds check (`Term_queue_chars` has none in a release build),
      so a term shorter than the 17 line narrow layout segfaulted; it
      also never closed the layout file. Both fixed in `ui-input.c`. The
      keyboard still shows only as many rows as fit.
- [x] you test (device): the same on the iPad, plus HiDPI crispness and
      that a hardware keyboard still works after a rotation. Passed
      2026-09-09, including the keyboard redraw fix.
- [x] commit (angband). 2026-09-09.
- [x] code: cherry-pick to `../NarSil_fork` and `../FAangband_fork`; NarSil
      `sdl2init.txt` gets its own region file with the 54 px status bar.
      2026-09-09: done. NarSil's `main-sdl2.c` was byte-identical to the
      pre-step-1 file, so the frontend hunks applied; `ui-display.c` and
      `ui-input.c` were merged by hand (one conflict, the event
      registrations). NarSil's region file keeps its old absolute rects
      (54 px bar) as fallbacks under the same region lines; with the
      unified frontend its status bar is 42 px like Angband's, and the
      regions are per-mille of the area below it either way. FAangband
      had no `sdl2-touch-panel` branch: created from
      `sdl2-term-touch-keyboard`; the cherry-pick had one whitespace
      conflict in `main-sdl2.c`; `gregsim.sh` arrived with it; the
      workflow trigger and the portrait `Info.plist` change (both step 0
      items in Angband) were added as separate commits. FAangband's
      uncommitted `src/ui-init.c` edit (default window flags for terms 5
      and 6) was left in its working tree, not committed. Both forks
      build for the simulator. The plan file stays in this repository
      only. NarSil's first simulator link failed once with no diagnostic
      and succeeded on a rerun of the same build.
- [x] you test: NarSil on the simulator in both orientations.
      2026-09-09: NarSil's `Info.plist` was still landscape-only, so the
      first portrait launch drew the landscape layout (82 by 24 at 36
      point, correct for 2420 by 1668) letterboxed in the portrait
      screen; with portrait allowed (the same plist change as Angband's,
      committed), a portrait launch gives 82 by 30 at 34 point, the same
      numbers as Angband. The Mac was locked, so no scripted rotation;
      the Size button plus a swipe resized the map without a crash. A
      real rotation of NarSil is still untested. Note: CMake bakes
      `Info.plist` into the Xcode project at configure time, so a plist
      edit needs `cmake build-sim` (a reconfigure) before the bundle
      picks it up; `cmake --build` alone reused the old one.
- [x] commit (NarSil, FAangband). 2026-09-09: NarSil `004f9d85b` (step
      1) and `e193f1ddc` (plist); FAangband `d4d957da5` (step 1),
      `6c2bcfb62` (plist), `e6be97d15` (CI trigger).

### Step 2. Panel scaffold

2a. Chrome keys.

- [x] code: `panel` config line (`panel:on` or `off`) and the panel region
      reserved: `get_subwindow_by_xy` ignores it; a pinned, borderless
      `sdlpui` dialog is created over it with `panel-alpha`. Done when a
      translucent rectangle sits where the panel goes and taps on it do not
      reach the term underneath. 2026-09-09: done. `panel:on|off` and
      `panel-alpha:<0-255>` bind to window 0 like the region lines and
      are written back after them; defaults on and 160. The panel is a
      dialog of a new type (`PANEL_CODE`), created in `start_window` once
      the panel rect is resolved and moved, created or removed by
      `relayout_panel` from `resolve_layout`. Like the toolkit's own
      dialogs it has no texture and draws straight to the window;
      `render_all` draws it after the terms, because that pass draws
      dialogs before them (the status bar never overlapped a term, so
      that never showed). While any dialog has focus the window is redrawn
      through the menu-active path and `term_xtra_fresh` skips redraws,
      so the panel yields mouse and key focus at every release and holds
      none between taps. Touch has no hover, so `handle_mousebutton` now
      gives the dialog under a press focus first, through the code the
      motion path uses (`give_dialog_focus_at`); SDL also drops a motion
      that does not change the position, so two taps on the same spot
      produce one motion. `get_subwindow_by_xy` returns NULL inside the
      panel. In `lib/ios/sdl2init.txt` the panel sits over the keyboard
      term, which shows through at alpha 160 but takes no taps; until
      step 2b the game is played with the eight chrome keys, a hardware
      keyboard or `idb` keys.
- [x] code: `panel_key` control type registered with
      `sdlpui_register_code`: label, action, pressed state, face font.
      Chrome keys Escape, Enter, Backspace, Space and the four arrows, sent
      through `send_sdl_keylike_event` extended with modifiers. Done when,
      on the simulator via `idb`, Escape closes the command menu and the
      arrows move the character. 2026-09-09: done. A key sends a keycode
      with modifiers (`push_key_event`) or text (`push_text_event`);
      `send_sdl_keylike_event` now goes through the same two. It fires on
      the press, not the release, so a held key can repeat in step 2c,
      and shows a pressed state; faces use the dialog font for now. Space
      is sent as text, as a keyboard does: `keyboard_event_to_angband_key`
      has no case for `SDLK_SPACE`, so the keyboard term's ␣ key had
      never worked; fixed there the same way. Chrome grid: four columns
      at the panel's top left, keys 44 points high and up to 88 wide.
      Verified on the simulator with `idb` taps: eight Enters take a new
      character from the splash screen to the town, three right arrows
      move it to a wall, Enter opens the command menu and Esc closes it,
      and a tap on the panel background over the keyboard term's `C`
      does not open the character sheet. Key centres in portrait, in
      points, for `idb ui tap`: Esc 46,855; ↑ 134,855; Enter 222,855;
      ⌫ 310,855; ← 46,903; ↓ 134,903; → 222,903; Space 310,903.
      Screenshots: `~/Downloads/step2a_panel_launch.png` (portrait
      launch, Menu closed, panel over the keyboard term) and
      `step2a_panel_town_menu.png` (in town with the command menu open).
- [x] you test (device): tap targets. Are 44 points times `ui_scale` big
      enough for you? Does anything need to move away from the screen edge?
      2026-09-09: passed on the iPad Pro 11-inch (M4). The keys are a
      good size and stay where they are, near the edge. The Menu is
      closed at launch on hardware too. The keyboard term behind the
      panel takes no taps, as intended: the panel owns its area, and the
      term goes in step 6.
- [x] code: find and fix the Menu-open-at-launch bug (section 2.6). It
      reproduces on the simulator and on the device, in both variants.
      2026-09-09: found with a temporary event trace in `get_event`:
      right after the window's mouse-enter event SDL delivers a mouse
      motion to (0,0) from device 0, not the touch id. It comes from
      `SDL_uikitview.m`'s `pointerInteraction:regionForRequest:` (SDL
      2.33), which reports the request's location as a motion when the
      pointer region is set up; the toolkit's submenu buttons open on
      gaining mouse focus, so the Menu opened. Fix in
      `handle_mousemotion`: a motion to exactly (0,0) with no button
      held is ignored. Verified closed at launch on the simulator; the
      device gets the same code. The fix reaches NarSil and FAangband
      with the next cherry-pick (step 8).
- [x] commit. 2026-09-09.

2b. Tabs and modifiers.

- [x] you decide: the Keys tab layout. Reuse the rows from
      `lib/help/keyboard_horiz.txt` as the letters and symbols layers, or a
      fresh grid? Where do F1 to F12 go? 2026-09-09: a fresh grid, seven
      by four, alphabetical like the keyboard files (neither file fits at
      touch size: one is 13 columns, the other 17 rows). Three layers
      behind one key in the grid's last cell: letters (a to z, Tab),
      symbols (the 27 command symbols), numbers (digits, the other five
      symbols, Del, Home, End, PgUp, PgDn). F1 to F12 are left out: no
      core binds them; their only use would be as keymap triggers at the
      "create a keymap" prompt (where the Android port flashes
      `${fkeys}`), and the Mine tab covers user macros. The chrome keeps
      the arrows (you liked the keys as they were) and grows Shift and
      Ctrl as a fifth column; section 4.2's "arrows on Keys" is dropped.
- [x] code: tab strip with five labels; only Keys populated: letters layer,
      symbols layer, a layer toggle, arrows, F-keys. 2026-09-09: done.
      One control type still: a `panel_key` has a kind (send, modifier,
      tab, layer), a group (chrome, tabs, or a layer) and a cell; keys
      of a layer are visible when their tab and layer are current. Rows
      are one touch target high; cells are capped at 64 points wide, so
      the stack is the same in both orientations at the panel's top
      left (in landscape the grid's keys are 36 points wide, narrower
      than the chrome's). Verified on the simulator with `idb`: `~` on
      the symbols layer opens the knowledge menu, `?` on the numbers
      layer opens help. Key centres in portrait, in points: chrome row
      855 (Esc 34, ↑ 98, Enter 162, ⌫ 226, Shift 290), row 903 (← 34,
      ↓ 98, → 162, Space 226, Ctrl 290); tabs row 951 (34 to 290 in
      steps of 64); grid rows 999, 1047, 1095, 1143 at columns 34 to
      418 in steps of 64; the layer key is at 418,1143.
- [x] code: sticky Shift and Ctrl per decision 9, with a visible state
      (off, one-shot, locked). Shift affects letters and shifted symbols;
      Ctrl produces KTRL codes. 2026-09-09: done. Taps cycle off,
      one-shot, locked, off. One-shot lights the key (slate face, white
      border); locked inverts it (white face, dark text), like the
      selected tab; the letters show upper case while Shift is active.
      A send key spends the one-shots; tab and layer keys do not. Shift
      on a letter sends the capital as text; Ctrl on a letter sends a
      key event with the control modifier, which the frontend turns
      into a KTRL code as it does for a keyboard; either on a keycode
      key (arrows, Enter) goes as the modifier, so Shift plus an arrow
      reaches the `{S}[Down]` run keymaps in `pref.prf` (there are no
      Ctrl arrow keymaps, so Ctrl on an arrow is inert until the rose).
      Symbols and digits ignore both. Verified on the simulator: Shift
      then `c` opened the character sheet and cleared Shift; Ctrl then
      `f` gave "Looks like a typical town."; Shift then ↓ moved the
      character, which in open town stops after one step either way.
      Screenshots `~/Downloads/step2b_shift_oneshot.png`,
      `step2b_shift_locked.png`, `step2b_symbols_layer.png`,
      `step2b_numbers_layer.png`.
- [x] you test (simulator): the modifier feel: tap once, double tap locks,
      tap from lock clears. Does the one-shot state read clearly?
      2026-09-09: the one-shot and locked states read clearly, and the
      keycaps changing case was liked. Wrong: a second tap seconds later
      locked, where iOS locks only on a quick double tap. Fixed: a second
      tap within 400 ms locks, a later one clears. Also found and fixed:
      the core's input flush (`term_xtra_flush`) dropped every queued
      SDL event including touch releases, so a key pressed just before a
      flush (the last Enter of birth) stayed armed and lit and the panel
      kept focus; releases now go through `handle_mousebutton` during a
      flush. You do not want to discuss layout or key sizes until the
      rose exists and everything works.
- [x] commit. 2026-09-09.

2c. Repeat.

- [x] code: press time recorded in the control's mouse-down; `panel_tick`
      from the main loop re-fires held repeatable controls at 350 ms then
      every 85 ms; release, focus loss and app background cancel.
      2026-09-09: done. The panel records the held control on the press;
      `panel_tick`, called from `term_xtra_event` before each poll (so
      only while the game waits for input), re-fires it on the schedule.
      Release, the panel yielding focus, the app entering the background
      and a button no longer down (`SDL_GetMouseState`, for a release
      the panel never saw) all cancel. Repeat keys: the arrows,
      Backspace, Del, PgUp, PgDn, and the rose. Verified: `idb ui tap
      --duration 1.5` on the rose's south petal moved the character
      about 13 squares.
- [x] you test (device): hold an arrow; hold Backspace in a name prompt.
      Are 350 and 85 right for you? 2026-09-09: both too fast; now 450
      and 120. The iPad looks and feels like the simulator.
- [x] test: a full turn from the panel with `idb` taps only, then by you by
      hand on the simulator. 2026-09-09: `idb` only: walk, run, stay,
      the command menu, the character sheet, help and the knowledge
      menu, all from the panel. The by-hand half is yours, with the
      device tests.
- [x] commit. 2026-09-09.

2d. Movable pieces (added 2026-09-09; design in section 8, "Movable
panel pieces"). Replaces the placement decisions of steps 2a, 2b and 5.

- [x] code: split the panel into pieces, one pinned dialog each (the
      rose; the key stack of chrome, tabs and grid), sharing the modifier,
      tab and layer state through one struct; `render_all`,
      `get_subwindow_by_xy`, `relayout_panel` and `free_window` treat
      every piece as they treat `window->panel` now. Done when both
      pieces draw and work exactly as before, on the simulator via `idb`.
      2026-09-09: done. `window->panel` is now a `panel_shared` (the
      tab, layer, modifier and repeat state, and the two piece dialogs);
      each piece dialog's private data is a `panel_piece` with its kind,
      the shared pointer and its controls. The type code `PANEL_CODE`
      marks a piece dialog, which is how `render_all`,
      `get_subwindow_by_xy` and the drag find them. The `panel` region
      stays as the home area: its dimmed background and tap shield are
      drawn and checked outside any dialog (`render_panel_home`), and a
      piece draws its own background only where it lies outside the
      home rect, so the default look is unchanged. Verified on the
      simulator with `idb`: the pieces logged at `0,1659 481x481` (rose)
      and `489,1659 904x680` (keys) in portrait, the old places; birth by
      Enter; arrows (the wall message); two rose taps stepped twice and
      a 1.5 s hold repeated about ten squares; Shift then `c` opened the
      character sheet; the symbols layer's `~` opened the knowledge
      menu; a tap on the home area off both pieces did nothing. Key
      centres in portrait moved with the stack to the rose's right:
      chrome row 855 (Esc 280, ↑ 344, Enter 408, ⌫ 472, Shift 536), row
      903 (← 280, ↓ 344, → 408, Space 472, Ctrl 536), tabs 951, grid
      rows 999 to 1143 at columns 280 to 664 in steps of 64; the rose's
      centre is 120,950 with the petals 90 points out. Seen, not
      chased: right after a launch, a first tap on the status bar's Menu
      button advanced the splash instead of opening the dropdown; after
      a tap anywhere else the Menu opens (with its Angband submenu open
      under it). The step 1 notes already advise a tap elsewhere first.
- [x] code: piece positions as regions (`region:rose:<orient>:x:y:w:h`
      and `region:keys:...`), per-mille like the others and written back
      by `dump_config_file`; a piece without a region takes its present
      place inside `region:panel`. Done when a hand-edited position in
      `Documents/Angband/sdl2init.txt` shows on launch in both
      orientations. 2026-09-09: done. `rose` and `keys` are region
      targets like `panel`; `get_panel_piece_rect` takes the piece's
      region for the orientation, else its default place in
      `region:panel`, else there is no piece. A piece region sets the
      size too: the rose takes the shorter side as its diameter; the
      key stack fits cells to the width (capped at 64 points) and
      shrinks its rows when the height is short. Verified with a user
      config carrying `region:rose:portrait:720:690:280:200`,
      `region:keys:portrait:20:690:560:300`,
      `region:rose:landscape:760:400:240:350` and
      `region:keys:landscape:0:640:400:360`: a portrait launch logged
      `rose piece at 1200,1682 468x476` and `keys piece at 33,1682
      934x714`; a scripted rotation (the Mac was unlocked) moved them to
      `1839,692 581x569` and `0,1082 968x586`, the stack over the lower
      terms with shrunk rows and its own dimmed background outside the
      home column; a launch in landscape gave the same; Ctrl-x, Enter
      and Esc quit the game and the rewritten user config kept all four
      lines. The test config was removed afterwards.
- [x] code: two-finger drag. Re-enable `SDL_FINGERDOWN`, `SDL_FINGERMOTION`
      and `SDL_FINGERUP` (disabled in `init_systems`) and count fingers;
      a second finger down while the first is on a piece starts a drag
      that follows the centroid, cancels any repeat and disarms the
      pressed key; any finger up ends it, clamps the piece into the
      window and stores its region for the current orientation. Finger
      coordinates are normalised to the window; scale by the renderer
      output size. `idb` cannot do two fingers and the Simulator's
      two-finger gesture (Option plus the mouse) needs a hand and an
      unlocked Mac, so the code test is a "you test". 2026-09-09: built;
      the drag itself is untested. Finger events are enabled again;
      `handle_finger` (from `get_event`, and from `term_xtra_flush` so
      a flush cannot lose a finger) acts only on a direct touch device,
      so a Mac touchpad still does nothing, and the first finger's mouse
      emulation is untouched. A second finger down while the mouse
      button (the first finger) is down on a piece picks the piece up:
      repeat cancelled, every control of the piece disarmed, the piece
      pushed to the top of the dialog stack. Any finger up puts it
      down, clamped into the inner rect, with its region stored for the
      current orientation and `... piece put down at ...` logged. A
      layout during a drag drops the drag. Everything else on the panel
      was re-verified on this build with single-finger `idb` taps, so
      the enabled finger events are harmless to taps.
      2026-09-09, after your iPad test: flaky. The rose, dragged to the
      bottom left, moved again when you next tried to drag the keys,
      then the app crashed; after a relaunch one drag of the keys
      worked and then nothing would drag. The first version took the
      first finger to be "the other finger in SDL's finger list" and
      followed the list's centroid, and both symptoms fit a phantom
      finger in that list (a lift SDL never received, which the iPad
      can do): a phantom resting where the rose was dropped makes the
      next single press look like two fingers with the phantom on the
      rose, so the rose follows half of the motion; and with a phantom
      the "exactly two fingers" test never passes again. Rewritten to
      read nothing from the list: the first finger is known by SDL's
      own rule mirrored from the events (the first finger down while
      none is tracked, until it lifts), a finger-down from any other
      finger while the mouse button is down on a piece picks the piece
      up, the piece follows the first finger's mouse motion in
      `handle_mousemotion` (so the drag is exact in the pieces' own
      coordinates, not a centroid), and the first finger's release in
      `handle_mousebutton` or any finger-up puts it down. The crash was
      not identified from the code; the finger-list reads are gone with
      the rewrite. Re-verified single-finger use with `idb` on the new
      build. If it crashes again, Console.app with the iPad attached
      shows the app's stderr, where the game's handler prints "Exiting
      on signal 11".
- [x] you test (simulator, then device): two-finger drag both pieces
      anywhere, including over the map; rotate; relaunch; a left-hand
      and a right-hand arrangement. Note what the first finger's press
      did before the second finger landed. 2026-09-09, how: in the
      Simulator hold Option and Shift to get two fingers that move
      together (Option alone pinches), press on a piece and drag. The
      console logs `picked up at` and `put down at` with the rect
      (`xcrun simctl launch --console`; the launch made at hand-off
      logs to `/tmp/panel/console5.log`). Check that keys under a moved
      piece take taps and the terms beside it do; that nothing repeats
      during the drag; that each orientation keeps its own positions
      and a piece never dragged in an orientation stays at its default
      place there; and that a quit from the game (not `simctl
      terminate`) and a relaunch without reinstalling bring the
      positions back (on the simulator with no user file they are
      written into the bundle's own `lib/ios/sdl2init.txt`).
      2026-09-09: first iPad round failed; see the drag box. Second
      round: the drag worked but updated once or twice over a few
      inches, with every touch backlogged for seconds afterwards. Not
      the rendering: on the simulator a drag frame measured 7 to 9 ms
      (the key stack's 92 captions go through TTF at 5 to 7 ms, and were
      rendered twice per frame, once by `render_status_bar`). The
      cause was `term_xtra_event`, which slept 16 ms after every event
      it polled and did not handle; with finger events enabled, the
      iPad's 120 Hz finger motion cost nearly two seconds of sleep per
      second of dragging, and the queue drained for seconds afterwards.
      `idb` sends few events, so the simulator never showed it. Fixed:
      `get_events` drains the queue before the loop sleeps, and each
      piece is cached in a texture, redrawn only when it changes and
      dropped on resize and renderer reset, so a drag frame is one
      copy (2 to 5 ms on the simulator, none of it the panel). `xctrace`
      could not attach to the simulator process (it hung), so the
      numbers came from temporary `SDL_Log` timing. A testing aid
      stays: with `ANGBAND_PANEL_DRAG_TEST` in the environment (on the
      simulator, `SIMCTL_CHILD_ANGBAND_PANEL_DRAG_TEST=1 xcrun simctl
      launch ...`) the first finger's own touch starts a drag, so an
      `idb ui swipe` on a piece drags it; used to exercise pickup,
      move, put-down and the stored region on the simulator. Third
      round on the iPad: passed, "great".
- [ ] you decide: whether the keyboard term (`sub1`) should go now that
      pieces float over the map, or wait for step 6; and what
      `region:panel` still means once pieces have their own regions.
      2026-09-09, your answer in part: `region:panel` stays, as a
      blank buffer strip along the bottom in both orientations for the
      pieces to sit on; above it, in portrait a few terms between the
      strip and the map, in landscape a couple under the map and a
      tall right column carved into three. Messages, the monster list
      and the item list first; the rest by the menu as today. Done so
      far: term 1 shows messages instead of the touch keyboard
      (`lib/ios/window.prf`; the hack's code stays until step 6); in a
      band the pieces default to the rose at the left and the key
      stack at the right, both centred vertically, and the stack takes
      a wide form there, the chrome block beside the tabs and grid,
      five rows instead of seven (the three empty rows under the chrome
      are where the step 3 fast-keys strip can go); the rose is 120
      points across with outlined petals (decision 5). Two candidate
      files sit untracked in the repository root, each with both
      orientations; screenshots of both in the town are
      `~/Downloads/step2d_strip1_portrait.png` and so on:
      - `sdl2init.strip1.txt`: messages under the map in both
        orientations (4 rows in portrait, 3 in landscape); monsters,
        items and recall as three columns above the strip in portrait
        (15 rows) and as the right column in landscape (10 rows each);
        the strip is 220 per mille in portrait (262 points) and 300 in
        landscape (244 points); the map is 82 by 27 at 34 point in
        portrait and 91 by 24 at 34 in landscape.
      - `sdl2init.strip2.txt`: the map keeps its height (82 by 30 at
        34 in portrait, 82 by 25 at 37 in landscape); in portrait
        monsters, items and recall are three columns of 11 rows and
        messages sit just above the strip, by the keys; in landscape
        all four side terms share the right column at 7 rows each.
      Open with the choice: the strip's dim, which now lies over black
      (nothing under it), the rose's outline weight at this size (10
      points is a third of a cardinal petal's width), and the rose's
      centre, which shows a dot because a word does not fit the dialog
      font at 120 points.
      2026-09-09, decided: candidate 2. `region:panel` stays as the
      strip; `sub1`, the touch keyboard term, goes now (it still shows
      on the iPad, and its window flag shows in the menus). The
      remaining items are the "Next session" list below.
- [x] commit. 2026-09-09.

Next session (from the 2026-09-09 evening hand-off; in order):

- [x] commit 2d as it stands (the split, piece regions, the drag, the
      event-loop and texture fixes, the rose, the wide key stack, term
      1 as messages, this file), then the items below as their own
      commits. 2026-09-09: committed.
- [x] code: `lib/ios/sdl2init.txt` takes candidate 2's regions
      (`sdl2init.strip2.txt`) and `subwindow-font:1:30`; the candidate
      files and `sdl2init.portraitA/B.txt` can then go. 2026-09-09: done;
      the four candidate files are deleted and the region comment
      rewritten to describe the layout rather than the comparison.
- [x] code: rose 30 percent bigger in both directions (156 points,
      `PANEL_ROSE_SIZE_POINTS`) and the outline 10 percent thinner (9
      points, `PANEL_ROSE_LINE_POINTS`). Check the strip still holds
      it (candidate 2's strip is 262 points in portrait, 244 in
      landscape; the rose is centred, so it fits, with 40 points to
      spare in landscape). 2026-09-09: done; on the simulator the rose
      clears the strip in both orientations, as the arithmetic said.
- [x] code: remove the touch keyboard hack now rather than in step 6:
      `PW_TOUCH_KEYBOARD` in `src/ui-term.h`,
      `update_touch_keyboard_subwindow` in `src/ui-display.c`,
      `display_touch_keyboard` in `src/ui-input.c`, the defaults in
      `src/ui-init.c`, `lib/help/keyboard_horiz.txt` and
      `keyboard_vert.txt`, and the "Display touch keyboard" entry in
      the window-flags menu, which you saw and which is not a thing.
      `send_sdl_keylike_event` in `main-sdl2.c` goes with it if nothing
      else uses it. Move the step 6 box here.
      2026-09-09: done, all of it. Nothing else used
      `send_sdl_keylike_event`, so it went, and with it
      `send_char_clicked_as_keystroke` on `struct term` and the two
      lines that set and read it (`load_term` set it on every subwindow
      term, so before this a tap on any term typed the glyph under the
      finger; taps now only reach the core as mouse presses, which is
      why a tap on the map no longer dismisses the splash screen -- use
      the panel). `ui-init.c`'s window-flag defaults go back to
      upstream's, term 1 included, which is what `lib/ios/window.prf`
      already asks for. `handle_mousebutton`'s `window` local became
      unused and went. Checked on the simulator: builds clean, a saved
      game loads and plays in portrait, and Term-1's Purpose submenu
      now ends at "Display borg status" with "Display messages" ticked.
- [ ] you decide: a blank term. Angband's window flags are a bitmask
      and a term with no flag set draws nothing, so "empty" already
      exists as "every flag off" in the window-flags menu; a named
      "Empty" entry would only make that discoverable. Is that wanted,
      or is "no flag" enough? (Asked 2026-09-09.)
- [ ] you test (device): the new rose size and line, candidate 2 as
      the shipped default, no keyboard term anywhere.
- [ ] commit; then step 3.

### Step 3. Core hooks

- [ ] code: `src/ui-panel.h` and `.c`: the buffer from angbandroid's
      `droid.c`, `ui_control_hook` defaulting to NULL, and a stderr
      consumer enabled by a `-m` subopt or environment variable. Done when
      both variants build with the hook unset and behave exactly as before.
- [ ] code: hook sites in `ui-input.c` (`inkey_ex` flush and clear,
      `get_check`, `get_char`, `get_quantity`, `askfor_aux` `${text}`) and
      `ui-menu.c` `keys_to_ui`. Done when stderr shows the expected strings
      at an inventory prompt, a yes/no prompt and a text prompt.
- [ ] code: remaining sites: targeting, birth, knowledge, options, player
      sheet, monster list, command menus.
- [ ] code: frontend consumer: fast-keys strip up to twelve, overflow fills
      the Keys tab and switches to it, Enter and Backspace relabel for
      `${yes_no}`, `${text}` switches to Keys, `${clear}` restores.
- [ ] you decide: when the core offers more than twelve keys, is switching
      to the Keys tab the right behaviour, or should the strip scroll?
- [ ] you test (simulator): inventory letters appear at an item prompt; y
      and n at a confirmation; the Keys tab appears at the name prompt.
- [ ] commit (angband).
- [ ] code: hand-merge the core side into `../NarSil_fork` (its `ui-*.c`
      differ; section 2.5). Cherry-pick into FAangband.
- [ ] you test: the same three prompts in NarSil.
- [ ] commit.

### Step 4. Slots and seeding

- [ ] code: `panel.txt` parser for the token grammar in section 4.3; user
      dir searched before `lib/customize`; unknown descriptions become
      disabled slots.
- [ ] code: command references resolved at press time against `cmds_all`
      for the active keyset (Angband `key[2]`; NarSil `key[4]` with its
      index).
- [ ] code: seeder from `cmds_all` with the section 4.4 group-to-tab rules,
      the face table, commented overflow rows, and a menu item to
      regenerate.
- [ ] code: word faces rendered on Act, Items and Info; Mine empty.
- [ ] you decide: review the generated Angband `panel.txt`. Which sixteen
      go on each tab, in what order, and which face words read badly?
      Whether to mine the Android thread (section 8) before settling this.
- [ ] you test (simulator): toggle roguelike keys in the options and
      confirm the same slot now sends the roguelike key without editing the
      file.
- [ ] commit (angband); cherry-pick to FAangband.
- [ ] code: NarSil seeding and the four keyset combinations.
- [ ] you test: NarSil under all four keyset combinations.
- [ ] commit.

### Step 5. Compass rose

- [x] code: check `textui_process_key` in all three variants for keypad
      digits with Shift and Ctrl mapping to run and alter. Report; choose
      keypad emission or command prefixes. 2026-09-09: the core does not
      handle them; `lib/customize/pref.prf` does, in all three games and
      for every keyset (NarSil's modes 0 to 3): `{K}N` walks (`;N`),
      `{SK}N` runs (`.N` or `,N`), `{^K}N` alters (`+N`, or `/N` for
      NarSil's Sil keyset), and keypad 5 stays (`,` in Angband and
      FAangband, `z` in NarSil). Chosen: keypad emission. It bypasses
      SDL: the frontend only turns keypad keycodes into keypad digits
      when the "keypad modifier" option is on, so the rose calls
      `Term_keypress` with the digit and `KC_MOD_KEYPAD` (plus
      `KC_MOD_SHIFT` or `KC_MOD_CONTROL`) and pushes an `SDL_USEREVENT`,
      which `get_event` treats as handled, to wake `Term_inkey`.
- [x] code: `panel_rose` control: geometry from section 4.5, hit test,
      `SDL_RenderGeometry` petals with a ghost outline and a solid pressed
      petal, center face. 2026-09-09: done, as a third control type
      (`PANEL_ROSE_CODE`) in the panel dialog. Petals are ten-point
      polygons (an arc at the tip, a narrower arc near the centre)
      filled as fans at alpha 40, outlined at 110, solid at 220 when
      pressed; the centre is a square with the face "Stay". Placement
      for now: bottom left of the panel, lifted 140 points, as large as
      the space allows; in a band (portrait) the key stack moves to the
      rose's right, in a column (landscape) it stays above. On the
      11-inch in portrait the rose is 481 px (240 points) across.
- [x] code: behaviour: tap steps, hold repeats, slide while held changes
      petal, Shift runs, Ctrl alters, center is `Stand still` by reference.
      2026-09-09: done, except that the centre sends keypad 5 (the stay
      keymap) rather than a command reference, which waits for step 4.
      Verified with `idb`: a tap steps, a 1.5 s hold repeats, a swipe
      from the east petal to the south petal stepped east then south,
      Shift then a petal ran. Ctrl (alter) is wired but untested.
- [ ] you decide: after seeing it, the rose radius, the 140 point lift, and
      bottom-left versus a right-hand mirror. Whether center long-press
      should do anything yet. 2026-09-09: deferred by you in favour of
      movable pieces (section 8), which would make the position a drag
      rather than a decision.
- [x] you test (device): walk, run, alter, stay; sliding; that a finger
      resting on the rose does not fire twice. 2026-09-09: passed on the
      iPad; it behaves as on the simulator.
- [x] commit. 2026-09-09. The cherry-pick to the other two waits for the
      step 8 milestone.

### Step 6. iOS

- [ ] code: `SDL_SetHint(SDL_HINT_ENABLE_SCREEN_KEYBOARD, "0")` before
      `SDL_StartTextInput`.
- [ ] you test (simulator, then device): the system keyboard never
      appears, including at the character name prompt; a hardware keyboard
      still types.
- [x] code: remove the `PW_TOUCH_KEYBOARD` hack (files in section 2.1) in
      Angband and NarSil; term 1 becomes messages; region files updated.
      2026-09-09: moved up to the step 2d follow-up and done there for
      Angband. NarSil and FAangband still carry the hack; they get it
      with the step 3 port.
- [ ] code: NarSil `Info.plist` orientations.
- [ ] code: the Menu-open-at-launch bug, if still open.
- [ ] you test (device): both orientations, a session from launch to the
      first dungeon level using only the panel, rotation mid-game.
- [ ] you decide: publish a new `.ipa` from `sdl2-touch-panel` for
      downloaders now, or wait for step 7.
- [ ] commit; cherry-pick to FAangband and NarSil; workflow triggers.

### Step 7. Editing and persistence

- [ ] code: report on reusing the shortcut editor dialog
      (`SHORTCUT_EDITOR_CODE`) for slots.
- [ ] you decide: reuse it, write a small slot editor, or ship version 1
      with `panel.txt` editing only.
- [ ] code: long press on a slot opens the chosen editor; edits persist to
      the user `panel.txt`.
- [ ] you test (device): edit a slot; relaunch; the edit survives; the file
      is readable in the Files app.
- [ ] commit; cherry-pick to the other two.

### Step 8. Port and publish

- [ ] code: FAangband caught up at each milestone above (after steps 1, 6
      and 7); NarSil at the same points, with hand-merges only for step 3.
- [ ] you test: one device session in each of the three.
- [ ] you decide: which of the three get published `.ipa` artifacts, and
      whether to open an upstream conversation about the panel.

## 6. Verification checklist

- Regions: portrait and landscape on 11 inch and 13 inch iPad sizes, at 2x,
  yield map >= 80 by 24 and no overlapping rects.
- Seeding: output for each variant matches the table in section 2.3, and
  NarSil resolves correctly under all four keyset combinations.
- Hooks: no change in behaviour for desktop builds with the hook unset.
- Input: `feed_keymap` text honours more-prompt skipping the same way a
  pref-file keymap does.
- Rose: repeat cancels on release and on focus loss; slide changes direction.
- iOS: system keyboard never appears; hardware keyboard still works through
  SDL; rotation re-lays out without a restart.
- Step 0: NarSil with the unified frontend plays a turn on the simulator
  and on the iPad (both done 2026-09-08) before any panel commit reaches
  it.

## 7. Porting notes for the other two variants

- FAangband: identical frontend and term code (section 2.5); three extra
  commands.
- NarSil, frontend unification: done in step 0 and committed in
  `../NarSil_fork`. What was done: copied `src/main-sdl2.c` and `src/sdl2/`
  from this repository; listed the three toolkit sources in `CMakeLists.txt`
  and `src/Makefile.src`; added `is_sound_inited` to `sound.h` and
  `sound-core.c` (Angband's is at `src/sound-core.c:423`). Compiled without
  any other change. The old NarSil copy had a few cosmetic settings that were
  not carried over and can be re-applied if missed: `TTF_HINTING_LIGHT_SUBPIXEL`,
  default font `LiterationMonoNerdFontMono-Regular.ttf` (moot while
  `lib/ios/sdl2init.txt` names JuliaMono), `COLOUR_SLATE` for the status
  bar, `DEFAULT_WINDOW_MINIMUM_W/H` set to `MIN_COLS_MAIN` and
  `MIN_ROWS_MAIN`, a relaxed `assert(y >= -2)` in the menu handler, and a
  "button disabled" `plog`. NarSil's `Info.plist` is still landscape-only and
  needs the same orientation change as Angband's (section 2.6).
- NarSil, after unification: `key[4]` and the keyset index at
  `ui-game.c:520`; `Z` rests, Tab opens abilities, extra commands listed in
  section 2.3. `angband_keyset` is set to `no` in
  `lib/ios/customized_interface_options.txt`. The core hooks (step 3) will
  need hand-merging because `ui-display.c`, `ui-game.c` and `ui-input.c`
  differ substantially from Angband's.

## 8. Later and open items

- Rose lift as a preference, and a right-hand mirror.
- Hold-to-run toggle on the center petal.
- Icons for faces via an icon font; angbandroid ships `ui-cmd.ttf` in
  `app/src/main/assets`, licence in `ui-cmd-README.md` there.
- Upstreaming the panel to `angband/angband`; the SDL2 frontend maintainer
  may accept a touch panel, and FAangband and NarSil both track that file.
- Mining the angband.live "Angband for Android" thread (18 pages) for the
  most requested buttons before finalising tab defaults.
- Haptics through a small Objective-C shim if wanted. VoiceOver is out of
  scope for an SDL-drawn panel.
- Section 5 is now a checklist. Still open: whether to copy this file into
  the other two repositories at first port, each with its own status block.
  This repository would stay canonical.
- Rebasing `../NarSil_fork` `main` onto upstream, 124 commits behind as of
  2026-09-08. Nothing there touches `main-sdl2.c`.
- The Menu dropdown open at launch (section 2.6): fixed in step 2a.
- TBD, discussion (asked 2026-09-09): a new branch with a squashed
  history that groups the work thematically rather than by session:
  building for iOS; term windows specified as fractional regions;
  responding to rotation and resize; the new touch keyboard (the panel:
  pieces, rose, key stack, drag); and whatever else turns up in the
  log (the `init.c` platform-directory fix, the cmake macro fix, the
  Menu-at-launch fix, `gregsim.sh`). To settle: which base (upstream
  `master` at the branch point), what the commits are, whether this
  file travels with them or stays a working document, and what the
  forks get.
- TBD, discussion (asked 2026-09-09): a text-file spec for the panel's
  keys, covering both the exhaustive one (the Keys tab: its layers,
  which characters and special keys sit where) and the thematic
  groupings (Act, Items, Info, Mine: which commands, in what order,
  with what faces). Section 4.3's `panel.txt` grammar is the starting
  point for the groupings; the Keys tab is fixed in code today
  (`create_panel_keys`) and would need the same treatment to be
  specified in a file. The spec would also be what step 4's seeder
  writes and what step 7's editor edits.
- Movable panel pieces (asked for 2026-09-09, after the rose): the rose
  and the key stack draggable, drawn above whatever they land on, moved
  with a two-finger drag as in Brogue. Feasibility, from the code as it
  stands:
  - Drawing above the terms already works: the panel is a toolkit dialog
    drawn straight to the window after the terms in `render_all` and
    last in the menu-active pass, wherever its rect is. Taps inside its
    rect never reach a term (`get_subwindow_by_xy`), taps outside do.
    Terms under a piece keep updating and show through its alpha.
  - What changes: one dialog per piece (rose, key stack, later the
    fast-keys strip) instead of one panel dialog, sharing the modifier
    and layer state through a common struct; the render and hit-test
    exclusions generalised from `window->panel` to a list of pieces.
    Controls are already positioned relative to their dialog, so moving
    a piece is moving its rect.
  - Persistence for free: make each piece a region (`region:rose:...`,
    `region:keys:...`) so positions are per orientation, survive
    rotation, and are written back by `dump_config_file`; a drag updates
    the per-mille values for the current orientation. `region:panel`
    would become the pieces' home area or go away.
  - Two-finger drag: SDL only emulates the mouse from the first finger,
    so enable the finger events the frontend disables at init
    (`SDL_FINGERDOWN`, `MOTION`, `UP`) and ignore them except for
    counting fingers: a second finger down while the first is on a
    piece starts a drag that follows the centroid; any finger up ends
    it and writes the region. Finger coordinates are normalised to the
    window, so scale by the renderer size. One wrinkle: the first
    finger's press has already fired its key (a step, or a letter) by
    the time the second finger lands; Brogue lives with the same.
  - Size: a few hundred lines, mostly moving code; no toolkit changes.
