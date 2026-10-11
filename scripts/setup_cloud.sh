#!/usr/bin/env bash
# Cloud prerequisite setup. Uses the existing isolated app checkout; no worktree.
set -euo pipefail
mkdir -p /workspace/toolchains
if [ ! -x /workspace/toolchains/android-sdk/cmdline-tools/19.0/bin/sdkmanager ]; then
  curl -fL --retry 2 https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip -o /workspace/toolchains/android-tools-19.zip
  python3 - <<'PY'
import pathlib, hashlib, zipfile, tempfile
archive = pathlib.Path('/workspace/toolchains/android-tools-19.zip')
if hashlib.sha1(archive.read_bytes()).hexdigest() != '5fdcc763663eefb86a5b8879697aa6088b041e70':
    raise SystemExit('Official Android repository checksum mismatch')
root = pathlib.Path('/workspace/toolchains/android-sdk/cmdline-tools')
root.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(dir='/workspace/toolchains') as temporary:
    with zipfile.ZipFile(archive) as source:
        source.extractall(temporary)
    pathlib.Path(temporary, 'cmdline-tools').rename(root / '19.0')
for executable in (root / '19.0' / 'bin').iterdir():
    executable.chmod(0o755)
PY
fi
if [ ! -x /workspace/toolchains/jdk-21.0.12.1+1/bin/javac ]; then
  curl -fL --retry 2 'https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.12.1%2B1/OpenJDK21U-jdk_x64_linux_hotspot_21.0.12.1_1.tar.gz' -o /workspace/toolchains/temurin-jdk.tar.gz
  python3 - <<'PY'
import pathlib, hashlib, tarfile
archive = pathlib.Path('/workspace/toolchains/temurin-jdk.tar.gz')
if hashlib.sha256(archive.read_bytes()).hexdigest() != 'ce79869e1307ed8ee1e2baa86a412b1eb5b75d10a01006d788a6f968bcfaee94':
    raise SystemExit('Official Temurin release checksum mismatch')
with tarfile.open(archive) as source:
    source.extractall('/workspace/toolchains', filter='data')
PY
fi
if [ ! -d /workspace/toolchains/flutter ]; then
  git clone --depth 1 --branch 3.47.7 https://github.com/flutter/flutter.git /workspace/toolchains/flutter
fi
if [ "$(git -C /workspace/toolchains/flutter rev-parse HEAD)" != abaf9c523780a608bd46686fd5e53740a07077f8 ]; then
  echo 'Flutter checkout does not match pinned 3.47.7. Preserve it and select the pinned SDK explicitly.' >&2
  exit 1
fi
cat > /workspace/toolchains/env.sh <<'ENV'
export PATH="/workspace/toolchains/flutter/bin:/workspace/toolchains/android-sdk/cmdline-tools/19.0/bin:/workspace/toolchains/android-sdk/platform-tools:$PATH"
export PUB_CACHE=/workspace/toolchains/pub-cache
export XDG_CONFIG_HOME=/workspace/toolchains/config
export XDG_CACHE_HOME=/workspace/toolchains/cache
export XDG_DATA_HOME=/workspace/toolchains/data
export GRADLE_USER_HOME=/workspace/toolchains/gradle
export ANDROID_HOME=/workspace/toolchains/android-sdk
export ANDROID_USER_HOME=/workspace/toolchains/android-user
export CI=true
export JAVA_HOME=/workspace/toolchains/jdk-21.0.12.1+1
export PATH="$JAVA_HOME/bin:$PATH"
ENV
source /workspace/toolchains/env.sh
mkdir -p "$GRADLE_USER_HOME"
# Preserve user Gradle preferences. Update only the proxy keys owned by setup.
python3 - <<'PY'
import pathlib, urllib.parse, os
path = pathlib.Path(os.environ['GRADLE_USER_HOME']) / 'gradle.properties'
settings = {'org.gradle.workers.max': '2', 'org.gradle.daemon': 'false'}
proxy = urllib.parse.urlparse(os.environ.get('HTTPS_PROXY', ''))
if proxy.hostname:
    for protocol in ['http', 'https']:
        settings[f'systemProp.{protocol}.proxyHost'] = proxy.hostname
        settings[f'systemProp.{protocol}.proxyPort'] = str(proxy.port or 80)
    settings['systemProp.http.nonProxyHosts'] = 'localhost|127.*'
# Use the machine's maintained CA trust store, including its proxy CA.
if pathlib.Path('/etc/ssl/certs/java/cacerts').exists():
    settings['systemProp.javax.net.ssl.trustStore'] = '/etc/ssl/certs/java/cacerts'
lines = path.read_text().splitlines() if path.exists() else []
lines = [line for line in lines if line.split('=', 1)[0] not in settings]
path.write_text('\n'.join(lines + [f'{k}={v}' for k,v in settings.items()]) + '\n')
PY
flutter config --no-analytics --android-sdk="$ANDROID_HOME" --jdk-dir="$JAVA_HOME"
# Refresh SDK license acceptance through the supported flow, as authorized during setup.
python3 - <<'PYSDK'
import os, pathlib, subprocess, urllib.parse
command = ['sdkmanager', '--sdk_root=' + os.environ['ANDROID_HOME'], 'platform-tools',
    'platforms;android-34', 'platforms;android-35', 'platforms;android-36', 'build-tools;36.0.0',
    'ndk;28.2.13676358', 'cmake;3.22.1']
proxy = urllib.parse.urlparse(os.environ.get('HTTPS_PROXY', ''))
if proxy.hostname:
    command += ['--proxy=http', '--proxy_host=' + proxy.hostname, '--proxy_port=' + str(proxy.port or 80)]
environment = dict(os.environ)
if pathlib.Path('/etc/ssl/certs/java/cacerts').exists():
    environment['JAVA_TOOL_OPTIONS'] = '-Djavax.net.ssl.trustStore=/etc/ssl/certs/java/cacerts'
license_command = command[:2] + ['--licenses'] + [arg for arg in command[2:] if arg.startswith('--proxy')]
subprocess.run(license_command, env=environment, input='y\n' * 20, text=True, check=True)
subprocess.run(command, env=environment, check=True)
PYSDK
cd /workspace/tahzeeb-libas
flutter pub get --enforce-lockfile
flutter --version
javac -version
