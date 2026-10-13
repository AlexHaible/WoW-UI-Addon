# Media

The top bar's textures. The console's own art is the original addon's, in `../art`.

Every theme folder (`Human`, `Orc`, `Undead`, `NightElf`, and the race themes
`Dwarf`, `Gnome`, `Tauren`, `Troll`, `HighOrder`, `Windshapers`) holds the same
files. The race theme folders are recoloured from a faction folder by
`tools/make_race_themes.py`; edit the palettes there rather than the files.
The addon loads them without a file extension, so a `.blp` or `.tga` with the same
name replaces them. Sizes must stay powers of two.

| File | Size | Used for |
| --- | --- | --- |
| `panel` | 256x256 | Tiled fill of the top bar |
| `edge` | 256x32 | Crenellated wall top, tiled horizontally (every 128 units at 16 thick) |
| `edgev` | 32x128 | Side post, tiled vertically; outer side on the left |
| `corner` | 64x64 | End of the wall top (mirrored for the left) |
| `clockframe` | 256x128 | Frame around the day/night clock under the top bar; the dial's centre is the top-middle of the texture (4 units down at 176x88) |

`Common/dial` (256x256) is the day/night disc: sun at the bottom, moon at the
top. It turns with the server time and only its lower half shows below the top
bar.

`Common/iconframe` (128x128) is Warcraft III's steel command-button frame with
a transparent centre and a soft inner shadow, to lay over action, bag and
inventory icons (SetAllPoints on the button, above the icon). The frame band is
6 px of 128 (about 5% per side), so crop the icon's own border with texcoords
around 0.07-0.93 as before. Taken from the HD BTN icons, where the frame is
baked in (the PASBTN versions have none), by
`D:\Blizzard\wc3-ui-extract\make_iconframe.py`.

The faction files and `Common/dial` are cropped from Warcraft III: Reforged's HD
console art (`_hd.w3mod/ui/console/<race>/<race>uitile0N`, `-timeindicatorframe`
and the `humanuitile-timeindicator` sky strip). Blizzard owns that art, so keep
this repo private. The dial is built from the scrolling sky strip with its sun
and moon centred 0.52 × radius from the middle, which matches the clock window
at `dialR = 52`, `clockW/H = 176x88`.

`tools/gen_textures.py` makes the original procedural art (it also writes
files the addon no longer uses). It refuses to overwrite existing files unless
run with `--force`.

`edge`, `edgev` and `corner` are cut from the original addon's console pieces (themselves
cut from Warcraft III) by `tools/import_console_art.py <console art source>`.
