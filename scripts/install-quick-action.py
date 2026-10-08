#!/usr/bin/env python3
"""Register Dice's native Finder Service (legacy installer filename)."""
import argparse, pathlib, plistlib, shutil, subprocess, datetime
root = pathlib.Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--app', type=pathlib.Path)
parser.add_argument('--update', action='store_true', help='Accepted for compatibility; native Services need no workflow update.')
args = parser.parse_args()
app = args.app or (pathlib.Path('/Applications/Dice.app') if pathlib.Path('/Applications/Dice.app').exists() else root / 'build/Dice.app')
if not app.exists(): raise SystemExit('Build Dice first: python3 scripts/package.py')
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
if info.get('DiceDevelopmentBuild'):
    raise SystemExit('Development builds do not register Finder Services.')
if not any(s.get('NSMessage') == 'editWithDice' for s in info.get('NSServices', [])):
    raise SystemExit('This app has no native Dice Service. Build and install the current app first.')
workflow = pathlib.Path.home() / 'Library/Services/Edit with Dice.workflow'
if workflow.exists():
    previous = plistlib.loads((workflow / 'Contents/document.wflow').read_bytes())
    command = previous.get('actions', [{}])[0].get('action', {}).get('ActionParameters', {}).get('COMMAND_STRING', '')
    import shlex
    allowed = ['/usr/bin/open -a ' + shlex.quote(str(candidate)) + ' "$@"' for candidate in [root / 'build/Dice.app', pathlib.Path('/Applications/Dice.app')]]
    if command not in allowed: raise SystemExit('Unrecognized existing workflow; left intact.')
    backup = root / 'build/backups' / datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    backup.mkdir(parents=True, exist_ok=True)
    shutil.move(str(workflow), str(backup / workflow.name))
subprocess.run(['/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister', '-f', str(app)], check=True)
subprocess.run(['/System/Library/CoreServices/pbs', '-update'], check=True)
print('Registered native Finder Service: Edit with Dice')
