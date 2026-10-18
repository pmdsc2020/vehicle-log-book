import os, shutil
from playwright.sync_api import sync_playwright
import make_logo as L

REPO = '/home/claude/vehicle-log-book'
RES = f'{REPO}/android/app/src/main/res'
SHARE = '/home/claude/logo/share'
os.makedirs(SHARE, exist_ok=True)
os.makedirs(f'{REPO}/assets/logo', exist_ok=True)

dens = {'mdpi':1,'hdpi':1.5,'xhdpi':2,'xxhdpi':3,'xxxhdpi':4}
with sync_playwright() as pw:
    b = pw.chromium.launch(); p = b.new_page()
    for d, m in dens.items():
        out = f'{RES}/mipmap-{d}'; os.makedirs(out, exist_ok=True)
        L.render(p, L.svg('legacy'), int(48*m), f'{out}/ic_launcher.png')
        L.render(p, L.svg('foreground'), int(108*m), f'{out}/ic_launcher_foreground.png')
        L.render(p, L.svg('mono'), int(108*m), f'{out}/ic_launcher_monochrome.png')
    # in-app logo files
    L.render(p, L.svg('legacy'), 512, f'{REPO}/assets/logo/logo_mark.png')
    L.render(p, L.svg('foreground'), 512, f'{REPO}/assets/logo/logo_glyph.png')
    # files for the user
    L.render(p, L.svg('master'), 1024, f'{SHARE}/vehicle-log-book-logo-1024.png', False)
    L.render(p, L.svg('master'), 512, f'{SHARE}/vehicle-log-book-logo-512.png', False)
    L.render(p, L.svg('legacy'), 512, f'{SHARE}/vehicle-log-book-logo-rounded-512.png')
    # lockup
    mark = L.svg('legacy').replace('width="432" height="432"', 'width="150" height="150"')
    html = f'''<html><head><style>
      @font-face{{font-family:B;font-weight:600;src:url(file:///tmp/fontdl/BarlowSemiCondensed-SemiBold.ttf)}}
      @font-face{{font-family:B;font-weight:400;src:url(file:///tmp/fontdl/BarlowSemiCondensed-Regular.ttf)}}
      body{{margin:0;background:#fff;font-family:B}}
      .row{{display:flex;align-items:center;gap:34px;padding:55px 70px}}
      .t1{{font-size:84px;font-weight:600;color:#0A3F33;line-height:1}}
      .t2{{font-size:36px;color:#4B5E57;margin-top:10px}}
    </style></head><body><div class="row">{mark}<div><div class="t1">Vehicle Log Book</div><div class="t2">Trips, odometer photos and monthly claims</div></div></div></body></html>'''
    open('/tmp/lockup.html','w').write(html); p.set_viewport_size({'width':1100,'height':260}); p.goto('file:///tmp/lockup.html'); p.wait_for_timeout(500)
    p.screenshot(path=f'{SHARE}/vehicle-log-book-logo-lockup.png', clip={'x':0,'y':0,'width':1100,'height':260})
    b.close()

shutil.copy('out/master.svg', f'{SHARE}/vehicle-log-book-logo.svg')
shutil.copy('out/legacy.svg', f'{SHARE}/vehicle-log-book-logo-rounded.svg')

# Android XML
os.makedirs(f'{RES}/mipmap-anydpi-v26', exist_ok=True)
open(f'{RES}/mipmap-anydpi-v26/ic_launcher.xml','w').write('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>
</adaptive-icon>
''')
open(f'{RES}/values/colors.xml','w').write('''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#0D6B55</color>
</resources>
''')
open(f'{RES}/drawable/launch_background.xml','w').write('''<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@color/ic_launcher_background" />
    <item>
        <bitmap android:gravity="center" android:src="@mipmap/ic_launcher_foreground" />
    </item>
</layer-list>
''')
os.makedirs(f'{RES}/values-v31', exist_ok=True)
open(f'{RES}/values-v31/styles.xml','w').write('''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:windowBackground">@drawable/launch_background</item>
        <item name="android:windowSplashScreenBackground">@color/ic_launcher_background</item>
    </style>
</resources>
''')
print('ok')
