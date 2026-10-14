#!/bin/bash
# 스펙 3절의 의존성 표를 강제한다. 위반하면 종료 코드 1.
source "$(dirname "$0")/env.sh"
cd "$MELLOW_ROOT/apple"
# 파이썬 스크립트가 heredoc으로 stdin을 쓰므로 패키지 JSON은 환경 변수로 넘긴다.
MELLOW_PACKAGE_JSON="$(swift package describe --type json)"
export MELLOW_PACKAGE_JSON
python3 - "$MELLOW_ROOT/apple/Sources" <<'PY'
import json, os, re, sys
allowed = {
    "MellowShared": set(),
    "MellowEditing": {"MellowShared"},
    "MellowLibrary": {"MellowShared", "MellowEditing"},
    "MellowRendering": {"MellowShared"},
    "MellowExport": {"MellowShared", "MellowRendering"},
}
forbidden = {
    "MellowShared": {"CoreImage", "Vision", "SwiftUI", "UIKit", "AppKit", "Photos", "PhotosUI", "ImageIO"},
    "MellowEditing": {"CoreImage", "Vision", "SwiftUI", "UIKit", "AppKit", "Photos", "PhotosUI"},
    "MellowLibrary": {"CoreImage", "Vision", "SwiftUI", "UIKit", "AppKit", "Photos", "PhotosUI"},
    "MellowRendering": {"SwiftUI", "UIKit", "AppKit", "Photos", "PhotosUI"},
    "MellowExport": {"SwiftUI", "UIKit", "AppKit", "Photos", "PhotosUI"},
}
package = json.loads(os.environ["MELLOW_PACKAGE_JSON"])
failures = []
for target in package["targets"]:
    name = target["name"]
    if name not in allowed: continue
    actual = {d for d in target.get("target_dependencies", [])}
    extra = actual - allowed[name]
    if extra: failures.append(f"{name} depends on {sorted(extra)}")
    missing = allowed[name] - actual
    if missing: failures.append(f"{name} must declare {sorted(missing)}")
sources = sys.argv[1]
for module, banned in forbidden.items():
    for root, _, files in os.walk(os.path.join(sources, module)):
        for file in files:
            if not file.endswith(".swift"): continue
            with open(os.path.join(root, file)) as handle:
                for line in handle:
                    match = re.match(r"\s*import\s+(\w+)", line)
                    if match and match.group(1) in banned:
                        failures.append(f"{module}/{file} imports {match.group(1)}")
for module in allowed:
    api = os.path.join(sources, module, "API")
    if not os.path.isdir(api): failures.append(f"{module} has no API/ folder")
if failures:
    print("\n".join("✗ " + f for f in failures)); sys.exit(1)
print("✓ module dependencies and imports match docs/architecture/modules.md")
PY
