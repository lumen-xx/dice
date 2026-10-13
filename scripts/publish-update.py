#!/usr/bin/env python3
"""Prepare signed Sparkle assets; --publish releases them in the source repository and passes the feed to the old one."""
import argparse, base64, datetime, json, pathlib, plistlib, subprocess, xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONFIG = json.loads((ROOT / 'updates/config.json').read_text())
VERSION = json.loads((ROOT / 'updates/version.json').read_text())
TOOLS = ROOT / '.build/artifacts/sparkle/Sparkle/bin'
SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', SPARKLE)

def call(*args):
    return subprocess.check_output(args, text=True).strip()

def prepare(notes):
    public_key = call(str(TOOLS / 'generate_keys'), '--account', CONFIG['keychain_account'], '-p')
    if public_key != CONFIG['public_key']:
        raise SystemExit('The Keychain signing key does not match updates/config.json.')
    app = ROOT / 'build/Dice.app'
    plist = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if (plist['CFBundleShortVersionString'], plist['CFBundleVersion']) != (VERSION['version'], str(VERSION['build'])):
        raise SystemExit('Package is out of date. Run python3 scripts/package.py first.')
    if plist['SUPublicEDKey'] != public_key or plist['SUFeedURL'] != CONFIG['feed_url']:
        raise SystemExit('Packaged updater configuration is out of date.')
    archive = ROOT / 'build' / f"Dice-v{VERSION['version']}-apple-silicon.zip"
    signature = call(str(TOOLS / 'sign_update'), '--account', CONFIG['keychain_account'], '-p', str(archive))
    call(str(TOOLS / 'sign_update'), '--account', CONFIG['keychain_account'], '--verify', str(archive), signature)
    # The feed continues from the latest release's signed appcast; before the source repository has a release, from
    # the old binary repository's feed file.
    previous_path = ROOT / 'build/previous-appcast.xml'
    previous_path.unlink(missing_ok=True)
    latest = subprocess.run(['gh', 'release', 'list', '--repo', CONFIG['repository'], '--limit', '1', '--json', 'tagName', '--jq', '.[0].tagName // empty'],
                            capture_output=True, text=True, check=True).stdout.strip()
    if latest:
        # Early releases in the source repository had no feed asset; those fall through to the old feed.
        subprocess.run(['gh', 'release', 'download', latest, '--repo', CONFIG['repository'], '--pattern', 'appcast.xml', '--output', str(previous_path), '--clobber'],
                       capture_output=True)
    if not previous_path.exists() and CONFIG.get('legacy_repository'):
        legacy = subprocess.run(['gh', 'api', f"repos/{CONFIG['legacy_repository']}/contents/appcast.xml"], capture_output=True, text=True, check=True)
        previous_path.write_bytes(base64.b64decode(json.loads(legacy.stdout)['content']))
    if previous_path.exists():
        call(str(TOOLS / 'sign_update'), '--account', CONFIG['keychain_account'], '--verify', str(previous_path))
        feed = ET.fromstring(previous_path.read_bytes())
    else:
        feed = ET.Element('rss', version='2.0')
        channel = ET.SubElement(feed, 'channel')
        ET.SubElement(channel, 'title').text = 'Dice updates'
        ET.SubElement(channel, 'link').text = 'https://github.com/' + CONFIG['repository']
        ET.SubElement(channel, 'description').text = 'Signed Dice releases for macOS.'
    previous_revision = latest
    channel = feed.find('channel')
    if channel is None: raise SystemExit('Existing appcast has no channel.')
    if any(item.findtext(f'{{{SPARKLE}}}version') == str(VERSION['build']) for item in channel.findall('item')):
        raise SystemExit('This build is already in the update feed. Increase updates/version.json.')
    if any(int(item.findtext(f'{{{SPARKLE}}}version', '0')) >= VERSION['build'] for item in channel.findall('item')):
        raise SystemExit('Build numbers must increase with every release.')
    item = ET.Element('item')
    ET.SubElement(item, 'title').text = 'Dice ' + VERSION['version']
    ET.SubElement(item, f'{{{SPARKLE}}}version').text = str(VERSION['build'])
    ET.SubElement(item, f'{{{SPARKLE}}}shortVersionString').text = VERSION['version']
    ET.SubElement(item, f'{{{SPARKLE}}}minimumSystemVersion').text = '14.0'
    if VERSION['channel'] == 'preview': ET.SubElement(item, f'{{{SPARKLE}}}channel').text = 'preview'
    elif VERSION['channel'] != 'stable': raise SystemExit('Channel must be stable or preview.')
    ET.SubElement(item, 'pubDate').text = datetime.datetime.now(datetime.timezone.utc).strftime('%a, %d %b %Y %H:%M:%S GMT')
    ET.SubElement(item, 'description').text = notes.read_text()
    ET.SubElement(item, 'enclosure', {
        'url': f"https://github.com/{CONFIG['repository']}/releases/download/v{VERSION['version']}/{archive.name}",
        'length': str(archive.stat().st_size), 'type': 'application/octet-stream',
        f'{{{SPARKLE}}}edSignature': signature
    })
    channel.insert(3, item)
    feed_path = ROOT / 'build/appcast.xml'
    ET.indent(feed, space='  ')
    ET.ElementTree(feed).write(feed_path, encoding='utf-8', xml_declaration=True)
    call(str(TOOLS / 'sign_update'), '--account', CONFIG['keychain_account'], str(feed_path))
    call(str(TOOLS / 'sign_update'), '--account', CONFIG['keychain_account'], '--verify', str(feed_path))
    return archive, feed_path, previous_revision

def publish(archive, feed, notes, previous_revision):
    repo = CONFIG['repository']
    visibility = json.loads(call('gh', 'repo', 'view', repo, '--json', 'visibility'))['visibility']
    if visibility != 'PUBLIC': raise SystemExit('The updater needs a public repository; no credentials are bundled in Dice.')
    # A release published meanwhile would be dropped from the feed: compare with the one the feed continued from.
    latest = call('gh', 'release', 'list', '--repo', repo, '--limit', '1', '--json', 'tagName', '--jq', '.[0].tagName // empty')
    if latest != previous_revision: raise SystemExit('A release was published while preparing this one. Prepare it again.')
    tag = 'v' + VERSION['version']
    # Published as GitHub's latest release, so releases/latest/download/appcast.xml is the feed; preview builds are
    # marked by their channel inside the feed.
    subprocess.run(['gh', 'release', 'create', tag, str(archive), str(feed), '--repo', repo, '--title', 'Dice ' + VERSION['version'],
                    '--notes-file', str(notes), '--latest'], check=True)
    # Builds up to 0.1.26 read the feed file in the old binary repository: it gets the same signed feed, whose download
    # points here, so those copies update to a build that reads the new feed.
    legacy = CONFIG.get('legacy_repository')
    if legacy:
        for path, content, message in [('appcast.xml', feed.read_bytes(), 'Publish Dice ' + VERSION['version'] + ' update feed'),
                                       ('README.md', (ROOT / 'docs/LEGACY_README.md').read_bytes(), 'Dice moved to ' + repo)]:
            current = subprocess.run(['gh', 'api', f'repos/{legacy}/contents/{path}'], capture_output=True, text=True)
            if current.returncode != 0 and '(HTTP 404)' not in current.stderr:
                raise SystemExit(f'Cannot read {path} in {legacy}: ' + current.stderr)
            payload = dict(message=message, content=base64.b64encode(content).decode(), branch='main')
            if current.returncode == 0:
                info = json.loads(current.stdout)
                if base64.b64decode(info['content']) == content: continue
                payload['sha'] = info['sha']
            subprocess.run(['gh', 'api', '--method', 'PUT', f'repos/{legacy}/contents/{path}', '--input', '-'], input=json.dumps(payload), text=True, check=True, stdout=subprocess.DEVNULL)
    print(f'https://github.com/{repo}/releases/tag/{tag}')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--notes', type=pathlib.Path, required=True)
    parser.add_argument('--publish', action='store_true')
    args = parser.parse_args()
    archive, feed, revision = prepare(args.notes)
    print('Verified signed archive and appcast:', archive.name)
    if args.publish: publish(archive, feed, args.notes, revision)
