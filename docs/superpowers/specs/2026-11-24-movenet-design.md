# MoveNet Thunder 전신 추적

사용자가 승인한 구성: Apple Vision 대신 MoveNet SinglePose Thunder로 전신 17개 지점을 추정한다. 정확도를 우선해 Thunder를 선택했으며 Lightning은 속도를 우선하는 대안이다.

카메라는 AVFoundation, 실행은 기기 내 TensorFlowLite Interpreter로 한다. 모델과 런타임 버전을 고정하고 Xcode와 Swift Playground의 동일 소스를 유지한다. 카메라 입력을 종횡비 유지 정사각 패딩으로 변환하고, 출력의 y/x/score를 원본 영상 좌표로 역변환한다. 영상 회전과 반전은 캡처 단계에서 한 번만 적용하고 동일 프레임에 점과 연결선을 그린다. 낮은 신뢰도 점은 숨기고 이전 프레임의 점을 재사용하지 않는다.

기존 넓은 카메라 UI 및 센서 탭 분리는 유지한다. 얼굴 전용 대체 추적, 자동 횟수 집계, 서버 변경은 포함하지 않는다. 카메라 영상은 저장·전송하지 않는다. 실제 인식률과 지연은 실기기 확인 전 단정하지 않는다.
