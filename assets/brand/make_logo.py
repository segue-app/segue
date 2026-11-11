"""Segue's mark: an S whose upper half is one solid ribbon and whose lower
half unravels into three strands — one song flowing into the next.
Writes the icon (dark squircle) and the bare mark (transparent)."""
import math, sys

def pt(cx, cy, r, deg):
    a = math.radians(deg)
    return cx + r * math.cos(a), cy + r * math.sin(a)

def arc(cx, cy, r, a0, a1, sweep):
    s, e = pt(cx, cy, r, a0), pt(cx, cy, r, a1)
    large = 1 if abs(a1 - a0) > 180 else 0
    return f"M{s[0]:.1f},{s[1]:.1f} A{r},{r} 0 {large} {sweep} {e[0]:.1f},{e[1]:.1f}"

def mark(scale=1.0, ox=0, oy=0):
    R, W = 112, 84            # ribbon radius and width
    top, bot = 400, 624       # circle centres (x = 512)
    gap = 6
    sw = (W - 2 * gap) / 3    # strand width; strands fill the ribbon exactly
    radii = [R - W / 2 + sw / 2 + i * (sw + gap) for i in range(3)]
    ends = [168, 150, 128]    # inner strand runs longest: a staggered fade
    parts = [
        # ribbon: square at the split, round at its free end
        f'<path d="{arc(512, top, R, -30, -270, 0)}" stroke-width="{W}" stroke-linecap="butt"/>',
        f'<circle cx="{pt(512, top, R, -30)[0]:.1f}" cy="{pt(512, top, R, -30)[1]:.1f}" r="{W/2}" fill="url(#ink)" stroke="none"/>',
    ]
    for r, end in zip(radii, ends):
        # Square where they leave the ribbon, round where they fade out.
        ex, ey = pt(512, bot, r, end)
        parts.insert(0,
            f'<path d="{arc(512, bot, r, -90.5, end, 1)}" stroke-width="{sw:.1f}" stroke-linecap="butt"/>'
            f'<circle cx="{ex:.1f}" cy="{ey:.1f}" r="{sw/2:.1f}" fill="url(#ink)" stroke="none"/>')
    return (f'<g transform="translate({ox},{oy}) scale({scale})" fill="none" '
            f'stroke="url(#ink)">' + ''.join(parts) + '</g>')

INK = '''<linearGradient id="ink" gradientUnits="userSpaceOnUse" x1="380" y1="270" x2="640" y2="780">
  <stop offset="0" stop-color="#FFB86B"/><stop offset="0.42" stop-color="#FF5E8A"/>
  <stop offset="1" stop-color="#7B5CFF"/></linearGradient>'''

def icon(bg=True):
    defs = INK
    body = ''
    if bg:
        defs += '''
<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#1E1726"/><stop offset="1" stop-color="#0A090E"/></linearGradient>
<radialGradient id="glow" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#FF5E8A" stop-opacity="0.32"/><stop offset="0.6" stop-color="#7B5CFF" stop-opacity="0.08"/><stop offset="1" stop-color="#7B5CFF" stop-opacity="0"/></radialGradient>'''
        body = ('<rect width="1024" height="1024" rx="230" fill="url(#bg)"/>'
                '<circle cx="512" cy="520" r="430" fill="url(#glow)"/>')
    # The mark is ~470 px tall; centre it.
    m = mark(scale=1.18, ox=512 - 512 * 1.18, oy=512 - 512 * 1.18)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">'
            f'<defs>{defs}</defs>{body}{m}</svg>')

open('segue_icon.svg', 'w').write(icon(True))
open('segue_mark.svg', 'w').write(icon(False))

BG = '''
<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#1E1726"/><stop offset="1" stop-color="#0A090E"/></linearGradient>
<radialGradient id="glow" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#FF5E8A" stop-opacity="0.32"/><stop offset="0.6" stop-color="#7B5CFF" stop-opacity="0.08"/><stop offset="1" stop-color="#7B5CFF" stop-opacity="0"/></radialGradient>
<filter id="shadow" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="18"/></filter>'''

def variant(name, *, size=1024, inset=0, radius=230, mark_scale=1.18, bg=True, shadow=False):
    """inset: transparent margin around the tile (macOS); radius 0 = square."""
    tile = size - 2 * inset
    k = tile / 1024
    s = mark_scale * k
    body = ''
    if bg:
        shade = (f'<rect x="{inset}" y="{inset + 14}" width="{tile}" height="{tile}" '
                 f'rx="{radius * k}" fill="#000" opacity="0.4" filter="url(#shadow)"/>'
                 if shadow else '')
        body = (shade + f'<g transform="translate({inset},{inset}) scale({k})">'
                f'<rect width="1024" height="1024" rx="{radius}" fill="url(#bg)"/>'
                f'<circle cx="512" cy="520" r="430" fill="url(#glow)"/></g>')
    c = size / 2
    m = mark(scale=s, ox=c - 512 * s, oy=c - 512 * s)
    open(name, 'w').write(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}">'
        f'<defs>{INK}{BG}</defs>{body}{m}</svg>')

variant('icon_square.svg', radius=0)                         # iOS, Android legacy
variant('icon_macos.svg', inset=100, radius=185, shadow=True)  # macOS tile
variant('icon_foreground.svg', bg=False, mark_scale=0.78)    # Android adaptive
variant('icon_rounded.svg')                                  # Windows, Linux, web

def social(name='social_preview.svg'):
    """1280x640 card for link previews (GitHub social preview)."""
    s = 0.8
    m = mark(scale=s, ox=265 - 512 * s, oy=320 - 512 * s)
    chips = ['YouTube', 'SoundCloud', 'Lyrics', 'Equalizer', 'Sync']
    x, out = 504, []
    for c in chips:
        w = 30 + len(c) * 13
        out.append(f'<rect x="{x}" y="430" width="{w:.0f}" height="44" rx="22" fill="#ffffff" fill-opacity="0.08"/>'
                   f'<text x="{x + w/2:.0f}" y="459" text-anchor="middle" font-size="22" font-weight="600" fill="#E9E4F0">{c}</text>')
        x += w + 12
    open(name, 'w').write(f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1280 640" font-family="Helvetica Neue, Helvetica, Arial, sans-serif">
<defs>{INK}{BG}
<radialGradient id="g2" cx="0.25" cy="0.5" r="0.6"><stop offset="0" stop-color="#FF5E8A" stop-opacity="0.30"/><stop offset="0.5" stop-color="#7B5CFF" stop-opacity="0.10"/><stop offset="1" stop-color="#7B5CFF" stop-opacity="0"/></radialGradient></defs>
<rect width="1280" height="640" fill="url(#bg)"/><rect width="1280" height="640" fill="url(#g2)"/>
{m}
<text x="498" y="280" font-size="124" font-weight="800" letter-spacing="-5" fill="#F6F2FA">Segue</text>
<text x="504" y="352" font-size="32" font-weight="500" fill="#B9B2C6">Open-source music player for every device</text>
{''.join(out)}
<text x="504" y="548" font-size="22" font-weight="500" fill="#7E768C">Android · iOS · Windows · macOS · Linux</text>
</svg>''')

social()
variant('avatar.svg', radius=0, mark_scale=1.25)
