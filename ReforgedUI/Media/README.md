# Media

The top bar's textures. The console's own art is the original addon's, in `../art`.

Every faction folder (`Human`, `Orc`, `Undead`, `NightElf`) holds the same files.
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
