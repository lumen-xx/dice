#!/usr/bin/env python3
"""Install the image-only Finder Quick Action for this development checkout."""
import pathlib, plistlib, shlex, subprocess, uuid, argparse
root = pathlib.Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--app', type=pathlib.Path)
parser.add_argument('--update', action='store_true')
args = parser.parse_args()
app = args.app or (pathlib.Path('/Applications/Dice.app') if pathlib.Path('/Applications/Dice.app').exists() else root / 'build/Dice.app')
if not app.exists(): raise SystemExit('Build Dice first: python3 scripts/package.py')
workflow = pathlib.Path.home() / 'Library/Services/Edit with Dice.workflow'
contents = workflow / 'Contents'
if workflow.exists():
    previous = plistlib.loads((contents / 'document.wflow').read_bytes())
    old = previous.get('actions', [{}])[0].get('action', {}).get('ActionParameters', {}).get('COMMAND_STRING', '')
    allowed = ['/usr/bin/open -a ' + shlex.quote(str(candidate)) + ' "$@"' for candidate in [root / 'build/Dice.app', pathlib.Path('/Applications/Dice.app')]]
    if not args.update or old not in allowed: raise SystemExit('Existing Quick Action was not replaced. Use --update only for Dice-generated actions.')
contents.mkdir(parents=True, exist_ok=True)
shell = '/usr/bin/open -a ' + shlex.quote(str(app)) + ' "$@"'
params = dict(COMMAND_STRING=shell, source=shell, inputMethod=1, shell='/bin/sh', CheckedForUserDefaultShell=True)
action = {
 'AMAccepts': dict(Container='List', Optional=True, Types=['com.apple.cocoa.string']),
 'AMProvides': dict(Container='List', Types=['com.apple.cocoa.string']),
 'AMActionVersion':'2.0.3', 'AMApplication':['Automator'],
 'ActionBundlePath':'/System/Library/Automator/Run Shell Script.action',
 'ActionName':'Run Shell Script', 'BundleIdentifier':'com.apple.RunShellScript',
 'CFBundleVersion':'2.0.3', 'Class Name':'RunShellScriptAction',
 'ActionParameters':params, 'AMParameterProperties':{key:{} for key in params},
 'UUID':str(uuid.uuid4()).upper(), 'InputUUID':str(uuid.uuid4()).upper(), 'OutputUUID':str(uuid.uuid4()).upper(),
 'CanShowWhenRun':True, 'CanShowSelectedItemsWhenRun':False,
 'Category':['AMCategoryUtilities'], 'UnlocalizedApplications':['Automator'],
 'isViewVisible':1, 'location':'0.000000:0.000000',
 'nibPath':'/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib'
}
metadata = dict(applicationBundleIDsByPath={}, applicationPaths=[], inputTypeIdentifier='com.apple.Automator.fileSystemObject.image', outputTypeIdentifier='com.apple.Automator.nothing', presentationMode=15, processesInput=False, serviceInputTypeIdentifier='com.apple.Automator.fileSystemObject.image', serviceOutputTypeIdentifier='com.apple.Automator.nothing', serviceProcessesInput=False, systemImageName='NSActionTemplate', useAutomaticInputType=False, workflowTypeIdentifier='com.apple.Automator.servicesMenu')
info = dict(NSServices=[dict(NSMenuItem={'default':'Edit with Dice'}, NSMessage='runWorkflowAsService', NSSendFileTypes=['public.image'], NSRequiredContext={'NSServiceApplicationIdentifier':'com.apple.finder'}, NSIconName='NSActionTemplate')])
document = dict(AMApplicationBuild='533', AMApplicationVersion='2.10', AMDocumentVersion='2', actions=[dict(action=action,isViewVisible=1)], connectors={}, workflowMetaData=metadata)
(contents / 'Info.plist').write_bytes(plistlib.dumps(info))
(contents / 'document.wflow').write_bytes(plistlib.dumps(document))
subprocess.run(['/System/Library/CoreServices/pbs','-update'], check=True)
print(workflow)
