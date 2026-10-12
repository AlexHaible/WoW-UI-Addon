# Reforged UI

A World of Warcraft: Forever addon that replaces the bottom of the screen with a
console in the style of the Warcraft III: Reforged UI, themed for the Human,
Orc, Undead and Night Elf factions.

![16:9 Human](docs/previews/16x9-human.png)

## What it does

Left to right the console holds chat, the minimap, your portrait, the hero
screen, action bars 1-3, the inventory and the target panel.

- **Action bars 1-3**: three full rows of twelve in the middle of the screen.
  These are Blizzard's own buttons, moved and reskinned, so bindings, paging,
  cooldowns and proc glows work as usual. Turn bars 2-5 on in Options >
  Gameplay > Action Bars.
- **Hero screen**: name, a level bar that fills with experience (hover for the
  numbers), and four stat icons. Bottom-left is armour; the other three show
  main hand, off hand (block chance and value with a shield), ranged, ammo
  (yellow under 400, red under 200), spell power, healing or nothing. Right-click
  an icon to choose; defaults depend on your class.
- **Portrait**: animated 3D player portrait with hit points and mana below it.
- **Inventory**: the 2x3 grid holds the backpack and bag slots, with the key
  ring beside it.
- **Target panel**: the target's portrait, name, level and type, health and
  power, your combo points on it, and the target's target underneath. Click to
  target, right-click for the unit menu.
- **Square minimap** with tracking, calendar, mail, addon and landing page
  buttons stacked beside it and mouse-wheel zoom.
- **Chat** in the left block, or floating above the console when the screen is
  too narrow. The micro menu sits on top of the inventory and target panel.
- **Top bar** with Quests, Menu, Allies and Map buttons, the **day/night clock**
  in the middle (the sun crosses the window during the day and the moon at
  night), and slots for **data broker feeds** like Titan Panel. Gold, bag space
  and durability fill the first three; right-click an empty slot (Alt-right-click
  a filled one) to choose any LibDataBroker feed for it.
- Frames that Edit Mode manages (cast bar, stance and pet bars, buffs, party
  frames, quest tracker) are left to Edit Mode: place them there around the
  console. Moving them from addon code breaks Blizzard's own code on current
  clients.

## Screen shapes

| Screen | Chat | Bars 4 and 5 |
| --- | --- | --- |
| 16:9, 16:10 | In the console (floats above it at large scales) | Right screen edge |
| 21:9 | In the console | Beside the console |
| 32:9 | In the console | Either side of the console |

The console is sized to the screen's height, so it covers the same share of
the screen at any resolution and UI scale; `/rui scale` adjusts it (default
0.75).

| 21:9 Night Elf | 32:9 Orc |
| --- | --- |
| ![21:9](docs/previews/21x9-nightelf.png) | ![32:9](docs/previews/32x9-orc.png) |

The previews are rendered from the real layout code and textures, with
placeholder icons, portrait, minimap and chat.

## Themes

`auto` (the default) picks a theme from your race: Human, Dwarf and Gnome use
Human; Night Elf uses Night Elf; Orc, Troll and Tauren use Orc; Undead uses
Undead. Change it any time with `/rui theme`.

## Commands

```
/rui theme auto|human|orc|undead|nightelf
/rui layout auto|16:9|21:9|32:9
/rui scale 0.5-1.5
/rui stat tl|tr|br main|offhand|ranged|ammo|spell|heal|none
/rui feeds                       list data feeds and top bar slots
/rui slot <number> <feed>|none   put a feed in a top bar slot
/rui module <actionbars|minimap|chat|unitinfo|stats|target|inventory|blizzard|topbar> on|off   (then /reload)
/rui status
/rui reset
```

## Install

Copy the `ReforgedUI` folder into `World of Warcraft\_classic_\Interface\AddOns`
(or the AddOns folder of your Forever install) and reload.

## Art

The faction textures are extracted from Warcraft III: Reforged; see
[Media/README.md](ReforgedUI/Media/README.md) for each file.

`ReforgedUI/Libs` embeds LibStub (public domain), CallbackHandler-1.0 (BSD) and
LibDataBroker-1.1 (public domain) for the top bar's data feeds.

## Development

- `luacheck ReforgedUI` lints the addon.
- `lua5.1 tools/smoke_test.lua` loads the addon against a stubbed game API and
  exercises login, every layout and theme, combat queuing and the main events.
- `python3 tools/gen_textures.py` regenerates the textures.
- `python3 tools/render_preview.py` re-renders the previews in `docs/previews`.
