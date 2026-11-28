// Math basics: Vector2/3/4 and Quaternion are plain float32 structs with operators,
// Matrix4 is row-major (_11 .. _44; a translation sits in _14, _24, _34).
// make_vector3(x, y, z) no longer matches any overload (removed 0.2.002; only
// make_vector3(s), (array) and (Vector2, z) remain): use literals, Vector3.{1, 2, 3}.
// Compare floats with Sloppy_Math.values_are_close, not ==.
// EXPECT: a+b {5, 7, 9}, a*2 {2, 4, 6}, dot 32, cross {-3, 6, -3}
// EXPECT: length 5, unit {0.6, 0.8, 0}, lerp {2.5, 3.5, 4.5}
// EXPECT: overlays: a.xy {1, 2}, a.component[2] 3
// EXPECT: quaternion turns x into y: true
// EXPECT: translation in _14 _24 _34: 10 20 30
// EXPECT: T * S * p = {12, 22, 32, 1}
// EXPECT: inverse ok: true, undoes T: true
// EXPECT: Quaternion.{} is the identity: w = 1
// EXPECT: [0.500] with zero_removal = .NO

#import "Basic";
#import "Math";
#import "Sloppy_Math";

main :: () {
    a := Vector3.{1, 2, 3};
    b := Vector3.{4, 5, 6};
    print("a+b %, a*2 %, dot %, cross %\n", a + b, a * 2, dot(a, b), cross(a, b));
    print("length %, unit %, lerp %\n", length(Vector3.{3, 4, 0}), unit_vector(Vector3.{3, 4, 0}), lerp(a, b, 0.5));
    print("overlays: a.xy %, a.component[2] %\n", a.xy, a.component[2]);   // #overlay members share storage

    q: Quaternion;
    set_from_axis_and_angle(*q, .{0, 0, 1}, PI / 2);                     // 90 degrees about z
    turned := rotate(Vector3.{1, 0, 0}, q);
    print("quaternion turns x into y: %\n", values_are_close(turned, Vector3.{0, 1, 0}));

    t := make_translation_matrix4(.{10, 20, 30});
    s := make_scale_matrix4(.{2, 2, 2});
    p := Vector4.{1, 1, 1, 1};
    print("translation in _14 _24 _34: % % %\n", t._14, t._24, t._34);
    print("T * S * p = %\n", t * s * p);
    ok, t_inverse := inverse(t);                                          // success first
    back := t_inverse * t * p;
    print("inverse ok: %, undoes T: %\n", ok, values_are_close(back.xyz, p.xyz));
    print("Quaternion.{} is the identity: w = %\n", Quaternion.{}.w);
    print("[%] with zero_removal = .NO\n", FormatFloat.{value = 0.5, trailing_width = 3, zero_removal = .NO});
}
