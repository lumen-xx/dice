#!/usr/bin/env python3
"""Vendor the JPEG XL encoder (cjxl) from Homebrew bottles into build/vendor/jxl.

Bottles are fetched into Homebrew's cache and unpacked here; nothing is installed or upgraded, so the pinned
webp and exiftool stay as they are. cjxl links a newer libpng than the one bundled for cwebp, so it gets its
own folder: bin/cjxl and lib/*.dylib, with install names relative to the binary.
"""
import json, os, pathlib, shutil, subprocess, tarfile, tempfile
ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / 'build/vendor/jxl'
LICENSES = ROOT / 'vendor/licenses/jpeg-xl'
PIN = 'jpeg-xl', '0.12.0'
ENV = dict(os.environ, HOMEBREW_NO_AUTO_UPDATE='1', HOMEBREW_NO_INSTALL_UPGRADE='1', HOMEBREW_NO_ENV_HINTS='1')
def call(*args): return subprocess.check_output(args, text=True, env=ENV).strip()
def run(*args): subprocess.run(args, check=True, env=ENV, stdout=subprocess.DEVNULL)

info = json.loads(call('brew', 'info', '--json=v2', PIN[0]))['formulae'][0]
if info['versions']['stable'] != PIN[1]:
    raise SystemExit(f'Homebrew now has jpeg-xl {info["versions"]["stable"]}; Dice pins {PIN[1]}. Update the pin deliberately.')
formulas = [PIN[0]] + call('brew', 'deps', '--formula', PIN[0]).split()
with tempfile.TemporaryDirectory() as scratch:
    scratch = pathlib.Path(scratch)
    libraries, prefixes = {}, {}
    for formula in formulas:
        run('brew', 'fetch', '--formula', formula)
        bottle = pathlib.Path(call('brew', '--cache', '--formula', formula))
        with tarfile.open(bottle) as archive: archive.extractall(scratch / formula, filter='data')
        prefix = next((scratch / formula / formula).iterdir())
        prefixes[formula] = prefix
        for dylib in (prefix / 'lib').glob('*.dylib'): libraries.setdefault(dylib.name, dylib)
    if OUT.exists(): shutil.rmtree(OUT)
    (OUT / 'bin').mkdir(parents=True); (OUT / 'lib').mkdir()
    binary = OUT / 'bin/cjxl'
    shutil.copy2(prefixes[PIN[0]] / 'bin/cjxl', binary)
    copied = set()
    def relocate(path, loader):
        path.chmod(0o755)
        for line in call('otool', '-L', str(path)).splitlines()[1:]:
            dep = line.strip().split(' (')[0]
            if dep.startswith(('/usr/lib/', '/System/')): continue
            name = pathlib.Path(dep).name
            if name == path.name: continue
            if name not in libraries: raise SystemExit('Cannot resolve dependency: ' + dep)
            if name not in copied:
                copied.add(name)
                target = OUT / 'lib' / name
                shutil.copy2(libraries[name].resolve(), target)
                target.chmod(0o755)
                run('install_name_tool', '-id', '@rpath/' + name, str(target))
                relocate(target, '@loader_path/')
            run('install_name_tool', '-change', dep, loader + name, str(path))
        for rpath in [l.split()[1] for l in call('otool', '-l', str(path)).replace('\n         path ', '\nRPATH ').splitlines() if l.startswith('RPATH ')]:
            run('install_name_tool', '-delete_rpath', rpath, str(path))
    relocate(binary, '@loader_path/../lib/')
    for file in list((OUT / 'lib').glob('*.dylib')) + [binary]: run('codesign', '--force', '--sign', '-', str(file))
    # Licences of everything that ships: the formula of each copied library, and jpeg-xl itself.
    owners = {PIN[0]} | {f for f, p in prefixes.items() if any((p / 'lib' / n).exists() for n in copied)}
    if LICENSES.exists(): shutil.rmtree(LICENSES)
    for formula in sorted(owners):
        found = [f for f in prefixes[formula].iterdir() if f.is_file() and f.name.upper().startswith(('LICENSE', 'COPYING', 'LICENCE', 'PATENTS', 'README.IJG', 'NOTICE'))]
        found += [f for f in (prefixes[formula] / 'share/doc').rglob('*') if f.is_file() and f.name.upper().startswith(('LICENSE', 'COPYING', 'PATENTS', 'README.IJG'))] if (prefixes[formula] / 'share/doc').exists() else []
        if not found: raise SystemExit('No licence file in the ' + formula + ' bottle')
        (LICENSES / formula).mkdir(parents=True, exist_ok=True)
        for f in found: shutil.copy2(f, LICENSES / formula / f.name)
    versions = {f: json.loads(call('brew', 'info', '--json=v2', f))['formulae'][0]['versions']['stable'] for f in sorted(owners)}
    (LICENSES / 'VERSIONS.txt').write_text(''.join(f'{f} {v}\n' for f, v in versions.items()))
print(call(str(binary), '--version').splitlines()[0])
print('Libraries:', ', '.join(sorted(copied)))
print(f'{sum(f.stat().st_size for f in OUT.rglob("*") if f.is_file()) / 1e6:.2f} MB')
