#!/usr/bin/env python3
"""Turns terminal captures into the animated demo of the README.

    tools/make-demo.py FRAMES_DIR OUTPUT.gif

FRAMES_DIR holds the screens of a tmux pane saved at regular intervals with
"tmux capture-pane -p -e" (text with colour sequences), named so that they
sort in order, and a file "interval" with the seconds between two captures.
Identical consecutive screens become one image; the long progress phases
(recognised by the "Ctrl-C" hint of the progress window) are sped up.

Needs Pillow and the DejaVu Sans Mono font.
"""
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFont

FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf'
FONT_BOLD = '/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf'
SIZE = 15
CW, CH = 9, 19                 # cell, in pixels
FG, BG = (214, 214, 214), (22, 22, 26)
MARGIN = 8
HOLD_MAX = 2.6                 # longest display of a still screen, seconds
PROGRESS_FRAMES = 40           # images kept for each operation, however long
PROGRESS_SHOW = 0.14           # display of each of them, seconds

BASE16 = [(0, 0, 0), (205, 49, 49), (13, 188, 121), (229, 229, 16), (36, 114, 200),
          (188, 63, 188), (17, 168, 205), (229, 229, 229), (102, 102, 102), (241, 76, 76),
          (35, 209, 139), (245, 245, 67), (59, 142, 234), (214, 112, 214), (41, 184, 219),
          (255, 255, 255)]


def xterm(n):
    if n < 16:
        return BASE16[n]
    if n < 232:
        n -= 16
        return tuple(0 if v == 0 else 55 + 40 * v for v in (n // 36, n // 6 % 6, n % 6))
    v = 8 + 10 * (n - 232)
    return (v, v, v)


def parse(text, cols, rows):
    """-> rows of cells (char, fg, bg, bold)"""
    grid = []
    for number, line in enumerate(text.split('\n')[:rows]):
        cells, fg, bg, bold, rev = [], None, None, False, False
        i = 0
        while i < len(line) and len(cells) < cols:
            if line[i] == '\x1b':
                m = re.match(r'\x1b\[([0-9;]*)m', line[i:])
                if not m:
                    i += 1
                    continue
                p = [int(x) if x else 0 for x in m.group(1).split(';')]
                j = 0
                while j < len(p):
                    c = p[j]
                    if c == 0:
                        fg, bg, bold, rev = None, None, False, False
                    elif c == 1:
                        bold = True
                    elif c == 22:
                        bold = False
                    elif c == 7:
                        rev = True
                    elif c == 27:
                        rev = False
                    elif c in (38, 48) and j + 2 < len(p) and p[j + 1] == 5:
                        if c == 38:
                            fg = xterm(p[j + 2])
                        else:
                            bg = xterm(p[j + 2])
                        j += 2
                    elif 30 <= c <= 37:
                        fg = BASE16[c - 30]
                    elif 90 <= c <= 97:
                        fg = BASE16[c - 82]
                    elif 40 <= c <= 47:
                        bg = BASE16[c - 40]
                    elif c == 39:
                        fg = None
                    elif c == 49:
                        bg = None
                    j += 1
                i += m.end()
                continue
            f, b = fg or FG, bg or BG
            if rev:
                f, b = b, f
            cells.append((line[i], f, b, bold))
            i += 1
        # tmux drops the spaces that end a line: the header and footer bars
        # are continued to the edge
        fill = cells[-1][2] if cells and number in (0, rows - 1) else BG
        cells += [(' ', FG, fill, False)] * (cols - len(cells))
        grid.append(cells)
    grid += [[(' ', FG, BG, False)] * cols] * (rows - len(grid))
    return grid


def render(grid, fonts):
    cols, rows = len(grid[0]), len(grid)
    im = Image.new('RGB', (cols * CW + 2 * MARGIN, rows * CH + 2 * MARGIN), BG)
    d = ImageDraw.Draw(im)
    for r, row in enumerate(grid):
        for c, (ch, fg, bg, bold) in enumerate(row):
            x, y = MARGIN + c * CW, MARGIN + r * CH
            if bg != BG:
                d.rectangle([x, y, x + CW - 1, y + CH - 1], fill=bg)
            if ch == ' ':
                continue
            mx, my = x + CW // 2, y + CH // 2
            # frame characters are drawn, so that they join from cell to cell
            if ch == '─':
                d.line([x, my, x + CW, my], fill=fg)
            elif ch == '━':
                d.rectangle([x, my - 1, x + CW, my + 1], fill=fg)
            elif ch == '│':
                d.line([mx, y, mx, y + CH], fill=fg)
            elif ch in '╭╮╰╯':
                right, down = ch in '╭╰', ch in '╭╮'
                d.line([mx + (2 if right else -2), my, x + CW if right else x, my], fill=fg)
                d.line([mx, my + (2 if down else -2), mx, y + CH if down else y], fill=fg)
                d.point([mx + (1 if right else -1), my + (1 if down else -1)], fill=fg)
            elif 0x2800 <= ord(ch) <= 0x28ff:
                # braille (the spinner): eight dots, two columns of four
                bits = ord(ch) - 0x2800
                for k, (cx, cy) in enumerate([(0, 0), (0, 1), (0, 2), (1, 0), (1, 1), (1, 2), (0, 3), (1, 3)]):
                    if bits >> k & 1:
                        px, py = x + 2 + cx * 4, y + 3 + cy * 4
                        d.rectangle([px, py, px + 1, py + 1], fill=fg)
            else:
                d.text((x, y + 1), ch, font=fonts[bold], fill=fg)
    return im


def main(src, out):
    interval = float(open(os.path.join(src, 'interval')).read())
    names = sorted(n for n in os.listdir(src) if n.endswith('.txt'))
    texts = [open(os.path.join(src, n), encoding='utf-8').read() for n in names]
    plain = [re.sub(r'\x1b\[[0-9;]*m', '', t) for t in texts]
    rows = max(len(p.rstrip('\n').split('\n')) for p in plain)
    cols = max(len(l) for p in plain for l in p.split('\n'))

    # (text, seconds); each progress phase is reduced to a fixed number of images
    shots, k = [], 0
    while k < len(texts):
        if 'Ctrl-C' in plain[k]:
            end = k
            while end < len(texts) and 'Ctrl-C' in plain[end]:
                end += 1
            step = max(1, (end - k) // PROGRESS_FRAMES)
            shots += [[texts[x], PROGRESS_SHOW, True] for x in range(k, end, step)]
            k = end
            continue
        if shots and shots[-1][0] == texts[k] and not shots[-1][2]:
            shots[-1][1] = min(shots[-1][1] + interval, HOLD_MAX)
        else:
            shots.append([texts[k], interval, False])
        k += 1
    shots[-1][1] = HOLD_MAX

    fonts = {False: ImageFont.truetype(FONT, SIZE), True: ImageFont.truetype(FONT_BOLD, SIZE)}
    images = [render(parse(t, cols, rows), fonts) for t, _, _ in shots]
    # one palette for the whole animation, taken from a sample of the screens
    sample = images[::max(1, len(images) // 12)][:12]
    strip = Image.new('RGB', (images[0].width, images[0].height * len(sample)))
    for i, im in enumerate(sample):
        strip.paste(im, (0, i * im.height))
    palette = strip.quantize(colors=96, method=Image.Quantize.MEDIANCUT)
    frames = [im.quantize(palette=palette, dither=Image.Dither.NONE) for im in images]
    frames[0].save(out, save_all=True, append_images=frames[1:], loop=0, optimize=True,
                   duration=[int(s * 1000) for _, s, _ in shots])
    total = sum(s for _, s, _ in shots)
    print('%s: %d images, %.0f s, %dx%d, %.0f kB' % (
        out, len(frames), total, images[0].width, images[0].height, os.path.getsize(out) / 1024))


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
