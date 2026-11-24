# Pose inference reference

`pose-person.jpeg` is the same reference photograph downloaded by TensorFlow's official MoveNet tutorial:

- Tutorial: https://github.com/tensorflow/docs/blob/master/site/en/hub/tutorials/movenet.ipynb
- Image source: https://images.pexels.com/photos/4384679/pexels-photo-4384679.jpeg
- Pexels photo and credits: https://www.pexels.com/photo/4384679/
- Photo license: https://www.pexels.com/license/

This fixture belongs only to the XCTest bundle, not the shipped MYMS app. It tests model execution and visible reference joints, not live-camera recognition accuracy.

## MediaPipe hand fixtures

- `hand-fist.jpg`: https://storage.googleapis.com/mediapipe-assets/fist.jpg
- `hand-open.jpg`: https://storage.googleapis.com/mediapipe-assets/right_hands.jpg
- Official fixture list: https://github.com/google-ai-edge/mediapipe/blob/master/mediapipe/tasks/testdata/vision/BUILD

These are test-only reference images; they are not copied into the normal app bundle.
