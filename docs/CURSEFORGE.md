# Reforged UI

**Your WoW: Forever UI, rebuilt as a Warcraft III console.**

Reforged UI replaces the bottom of your screen with the Warcraft III command console: minimap block, portrait, hero screen, action grid, inventory and chat, all set into one stone (or wood, bone, iron…) wall. A top bar adds a Warcraft III day/night clock, Blizzard's menu buttons and slots for data feeds. Every playable race gets its own console.

It works on 16:9, 16:10, 21:9 and 32:9 screens. On wide screens the console stays centred and leaves the sides free. On 16:10 it scales down to a 16:9 screen's width, so the chat area stays as wide as on 16:9.

---

## A console for every race

The theme follows your character's race automatically, and you can pick any theme yourself.

- **Human**: Warcraft III's stone and gold console
- **Orc**: Warcraft III's wood and iron console
- **Undead**: the Forsaken console (purple and green, banshee crest), or the classic Scourge console if you prefer
- **Night Elf**: Warcraft III's living wood and vines
- **Dwarf**: dark granite and riveted iron, with a forge glow ("Great Forge")
- **Gnome**: Gnomeregan machinery: steel housing, brass cogs, copper pipes and gauges
- **Tauren**: Thunder Bluff timber, coral tent hides, hexagon-painted totem posts and a kodo-head totem
- **Troll**: Darkspear poles bound in crimson rope, tiki masks, tusks and straw cones
- **Skyborne**: wind-swept teal and rose foliage, pale Highborne stone and floating wind-pylons, in two variants: **High Order** (silver and violet) and **Windshapers** (gold and cyan)

Each theme has its own top bar, clock frame, target plate, end caps, damage meter frame and bag frame.

---

## What's on the console

**Minimap block**
- Square minimap with mouse-wheel zoom, and the zone name on its edge.
- Tracking button and mail slot.
- Three extra action slots, which use Action Bar 8, so they bind like any bar.
- Addon minimap buttons are tucked into a compartment: click the bag above the map to open a flyout of them.

**Portrait and hero screen**
- Animated 3D portrait with health and power bars.
- Rest, combat, leader and PvP icons. The portrait pulses red when your health is low.
- Name, level and class, plus an experience bar showing rested XP. Right-click the bar to choose its colour.
- Four stat icons, each showing main hand, off hand (block chance and value with a shield), ranged, ammo, spell power, healing, armour, strength, agility, intellect, crit chance or nothing. Pick them per class from each icon's right-click menu or the options menu. Hover an icon for the details of that slot.

**Target**
- By default the hero screen switches to your target, just like selecting a unit in Warcraft III: portrait, name coloured by reaction, level and type, health and power, combo points and cast bar.
- Prefer seeing both at once? Switch to **wall plate** mode. A small portrait arch with the target's details then stands on the console wall.
- The target's target appears as a small Warcraft III unit icon in your theme's frame. A gem on its corner shows who it is: red, yellow or green by reaction, blue when it's you, and crossed swords when an enemy has you targeted.
- The target's buffs and debuffs show next to it. They work in combat too: they're Blizzard's own aura icons, placed for you.
- Want the target's health closer to the action? Turn on the **target bar** in the options (or `/rui targetbar on`): a small bar with the target's name, level, health and power. Hold Shift and drag it anywhere (out of combat), or move it in Edit Mode. Its health turns red at your HP warning threshold. It works alongside either target display.

**Pet**
- Your pet gets its own unit icon beside the target's target, in your theme's frame: name, portrait, health and power (focus, mana or energy).
- Hunters see their pet's happiness on the portrait. Hover it for the details: damage, whether it's gaining or losing loyalty, and its diet.
- The pet's buffs and debuffs stand above its name, debuffs nearest.
- Left-click targets your pet, right-click opens its menu. **Shift-drag** moves the icon anywhere (out of combat); `/rui pet reset` puts it back.

**Action grid**
- Action bars 1–3, twelve slots each.
- These are Blizzard's own buttons, so bindings, paging, cooldowns and proc glows all work as normal. Icons show in full, in Warcraft III's steel button frame.
- Rather arrange the bars yourself? Turn on **Let Edit Mode place action bars 1-3**: they start over the grid and you can then move, resize and reflow them in Edit Mode like any bar.
- Stance, aura and form buttons stand on the wall above the grid.
- The pet bar starts just above them (in their place, for classes without stances), clear of the chat. Move and resize it in Edit Mode.

**Inventory**
- Your bags in the 2×3 inventory, each with its free slots, plus the classic key ring button on the wall beside them.
- Clicks go through Blizzard's bag buttons, so bag addons like **BetterBags** open as usual.

**Chat area**
- Your main chat window sits in the black panel at the right end of the console.
- Two sliders in the options size it: **Chat height** raises the chat area, and **Chat width** makes it wider on screens too narrow for the full chat area by scaling the console down a little more.
- Prefer it elsewhere? Turn on **Let me move and resize the chat window**, then drag and resize it as you like.

**Top bar**
- The **day/night clock** in the middle, with Blizzard's menu buttons either side of it. A capsule under it shows the time, so you can read it without hovering: server or local time, on a 24 or 12 hour clock, or hidden, from the options.
- Rather not have it? Tick **Hide top bar** in the options (or type `/rui topbar off`): the menu buttons move to just above the minimap, beside the addon button drawer, and your buffs move up to the top edge of the screen.
- **Data broker slots** (LibDataBroker) out to the screen edges. Gold (in gold, silver and copper coins), bag space and durability are filled in by default; hover the gold to see every character's gold, with Horde and Alliance listed and totalled apart (gold can't cross factions). A **Ping & FPS** feed shows your world latency on the left of its slot (green, yellow or red) and your framerate on the right; hover it for home latency and bandwidth. A **Zone** feed shows where you are, coloured by PvP status like the minimap's. Right-click an empty slot (Alt-right-click a filled one) to show any feed from your other addons, or one of the game's own panels: character, spellbook, talents, skills, quest log, social, guild, world map, game menu and the rest your client has. Panels show by name in the theme's menu font; click one to open it, in combat too.

**Damage meter**
- The game's built-in damage meter wears your theme: the top bar's trim around each window, a dark inset, the theme's rail under the header and every bar, and Warcraft III's bar texture and font. The breakdown window that opens on click matches.
- It follows your theme as you switch, and you still move and size the meter in Edit Mode.
- It comes as a separate addon in the same download, **Reforged UI: Damage Meter**. Untick it in the addon list if you'd rather keep Blizzard's look or use another meter.

**Bags**
- Your bag windows wear your theme too: the top bar's trim around each bag, a dark inset, the theme's rail under the title, and the bag's icon in Warcraft III's steel button frame on the corner. Click the icon for Blizzard's bag menu as before.
- Using **BetterBags**? Pick the **Reforged UI** theme in BetterBags' settings and its bag, bank and option windows match, following your theme as you switch. Without BetterBags installed, that part simply stays off.
- It comes as a separate addon in the same download, **Reforged UI: Bags**. Untick it in the addon list to keep your bags as they were.

---

## Edit Mode

The first time each character logs in, Reforged UI creates an Edit Mode layout called **"Reforged UI"** and switches to it. It's a copy of your current layout with these changes:
- The cast bar is above the console.
- Party frames use the raid-style frames, with class colours, power bars, debuffs, aggro highlight and incoming heals turned on.
- The target frame is placed so its buff and debuff icons sit next to the target display.
- Your buffs and debuffs start in the top-right corner, just below the top bar (or at the very top with the top bar hidden).
- The pet bar starts on the console wall, just above the stance buttons (in your other layouts too, unless you've moved it).

When Reforged UI changes the layout it offers a quick reload, so Blizzard's frames pick the change up cleanly.

Frames that Edit Mode manages (buffs and debuffs, pet bar, cast bar, focus, party, quest tracker…) stay wherever Edit Mode puts them. Move them in Edit Mode, and switch layouts any time.

---

## Getting started

1. Install the addon, then **fully restart the game** the first time. A `/reload` isn't enough for new addon files.
2. That's it. Your race's theme, the action bars and the Edit Mode layout are set up automatically.
3. Optional: arrange the focus frame and anything else around the console in Edit Mode.

## Options

Click the **cogwheel** in the bottom-right corner of the chat area, type `/rui config`, or go to **Options → AddOns → Reforged UI**, where the menu opens right inside the game's options. Options include:
- theme and UI scale
- UI size, which makes the console and top bar smaller (70-100%, also `/rui size 85`)
- console transparency, which fades the console's art so the world shows through while buttons, icons, text and the portrait stay solid
- chat width and height
- portrait position
- low-health warning threshold
- zone text position
- the time under the clock: server, local or hidden, 24 or 12 hour
- health and power as percentages
- moving and resizing the chat window yourself
- hiding the top bar
- letting Edit Mode place action bars 1-3
- the four stat icons
- and a few more.

## Commands

```
/rui config                      open the options
/rui theme <name>|auto           pick a theme (auto follows your race)
/rui target swap|plate           target on the hero screen, or a plate on the wall
/rui pet reset                   put the pet icon back beside the target's target
/rui targetbar on|off|reset      a movable target health bar (reset puts it back in place)
/rui feeds                       list data feeds, game panels and top bar slots
/rui slot <number> <feed>|none   put a feed or game panel ("quests", "map") in a top bar slot
/rui size 70-100                 console and top bar size, in %
/rui scale 0.5-1.5               top bar scale
/rui layout auto|16:9|21:9|32:9  top bar layout
/rui topbar on|off               show or hide the top bar
/rui status                      show current settings
/rui reset                       reset settings
```

Theme names: `human`, `dwarf`, `gnome`, `nightelf`, `highorder`, `windshapers`, `skyborne`, `orc`, `tauren`, `troll`, `forsaken`, `undead`.

---

## Good to know

- Blizzard's player and target frames are replaced by the console. The focus frame is left to Edit Mode.
- In combat this client doesn't let any addon read a target's auras. That's why Reforged UI uses Blizzard's own aura icons for the target: they keep working when the fighting starts.
- Names in Korean, Chinese or Cyrillic show properly. The console's font only has Latin letters, so the game's own fonts fill in the rest.
- If you turn Action Bar 8 off, the three slots beside the minimap become empty sockets. Hover them to see how to turn it back on.

## Bugs and suggestions

Found something off? Please report it with a screenshot, your screen resolution and theme, and any error text (BugSack makes this easy).
