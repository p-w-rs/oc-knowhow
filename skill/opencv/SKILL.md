---
name: opencv
description: Expert OpenCV (5.x, and 4.x where it differs) from Python and C++ — choosing a build (conda-forge opencv/py-opencv vs pip opencv-python(-headless)/opencv-contrib-python, never mixed; CUDA builds from source; JetPack's system OpenCV), the 4→5 changes (calib3d split into calib/geometry/stereo, features2d→features, 1-D Mat, contrib moves, DNN engines), numpy interop (BGR, dtype, contiguity, views), image/video I/O (imread/imwrite flags, VideoCapture/VideoWriter backends and fourccs, FFmpeg, GStreamer on Jetson with nvarguscamerasrc/nvv4l2decoder, hardware decode), camera calibration with ChArUco (CharucoBoard/CharucoDetector), distortion models and fisheye, stereo calibration/rectification and SGBM, undistort/remap, solvePnP methods and RANSAC/USAC, homography/essential/recoverPose/triangulation, hand-eye, ArUco/AprilTag, features (SIFT/ORB/AKAZE, learned DISK/ALIKED/XFeat/LightGlue) and matching, optical flow (LK, DIS) and trackers, cv2.dnn with ONNX (export pitfalls, CUDA, vs TensorRT), performance (threads, UMat/OpenCL, cv2.cuda), C++ with CMake via Pixi, Odin via a C wrapper, and robotics glue (JPEG over Zenoh, Foxglove CompressedImage/CameraCalibration in MCAP, Rerun). Load before writing or debugging OpenCV code.
---

# OpenCV

Validated 13 Nov 2026 on macOS arm64 (conda-forge 5.0.0), powerslabs (Linux x86_64, RTX 5090: 5.1.0 + contrib built with
CUDA 13.5/cuDNN 9.28) and Jetson AGX Orin (JetPack 7.2.1 system OpenCV 4.8.0). Numbers below come from synthetic tests
with known ground truth (scripts and outputs in the validation report). Verify versions; the API moved a lot in 4.7–5.1.

## 0. Versions, packages, ground truth

- As of Nov 2026: **5.1.0** (2026-11-06, first 5.x feature release), 5.0.0 (2026-06), **4.14.0** (2026-07, 4.x is
  still maintained). conda-forge: `opencv` = `libopencv` + `py-opencv` **5.0.0**, variants `qt6_*` and `headless_*`,
  **includes most contrib modules** (tracking, xfeatures2d, ximgproc, aruco extras), OpenVINO, FFmpeg; **no CUDA builds**,
  no ONNX Runtime, OpenCL off on macOS. PyPI: `opencv-python`, `-headless`, `opencv-contrib-python(-headless)`
  **5.0.0.93** (also 4.14.0.94).
- **Never mix** them: two `cv2` packages in one environment overwrite each other's files (random `AttributeError`s, wrong
  version). In Pixi pick one: `pixi add opencv` (conda, also gives C++ headers and CMake config) or
  `pixi add --pypi opencv-contrib-python-headless` (Python only). Torch/torchvision from conda-forge pull no cv2.
- Always check what you got: `cv2.__version__`, `cv2.getBuildInformation()` (look for CUDA, cuDNN, GStreamer, FFMPEG,
  Parallel framework, Python limited API), `cv2.cuda.getCudaEnabledDeviceCount()`.
- Jetson: JetPack 7.2.1 ships `/usr/lib/python3.12/dist-packages/cv2` **4.8.0 without CUDA** but with GStreamer 1.24
  (needed for nvarguscamerasrc/nvv4l2decoder); conda/pip builds have no NVIDIA GStreamer plugins. Use the system one for
  CSI capture, or build from source with `-DWITH_CUDA=ON -DWITH_GSTREAMER=ON -DCUDA_ARCH_BIN=8.7`.
- Exact signatures: `library_search` the pinned sources (`opencv-source` 5.1.0, `opencv-contrib-source`), e.g.
  `library_search query="solvePnPRansac UsacParams" sources=["opencv-source"]`. Python signatures: `print(cv2.fn.__doc__)`
  (shows every overload and its return tuple). Docs: https://docs.opencv.org/5.x/ (4.x: /4.x/).

## 1. What changed in 5.x (bites old code and old answers)

- Modules: `calib3d` → `calib` (calibrateCamera, stereoCalibrate, hand-eye), `geometry` (solvePnP, findHomography,
  undistortPoints, triangulatePoints, convexHull, minAreaRect…), `stereo` (StereoBM/SGBM, stereoRectify,
  reprojectImageTo3D), `ptcloud`; `features2d` → `features`. `<opencv2/calib3d.hpp>` and `features2d.hpp` still
  include the new headers. Python names unchanged (`cv2.*`).
- Moved to contrib: `ml`, `gapi`, CascadeClassifier/HOG (`xobjdetect`), SURF/BRIEF/FREAK/DAISY **and AKAZE/KAZE/BRISK**
  (`cv2.xfeatures2d.AKAZE_create()`; validated). CSRT/KCF trackers were always contrib (`tracking`); main `video` has
  MIL, Nano, Vit, DaSiamRPN (the last three need ONNX models). New in main: learned features `DISK`, `ALIKED`, `XFeat`
  (5.1), `LightGlueMatcher` (all ONNX via dnn), `FaceDetectorYN`.
- `std::vector`/1-D numpy → **1-D Mat** (C++ `Mat(vector<int>{1,2,3})`: dims 1, 1x3, validated); use `.total()`.
  Python returns often shrink: `CharucoDetector.detectBoard` returns corners `(N,2)` and ids `(N,)`, so
  `cv2.aruco.drawDetectedCornersCharuco(img, corners, ids)` **asserts** until you pass `corners.reshape(-1,1,2)`.
- New depths `CV_16BF, CV_32U, CV_64U, CV_64S, CV_Bool` (5.1: FP8). 5.1: int64 numpy arrays stay `CV_64S` unless all
  values fit int32; integer add/sub saturate; `Mat_ << a, b, c` removed.
- `undistortPoints(src, K, D, R, P, criteria)` now takes the criteria (default **5 fixed iterations**: too few for
  strong distortion, pass `(COUNT|EPS, 100, 1e-12)`); `undistortPointsIter` is gone.
- `VideoCapture.get()` of an unsupported property returns **-1** (was 0). `INTER_NEAREST` follows Pillow; warp/remap
  numerics changed slightly; `putText` renders with a TrueType engine (HarfBuzz in 5.1; `FontFace`).
- DNN: Caffe/Darknet (5.0) and TensorFlow (5.1) importers removed: ONNX or TFLite only. 5.0 has
  `ENGINE_CLASSIC/NEW/ORT`; **5.1 removed the classic engine** (`ENGINE_AUTO/OPENCV/ORT`); env
  `OPENCV_FORCE_DNN_ENGINE`. 5.1 adds the CUDA backend to the new engine and `Net.enableTF32`.
- Python `cv2.calibrateHandEye` exists only from **5.1** (absent in the 5.0 wheels/conda; 4.x had it).

## 2. numpy interop (Python)

- Images are `HxWxC` uint8 **BGR** (`imread`, `VideoCapture`, drawing colours `(B,G,R)`). Convert at the boundary
  (`cv2.cvtColor(img, cv2.COLOR_BGR2RGB)`) for torch/PIL/matplotlib/Rerun (`rr.Image(img, color_model="BGR")` works).
- Output-writing functions (drawing, `dst=` args) need **C-contiguous** arrays. `img[:, ::2]` or `img[..., ::-1]`
  fails with the unhelpful `Expected Ptr<cv::UMat> for argument 'img'` (validated); `np.ascontiguousarray(...)` first.
  Read-only inputs accept views (copied internally). Row/column ROI slices (`img[100:200, 100:300]`) are contiguous per
  row and **write through** to the parent: handy, and a source of surprises.
- Functions keep the input dtype: float64 in → float64 out (slow, 2× memory); use float32 for images, float64 for
  geometry (points, K, D). Points: `float32/float64` arrays of shape `(N,2)`/`(N,1,2)`; int arrays are rejected by
  most geometry functions.
- Never loop over pixels in Python: a 200x3840 threshold count took 111 ms in a loop vs 0.34 ms with
  `cv2.threshold`+`countNonZero` (Mac). Preallocate `dst=` in hot loops; use LUTs (`cv2.LUT`) for per-pixel maps.

## 3. Image and video I/O

- `imread(path, cv2.IMREAD_UNCHANGED)` keeps 16-bit/alpha; `IMREAD_GRAYSCALE`, `IMREAD_REDUCED_COLOR_2`; returns
  `None` (no exception) on failure: check it. EXIF orientation is applied unless `IMREAD_IGNORE_ORIENTATION`.
  `imencode/imdecode` for buffers. 1280x960 frame (Mac): JPEG q90 206 kB, 2.8 ms enc / 3.0 ms dec; q75 129 kB; PNG
  level 1 743 kB, 30 ms; WebP q80 104 kB but 60 ms to encode. Params: `IMWRITE_JPEG_QUALITY`, `IMWRITE_PNG_COMPRESSION`
  (0–9; 1–3 for speed), `IMWRITE_WEBP_QUALITY`.
- `VideoWriter(path, cv2.CAP_FFMPEG, fourcc, fps, (w, h))`: frame size must match exactly, BGR uint8, or frames are
  dropped **silently**; check `isOpened()`. FFmpeg 9 (conda-forge, Mac) worked with `mp4v`/`avc1`/`hvc1` (.mp4), `MJPG`/
  `XVID` (.avi), `FFV1` (.mkv, lossless), `VP90` (.webm), `av01` (.mkv, very slow: 13.8 s for 60 VGA frames). `H264` in
  .mp4 warns and falls back to `avc1`; pip wheels may lack x264 (GPL), so prefer `avc1` and check the log.
  5.1 adds open-time encoder params: `VIDEOWRITER_PROP_BITRATE/CRF/PRESET/GOP_SIZE` (not in 5.0).
- `VideoCapture(src, apiPreference, params)`: pin the backend (`CAP_FFMPEG`, `CAP_GSTREAMER`, `CAP_V4L2`, `CAP_AVFOUNDATION`)
  instead of `CAP_ANY`. List: `cv2.videoio_registry.getBackends()`; 5.1: `enumerateDevices()`. Seeking with
  `CAP_PROP_POS_FRAMES` was frame-exact on an mp4v file. Set camera properties (`CAP_PROP_FRAME_WIDTH/HEIGHT/FPS/FOURCC`
  e.g. `MJPG` for USB cams at high fps) **before** the first read and read them back (drivers ignore what they don't do).
- HW decode: `VideoCapture(path, cv2.CAP_FFMPEG, [cv2.CAP_PROP_HW_ACCELERATION, cv2.VIDEO_ACCELERATION_ANY])` falls
  back silently; read `CAP_PROP_HW_ACCELERATION` (0 = software; values 0–5: NONE, ANY, D3D11, VAAPI, MFX, DRM; no NVDEC
  or VideoToolbox entry — it stayed 0 on the Mac). For NVIDIA use `cudacodec` (contrib, needs Video Codec SDK) or
  GStreamer/PyNvVideoCodec/TorchCodec (ml-data).
- Jetson CSI (validated on AGX Orin, IMX-type sensor): caps must be explicit and the sink must not block:
  ```python
  p = ("nvarguscamerasrc sensor-id=0 ! video/x-raw(memory:NVMM),width=1920,height=1080,framerate=30/1,format=NV12 ! "
       "nvvidconv ! video/x-raw,format=BGRx ! videoconvert ! video/x-raw,format=BGR ! appsink drop=1 max-buffers=2 sync=false")
  cap = cv2.VideoCapture(p, cv2.CAP_GSTREAMER)     # first read() may fail while Argus starts: retry a few times
  ```
  A plain `appsink` produced 67 188 failed reads in 3 s; the CPU `videoconvert` BGRx→BGR caps throughput (camera 12–15
  fps in that light, cv2 8–9 fps): read BGRx and drop alpha in numpy, or keep the frame on the GPU (DeepStream/VPI).
  HW decode: `filesrc ! qtdemux ! h264parse ! nvv4l2decoder ! nvvidconv ! video/x-raw,format=BGRx ! videoconvert !
  video/x-raw,format=BGR ! appsink` decoded 90/90 frames. Encoding with `appsrc ! videoconvert ! x264enc` from BGR makes
  **4:4:4 H.264** that nvv4l2decoder rejects ("Unsupported Codec"): add `video/x-raw,format=I420` before the encoder.

## 4. Camera calibration (ChArUco)

```python
dic = cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_5X5_100)
board = cv2.aruco.CharucoBoard((9, 6), 0.030, 0.022, dic)       # squares X,Y; square and marker length in metres
cv2.imwrite("board.png", board.generateImage((1800, 1200), marginSize=40, borderBits=1))
det = cv2.aruco.CharucoDetector(board)                          # 4.7+ API; cv2.aruco.CharucoBoard_create etc. are gone
obj, img = [], []
for im in frames:
    corners, ids, mcorners, mids = det.detectBoard(im)
    if ids is not None and len(ids) >= 8:
        o, i = board.matchImagePoints(corners, ids); obj.append(o); img.append(i)
rms, K, D, rvecs, tvecs, stdIntr, stdExtr, perView = cv2.calibrateCameraExtended(
    obj, img, (W, H), None, None, criteria=(cv2.TERM_CRITERIA_COUNT | cv2.TERM_CRITERIA_EPS, 100, 1e-12))
```
- Synthetic ground truth (Mac, 1280x960, K fx=900, k1=-0.28, 0.6 px blur + σ=2 noise): 22 views, all 40 corners →
  RMS 0.090 px, fx/fy/cx/cy within ±0.6 px (≈2σ of `stdIntr`), poses 0.04°/0.4 mm. With 40 views covering 66 % of the
  frame: fx error +0.19 px. **Coverage, not RMS, decides quality**: the estimated undistortion map was within 0.65–1.06 px
  of the truth inside the area the board covered but off by 2.2–2.9 px in uncovered corners. Low RMS with narrow
  coverage is a trap; tilt the board ±30–40° and fill the corners. Reject views with high `perViewErrors`.
- Models: default 5 coeffs `k1 k2 p1 p2 k3`; `CALIB_FIX_K3` for normal lenses (k3 is poorly constrained: σ 0.02 here);
  `CALIB_RATIONAL_MODEL` (k4–k6) for wide lenses; `cv2.fisheye.*` (4 coeffs, own functions; 5.1 rejects old numeric
  fisheye flags). `CALIB_USE_LU` is faster. Save with `cv2.FileStorage` (YAML/JSON) or as ROS/Foxglove CameraInfo.
- Undistort: `newK, roi = cv2.getOptimalNewCameraMatrix(K, D, (W,H), alpha)` (0 = no black borders, 1 = keep all
  pixels), then once `m1, m2 = cv2.initUndistortRectifyMap(K, D, None, newK, (W,H), cv2.CV_16SC2)` and per frame
  `cv2.remap(img, m1, m2, cv2.INTER_LINEAR)` (fixed-point maps are fastest). `cv2.undistort` rebuilds maps every call.
- ArUco/AprilTag: `cv2.aruco.ArucoDetector(dic, cv2.aruco.DetectorParameters())` with `DICT_APRILTAG_36h11` etc.;
  set `params.cornerRefinementMethod = cv2.aruco.CORNER_REFINE_SUBPIX` (default NONE) for pose work.
- Hand-eye: `cv2.calibrateHandEye(R_g2b, t_g2b, R_t2c, t_t2c, method=cv2.CALIB_HAND_EYE_PARK)` (Python ≥ 5.1/≤ 4.x),
  `calibrateRobotWorldHandEye`; feed ≥ 10 poses with large rotation diversity. See robot-math for SE(3) conventions.

## 5. Stereo

- Calibrate each camera alone, then `cv2.stereoCalibrate(..., flags=cv2.CALIB_FIX_INTRINSIC)` → R, T (x_right = R x_left
  + T). `R1,R2,P1,P2,Q,_,_ = cv2.stereoRectify(K1,D1,K2,D2,(W,H),R,T,flags=cv2.CALIB_ZERO_DISPARITY, alpha=0)`, maps
  with `initUndistortRectifyMap(K1, D1, R1, P1, …)`. Baseline·f = `-P2[0,3]`.
- Synthetic (Mac, 12 cm baseline, f=1000): stereo RMS 0.11 px still left R off by **0.107°**. Rectified with GT
  parameters: |Δy| median 0.018 px; with the estimated ones: 95th percentile 1.05 px, SGBM bad>1 px rose from 1.3 % to
  8.1 % and depth error from 6.9 to 11.3 mm. Check rectification by tracking features (LK) left→right and looking at
  Δy; ORB keypoints are integer-quantized and useless for that. Extrinsic drift is the usual cause of bad disparity.
- `StereoSGBM_create(minDisparity=0, numDisparities=192 (multiple of 16), blockSize=5, P1=8*bs², P2=32*bs² (×channels),
  disp12MaxDiff=1, uniquenessRatio=10, speckleWindowSize=100, speckleRange=2, mode=STEREO_SGBM_MODE_SGBM_3WAY)`;
  output is **int16 fixed point ×16**: divide by 16. 1280x800, 192 disparities: 55 ms (Mac M-series, 3WAY), median error
  0.12 px. `reprojectImageTo3D(disp, Q)`; invalid pixels are `minDisparity-1`. CUDA: `cv2.cuda.createStereoSGM`.

## 6. Pose and two-view geometry

- `solvePnP` methods (Mac, 300 Monte Carlo trials, σ 0.5 px): non-planar 20 pts SQPNP 0.19° (11 µs) ≈ ITERATIVE ≈
  +RefineLM; EPNP slightly worse. Planar 20 pts: SQPNP/ITERATIVE 0.63°, IPPE 0.79° (fastest), **EPNP has bad tails**
  (95th pct translation 97 mm). One 5 cm square marker (4 pts): median 8°, 95th pct **63°** for every method: the
  planar flip ambiguity. Use `SOLVEPNP_IPPE_SQUARE` + `solvePnPGeneric` (returns both solutions with errors), temporal
  consistency, or a board. P3P/AP3P need exactly 4 points.
- `solvePnPRansac(obj, img, K, D, iterationsCount, reprojectionError, confidence, flags=SOLVEPNP_SQPNP)` → `(ok, rvec,
  tvec, inliers)`: 30 % outliers, 0.08°, 1.3 ms. The **UsacParams overload returns 5 values** `(ok, K, rvec, tvec,
  inliers)`: unpacking 4 silently gives garbage (validated). Refine: `solvePnPRefineLM/VVS`.
- `findHomography(src, dst, cv2.USAC_MAGSAC, 3.0)` was as fast as RANSAC and more accurate on AKAZE matches (0.10 vs
  0.22 px). `findEssentialMat(p1, p2, K, cv2.USAC_MAGSAC, 0.999, 1.0)` → `recoverPose(E, p1, p2, K)` (translation is
  up to scale) → `triangulatePoints(P1, P2, x1, x2)` (2xN float, returns 4xN homogeneous). Undistort points first
  (`undistortPoints(..., P=K)`) when D ≠ 0.

## 7. Features, flow, tracking

- 1080x720 synthetic pair under H with rotation/scale/perspective (Mac): SIFT 4000 kp 103 ms (both images), ratio test
  0.75 → 99 % true matches, H error 0.15 px; ORB 4000 kp 42 ms, 95 % true, 0.3 px; AKAZE 0.1–0.2 px. FLANN (KD-tree
  for SIFT, LSH `algorithm=6` for binary) was not faster than BF at 4000 descriptors. ORB needs `fastThreshold` lowered
  on low-contrast images.
- LK: `goodFeaturesToTrack` + `calcOpticalFlowPyrLK(winSize=(21,21), maxLevel=3)` with a forward-backward check
  (< 0.5 px): drift after 30 frames median 0.29 px, 5 ms/frame for 500 points both ways. Dense: DIS
  (`DISOpticalFlow_create(PRESET_ULTRAFAST/FAST/MEDIUM)`) 1.8 / 7.3 / 22 ms at 960x640 with EPE 0.16 / 0.12 / 0.034 px;
  Farneback 62 ms, 0.039 px. DIS medium is the default choice on CPU.
- Trackers (`TrackerX_create()`; `init(frame, box)`, `update` → `(ok, box)`): CSRT 0.9 px error/18 ms, KCF 3.9 px/7 ms,
  MIL 1.8 px/79 ms (contrib build, 20 frames). For multi-object tracking use a detector + `cv2.linearAssignment` (5.1)
  or a dedicated tracker.

## 8. DNN

- `net = cv2.dnn.readNetFromONNX(path)`; `blob = cv2.dnn.blobFromImage(img, 1/255, (224,224), swapRB=True)`
  (bit-exact vs numpy); ImageNet mean/std per channel: `Image2BlobParams` + `blobFromImageWithParams` (validated).
  `net.setPreferableBackend(cv2.dnn.DNN_BACKEND_CUDA); net.setPreferableTarget(cv2.dnn.DNN_TARGET_CUDA_FP16)` needs a CUDA
  build; check `cv2.dnn.getAvailableTargets(cv2.dnn.DNN_BACKEND_CUDA)`.
- **Validate against ONNX Runtime before trusting it.** OpenCV 5.0 returned garbage (|Δ| 1e6) for torchvision
  MobileNetV3 exported with the PyTorch 2.14 dynamo exporter (opset 18: SE block `ReduceMean(keepdims)` + broadcast
  `Mul` collapsed to `(1,C)`), on both engines and still in 5.1 (CPU and CUDA), while the TorchScript export
  (`dynamo=False`, opset 17) matched to 6e-6.
- **5.1 CUDA is all-or-nothing and silent**: if any op lacks a CUDA executor (e.g. a Conv with fused HardSwish in
  MobileNetV3) the **whole graph runs on CPU** with no warning; `OPENCV_LOG_LEVEL=INFO` prints "has no CUDA exec;
  running the whole graph on CPU" / per-op `-> CPU|CUDA`. ResNet-18 (RTX 5090, 5.1 source build): CPU 2.82 ms,
  CUDA FP32 0.74 ms, FP16 0.39 ms. FP32 uses **TF32 by default** (|Δ| 3.6e-3); `net.enableTF32(False)` → 3e-6.
- Use cv2.dnn for small CPU models inside an OpenCV pipeline and zero extra dependencies. For GPU throughput or Jetson
  use TensorRT (ml-deploy) or ONNX Runtime; for training-side preprocessing use torch/DALI (ml-data).

## 9. Performance

- Threads: OpenCV parallelizes internally (TBB/OpenMP/pthreads/GCD). `cv2.setNumThreads(0)` = **sequential** (4K blur
  11 ms vs 2.3 ms default on the Mac). Inside DataLoader workers or multiprocessing pools set 0 or 1 to avoid
  oversubscription (ml-data). With the GCD backend `getNumThreads()` misreports; measure instead.
- UMat (T-API): `cv2.UMat(img)` runs the same functions through OpenCL if `cv2.ocl.haveOpenCL()`; the conda-forge Mac
  build has OpenCL off (UMat then just works on CPU). 5.1 adds a CUDA UMat allocator.
- `cv2.cuda` exists only in CUDA builds: `GpuMat.upload/download`, `cv2.cuda.cvtColor/resize/warpPerspective`, filters
  via `createGaussianFilter`, `createStereoSGM`, `FarnebackOpticalFlow`, `cuda.Stream` for async. RTX 5090 vs 24 CPU
  threads, 4K BGR: upload 0.88 ms + download 1.52 ms (pageable) vs GaussianBlur 2.12 → 0.33 ms, warpPerspective
  1.45 → 0.15 ms, cvtColor 0.37 → 0.08 ms: one op never pays for its transfers; chain several on the GPU. Big wins:
  StereoSGM 1080p/128 disp 2.5 ms vs SGBM 50 ms (same result); CUDA Farneback 5.1 ms vs 254 ms (its defaults
  underestimated a 3 px shift: tune pyramid/window).
- CUDA build from source with Pixi (validated, powerslabs; conda-forge has none): env with `cuda-nvcc cuda-cudart-dev
  libcublas-dev libcufft-dev libnpp-dev cudnn cuda-version=13.* cxx-compiler cmake ninja ffmpeg python numpy`; cmake
  with `-DOPENCV_EXTRA_MODULES_PATH=<contrib>/modules -DWITH_CUDA=ON -DWITH_CUDNN=ON -DOPENCV_DNN_CUDA=ON
  -DCUDA_ARCH_BIN=12.0 -DBUILD_LIST=core,imgproc,…,cudaarithm,cudaimgproc,cudawarping,cudafilters,cudastereo,cudaoptflow,python3`.
  Fixes needed: `export PATH=$CONDA_PREFIX/nvvm/bin:$PATH` ("cicc: command not found"; setting
  `CUDA_TOOLKIT_ROOT_DIR=$CONDA_PREFIX` instead breaks detection), `-DWITH_AVIF=OFF -DWITH_OPENEXR=OFF -DWITH_JPEGXL=OFF
  -DWITH_OPENJPEG=OFF` (system headers leaked in), `-DBUILD_HARFBUZZ=ON` (5.1 needs `hb_raster_*`). ~25 min on 22 jobs.
  Use it with `PYTHONPATH=<install>/python LD_LIBRARY_PATH=<install>/lib`.
- Work at the resolution you need (`resize(INTER_AREA)` first), use `CV_16SC2` remap maps, grayscale where possible,
  fixed-size preallocated outputs, and `cv2.TickMeter`/`perf_counter` around the real pipeline. G-API now lives in contrib.

## 10. C++ via Pixi, and Odin

```toml
[dependencies]   # pixi.toml
opencv = "*"     # libopencv headers, libs and OpenCVConfig.cmake
cxx-compiler = "*"
cmake = "*"
ninja = "*"
```
```cmake
set(CMAKE_CXX_STANDARD 17)   # 5.x requires C++17
find_package(OpenCV REQUIRED COMPONENTS core imgproc imgcodecs calib objdetect features)
target_link_libraries(app PRIVATE ${OpenCV_LIBS})
```
`pixi run cmake -G Ninja -S . -B build && pixi run cmake --build build` (validated, Mac). 4.x component names are
`calib3d features2d`. Catch `cv::Exception` at API boundaries.
- Odin: no binding exists (OpenCV is C++). Write a small `extern "C"` wrapper (plain pointers, sizes, int return codes;
  wrap caller buffers with `cv::Mat(h, w, CV_8UC1, ptr, stride)` without copying; catch all exceptions), build it as a
  shared library in the same CMake project, and `foreign import cvw "libcvwrap.dylib"` with
  `@(default_calling_convention = "c")` (validated: Odin dev-2026-11a detected 40 ChArUco corners through it; add
  `-extra-linker-flags:"-Wl,-rpath,<dir>"`). Prefer doing heavy vision in C++/Python and exchanging results over Zenoh.

## 11. Robotics glue

- Over Zenoh: JPEG payload (q85–90; 15–20× smaller than raw, ~3 ms) with `encoding=zenoh.Encoding.IMAGE_JPEG` and
  metadata (stamp, frame_id, size) as a JSON or protobuf **attachment** (validated in-process); raw/PNG only for
  lossless needs (depth: 16-bit PNG or raw + `Encoding` and shape in the attachment). See zenoh, robot-serialization.
- MCAP/Foxglove: `foxglove.CompressedImage(timestamp, frame_id, data=jpg_bytes, format="jpeg")` plus
  `foxglove.CameraCalibration(width, height, distortion_model="plumb_bob", D=[k1,k2,p1,p2,k3], K=row-major 9, R=I, P=3x4)`
  with `mcap-protobuf-support` (round-trip validated). Fisheye: `distortion_model="kannala_brandt"`. Don't zstd-compress
  JPEG chunks. See mcap.
- Rerun: `rr.Pinhole(image_from_camera=K, width=W, height=H, camera_xyz=rr.ViewCoordinates.RDF)` (OpenCV camera
  frame = RDF), `rr.EncodedImage(contents=jpg_bytes, media_type="image/jpeg")` for streams, `rr.Image(img,
  color_model="BGR")` for debugging. See rerun.
