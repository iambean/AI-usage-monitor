#!/bin/zsh
set -euo pipefail
project_root=${0:A:h:h}
cd "$project_root"
swift build --product AIUsageMonitor
bin_dir=$(swift build --show-bin-path)
qa_dir="$project_root/.build/panel-acceptance"
qa_app="$qa_dir/AI Usage Acceptance.app"
mkdir -p "$qa_app/Contents/MacOS"
python3 - "$bin_dir" "$qa_dir" <<'PY'
import pathlib, plistlib, sys
bin_dir, qa_dir = map(pathlib.Path, sys.argv[1:])
objects = sorted((bin_dir / 'AIUsageMonitor.build').glob('*.swift.o'))
(qa_dir / 'objects.list').write_text('\n'.join(str(p) for p in objects if p.name != 'AIUsageMonitorApp.swift.o') + '\n')
with (qa_dir / 'AI Usage Acceptance.app/Contents/Info.plist').open('wb') as f:
    plistlib.dump({'CFBundleIdentifier': 'com.xinfan.ai-usage-monitor.acceptance',
                  'CFBundleExecutable': 'PanelAcceptance', 'CFBundleName': 'AI Usage Acceptance',
                  'CFBundlePackageType': 'APPL', 'LSUIElement': True}, f)
PY
swiftc -target arm64-apple-macosx13.0 -parse-as-library -g -I "$bin_dir/Modules" -F "$bin_dir" \
  -framework Sparkle -Xlinker -rpath -Xlinker "$bin_dir" \
  Tests/Acceptance/PanelAcceptance.swift @"$qa_dir/objects.list" \
  -o "$qa_app/Contents/MacOS/PanelAcceptance"
codesign --force --sign - "$qa_app"
python3 - "$qa_app" "$qa_dir/Foreground Companion.app" <<'PY'
import pathlib, plistlib, shutil, sys
source, companion = map(pathlib.Path, sys.argv[1:])
if companion.exists():
    shutil.rmtree(companion)
shutil.copytree(source, companion)
p = companion / 'Contents/Info.plist'
info = plistlib.loads(p.read_bytes())
info['CFBundleIdentifier'] = 'com.xinfan.ai-usage-monitor.acceptance.companion'
info['CFBundleName'] = 'Foreground Companion'
p.write_bytes(plistlib.dumps(info))
PY
codesign --force --sign - "$qa_dir/Foreground Companion.app"
python3 - "$qa_dir/results.json" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[1]).unlink(missing_ok=True)
PY
if [[ "${1:-}" == "--background-click" ]]; then
  open -n "$qa_app" --args --background-click
else
  open -n "$qa_app"
fi
python3 - "$qa_dir/results.json" "${1:-}" <<'PY'
import json, pathlib, sys, time
report = pathlib.Path(sys.argv[1])
for _ in range(240):
    if report.exists():
        checks = json.loads(report.read_text())
        if checks and (checks[-1]['check'] == 'all native checks completed' or (sys.argv[2] == '--background-click' and checks[-1]['check'] == 'third status button click reopens panel')):
            failures = [c['check'] for c in checks if not c['passed']]
            print(f"Native acceptance: {len(checks)} checks, {len(failures)} failures")
            for name in failures:
                print('FAIL: ' + name)
            print('Results: ' + str(report))
            sys.exit(bool(failures))
    time.sleep(0.25)
raise SystemExit('Native acceptance did not finish within 60 seconds: ' + str(report))
PY
