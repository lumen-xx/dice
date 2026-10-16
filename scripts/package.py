#!/usr/bin/env python3
"""Build an Apple-silicon development app using pinned Homebrew tool versions."""
import pathlib, subprocess, shutil, plistlib, re, os, tempfile, json, argparse
ROOT = pathlib.Path(__file__).resolve().parent.parent
BUILD = ROOT / 'build'
APP = BUILD / 'Dice.app'
UPDATE_CONFIG = json.loads((ROOT / 'updates/config.json').read_text())
VERSION = json.loads((ROOT / 'updates/version.json').read_text())
def call(*args): return subprocess.check_output(args, text=True).strip()
def run(*args): subprocess.run(args, check=True)
def prepare_tools(destination):
    renderer = BUILD / 'vendor/resvg/bin/resvg'
    if not renderer.exists() or call(str(renderer), '--version') != '0.48.1':
        raise SystemExit('Build the pinned SVG renderer: cargo install resvg --version 0.48.1 --locked --root build/vendor/resvg')
    optimizer = BUILD / 'vendor/oxipng/bin/oxipng'
    if not optimizer.exists() or call(str(optimizer), '--version') != 'oxipng 10.2.1':
        raise SystemExit('Build the pinned PNG optimizer: cargo install oxipng --version 10.2.1 --locked --root build/vendor/oxipng')
    encoder = BUILD / 'vendor/jxl/bin/cjxl'
    if not encoder.exists() or not call(str(encoder), '--version').startswith('cjxl v0.12.0 '):
        raise SystemExit('Vendor the pinned JPEG XL encoder: python3 scripts/vendor-jxl.py')
    exifprefix = pathlib.Path(call('brew', '--prefix', 'exiftool'))
    webpprefix = pathlib.Path(call('brew', '--prefix', 'webp'))
    webpversion = call(str(webpprefix / 'bin/cwebp'), '-version')
    if webpversion.splitlines()[0] != '1.6.0': raise SystemExit('This preview pins WebP 1.6.0.')
    version = call(str(exifprefix / 'bin/exiftool'), '-ver')
    if version != '13.50': raise SystemExit('This preview pins ExifTool 13.50. Update the pin deliberately before using another version.')
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copy2(renderer, destination / 'resvg')
    run('codesign', '--force', '--sign', '-', str(destination / 'resvg'))
    shutil.copy2(optimizer, destination / 'oxipng')
    run('codesign', '--force', '--sign', '-', str(destination / 'oxipng'))
    exif = destination / 'exiftool'; exif.mkdir(exist_ok=True)
    script = (exifprefix / 'bin/exiftool').read_text()
    script = '\n'.join(line for line in script.split('\n') if not (line.startswith('unshift @INC,') and '/opt/homebrew/' in line))
    # The Artistic License asks for a notice in each changed file saying how it was changed.
    first, rest = script.split('\n', 1)
    script = first + '\n# Modified for Dice: the Homebrew-specific "unshift @INC" lines were removed so the bundled modules are used.\n' + rest
    (exif / 'exiftool').write_text(script)
    lib = exif / 'lib'; lib.mkdir(exist_ok=True)
    source = exifprefix / 'libexec/lib/perl5'
    shutil.copytree(source / 'Image', lib / 'Image', dirs_exist_ok=True)
    (lib / 'File').mkdir(exist_ok=True)
    shutil.copy2(source / 'File/RandomAccess.pm', lib / 'File/RandomAccess.pm')
    # Documentation is shipped through links and notices, not duplicated inside the engine.
    for pod in lib.rglob('*.pod'): pod.unlink()
    binary = destination / 'cwebp'
    shutil.copy2(webpprefix / 'bin/cwebp', binary)
    # img2webp writes animated WebP; it shares cwebp's bundled libraries.
    animator = destination / 'img2webp'
    shutil.copy2(webpprefix / 'bin/img2webp', animator)
    dylibs = destination / 'lib'; dylibs.mkdir(exist_ok=True)
    seen = set()
    def bundle(binary_path):
        lines = call('otool', '-L', str(binary_path)).splitlines()[1:]
        for line in lines:
            dep = line.strip().split(' (')[0]
            if dep.startswith('/usr/lib/') or dep.startswith('/System/'): continue
            name = pathlib.Path(dep).name
            if binary_path.name == name: continue
            original = pathlib.Path(dep) if dep.startswith('/') else webpprefix / 'lib' / name
            if not original.exists(): raise SystemExit('Cannot resolve dependency: ' + dep)
            target = dylibs / name
            if name not in seen:
                seen.add(name); shutil.copy2(original.resolve(), target); target.chmod(0o755)
                run('install_name_tool', '-id', '@rpath/' + name, str(target))
                bundle(target)
            replacement = ('@loader_path/lib/' if binary_path in (binary, animator) else '@loader_path/') + name
            run('install_name_tool', '-change', dep, replacement, str(binary_path))
    binary.chmod(0o755); bundle(binary)
    animator.chmod(0o755); bundle(animator)
    for file in list(dylibs.glob('*.dylib')) + [binary, animator]: run('codesign', '--force', '--sign', '-', str(file))
    # cjxl keeps its own libraries (it needs a newer libpng than cwebp); scripts/vendor-jxl.py relocated and signed them.
    shutil.copytree(BUILD / 'vendor/jxl', destination / 'jxl', dirs_exist_ok=True)
    for file in list((destination / 'jxl/lib').glob('*.dylib')) + [destination / 'jxl/bin/cjxl']: run('codesign', '--force', '--sign', '-', str(file))
    shutil.copytree(ROOT / 'vendor/licenses', destination / 'Licenses', dirs_exist_ok=True)
    (destination / 'versions.txt').write_text('ExifTool 13.50\nresvg 0.48.1\noxipng 10.2.1\ncjxl 0.12.0\n' + call(str(binary), '-version') + '\n')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dev', action='store_true', help='Build Dice Dev without Finder Services or file associations.')
    args = parser.parse_args()
    if args.dev: APP = BUILD / 'Dice Dev.app'
    run('swift', 'build', '-c', 'release', '--package-path', str(ROOT))
    if APP.exists(): shutil.rmtree(APP)
    contents = APP / 'Contents'
    (contents / 'MacOS').mkdir(parents=True)
    resources = contents / 'Resources'; resources.mkdir()
    sparkle_root = ROOT / '.build/artifacts/sparkle/Sparkle'
    framework = sparkle_root / 'Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework'
    (contents / 'Frameworks').mkdir()
    shutil.copytree(framework, contents / 'Frameworks/Sparkle.framework', symlinks=True)
    shutil.copy2(sparkle_root / 'LICENSE', resources / 'Sparkle-LICENSE.txt')
    binpath = pathlib.Path(call('swift', 'build', '-c', 'release', '--show-bin-path', '--package-path', str(ROOT)))
    shutil.copy2(binpath / 'Dice', contents / 'MacOS/Dice')
    prepare_tools(resources / 'Tools')
    shutil.copy2(ROOT / 'THIRD_PARTY_NOTICES.md', resources)
    plist = dict(CFBundleExecutable='Dice', CFBundleIdentifier='com.opyuii.dice', CFBundleName='Dice', CFBundleDisplayName='Dice', CFBundlePackageType='APPL', CFBundleShortVersionString=VERSION['version'], CFBundleVersion=str(VERSION['build']), LSMinimumSystemVersion='14.0', LSUIElement=True, NSHighResolutionCapable=True, CFBundleIconFile='Dice', CFBundleDocumentTypes=[dict(CFBundleTypeName='Image', CFBundleTypeRole='Viewer', LSItemContentTypes=['public.image', 'public.svg-image', 'com.adobe.pdf'], LSHandlerRank='Alternate')], SUFeedURL=UPDATE_CONFIG['feed_url'], SUPublicEDKey=UPDATE_CONFIG['public_key'], SUEnableAutomaticChecks=False, SUAutomaticallyUpdate=False, SUEnableSystemProfiling=False, SUVerifyUpdateBeforeExtraction=True, SURequireSignedFeed=True, SUSignedFeedFailureExpirationInterval=0)
    plist['NSServices'] = [dict(
        NSMenuItem={'default': 'Edit with Dice'}, NSMessage='editWithDice', NSPortName='Dice',
        NSSendTypes=['public.file-url', 'NSFilenamesPboardType'],
        NSSendFileTypes=['public.image', 'public.svg-image', 'com.adobe.pdf'],
        NSRequiredContext={'NSServiceApplicationIdentifier': 'com.apple.finder'}
    )]
    plist['DiceDevelopmentBuild'] = args.dev
    if args.dev:
        plist.update(CFBundleIdentifier='com.opyuii.dice.dev', CFBundleName='Dice Dev', CFBundleDisplayName='Dice Dev')
        plist.pop('NSServices', None)
        plist.pop('CFBundleDocumentTypes', None)
    (contents / 'Info.plist').write_bytes(plistlib.dumps(plist))
    run('swift', str(ROOT / 'scripts/icon.swift'), str(BUILD))
    run('iconutil', '-c', 'icns', str(BUILD / 'Dice.iconset'), '-o', str(resources / 'Dice.icns'))
    for key in ('com.apple.FinderInfo', 'com.apple.ResourceFork'):
        subprocess.run(['xattr', '-dr', key, str(APP)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    # A stable identity keeps macOS privacy permissions across updates; an ad-hoc signature changes with every build.
    keychain = call('bash', str(ROOT / 'scripts/signing-identity.sh'))
    run('codesign', '--force', '--keychain', keychain, '--sign', 'Dice Local Signing', str(APP))
    requirement = subprocess.run(['codesign', '-d', '--requirements', '-', str(APP)], capture_output=True, text=True)
    if 'certificate leaf' not in requirement.stdout + requirement.stderr:
        raise SystemExit('Dice was not signed with the stable identity.')
    run('codesign', '--verify', '--deep', '--strict', str(APP))
    size = sum(f.stat().st_size for f in APP.rglob('*') if f.is_file())
    print(f'Installed app: {size / 1_000_000:.2f} MB')
    if size >= 45_000_000: raise SystemExit('App exceeds the 45 MB budget')
    archive = BUILD / (('Dice-Dev-v' if args.dev else 'Dice-v') + VERSION['version'] + '-apple-silicon.zip')
    if archive.exists(): archive.unlink()
    run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(APP), str(archive))
    (BUILD / ('dev-app-path.txt' if args.dev else 'app-path.txt')).write_text(str(APP))
    print(f'Download: {archive.stat().st_size / 1_000_000:.2f} MB\n{APP}')
