# Reforged UI for WoW: Forever

A World of Warcraft: Forever addon that replaces the bottom of the screen with
the Warcraft III console, with a theme for every playable race: Human, Dwarf,
Gnome, Night Elf, Orc, Tauren, Troll, Undead and Skyborne (High Order and
Windshapers).

The console is a port of a WoW 1.12 console addon: its layout, art, fonts and options menu,
rebuilt for the current engine (Edit Mode, secret values, protected frames).
All console art and the font in `ReforgedUI/art` are the original addon's. Reforged UI
adds the top bar with the day/night clock and data broker feeds.

![16:9 Orc](docs/previews/16x9-orc.png)

## What it does

Left to right, as in the original addon with its "Center UI" option, which is always on:
the console sits in the middle of the screen with the original addon's chat width (on a
16:9 screen it fills the width, on 21:9 and 32:9 screens the rest of the
screen stays free on either side).

- **Minimap block**: a square minimap with mouse-wheel zoom, the zone name on
  its bottom or top edge, the tracking button in the round slot below it, the
  mail slot (a grey letter when there is no mail) and three action slots
  beside it. Other minimap buttons (addon buttons) line up along the top edge
  of the map; the minimap's day/night indicator is hidden (the top bar has the
  clock).
- **Portrait block**: animated 3D portrait (click to target yourself,
  right-click for your menu), health and power bars under it, rest/combat,
  group leader and PvP icons. The background pulses red under the low health
  threshold.
- **Hero screen**: name, level and class, the experience bar with rested
  experience (hover for the numbers) and four stat icons. Armour is fixed; the
  other three show main hand, off hand (block chance and value with a shield),
  ranged, ammo (yellow under 400, red under 200), spell power, healing or
  nothing, chosen per class in the options. Druid forms and Ghost Wolf swap
  the icons like the original addon.
- **Action grid**: action bars 1-3, twelve slots each. These are Blizzard's
  own buttons, moved into the grid and reskinned, so bindings, paging,
  cooldowns and proc glows work as usual. The stance buttons (Paladin auras,
  Warrior stances, Druid forms, ...) and the pet bar stand in a row on the wall
  above the grid, as in Warcraft III; these are Blizzard's buttons too.
- **Inventory**: the bags in the 2x3 inventory (backpack top-left, bags 1-4,
  reagent bag bottom-right where the client has one) with the key ring to its
  left. Clicks go through Blizzard's own bag buttons, so bag addons such as
  BetterBags open as usual; drag a bag onto a slot to equip it.
- **Chat area**: the main chat window and its input box fill the black area
  at the right end of the console, which can be raised.
- **Top bar** (Reforged UI) with Quests, Menu, Allies and Map buttons, the
  day/night clock in the middle and slots for LibDataBroker feeds: gold, bag
  space and durability fill the first three; right-click an empty slot
  (Alt-right-click a filled one) to choose any feed.

The three action slots beside the minimap are the first three buttons of
Blizzard's **Action Bar 8**, so they bind like any other bar (Key Bindings >
Action Bars > Action Bar 8). The addon turns on Action Bars 2, 3 and 8 once per
character; if you turn bar 8 off later, the slots are empty sockets whose
tooltip says how to turn it back on.

Buffs and debuffs are held in the top-right corner just below the top bar.
Other frames that Edit Mode manages (cast bar, target and party
frames, quest tracker) stay wherever Edit Mode puts them: place them around
the console there. Moving them from addon code breaks Blizzard's own code on
this client. (The stance and pet bars' own frames stay put too, empty and
click-through; only their buttons move into the console.)

## Options

Move the mouse to the bottom-right corner of the screen and click the
cogwheel (or type `/rui config`, or use Options > AddOns > Reforged UI). The
menu keeps the original addon's options, minus the layout ones (the centre modes, chat
area width, chat placement and hiding the bags: the console is always
centred with its chat area and inventory): theme, UI scale (240-270), extend
the chat area upwards, portrait position and scale, low health threshold,
rested XP colour, the stat icons, zone text position, chat input above the
chat, health and power as percentages, and hiding the grid texture, micro
buttons and chat icons.

| 21:9 Night Elf | 32:9 Orc |
| --- | --- |
| ![21:9](docs/previews/21x9-nightelf.png) | ![32:9](docs/previews/32x9-orc.png) |

![32:9 Dwarf](docs/previews/32x9-dwarf.png)

The previews are rendered from the real layout code and art, with placeholder
icons, portrait, minimap and chat.

### Themes

| Theme | Key | Art |
| --- | --- | --- |
| Human | `human` | Warcraft III (Human console) |
| Orc | `orc` | Warcraft III (Orc console) |
| Undead | `undead` | Warcraft III (Undead console) |
| Night Elf | `nightelf` | Warcraft III (Night Elf console) |
| Dwarf | `dwarf` | Human art recoloured: granite, bronze trim, forge-ember accents |
| Gnome | `gnome` | Human art recoloured: brushed steel, copper trim, teal and pink accents |
| Tauren | `tauren` | Orc art recoloured: tanned wood and hide, ochre-red bands, totem turquoise |
| Troll | `troll` | Orc art recoloured: bamboo and bone, teal patina, voodoo purple |
| Skyborne (High Order) | `highorder` | Night Elf art recoloured: powder-blue stone, silver, arcane violet, twilight navy |
| Skyborne (Windshapers) | `windshapers` | Night Elf art recoloured: powder-blue stone, gold, storm teal, twilight navy |

| Dwarf | Gnome |
| --- | --- |
| ![Dwarf](docs/previews/16x9-dwarf.png) | ![Gnome](docs/previews/16x9-gnome.png) |
| **Tauren** | **Troll** |
| ![Tauren](docs/previews/16x9-tauren.png) | ![Troll](docs/previews/16x9-troll.png) |
| **Skyborne: High Order** | **Skyborne: Windshapers** |
| ![High Order](docs/previews/16x9-highorder.png) | ![Windshapers](docs/previews/16x9-windshapers.png) |

The race themes keep their base faction's shapes and layout; only the colours
change. `tools/make_race_themes.py` makes them (see Development).

**Default theme.** `auto` (the default) picks the theme of your character's
race (`UnitRace("player")`): Human, Dwarf, Gnome, Night Elf, Orc, Tauren,
Troll and Undead (`Scourge`) each get their own. Skyborne is token `Skyborne`
with race id 95 ("High Order Skyborne") or 96 ("Windshaper Skyborne"); the id
picks the High Order or Windshapers theme. Without an id, the race name
("High Order", "Windshaper") or else the faction picks the variant.
Any other race gets its faction's default (Alliance: Human, Horde: Orc), and
later-expansion races take the closest theme (e.g. Dark Iron Dwarf: Dwarf).
Choosing a theme in the menu or with `/rui theme` saves it and overrides the
race default until you pick `auto` again; `skyborne` picks the Skyborne theme
of your faction. Saved themes from earlier versions keep working.

## Setting up

1. Copy the `ReforgedUI` folder into the AddOns folder of your Forever install.
   **Restart the game client completely** (not just `/reload`): the addon has
   new files, which the game only picks up on a full restart.
2. Action Bars 2, 3 and 8 are turned on for you the first time each character
   logs in. Only the first three buttons of bar 8 are used (the slots beside
   the minimap); the rest are parked off screen, so you can set it to as few
   icons as Edit Mode allows.
3. Move the cast bar, target frame and anything else Edit Mode manages to
   where you want them around the console.

## Commands

```
/rui config                      open the options menu
/rui theme auto|human|dwarf|gnome|nightelf|highorder|orc|tauren|troll|undead|windshapers|skyborne
/rui feeds                       list data feeds and top bar slots
/rui slot <number> <feed>|none   put a feed in a top bar slot
/rui scale 0.5-1.5               top bar scale
/rui layout auto|16:9|21:9|32:9  top bar layout
/rui module <console|hero|actionbars|minimap|chat|inventory|blizzard|topbar|config> on|off   (then /reload)
/rui status
/rui reset
```

## Not ported

Things the original addon does that have no taint-safe equivalent on this client, or that
the client now does itself:

- The **Customize** tab (moving and resizing every piece) and the eight
  custom themes.
- **Cast bar alignment**, the **buff position** option (buffs always sit under
  the top bar) and moving the **pet
  frame**: these are Edit Mode frames; place them in Edit Mode. (The stance
  and pet bar buttons are placed, see above; the position options are not.)
- Moving Blizzard's **player status icons** (rest, combat, leader, master
  looter, PvP): replaced by our own icons in the same places (no master
  looter icon).
- The **"Center UI, no chat area"** modes, the **chat width** and **"Hide
  bags"** options: the console is always centred with its chat area and
  inventory, and the bags always show.
- **Horizontal multibars** (and their beta option), the **"Server is V+"**
  option and the **first-run reload** prompt.
- Spell and healing power **scanned from tooltips and auras**: the client's
  own spell power API is used instead.
- the original addon's **Bindings.xml**: the three extra slots use Action Bar 8's bindings.
- **Bonus action bar** handling (stances, stealth): the client pages the main
  bar by itself.
- Moving the **battleground minimap button**: it lines up with the other
  minimap buttons.
- The **chat scroll arrows** option hides the chat buttons beside the window
  instead (the client has no scroll arrows).
- Blizzard's player frame is hidden (our portrait block replaces it); the
  target frame is left to Edit Mode.

## Art and licences

`ReforgedUI/art` is the original addon's art and font (the race theme folders are
recoloured copies of it) (`blq55.TTF`), cut from Warcraft III; the one `.dds` was converted to `.tga`. The top bar's
textures in `ReforgedUI/Media` are cropped from Warcraft III: Reforged (see
[Media/README.md](ReforgedUI/Media/README.md)). Blizzard owns that art, and
the console art ships without a licence file, so keep this repository private.

`ReforgedUI/Libs` embeds LibStub (public domain), CallbackHandler-1.0 (BSD) and
LibDataBroker-1.1 (public domain) for the top bar's data feeds.

## Development

- `luacheck ReforgedUI` lints the addon.
- `lua5.1 tools/smoke_test.lua` loads the addon against a stubbed game API and
  exercises login, every theme, UI scale and screen shape, the
  hero screen, combat queuing and the main events.
- `python3 tools/make_race_themes.py [race ...]` regenerates the race themes'
  art (`ReforgedUI/art/<race>` and `ReforgedUI/Media/<Race>`) from the
  the original faction art: a gradient map per material (stone, trim, accents,
  dark fills) that keeps alpha and the original's shading. Palettes are at the
  top of the script. Needs Pillow and NumPy.
- `python3 tools/render_preview.py` re-renders the previews in `docs/previews`
  (`tools/dump_layout.lua` prints the layout as JSON).
- `Layout.lua` holds all of the original addon's placement math, free of game API calls.
