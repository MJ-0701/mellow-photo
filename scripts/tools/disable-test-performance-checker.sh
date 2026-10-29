#!/bin/bash
# xcodegen generate 직후(project.yml의 postGenCommand) apple 폴더에서 실행한다.
# XcodeGen은 테스트 액션의 스레드 성능 검사기 끄기를 만들지 못한다.
# 이 검사기(libRPAC)는 iOS 18 시뮬레이터에서 Core Image 타일 렌더 중 자기 내부에서 죽으므로 테스트에서만 끈다.
# Xcode가 테스트 실행 때만 끼워 넣는 진단 도구라 배포 앱 동작은 바뀌지 않는다.
set -euo pipefail
/usr/bin/python3 - \
    MellowPhoto.xcodeproj/xcshareddata/xcschemes/MellowPhoto.xcscheme \
    MellowPhoto.xcodeproj/xcshareddata/xcschemes/MellowPhotoUITests.xcscheme <<'PYTHON'
import sys
import xml.etree.ElementTree as ET

# 두 스킴 모두 유효한지 먼저 검사한다. 일부 스킴만 수정한 상태로 성공하지 않는다.
updates = []
marker = "   <TestAction\n"
attribute = '      disablePerformanceAntipatternChecker = "YES"\n'
for path in sys.argv[1:]:
    text = open(path).read()
    actions = ET.fromstring(text).findall("TestAction")
    if len(actions) != 1 or text.count(marker) != 1:
        raise SystemExit(f"Expected exactly one generated TestAction: {path}")
    existing = actions[0].get("disablePerformanceAntipatternChecker")
    if existing not in (None, "YES"):
        raise SystemExit(f"Unexpected performance checker setting: {path}")
    if existing is None:
        start = text.index(marker) + len(marker)
        text = text[:start] + attribute + text[start:]
    updates.append((path, text))

for path, text in updates:
    if open(path).read() != text:
        open(path, "w").write(text)
PYTHON
