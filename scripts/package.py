#!/usr/bin/env python3
"""Build an Apple-silicon development app using pinned Homebrew tool versions."""
import pathlib, subprocess, shutil, plistlib, re, os, tempfile, json
ROOT = pathlib.Path(__file__).resolve().parent.parent
BUILD = ROOT / 'build'
APP = BUILD / 'Dice.app'
UPDATE_CONFIG = json.loads((ROOT / 'updates/config.json').read_text())
VERSION = json.loads((ROOT / 'updates/version.json').read_text())
def call(*args): return subprocess.check_output(args, text=True).strip()
def run(*args): subprocess.run(args, check=True)
def prepare_tools(destination):
    exifprefix = pathlib.Path(call('brew', '--prefix', 'exiftool'))
    webpprefix = pathlib.Path(call('brew', '--prefix', 'webp'))
    webpversion = call(str(webpprefix / 'bin/cwebp'), '-version')
    if webpversion.splitlines()[0] != '1.6.0': raise SystemExit('This preview pins WebP 1.6.0.')
    version = call(str(exifprefix / 'bin/exiftool'), '-ver')
    if version != '13.50': raise SystemExit('This preview pins ExifTool 13.50. Update the pin deliberately before using another version.')
    destination.mkdir(parents=True, exist_ok=True)
    exif = destination / 'exiftool'; exif.mkdir(exist_ok=True)
    script = (exifprefix / 'bin/exiftool').read_text()
    script = '\n'.join(line for line in script.split('\n') if not (line.startswith('unshift @INC,') and '/opt/homebrew/' in line))
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
            replacement = ('@loader_path/lib/' if binary_path == binary else '@loader_path/') + name
            run('install_name_tool', '-change', dep, replacement, str(binary_path))
    binary.chmod(0o755); bundle(binary)
    for file in list(dylibs.glob('*.dylib')) + [binary]: run('codesign', '--force', '--sign', '-', str(file))
    shutil.copytree(ROOT / 'vendor/licenses', destination / 'Licenses', dirs_exist_ok=True)
    (destination / 'versions.txt').write_text('ExifTool 13.50\n' + call(str(binary), '-version') + '\n')

if __name__ == '__main__':
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
    plist = dict(CFBundleExecutable='Dice', CFBundleIdentifier='com.opyuii.dice', CFBundleName='Dice', CFBundleDisplayName='Dice', CFBundlePackageType='APPL', CFBundleShortVersionString=VERSION['version'], CFBundleVersion=str(VERSION['build']), LSMinimumSystemVersion='14.0', LSUIElement=True, NSHighResolutionCapable=True, CFBundleIconFile='Dice', CFBundleDocumentTypes=[dict(CFBundleTypeName='Image', CFBundleTypeRole='Viewer', LSItemContentTypes=['public.image'], LSHandlerRank='Alternate')], SUFeedURL=UPDATE_CONFIG['feed_url'], SUPublicEDKey=UPDATE_CONFIG['public_key'], SUEnableAutomaticChecks=False, SUAutomaticallyUpdate=False, SUEnableSystemProfiling=False, SUVerifyUpdateBeforeExtraction=True, SURequireSignedFeed=True, SUSignedFeedFailureExpirationInterval=0)
    (contents / 'Info.plist').write_bytes(plistlib.dumps(plist))
    run('swift', str(ROOT / 'scripts/icon.swift'), str(BUILD))
    run('iconutil', '-c', 'icns', str(BUILD / 'Dice.iconset'), '-o', str(resources / 'Dice.icns'))
    for key in ('com.apple.FinderInfo', 'com.apple.ResourceFork'):
        subprocess.run(['xattr', '-dr', key, str(APP)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    run('codesign', '--force', '--sign', '-', str(APP))
    run('codesign', '--verify', '--deep', '--strict', str(APP))
    size = sum(f.stat().st_size for f in APP.rglob('*') if f.is_file())
    print(f'Installed app: {size / 1_000_000:.2f} MB')
    if size >= 40_000_000: raise SystemExit('App exceeds the 40 MB budget')
    archive = BUILD / ('Dice-v' + VERSION['version'] + '-apple-silicon.zip')
    if archive.exists(): archive.unlink()
    run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(APP), str(archive))
    (BUILD / 'app-path.txt').write_text(str(APP))
    print(f'Download: {archive.stat().st_size / 1_000_000:.2f} MB\n{APP}')
