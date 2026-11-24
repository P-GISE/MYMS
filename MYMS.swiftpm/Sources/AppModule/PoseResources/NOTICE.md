# MoveNet Thunder

Model: Google MoveNet SinglePose Thunder, TFLite float16, version 4.

Download: https://tfhub.dev/google/lite-model/movenet/singlepose/thunder/tflite/float16/4?lite-format=tflite

SHA-256: `41641538679ec79b07d4101e591dda47d098c09af29607674b2a40b8a3798dd3`

Input: uint8 RGB `[1,256,256,3]`, values 0–255. Output: float32 `[1,1,17,3]`, y/x/confidence, top-left origin.

Model source/specification: https://github.com/tensorflow/tfhub.dev/blob/master/assets/docs/google/models/movenet/singlepose/thunder/tflite/float16/lite/4.md

Model license: Apache 2.0, declared by the parent model card at https://github.com/tensorflow/tfhub.dev/blob/master/assets/docs/google/models/movenet/singlepose/thunder/4.md . Full license included in `TensorFlow-LICENSE.txt`.

Runtime: Google LiteRT-Swift v2.4.0 TensorFlowLite interpreter, Apache 2.0. Full license included in `LiteRT-LICENSE.txt`. Vendored runtime source, binary hashes and packaging adjustments are recorded in `MYMS.swiftpm/Vendor/TensorFlowLite/PROVENANCE.json`.

# Hand gesture tracking

Google MediaPipe Gesture Recognizer float16 v1 (`gesture_recognizer.task`).

Model source: https://storage.googleapis.com/mediapipe-models/gesture_recognizer/gesture_recognizer/float16/1/gesture_recognizer.task

SHA-256: `97952348cf6a6a4915c2ea1496b4b37ebabc50cbbf80571435643c455f2b0482`

The model combines hand detection, 21 hand landmarks, handedness, and built-in gesture classification. MYMS displays Open_Palm/Closed_Fist only at score >= 0.6; other results remain unknown.

Official documentation/model distribution: https://developers.google.com/edge/mediapipe/solutions/vision/gesture_recognizer

Runtime: official MediaPipe Tasks Vision/Common/TaskGraphs 1.2.3 binary archives. Sources, checksums and package configuration are recorded in `MYMS.swiftpm/Vendor/MediaPipeVision`. Apache 2.0 license included as `MediaPipe-LICENSE.txt`.
