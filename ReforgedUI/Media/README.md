# Media

Every faction folder (`Human`, `Orc`, `Undead`, `NightElf`) holds the same files.
The addon loads them without a file extension, so a `.blp` or `.tga` with the same
name replaces the generated art. Sizes must stay powers of two.

| File | Size | Used for |
| --- | --- | --- |
| `panel` | 256x256 | Tiled fill of the console panels |
| `edge` | 128x32 | Top trim, tiled horizontally; outer side at the top |
| `edgev` | 32x128 | Side trim, tiled vertically; outer side on the left |
| `corner` | 64x64 | Corner ornament for the top-left corner (mirrored for the right) |
| `well` | 64x64 | Socket behind each action, inventory and bag slot |
| `crest` | 256x256 | Faction emblem above the portrait |
| `clockframe` | 256x128 | Frame around the day/night clock under the top bar; the dial's centre is the top-middle of the texture (4 units down at 176x88) |

`Common/bevel` (64x64) is drawn over every button icon. `Common/dial` (256x256)
is the day/night disc: sun at the bottom, moon at the top. It turns with the
server time and only its lower half shows below the top bar.

The current files are original procedural art from `tools/gen_textures.py`;
re-run it to regenerate them. Running it overwrites every file here, including
art copied in from elsewhere.
