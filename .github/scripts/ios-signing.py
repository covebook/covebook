"""Import CI signing material without logging it or including it in an artifact."""
import base64
import datetime
import os
from pathlib import Path
import plistlib
import secrets
import subprocess

required = ['APPLE_TEAM_ID', 'ASC_KEY_ID', 'ASC_ISSUER_ID', 'ASC_PRIVATE_KEY',
            'IOS_DISTRIBUTION_P12', 'IOS_DISTRIBUTION_PASSWORD', 'IOS_PROVISION_PROFILE']
missing = [key for key in required if not os.environ.get(key)]
if missing:
    raise SystemExit('Missing iOS configuration: ' + ', '.join(missing))
tmp = Path(os.environ['RUNNER_TEMP'])
p12 = tmp / 'distribution.p12'
profile = tmp / 'profile.mobileprovision'
for path, key in [(p12, 'IOS_DISTRIBUTION_P12'), (profile, 'IOS_PROVISION_PROFILE')]:
    path.write_bytes(base64.b64decode(os.environ[key], validate=True))
    path.chmod(0o600)
run = lambda *args: subprocess.run(args, check=True, capture_output=True)
try:
    info = plistlib.loads(run('security', 'cms', '-D', '-i', str(profile)).stdout)
    team = os.environ['APPLE_TEAM_ID']
    ent = info['Entitlements']
    if (info['TeamIdentifier'] != [team] or ent.get('application-identifier') != team + '.app.covebook'
            or ent.get('get-task-allow') or 'ProvisionedDevices' in info or info.get('ProvisionsAllDevices')
            or ent.get('com.apple.developer.applesignin') != ['Default']
            or info['ExpirationDate'] <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)):
        raise SystemExit('Profile must be an unexpired App Store profile for app.covebook with Sign in with Apple.')
    keychain = tmp / 'ios-signing.keychain-db'
    password = secrets.token_urlsafe(32)
    run('security', 'create-keychain', '-p', password, str(keychain))
    run('security', 'set-keychain-settings', '-lut', '21600', str(keychain))
    run('security', 'unlock-keychain', '-p', password, str(keychain))
    run('security', 'import', str(p12), '-P', os.environ['IOS_DISTRIBUTION_PASSWORD'], '-A', '-t', 'cert', '-f', 'pkcs12', '-k', str(keychain))
    run('security', 'set-key-partition-list', '-S', 'apple-tool:,apple:', '-k', password, str(keychain))
    run('security', 'list-keychains', '-d', 'user', '-s', str(keychain), str(Path.home() / 'Library/Keychains/login.keychain-db'))
    dest = Path.home() / 'Library/MobileDevice/Provisioning Profiles' / (info['UUID'] + '.mobileprovision')
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(profile.read_bytes())
    options = dict(method='app-store-connect', teamID=team, signingStyle='manual',
                   provisioningProfiles={'app.covebook': info['Name']}, uploadSymbols=True,
                   manageAppVersionAndBuildNumber=False)
    (tmp / 'ExportOptions.plist').write_bytes(plistlib.dumps(options))
    # A rerun must get a new monotonically increasing CFBundleVersion too.
    build = str(int(datetime.datetime.now(datetime.timezone.utc).timestamp()))
    with open(os.environ['GITHUB_ENV'], 'a') as env:
        env.write(f'IOS_PROFILE_NAME={info["Name"]}\nIOS_INSTALLED_PROFILE={dest}\nIOS_BUILD_NUMBER={build}\n')
except subprocess.CalledProcessError:
    raise SystemExit('Apple signing setup failed; check the certificate, password, and provisioning profile.') from None
finally:
    p12.unlink(missing_ok=True)
