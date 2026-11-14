---
name: robot-math
description: Robotics geometry and estimation in C++/Python — Eigen 5 (Isometry3d, Quaterniond, AngleAxis, canonicalEulerAngles, Map and row-major interop, alignment, fixed vs dynamic sizes, EIGEN_NO_DEBUG, choosing LLT/LDLT/LU/QR/COD/SVD), Lie groups with Sophus (SO3/SE3 exp/log, hat/vee, Adj, interpolate) and manif (rplus/lplus, between, analytic Jacobians, manifpy), factor graphs with GTSAM 4.3 (NonlinearFactorGraph, Values, Pose3, PriorFactor/BetweenFactor, noise models incl. robust, LM, ISAM2, Marginals, Python gtsam), nonlinear least squares with Ceres 2.2 (AutoDiffCostFunction, Problem, loss functions, Solver::Options, Manifold API replacing LocalParameterization, quaternion manifolds), lidar odometry/registration with KISS-ICP and small_gicp (ICP/PLANE_ICP/GICP/VGICP, threads), conventions (frames T_a_b, Hamilton vs JPL, w-first vs w-last storage, tangent ordering, left vs right perturbation, row/col-major), conda-forge/Pixi build pitfalls, and Odin core:math/linalg equivalents. Load before writing pose math, SLAM/odometry back-ends, calibration or registration code.
---

# Robot math: Eigen, Sophus, manif, GTSAM, Ceres, KISS-ICP, small_gicp

Environments come from **pixi**, and statistics on results (ATE intervals, comparisons) are covered in
**stats-inference** / **experiment-design**. ROS 2 transport is in **zenoh-ros2**, recording in **mcap**, and dataflows in
**dora**. Odin details are in **odin** / **odin-performance**. The reference library holds the pinned sources:
`eigen-source` (Eigen/src/Geometry, Cholesky, QR, SVD, Core/util), `sophus-source`, `manif-source`, `gtsam-source`
(gtsam/geometry, nonlinear, slam, linear/NoiseModel.h, doc/), `ceres-source` (include/ceres, docs/source),
`kiss-icp-source`, `small-gicp-source`. `library_search` them for exact signatures. These APIs changed across major
versions, and memory of older versions is often wrong.

## 0. Ground truth (checked 13 Nov 2026, verify)

| Library | Version | Get it | Notes |
|---|---|---|---|
| Eigen | **5.0.1** (3.4.1 is the previous line) | conda-forge `eigen` (linux-64, linux-aarch64, osx-arm64) | Semver since 5.0. Header macros `EIGEN_WORLD_VERSION 3`, `EIGEN_MAJOR_VERSION 5`. CMake `find_package(Eigen3)` → `Eigen3::Eigen`. Needs ≥ C++14. Hosted on GitLab only. |
| Sophus | **1.24.6** | conda-forge `sophus` (version `1!1.24.6`) | Header-only, `Sophus::Sophus`. Its config requires Eigen3 5.0.1 in that build. |
| manif | **0.0.5** | conda-forge `manif` + `manifpy` (Python) | Header-only, `MANIF::manif`. Groups: SO2/SO3/SE2/SE3/SE_2_3/SGal3/Rn/Bundle. |
| GTSAM | **4.3.0** | conda-forge `gtsam` (C++ **and** Python), PyPI `gtsam` | Built with TBB, `GTSAM_POSE3_EXPMAP`, `GTSAM_ROT3_EXPMAP`, Boost features on, `GTSAM_ALLOW_DEPRECATED_SINCE_V43`. |
| Ceres | **2.2.0** | conda-forge `ceres-solver` | `Ceres::ceres`. `LocalParameterization` is **gone**: use `Manifold`. PyPI `pyceres` 2.6 has no linux-aarch64 wheel. |
| KISS-ICP | **1.3.0** | PyPI `kiss-icp` only | CLI `kiss_icp_pipeline`, `kiss_icp_dump_config`. |
| small_gicp | **1.0.1** | PyPI `small-gicp` only (`import small_gicp`) | Header-only C++ also available (`include/small_gicp`). |

Working Pixi manifest (tested on linux-64 and linux-aarch64; all packages also exist for osx-arm64):
```toml
[dependencies]
python = "3.12.*"
numpy = "*"
scipy = "*"
eigen = "5.0.*"
sophus = "*"
manif = "*"
manifpy = "*"
gtsam = "4.3.*"
ceres-solver = "2.2.*"
cxx-compiler = "*"
cmake = "*"
ninja = "*"
tbb-devel = "*"        # GTSAMConfig.cmake: find_dependency(TBB) — runtime tbb has no CMake config
libboost-devel = "*"   # gtsam headers include boost/concept_check.hpp; see pitfall 3
[pypi-dependencies]
kiss-icp = "==1.3.0"
small-gicp = "==1.0.1"
```
```cmake
project(app C CXX)          # C is required: Ceres → SuiteSparse config calls find_package(OpenMP C)
set(CMAKE_CXX_STANDARD 17)
find_package(Eigen3 REQUIRED CONFIG)  find_package(Sophus REQUIRED CONFIG)  find_package(manif REQUIRED CONFIG)
find_package(Ceres REQUIRED CONFIG)   find_package(GTSAM REQUIRED CONFIG)
target_link_libraries(a Eigen3::Eigen Sophus::Sophus MANIF::manif)  # b: Ceres::ceres   c: gtsam
```
Build pitfalls hit while testing (all fixed by the manifest and CMake above):
1. `project(x CXX)` failed with `Could NOT find OpenMP (missing: OpenMP_C_FOUND C)` (from `CeresConfig.cmake` → SuiteSparse).
2. Without `tbb-devel`, CMake failed: `Could not find a package configuration file provided by "TBB" (requested version 4.4)`.
3. Without Boost, the build failed with `fatal error: boost/concept_check.hpp`. With only `libboost-headers`, CMake picked up the **system**
   `/usr/lib/libboost_*.so.1.92` while conda's libgtsam needs 1.90, which gave `may conflict with libboost_serialization.so.1.92.0` and a link
   error. `libboost-devel` puts `Boost_DIR` in the env. Delete `build/` after changing packages.
4. aarch64 GCC prints `note: parameter passing for argument of type 'Eigen::Matrix<double, 2, 1>' when C++17 is enabled changed
   to match C++14 in GCC 10.1`. This is an ABI note, not an error. Silence it with `-Wno-psabi`.

## 1. Conventions: decide once, write them down

- **Frames**: name transforms `T_a_b`, mapping coordinates in frame b into frame a: `p_a = T_a_b * p_b`. Compose by
  matching inner indices, `T_w_c = T_w_b * T_b_c`, and invert by swapping, `T_b_a = T_a_b.inverse()`. Most bugs here are a
  missing inverse.
- **Quaternions**: Eigen, Sophus, manif, GTSAM and Ceres all use **Hamilton** (`ij = k`, active rotation,
  `R(q1 q2) = R(q1) R(q2)`). JPL (`ij = -k`, used in some VIO/Kalman-filter papers such as MSCKF) composes in the opposite
  order, so convert at the boundary. The **storage order** differs, which matters for raw arrays:
  `Eigen::Quaterniond(w, x, y, z)` constructor but `coeffs()`/memory = **x, y, z, w** (tested). Ceres
  `QuaternionManifold` and `ceres/rotation.h` use **w, x, y, z**, and `EigenQuaternionManifold` uses x, y, z, w. manif `SE3(t, quat)`
  stores `[x y z | qx qy qz qw]` (manifpy coeffs `[1,2,3,0,0,0,1]`). GTSAM `Rot3::Quaternion(w,x,y,z)`, while
  `toQuaternion().coeffs()` is x,y,z,w (tested). ROS `geometry_msgs/Quaternion` is x,y,z,w, and scipy `as_quat()` is x,y,z,w
  (`scalar_first=True` changes that).
- **Tangent ordering** (6-vectors): Sophus and manif SE3 use **[translation ρ; rotation θ]**. GTSAM Pose3 uses
  **[rotation ω; translation v]**: `Pose3.Logmap(Yaw 0.1, t=(1,0,0)) = [0 0 0.1 0.9992 -0.05 0]` (tested). Noise
  sigmas and covariances follow that order: `Diagonal::Sigmas([σrot×3, σtrans×3])`. The translation part of the tangent is
  **not** the translation: `SE3::exp([υ; ω]).translation() = V(ω)·υ` (tested, (0.881, 0.536, -0.091) for υ = (1, 0.2, -0.3)).
- **Perturbations**: right means `X ⊕ τ = X·Exp(τ)` (τ in the body/local frame), left means `Exp(τ)·X` (τ in the
  world frame). manif has both (`rplus`, `lplus`; `plus` = `rplus`). GTSAM `retract` = `compose(Expmap(v))` (right), Ceres
  `QuaternionManifold::Plus = Exp(δ)·q` (left), and Sophus `ceres_manifold.hpp` = `T·exp(δ)` (right). Jacobians and covariances
  must be expressed with the **same** convention: convert with the adjoint (`Σ_left = Adj·Σ_right·Adjᵀ`).
- **Euler angles**: avoid them except for display. Eigen 5's `R.canonicalEulerAngles(2,1,0)` gives yaw/pitch/roll in
  [-π,π]×[-π/2,π/2]×[-π,π]. The older `eulerAngles(2,1,0)` returns **non-canonical** ranges ([0,π] first). Tested: yaw -2.5, pitch
  0.2 → canonical (-2.5, 0.2, 0), `eulerAngles` (0.642, 2.942, 3.142), which describe the same rotation but are useless for logging.
- **Matrix layout**: Eigen is column-major, numpy is C-order (row-major). `Map<Matrix<double,4,4,RowMajor>>(ptr)` reads a
  numpy 4×4 correctly, and plain `Map<Matrix4d>` reads its transpose (tested: translation (10,20,30) became (0,0,0)).

## 2. Eigen 5

```cpp
Quaterniond q(AngleAxisd(yaw, Vector3d::UnitZ()) * AngleAxisd(pitch, Vector3d::UnitY()) * AngleAxisd(roll, Vector3d::UnitX()));
Isometry3d T_w_a = Translation3d(1, 2, 0) * q;         // Isometry: inverse() uses Rᵀ (Affine3d does a general inverse)
Vector3d p_w = T_w_a * p_a;  Isometry3d T_w_b = T_w_a * T_a_b;
Quaterniond qm = qa.slerp(t, qb);  q.normalize();       // re-normalize after many products
Map<const Matrix<double, Dynamic, 3, RowMajor>> P(np_ptr, n, 3);   // view an N×3 point buffer without copying
```
- **Fixed vs dynamic**: use fixed sizes (`Matrix3d`, `Matrix<double,6,6>`) up to about 16 elements. They live on the stack, are
  unrolled and vectorized. Use `MatrixXd` for large or runtime sizes. Don't mix them in hot loops (heap allocation): reuse
  dynamic matrices and `noalias()` products.
- **Alignment**: with C++17 the old rules (`EIGEN_MAKE_ALIGNED_OPERATOR_NEW`, `aligned_allocator` for `std::vector<Vector4d>`)
  are no-ops. The macro is defined empty when `EIGEN_HAS_CXX17_OVERALIGN`. Tested: `std::vector<Vector4d>` was 32-byte aligned
  on x86 and 16-byte on aarch64, both correct. Under C++14, or with structs passed by value to ABIs compiled with other flags,
  the old crashes come back: compile everything with the same `-std` and `-march`. Never pass fixed-size Eigen
  objects by value across a library boundary; pass `const&`.
- `EIGEN_NO_DEBUG` (implied by `-DNDEBUG`) removes bounds and size asserts. Keep asserts in debug builds: they catch
  size mismatches that would otherwise silently corrupt memory. `EIGEN_DONT_VECTORIZE` and `EIGEN_MAX_ALIGN_BYTES=0` are for
  ABI debugging only.
- Watch out for `auto` with expressions: `auto x = A * b;` stores an unevaluated expression that refers to temporaries. Write
  `Vector3d x = …` or `.eval()`.
- 5.0 changes: `JacobiSVD`/`BDCSVD` take options as a **template parameter**
  (`BDCSVD<MatrixXd, ComputeThinU | ComputeThinV>`). The constructor option is deprecated.

**Solver choice** (tested: 400×400 SPD, x86_64 / Jetson Orin; residuals all < 1e-14):

| Solver | when | x86 / Orin ms |
|---|---|---|
| `llt()` | SPD (normal equations, covariances, Hessians) | 1.5 / 2.6 |
| `ldlt()` | symmetric semidefinite, robust to near-singular | 1.4 / 5.5 |
| `partialPivLu()` | square invertible, general | 2.3 / 4.0 |
| `householderQr()` | least squares, full rank, fast | 4.8 / 9.4 |
| `colPivHouseholderQr()` | least squares, rank-revealing (`.rank()`) | 6.0 / 20 |
| `completeOrthogonalDecomposition()` | rank-deficient, gives the minimum-norm solution | – |
| `BDCSVD<…ComputeThin…>` | rank, null space, pseudo-inverse; large matrices | 54 / 133 |
| `JacobiSVD<…>` | small matrices (≤ ~20) only; 10× slower at 400 | 548 / 1630 |

Rank-deficient 200×6 test: COD and ColPivQR both reported rank 5, and COD and SVD gave the same minimum-norm |x| = 0.1648.
For sparse problems use `SimplicialLDLT`, `SparseLU` or CHOLMOD through SuiteSparse (what GTSAM and Ceres do internally).

## 3. Lie groups: Sophus and manif

```cpp
#include <sophus/se3.hpp>
#include <sophus/interpolate.hpp>
Sophus::SE3d X = Sophus::SE3d::exp(xi);            // xi = [υ; ω]
Vector6d v = X.log();  Matrix3d W = Sophus::SO3d::hat(w);  Vector3d w2 = Sophus::SO3d::vee(W);
Sophus::SE3d Tm = Sophus::interpolate(Ta, Tb, 0.5);   // == Ta * exp(0.5 * log(Ta⁻¹ Tb)) (tested: exact)
Matrix6d A = X.Adj();                               // X·exp(ξ)·X⁻¹ = exp(Adj·ξ) (tested 2e-16)
Sophus::SE3d S(T_eigen.matrix());                   // from a 4×4; .matrix() back. Asserts orthonormal R
```
```cpp
#include <manif/SE3.h>
manif::SE3d M(t, Quaterniond(R));  manif::SE3Tangentd tau; tau.coeffs() << rho, theta;
manif::SE3d::Jacobian J_x, J_t;
manif::SE3d Y = M.rplus(tau, J_x, J_t);            // Y = M·Exp(τ); Jacobians on right-perturbation convention
manif::SE3Tangentd d = Ma.between(Mb).log();       // between = Ma⁻¹·Mb;   rminus(a,b) = Log(b⁻¹ a)
Vector3d p2 = M.act(p, J_p_m, J_p_p);              // transform a point, with Jacobians
```
- Tested: manif `exp`/`log` equal Sophus to 1e-16 (same tangent order). Analytic `rplus` Jacobian vs numeric differences:
  max error 8.7e-8. `rplus` and `lplus` differ (1.396 for the test pose), so pick one convention.
- Python: `manifpy.SE3(t, quat_xyzw)`, `SE3Tangent(np.array(6))`. Jacobians are passed as **preallocated writable
  C-contiguous** `np.zeros((6,6))` arrays: `Y = X.rplus(t, J_x, J_t)` fills them.
- Sophus or manif? Sophus is smaller and simpler, with splines (`sophus/spline.hpp`), and is the usual choice inside Ceres
  (`sophus/ceres_manifold.hpp`). manif comes with Jacobians for every operation and Python bindings, and fits hand-written
  Gauss-Newton or error-state Kalman filters (see "A micro Lie theory", Solà et al., which manif implements).

## 4. GTSAM 4.3 factor graphs (tested: C++ and Python gave identical numbers)

```cpp
using symbol_shorthand::X;
NonlinearFactorGraph graph;  Values init;
auto odom = noiseModel::Diagonal::Sigmas((Vector6() << 0.02,0.02,0.02, 0.05,0.05,0.05).finished());  // [rot; trans]
auto loop = noiseModel::Robust::Create(noiseModel::mEstimator::Huber::Create(1.345), odom);
graph.addPrior(X(0), Pose3(), noiseModel::Isotropic::Sigma(6, 1e-4));             // PriorFactor<Pose3>
graph.emplace_shared<BetweenFactor<Pose3>>(X(i-1), X(i), odo_meas, odom);          // measured = T_{i-1}⁻¹ T_i
init.insert(X(i), guess);
Values res = LevenbergMarquardtOptimizer(graph, init, LevenbergMarquardtParams()).optimize();
Marginals(graph, res).marginalCovariance(X(10));                                   // 6×6 in [rot; trans] order
ISAM2Params ip; ip.relinearizeThreshold = 0.01; ip.relinearizeSkip = 1; ISAM2 isam(ip);
isam.update(newFactors, newValues);  Values est = isam.calculateEstimate();
```
Python: `gtsam.PriorFactorPose3`, `gtsam.BetweenFactorPose3`, `gtsam.symbol_shorthand.X`, `values.atPose3(k)`,
`isam.calculateEstimatePose3(k)`, `ip.setRelinearizeThreshold(0.01)`.
- Toy result (square loop, 20 poses, biased odometry, one loop closure): dead-reckoning error 1.974 m, LM **0.152 m**
  (graph error 156.2 → 22.2), marginal σ of pose 10 = 0.171 m. ISAM2 incremental gave 0.232 m after the loop plus two extra
  `update()` calls: incremental is approximate. Run a batch LM (or more ISAM2 updates and a lower `relinearizeThreshold`)
  when accuracy matters more than latency.
- Use `Values::insert` for new keys and `update` for existing ones (inserting a key twice throws). Every connected component
  needs a prior (gauge freedom). Otherwise you get an `IndeterminantLinearSystemException` naming the variable.
- Factor library (`gtsam/slam`, `gtsam/navigation`): `BetweenFactor`, `PriorFactor`, `GenericProjectionFactor`,
  `SmartProjectionPoseFactor`, `GeneralSFMFactor`, `RangeFactor`/`BearingRangeFactor`, IMU `ImuFactor` /
  `CombinedImuFactor` with `PreintegratedImuMeasurements`, `GPSFactor`. Custom factors: derive from `NoiseModelFactorN<…>`
  and implement `evaluateError(x…, OptionalMatrixType H…)`, or use expressions (`gtsam/nonlinear/expressions.h`).

## 5. Ceres 2.2

```cpp
struct Res { double x, y;
  template <typename T> bool operator()(const T* m, const T* c, T* r) const { r[0] = T(y) - exp(m[0]*T(x) + c[0]); return true; } };
problem.AddResidualBlock(new ceres::AutoDiffCostFunction<Res, 1, 1, 1>(new Res{x, y}),   // <Functor, nres, block sizes…>
                         new ceres::CauchyLoss(0.5), &m, &c);
problem.SetManifold(q, new ceres::EigenQuaternionManifold);   // q stored x,y,z,w; QuaternionManifold for w,x,y,z
problem.SetParameterBlockConstant(t0);                        // fix the gauge
ceres::Solver::Options o; o.linear_solver_type = ceres::SPARSE_SCHUR; o.num_threads = 8;
ceres::Solver::Summary s; ceres::Solve(o, &problem, &s);      // s.BriefReport(), s.IsSolutionUsable()
```
- **API changes**: `AutoDiffCostFunction<F,…>(x, y)` does **not** forward constructor arguments. Pass `new F(…)` (tested
  compile error: "no matching function"). `LocalParameterization`/`SetParameterization` were removed in 2.2. The
  replacements are `Manifold` subclasses: `EuclideanManifold<N>`, `SubsetManifold(size, constant_indices)`,
  `QuaternionManifold`, `EigenQuaternionManifold`, `SphereManifold<N>`, `LineManifold<N>`,
  `ProductManifold<M1, M2>`, `AutoDiffManifold<Functor, ambient, tangent>`, or `Sophus::Manifold<Sophus::SE3>`
  (`sophus/ceres_manifold.hpp`, parameter block = `SE3d::data()`, 7 doubles: quaternion x,y,z,w then translation).
- Tested: the exponential curve fit with 5 gross outliers gave m = 0.266, c = 0.296 without a loss and **0.2994, 0.1031** with
  `CauchyLoss(0.5)` (truth 0.3, 0.1). BA-lite (3 cameras, 60 points, Huber, SPARSE_SCHUR, camera 0 and point 0 fixed) went from
  cost 4105 to 1.02 in 4 iterations and 1.1 ms; pose error 1 cm / 0.0012 rad.
- Linear solvers: `DENSE_QR` for small problems, `DENSE_SCHUR` for BA with few cameras, `SPARSE_SCHUR` for BA,
  `SPARSE_NORMAL_CHOLESKY` for pose graphs, `ITERATIVE_SCHUR` + `SCHUR_JACOBI` for very large BA.
- Ceres or GTSAM? Ceres suits one-shot batch problems with custom residuals (calibration, BA, curve fits) and is
  well documented. GTSAM fits when the problem *is* a factor graph that grows over time (SLAM, VIO with IMU preintegration,
  ISAM2, marginals). Both are used in production; mixing them is rare.

## 6. Lidar registration: KISS-ICP and small_gicp (tested on a synthetic sequence)

The test sequence: a ray-cast room with 40 boxes, a 32×1024 beam lidar with 1 cm noise, and a 108 m figure-eight of 120 frames (~0.9 m/frame).

```python
from kiss_icp.config import KISSConfig
from kiss_icp.kiss_icp import KissICP
cfg = KISSConfig(); cfg.data.max_range = 60.0; cfg.data.deskew = False
cfg.mapping.voxel_size = 0.6                 # MUST set: bare KISSConfig() leaves None (load_config uses max_range/100)
odom = KissICP(cfg)
for pts in scans:                            # Nx3 float64 in the sensor frame
    odom.register_frame(pts, np.zeros(len(pts)))      # timestamps per point (used by deskew)
    poses.append(odom.last_pose.copy())               # T_world_sensor, world = first frame
```
```python
import small_gicp
r = small_gicp.align(target_pts, source_pts, init_T_target_source=np.eye(4), registration_type="GICP",  # ICP|PLANE_ICP|GICP|VGICP
                     downsampling_resolution=0.25, max_correspondence_distance=1.0, num_threads=8)
r.T_target_source, r.converged, r.iterations, r.num_inliers
tgt, tree = small_gicp.preprocess_points(pts, downsampling_resolution=0.25, num_threads=8)  # reuse in a loop:
r = small_gicp.align(tgt, src, tree, init_T_target_source=guess, num_threads=8)
```

| Method (x86 24 cores) | ms/frame | rel. error | trajectory ATE RMSE |
|---|---|---|---|
| KISS-ICP (voxel 0.6, own threads) | 10.3 (Orin: 56) | – | **0.046 m**, 0.16° |
| small_gicp ICP, identity init | 87 (1 thr) / 47 (24) | 5.6 cm, 78/119 converged | 9.6 m (fails) |
| small_gicp PLANE_ICP | 60 / 30 | 0.89 cm | 0.55 m |
| small_gicp GICP | 32 / 18 | 0.29 cm | 0.086 m (chained scan-to-scan) |
| small_gicp VGICP | 26 / 11 | 0.17 cm | 0.082 m |
| GICP, preprocessed clouds | **0.99** (Orin 12 thr: 8.9) | 0.08 cm | – |

- The `align(points…)` timings include downsampling, the kd-tree and covariance estimation. In a loop, preprocess each scan once,
  reuse the target tree, and pass the previous motion as `init_T_target_source`. Plain point-to-point ICP without an initial guess
  diverged at 0.9 m/frame. GICP thread scaling on preprocessed clouds (x86): 1→11.6 ms, 4→4.2, 24→1.3. On a shared Jetson
  (load average 20) the scaling was erratic: benchmark on an idle machine.
- KISS-ICP is a complete odometry (motion prediction, adaptive threshold, local voxel map, deskew). small_gicp is a fast
  registration library for building your own odometry, loop-closure checks or map alignment. Feed both results into GTSAM
  as `BetweenFactor`s for a full SLAM back end.
- `kiss_icp.metrics.absolute_trajectory_error(gt, est)` returns **(rot_rad, trans_m)** after **Umeyama SE(3)
  alignment** (it reported 0.0105 m for the run whose unaligned RMSE was 0.046 m). State which ATE you report, and add
  intervals (**stats-inference**). CLI: `kiss_icp_pipeline <data_dir>` (KITTI/rosbag/mcap/ply readers, `--visualize`
  needs a display), `kiss_icp_dump_config` writes the YAML.

## 7. Odin equivalents (`core:math/linalg`, tested dev-2026-11a, x86_64 and aarch64)

```odin
import "core:math/linalg"
q := linalg.quaternion_angle_axis_f64(0.7, linalg.normalize([3]f64{1, 2, 3}))   // quaternion256; real(q)=w, imag/jmag/kmag
T := linalg.matrix4_from_trs_f64({1, -2, 0.5}, q, {1, 1, 1})                  // matrix[4,4]f64, column-major
a := (T * U) * [4]f64{0.4, -0.7, 2.0, 1}                                       // built-in matrix ops
R := linalg.matrix3_from_quaternion_f64(q);  b := linalg.transpose(R) * (p - t)  // rigid inverse
s := linalg.quaternion_slerp_f64(q, qu, 0.3);  v := linalg.quaternion_mul_vector3(q, [3]f64{1, 0, 0})
```
Hamilton convention. `m[row, col]` indexing, column-major memory (so the flat `[16]f64` equals Eigen's `data()` order). The outputs
matched Eigen to all 9 printed digits (quaternion, composition, inverse, slerp, R[0,1]) on both machines. There are no Lie
exp/log, SE(3) Jacobians or solvers in core: write `exp`/`log` yourself (Rodrigues; `V(ω)` for SE(3)) or call C. On aarch64 Linux
without clang, `ODIN_CLANG_PATH=gcc odin build …` linked fine. Pitfall: `(transmute([16]f64)T)[0:4]` fails ("value is not
addressable"); assign it to a variable first.

## 8. Checklist

1. Write the frame convention (`T_a_b`), quaternion storage order and perturbation side at the top of each module.
2. Don't hand quaternions between libraries as raw arrays without checking w-first vs w-last. Re-normalize after integration.
3. Order sigmas and covariances in the library's tangent order: GTSAM [rot; trans], Sophus/manif [trans; rot].
4. Fix the gauge (prior or constant block). Use robust losses on loop closures and outliers.
5. Check analytic Jacobians against numeric differences once (manif: done here, 8.7e-8).
6. Eigen: fixed sizes for small objects, no `auto` on expressions, one `-std`/`-march` everywhere. Choose LLT for SPD, COD/SVD
   for rank-deficient systems, and avoid JacobiSVD for big matrices.
7. Pixi C++ builds: `project(… C CXX)`, add `tbb-devel` and `libboost-devel` for GTSAM, and delete `build/` after changing packages.
8. Registration: preprocess once, give an initial guess, prefer GICP/VGICP, and report ATE with its alignment method.
