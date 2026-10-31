#!/usr/bin/env python3
"""Builds the reviewer: one standalone HTML file (web/vehicle-log-reviewer.html) and an artifact fragment
(web/dist/reviewer-artifact.html) from web/src. No packages needed.  python3 web/build.py"""
import pathlib, re

here = pathlib.Path(__file__).parent
src = here / 'src'
dist = here / 'dist'
dist.mkdir(exist_ok=True)

def rd(name):
    return (src / name).read_text(encoding='utf-8')

def script_safe(text):
    # A literal "</script" inside inline code would end the tag early.
    return re.sub(r'</(script)', r'<\\/\1', text, flags=re.I)

css = rd('fonts.css') + '\n' + rd('app.css')
core = script_safe(rd('core.js'))
app = script_safe("(function () {\n'use strict';\n" + '\n'.join(rd(n) for n in ['app-1.js', 'app-2.js', 'app-3.js']) + "\n})();\n")
body = '<div id="root"></div>\n<input type="file" id="filein" multiple hidden>\n<noscript>The reviewer needs JavaScript.</noscript>\n'
title = 'Vehicle Log Reviewer'

standalone = (
    '<!doctype html>\n<html lang="en"><head><meta charset="utf-8">'
    '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">'
    '<meta name="color-scheme" content="light dark">'
    f'<title>{title}</title>\n<style>\n{css}\n</style></head>\n<body>\n{body}<script>\n{core}\n</script>\n<script>\n{app}\n</script>\n</body></html>\n'
)
fragment = (
    f'<title>{title}</title>\n<meta name="claude:viewport-fit-sides" content="cover">\n<style>\n{css}\n</style>\n'
    f'{body}<script>\n{core}\n</script>\n<script>\n{app}\n</script>\n'
)
(here / 'vehicle-log-reviewer.html').write_text(standalone, encoding='utf-8')
(dist / 'reviewer-artifact.html').write_text(fragment, encoding='utf-8')
print('standalone', len(standalone) // 1024, 'KB; artifact', len(fragment) // 1024, 'KB')
