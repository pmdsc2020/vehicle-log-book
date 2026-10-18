import sys, os, json
from playwright.sync_api import sync_playwright


from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
_font = TTFont('/tmp/fontdl/BarlowSemiCondensed-Bold.ttf')
_gs = _font.getGlyphSet(); _cmap = _font.getBestCmap(); _upm = _font['head'].unitsPerEm
def digit_path(ch, cx, cy, height):
    """Outline of one digit, centred at (cx, cy), `height` tall (cap height)."""
    g = _gs[_cmap[ord(ch)]]
    cap = _font['OS/2'].sCapHeight or 700
    sc = height / cap
    w = g.width * sc
    pen = SVGPathPen(_gs)
    tp = TransformPen(pen, (sc, 0, 0, -sc, cx - w/2, cy + height/2))
    g.draw(tp)
    return pen.getCommands()

GREEN='#0D6B55'; DEEP='#0A5443'; AMBER='#F2A93B'; WHITE='#FFFFFF'

def art(fill=WHITE, hole=GREEN, last=AMBER, cell_fill=None):
    """Foreground artwork on a 108x108 canvas, inside the 66dp safe zone."""
    cell_fill = cell_fill or fill
    cells = ''
    x0, w, gap, y, h = 33.3, 9.0, 1.8, 70.0, 11.0
    for i in range(4):
        c = last if i == 3 else cell_fill
        cx = x0 + i*(w+gap) + w/2
        cells += f'<rect x="{x0 + i*(w+gap):.1f}" y="{y}" width="{w}" height="{h}" rx="2.2" fill="{c}"/>'
        cells += f'<path d="{digit_path("0426"[i], cx, y + h/2, 6.4)}" fill="{hole}"/>'
    return f'''
    <path d="M54 65 C54 65 38.5 52 38.5 41 A15.5 15.5 0 1 1 69.5 41 C69.5 52 54 65 54 65 Z" fill="{fill}"/>
    <circle cx="54" cy="39.2" r="6" fill="{hole}"/>
    <path d="M51.3 42.5 L56.7 42.5 L58.4 51 Q58.5 51.8 57.7 51.8 L50.3 51.8 Q49.5 51.8 49.6 51 Z" fill="{hole}"/>
    {cells}'''

def svg(kind, size=432):
    if kind == 'foreground':   # transparent, adaptive foreground
        body = art()
        bg = ''
    elif kind == 'mono':       # themed icon: single colour, transparent holes
        body = f'''
        <defs><mask id="m"><rect width="108" height="108" fill="#fff"/>
          <circle cx="54" cy="39.2" r="6" fill="#000"/>
          <path d="M51.3 42.5 L56.7 42.5 L58.4 51 Q58.5 51.8 57.7 51.8 L50.3 51.8 Q49.5 51.8 49.6 51 Z" fill="#000"/></mask></defs>
        <g mask="url(#m)"><path d="M54 65 C54 65 38.5 52 38.5 41 A15.5 15.5 0 1 1 69.5 41 C69.5 52 54 65 54 65 Z" fill="#000"/></g>
        ''' + ''.join(f'<rect x="{33.3+i*10.8:.1f}" y="70" width="9" height="11" rx="2.2" fill="#000"/>' for i in range(4))
        bg = ''
    elif kind == 'legacy':     # full icon, rounded square, art enlarged
        body = f'<g transform="translate(54 54) scale(1.22) translate(-54 -53)">{art()}</g>'
        bg = f'<rect width="108" height="108" rx="24" fill="{GREEN}"/>'
    elif kind == 'master':     # store / share icon
        body = f'<g transform="translate(54 54) scale(1.22) translate(-54 -53)">{art()}</g>'
        bg = f'<rect width="108" height="108" fill="{GREEN}"/>'
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 108 108" width="{size}" height="{size}">{bg}{body}</svg>'

def render(pw_page, svg_str, size, path, transparent=True):
    html = f'<html><body style="margin:0;background:transparent">{svg_str.replace("width=\"432\" height=\"432\"", f"width=\"{size}\" height=\"{size}\"")}</body></html>'
    pw_page.set_viewport_size({'width': size, 'height': size})
    pw_page.set_content(html)
    pw_page.screenshot(path=path, omit_background=transparent, clip={'x':0,'y':0,'width':size,'height':size})

if __name__ == '__main__':
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    with sync_playwright() as pw:
        b = pw.chromium.launch(); p = b.new_page()
        for k in ('foreground','mono','legacy','master'):
            open(f'{out}/{k}.svg','w').write(svg(k))
        render(p, svg('master', 512), 512, f'{out}/preview_master.png', False)
        render(p, svg('legacy', 192), 192, f'{out}/preview_legacy192.png')
        render(p, svg('legacy', 48), 48, f'{out}/preview_legacy48.png')
        render(p, svg('foreground', 432), 432, f'{out}/preview_fg.png')
        b.close()
