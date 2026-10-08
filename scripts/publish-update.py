#!/usr/bin/env python3
"""Prepare signed Sparkle assets; --publish uploads them to the binary-only repository."""
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
    # Use GitHub's authoritative file API for publishing; the public raw feed may lag in its CDN.
    previous_result = subprocess.run(['gh', 'api', f"repos/{CONFIG['repository']}/contents/appcast.xml"], capture_output=True, text=True)
    if previous_result.returncode == 0:
        previous_revision = json.loads(previous_result.stdout)['sha']
        previous = base64.b64decode(json.loads(previous_result.stdout)['content'])
        previous_path = ROOT / 'build/previous-appcast.xml'
        previous_path.write_bytes(previous)
        call(str(TOOLS / 'sign_update'), '--account', CONFIG['keychain_account'], '--verify', str(previous_path))
        feed = ET.fromstring(previous)
    elif '(HTTP 404)' in previous_result.stderr:
        previous_revision = None
        feed = ET.Element('rss', version='2.0')
        channel = ET.SubElement(feed, 'channel')
        ET.SubElement(channel, 'title').text = 'Dice updates'
        ET.SubElement(channel, 'link').text = 'https://github.com/' + CONFIG['repository']
        ET.SubElement(channel, 'description').text = 'Signed Dice releases for macOS.'
    else:
        raise SystemExit('Cannot read the current GitHub feed: ' + previous_result.stderr)
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
    if visibility != 'PUBLIC': raise SystemExit('The updater needs a public binary-only repository; no credentials are bundled in Dice.')
    # Read the feed revision before publishing so a concurrent release cannot be silently overwritten.
    current = subprocess.run(['gh', 'api', f'repos/{repo}/contents/appcast.xml'], capture_output=True, text=True)
    if current.returncode != 0 and '(HTTP 404)' not in current.stderr:
        raise SystemExit('Cannot check the current feed revision: ' + current.stderr)
    sha = json.loads(current.stdout)['sha'] if current.returncode == 0 else None
    if sha != previous_revision: raise SystemExit('The feed changed while preparing this release. Prepare it again.')
    tag = 'v' + VERSION['version']
    args = ['gh', 'release', 'create', tag, str(archive), str(feed), '--repo', repo, '--draft', '--title', 'Dice ' + VERSION['version'], '--notes-file', str(notes)]
    if VERSION['channel'] == 'preview': args.append('--prerelease')
    subprocess.run(args, check=True)
    subprocess.run(['gh', 'release', 'edit', tag, '--repo', repo, '--draft=false'], check=True)
    payload = dict(message='Publish Dice ' + VERSION['version'] + ' update feed', content=base64.b64encode(feed.read_bytes()).decode(), branch='main')
    if sha: payload['sha'] = sha
    subprocess.run(['gh', 'api', '--method', 'PUT', f'repos/{repo}/contents/appcast.xml', '--input', '-'], input=json.dumps(payload), text=True, check=True, stdout=subprocess.DEVNULL)
    print(f'https://github.com/{repo}/releases/tag/{tag}')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--notes', type=pathlib.Path, required=True)
    parser.add_argument('--publish', action='store_true')
    args = parser.parse_args()
    archive, feed, revision = prepare(args.notes)
    print('Verified signed archive and appcast:', archive.name)
    if args.publish: publish(archive, feed, args.notes, revision)
