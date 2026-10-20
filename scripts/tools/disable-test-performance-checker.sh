#!/bin/bash
# xcodegen generate 직후(project.yml의 postGenCommand) apple 폴더에서 실행한다.
# XcodeGen은 테스트 액션의 스레드 성능 검사기 끄기를 만들지 못한다.
# 이 검사기(libRPAC)는 iOS 18 시뮬레이터에서 Core Image 타일 렌더 중 자기 내부에서 죽으므로 테스트에서만 끈다.
# Xcode가 테스트 실행 때만 끼워 넣는 진단 도구라 배포 앱 동작은 바뀌지 않는다.
set -euo pipefail
/usr/bin/python3 - MellowPhoto.xcodeproj/xcshareddata/xcschemes/MellowPhoto.xcscheme <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
marker = "   <TestAction\n"
attribute = '      disablePerformanceAntipatternChecker = "YES"\n'
start = text.index(marker) + len(marker)
end = text.index(">", start)
if attribute not in text[start:end]:
    text = text[:start] + attribute + text[start:]
    open(path, "w").write(text)
PY
