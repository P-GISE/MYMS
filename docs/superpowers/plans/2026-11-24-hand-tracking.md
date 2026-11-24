# Hand Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Thunder와 함께 양손 21개 점과 펼침/주먹 상태를 표시한다.
**Architecture:** MediaPipe Gesture Recognizer를 기존 직렬 카메라 큐에서 실행하고 동일 프레임에 합성한다. 순수 상태 모델과 iOS 추론 서비스를 분리한다.
**Tech Stack:** Swift, AVFoundation, MediaPipeTasksVision 1.2.3, gesture_recognizer float16 v1, 기존 Thunder.
**Spec:** `docs/superpowers/specs/2026-11-24-hand-tracking-design.md`

## Global Constraints
- 사용자가 요청한 현재 checkout의 변경을 보존하고 작업한다. 별도 승인/commit/push 없음.
- 손당 21점, 최대 2손. Open_Palm/Closed_Fist score >= 0.6만 확정, 나머지 판별 중.
- 영상 저장/전송 없음. 손 동작으로 운동을 자동 제어하지 않는다.

## Review Focus
- 부분 손/경계 밖/NaN/무한대 좌표와 낮은 분류 신뢰도.
- 손이 사라지면 이전 프레임의 점/상태를 재사용하지 않는다.
- Thunder와 MediaPipe 런타임 동시 링크 및 추론 호환성.
- 양손과 전면/후면·회전에서 같은 프레임 좌표 사용.
- 초기화/추론 오류는 전신 추적을 막지 않고 손 오류로 표시.

### Task 1: 손 모델과 검증
Files: `Models/HandLandmarks.swift`, `Tests/HandLandmarkChecks.swift`.
- [x] 범주·신뢰도·21개 순서·잘못된 좌표·빈 프레임 검사를 먼저 실패시킨다.
- [x] 손 모델과 연결선/상태 판정을 구현하고 통과시킨다.

### Task 2: 실제 추론과 화면 통합
Files: `Services/HandGestureEstimator.swift`, `Services/HandOverlay.swift`, camera view, package/project files, model resource, XCTest.
- [x] 공식 모델/런타임을 버전·체크섬으로 고정하고 출처/라이선스를 기록한다.
- [x] 같은 프레임의 손 점/선 및 상태를 그린다. 손 오류와 지연을 기록한다.
- [x] 실제 iPad에서 펼친 손·주먹·양손·빈 화면과 Thunder 동시 추론을 검증한다.
- [x] 코드 검토 지적을 수정하고 최종 빌드·아이패드 설치·실행.

## Execution record

- HandLandmarkChecks observed failing before model implementation, then passed: thresholds, invalid/partial/empty points and connections.
- Ruling: used Gesture Recognizer (includes Hand Landmarker) so palm/fist uses Google's classifier rather than a new heuristic.
- Ruling: use isolated dynamic TensorFlowLite wrapper while keeping its C archive hashes unchanged. MediaPipe's official registration and shared system dependencies retained.
- Reviewer found missing dynamic framework embedding/runpath. Fixed with signed embed phase plus @executable_path/Frameworks. Actual iPad test suite then passed 4 tests, 0 failures.
- Reference images: two hands each 21 points, Open_Palm 0.604 (one hand; other None), Closed_Fist 0.901. Video blank clears hands; duplicate timestamp rejected; Thunder still detects full body.
- Camera input raised from VGA to 720p BGRA for hand detail. This capture setting is build-verified; user live-camera accuracy is pending.
- No commits or GitHub push. Swift Playground loading remains unverified.
- Final build and strict code signature/runtime embedding checks passed; installed on iPad and confirmed live process after launch.
