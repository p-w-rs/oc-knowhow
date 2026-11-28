// b. AoS vs SoA vs hot/cold split: the same particles in three layouts, four loops over them.
//   AoS       [] Particle, 64 bytes per element
//   SoA       one array per field (Particles_SoA below)
//   hot/cold  [] Hot (x, y, z, vx, vy, vz: 24 bytes) + [] Cold (the other 40 bytes)
// Loops (ns per element, median of the timed runs, min in parentheses):
//   x += vx*dt     2 of the 16 fields (8 bytes), written in place
//   sum of id      1 field (4 bytes), read only; in the hot/cold split, id is a COLD field
//   pos += vel*dt  6 fields (24 bytes): exactly the Hot struct
//   all 8 floats   reads 8 fields (32 bytes) of every element, writes one output array
// All values are exact binary fractions, so the three layouts must end with identical data.
//
// Extra row "SoA, 4 floats per step": LLVM does not vectorize loops that STORE through a Jai array
// view or pointer in 0.2.032 (element addresses go through integer casts and every access is
// marked align 1, so it cannot prove the stores do not overlap the loads). Copying four floats at
// a time as a 16-byte struct (F4 below) lets it use vector registers anyway (NEON fmul.4s/fadd.4s,
// SSE mulps/addps). The row measures what that is worth.
#load "harness.jai";

Particle :: struct {
    x, y, z:    float32;
    vx, vy, vz: float32;
    mass:       float32;
    age:        float32;
    color:      u32;
    id:         u32;
    seed:       u64;
    name:       string;
}
#assert size_of(Particle) == 64;

Particles_SoA :: struct {
    x, y, z, vx, vy, vz, mass, age: [] float32;
    color, id: [] u32;
    seed: [] u64;
    name: [] string;
}

Hot  :: struct { x, y, z, vx, vy, vz: float32; }
Cold :: struct { mass, age: float32; color, id: u32; seed: u64; name: string; }
#assert size_of(Hot) == 24 && size_of(Cold) == 40;

DT :: cast(float32) 0.25;

ELEMENTS    :: s64.[512, 16384, 131072, 524288, 2097152];
SIZE_LABELS :: string.["32 KiB", "1 MiB", "8 MiB", "32 MiB", "128 MiB"];
TARGET      :: 4_000_000;      // elements per timed run

// ---------------------------------------------------------------- kernels

aos_x :: (p: [] Particle, passes: s64) {
    for 1..passes for * p it.x += it.vx * DT;
}
soa_x :: (x: [] float32, vx: [] float32, passes: s64) {
    for 1..passes for i: 0..x.count-1 x[i] += vx[i] * DT;
}

F4 :: struct { a, b, c, d: float32; }

// Same work as soa_x, four elements per step through a 16-byte struct copy (count % 4 == 0 here).
soa_x_4wide :: (x: [] float32, vx: [] float32, passes: s64) {
    xs  := cast(*F4) x.data;
    vxs := cast(*F4) vx.data;
    for 1..passes for i: 0..x.count/4-1 {
        p := xs[i];
        v := vxs[i];
        p.a += v.a * DT; p.b += v.b * DT; p.c += v.c * DT; p.d += v.d * DT;
        xs[i] = p;
    }
}
hot_x :: (h: [] Hot, passes: s64) {
    for 1..passes for * h it.x += it.vx * DT;
}

aos_id :: (p: [] Particle, passes: s64, salt: s64) -> s64 {
    sum: s64;
    for q: 1..passes { k := salt + q; for p sum += cast(s64) it.id ^ k; }
    return sum;
}
soa_id :: (id: [] u32, passes: s64, salt: s64) -> s64 {
    sum: s64;
    for q: 1..passes { k := salt + q; for id sum += cast(s64) it ^ k; }
    return sum;
}
cold_id :: (c: [] Cold, passes: s64, salt: s64) -> s64 {
    sum: s64;
    for q: 1..passes { k := salt + q; for c sum += cast(s64) it.id ^ k; }
    return sum;
}

aos_pos :: (p: [] Particle, passes: s64) {
    for 1..passes for * p { it.x += it.vx * DT; it.y += it.vy * DT; it.z += it.vz * DT; }
}
soa_pos :: (s: *Particles_SoA, passes: s64) {
    x, y, z, vx, vy, vz := s.x, s.y, s.z, s.vx, s.vy, s.vz;
    for 1..passes for i: 0..x.count-1 { x[i] += vx[i] * DT; y[i] += vy[i] * DT; z[i] += vz[i] * DT; }
}
hot_pos :: (h: [] Hot, passes: s64) {
    for 1..passes for * h { it.x += it.vx * DT; it.y += it.vy * DT; it.z += it.vz * DT; }
}

aos_all :: (p: [] Particle, out: [] float32, passes: s64) {
    for q: 1..passes {
        k := cast(float32) q;
        for p out[it_index] = it.x + it.y + it.z + it.vx + it.vy + it.vz + it.mass + it.age + k;
    }
}
soa_all :: (s: *Particles_SoA, out: [] float32, passes: s64) {
    x, y, z, vx, vy, vz, mass, age := s.x, s.y, s.z, s.vx, s.vy, s.vz, s.mass, s.age;
    for q: 1..passes {
        k := cast(float32) q;
        for i: 0..x.count-1 out[i] = x[i] + y[i] + z[i] + vx[i] + vy[i] + vz[i] + mass[i] + age[i] + k;
    }
}
hot_cold_all :: (h: [] Hot, c: [] Cold, out: [] float32, passes: s64) {
    for q: 1..passes {
        k := cast(float32) q;
        for h out[it_index] = it.x + it.y + it.z + it.vx + it.vy + it.vz + c[it_index].mass + c[it_index].age + k;
    }
}

// ---------------------------------------------------------------- setup

make_soa :: (n: s64) -> Particles_SoA {
    s: Particles_SoA;
    floats := (*[] float32).[*s.x, *s.y, *s.z, *s.vx, *s.vy, *s.vz, *s.mass, *s.age];
    for floats it.* = NewArray(n, float32, initialize = false);
    s.color = NewArray(n, u32, initialize = false);
    s.id    = NewArray(n, u32, initialize = false);
    s.seed  = NewArray(n, u64, initialize = false);
    s.name  = NewArray(n, string);
    return s;
}

free_soa :: (s: *Particles_SoA) {
    for array: (*[] float32).[*s.x, *s.y, *s.z, *s.vx, *s.vy, *s.vz, *s.mass, *s.age] array_free(array.*);
    array_free(s.color); array_free(s.id); array_free(s.seed); array_free(s.name);
}

fill :: (aos: [] Particle, soa: *Particles_SoA, hot: [] Hot, cold: [] Cold) {
    for i: 0..aos.count-1 {
        p: Particle;
        p.x, p.y, p.z    = xx (i % 1024), xx ((i * 3) % 1024), xx ((i * 5) % 1024);
        p.vx, p.vy, p.vz = xx ((i % 7) - 3), xx ((i % 5) - 2), xx ((i % 3) - 1);
        p.mass, p.age    = xx (1 + i % 16), xx (i % 100);
        p.color, p.id, p.seed = xx i, xx i, xx (i * i);
        aos[i] = p;
        soa.x[i], soa.y[i], soa.z[i], soa.vx[i], soa.vy[i], soa.vz[i] = p.x, p.y, p.z, p.vx, p.vy, p.vz;
        soa.mass[i], soa.age[i], soa.color[i], soa.id[i], soa.seed[i] = p.mass, p.age, p.color, p.id, p.seed;
        hot[i] = .{p.x, p.y, p.z, p.vx, p.vy, p.vz};
        cold[i] = .{mass = p.mass, age = p.age, color = p.color, id = p.id, seed = p.seed};
    }
}

same_data :: (aos: [] Particle, soa: *Particles_SoA, hot: [] Hot) -> bool {
    for i: 0..aos.count-1 {
        a := aos[i];
        if a.x != soa.x[i] || a.y != soa.y[i] || a.z != soa.z[i] return false;
        if a.x != hot[i].x || a.y != hot[i].y || a.z != hot[i].z return false;
    }
    return true;
}

// ---------------------------------------------------------------- main

KERNELS :: string.["x += vx*dt (8 of 64 bytes)", "sum of id (4 bytes, cold)", "pos += vel*dt (24 bytes)", "all 8 floats -> out[] (32 bytes)"];
LAYOUTS :: string.["AoS", "SoA", "hot/cold", "SoA, 4 floats per step"];   // the last one only for the first loop

main :: () {
    parse_common_args();
    size_count := ifx quick then 3 else ELEMENTS.count;
    results: [KERNELS.count][LAYOUTS.count][ELEMENTS.count] Timing;
    checksum: s64;
    all_same := true;

    for s: 0..size_count-1 {
        n := ELEMENTS[s];
        passes := max(1, TARGET / n);
        aos := NewArray(n, Particle, initialize = false);
        soa := make_soa(n);
        hot := NewArray(n, Hot, initialize = false);
        cold := NewArray(n, Cold);
        out_a := NewArray(n, float32);
        out_s := NewArray(n, float32);
        out_h := NewArray(n, float32);
        x4 := NewArray(n, float32);     // a copy of x for the 4-wide variant
        fill(aos, *soa, hot, cold);
        for i: 0..n-1 x4[i] = soa.x[i];
        salt: s64;

        results[0][0][s] = measure(#code { aos_x(aos, passes); });
        results[0][1][s] = measure(#code { soa_x(soa.x, soa.vx, passes); });
        results[0][2][s] = measure(#code { hot_x(hot, passes); });
        results[0][3][s] = measure(#code { soa_x_4wide(x4, soa.vx, passes); });
        for i: 0..n-1 if x4[i] != soa.x[i] all_same = false;   // both got the same updates so far

        results[1][0][s] = measure(#code { salt += 1; checksum += aos_id(aos, passes, salt); });
        results[1][1][s] = measure(#code { salt += 1; checksum += soa_id(soa.id, passes, salt); });
        results[1][2][s] = measure(#code { salt += 1; checksum += cold_id(cold, passes, salt); });

        results[2][0][s] = measure(#code { aos_pos(aos, passes); });
        results[2][1][s] = measure(#code { soa_pos(*soa, passes); });
        results[2][2][s] = measure(#code { hot_pos(hot, passes); });

        results[3][0][s] = measure(#code { aos_all(aos, out_a, passes); });
        results[3][1][s] = measure(#code { soa_all(*soa, out_s, passes); });
        results[3][2][s] = measure(#code { hot_cold_all(hot, cold, out_h, passes); });

        if !same_data(aos, *soa, hot) all_same = false;
        for i: 0..n-1 {
            if out_a[i] != out_s[i] || out_a[i] != out_h[i] all_same = false;
            checksum += cast(s64) aos[i].x + cast(s64) out_a[i];
        }
        for k: 0..KERNELS.count-1 for l: 0..LAYOUTS.count-1 results[k][l][s] = per_op(results[k][l][s], passes * n);

        array_free(aos); free_soa(*soa); array_free(hot); array_free(cold);
        array_free(out_a); array_free(out_s); array_free(out_h); array_free(x4);
    }

    print("### b. AoS vs SoA vs hot/cold: ns per element, median of % runs (min)\n\n", runs);
    print("Particle = 64 bytes (16 fields). Column = size of the AoS array (n particles * 64 bytes). Each timed run processes at least % elements.\n\n", TARGET);
    columns: [..] string;
    for 0..size_count-1 array_add(*columns, tprint("% (n = %)", SIZE_LABELS[it], ELEMENTS[it]));
    for k: 0..KERNELS.count-1 {
        print("**%**\n\n", KERNELS[k]);
        print_table_header("layout", columns);
        for l: 0..LAYOUTS.count-1 {
            if l == 3 && k != 0 continue;
            print("| % |", LAYOUTS[l]);
            for s: 0..size_count-1 print(" % |", cell(results[k][l][s]));
            print("\n");
        }
        print("\n");
    }
    print("All three layouts ended with identical data: %. Checksum %.\n\n", all_same, checksum);
}
