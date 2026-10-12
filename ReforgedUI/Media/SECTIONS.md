# Console sections

`<Faction>/sections/` holds the original addon's whole console pieces (themselves cut from
Warcraft III: Reforged's HD console). Unlike `panel`/`edge`/`corner`, each piece
already contains its pillars, so pieces placed edge to edge join like the real
WC3 console. All are uncompressed 32-bit TGA. Pixel positions below are in the
texture, origin top-left; everything above the opaque top is transparent.

The original addon draws every 512x512 section at 288x288 units with its bottom on the
screen bottom, side by side (minimap at x 0, portrait at x 288), and fills gaps
with the `ext` trim pieces at 270x34.

| File | Size | What it is |
| --- | --- | --- |
| `minimap` | 512x512 | Minimap block: wall, pillar and the small button column on its right. Map window x 19-297, y 220-498 (same in every race); top of the wall at y 158-185 |
| `portrait` | 512x512 | Arched portrait section with the stats area to its right; opaque from y 211-237 down. Windows are filled black, so frames sit on top |
| `inventory` | 512x512 | The 2x3 bag/inventory slots plus pillar and the dark window to their right |
| `inventory_none` | 256x512 | Same section without the slot grid (pillar only) |
| `inventory_slim` | 512x512 | Narrower centre without the chat window (Undead and Night Elf only) |
| `actiongrid` | 512x512 | Action-button grid; opaque area x 0-342, y 257-512 |
| `ext1` | 512x64 | Long crenellated wall-top strip, to widen the console |
| `ext2` | 256x64 | Short wall-top strip / step piece |
| `right_top` | 512x128 | Wall top of the console's right end |
| `right_middle` | 32x512 | Right end's side post; stretch it vertically |
| `right_bottom` | 512x64 | Bottom strip of the right end |
| `right_filler_top`, `right_filler_bottom` | 256x128, 256x32 | Top/bottom fillers to widen the right end |
| `right_lid` | 512x512 | L-shaped corner closing the right end (wall top turning down into the post) |
| `right_lid_alt` | 512x512 | Alternative lid (Undead only) |

Rebuild with `D:\Blizzard\wc3-ui-extract\import_sections.py <console art source> ReforgedUI\Media`
(kept outside the repo; it converts the original addon's RLE TGAs).
