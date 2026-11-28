// AoS vs SoA vs hot/cold split: count the bytes a hot loop drags through the caches.
// Memory moves in whole cache lines (64 bytes on the Intel machines, 128 on Apple M-series), so a
// loop that reads 8 bytes of a 64-byte struct still pays for all 64 when it walks an array of them.
// - AoS (array of structs): [] Particle. Simple, and best when a loop uses most fields.
// - SoA (struct of arrays): one array per field. A loop pays only for the fields it reads and the
//   compiler can vectorize it. Jai has no built-in SoA (modules/Soa.jai is an experimental
//   metaprogram, see jai-metaprogramming); writing it by hand, as below, is short.
// - Hot/cold split: the fields the hot loops use in one array of small structs, the rest in a
//   parallel array: most of SoA's benefit with fewer arrays to manage.
// The counts below come from size_of and the member offsets, assuming line-aligned arrays; the
// update step runs on all three layouts and must give identical numbers (the values are exact
// binary fractions, so there is no rounding to differ). Timings: _bench/b_aos_soa.jai.
// EXPECT: Particle: 64 bytes; the update reads x@0 and vx@12 (8 bytes) and writes x
// EXPECT: AoS:      4096 particles = 262144 bytes = 4096 lines of 64 B (2048 of 128 B); 8 of 64 bytes per element useful (12.5 percent)
// EXPECT: SoA:      x[] and vx[] = 32768 bytes = 512 lines of 64 B (256 of 128 B); 8 of 8 bytes useful
// EXPECT: hot/cold: Hot is 24 bytes: 98304 bytes = 1536 lines of 64 B (768 of 128 B); 8 of 24 bytes useful (33.3 percent)
// EXPECT: one element's x and vx share a line in AoS: true (64 B lines), true (128 B lines)
// EXPECT: after 10 steps all three layouts agree: true (sum of x = 2095096.5)
#import "Basic";

Particle :: struct {            // 64 bytes, a typical "entity" record
    x, y, z:    float32;        // hot: position
    vx, vy, vz: float32;        // hot: velocity
    mass:       float32;
    age:        float32;
    color:      u32;
    id:         u32;
    seed:       u64;
    name:       string;         // cold: only the editor reads it
}

// Struct of arrays, by hand: one view per field, all with the same count.
Particles_SoA :: struct {
    count: int;
    x, y, z, vx, vy, vz, mass, age: [] float32;
    color, id: [] u32;
    seed: [] u64;
    name: [] string;
}

make_soa :: (count: int) -> Particles_SoA {
    s: Particles_SoA;
    s.count = count;
    floats := (*[] float32).[*s.x, *s.y, *s.z, *s.vx, *s.vy, *s.vz, *s.mass, *s.age];   // typed literal
    for floats it.* = NewArray(count, float32, alignment = 64);   // 64 B aligned starts
    s.color = NewArray(count, u32);
    s.id    = NewArray(count, u32);
    s.seed  = NewArray(count, u64);
    s.name  = NewArray(count, string);
    return s;
}

// Hot/cold split: what the update loop needs, and everything else.
Hot  :: struct { x, y, z, vx, vy, vz: float32; }
Cold :: struct { mass, age: float32; color, id: u32; seed: u64; name: string; }

N  :: 4096;
DT :: 0.25;                     // a power of two: x stays an exact binary fraction

lines :: (bytes: int, line: int) -> int { return (bytes + line - 1) / line; }

offset_of :: ($T: Type, name: string) -> int {
    for type_info(T).members if it.name == name return it.offset_in_bytes;
    return -1;
}

main :: () {
    ox, ovx := offset_of(Particle, "x"), offset_of(Particle, "vx");
    used := size_of(float32) * 2;
    print("Particle: % bytes; the update reads x@% and vx@% (% bytes) and writes x\n", size_of(Particle), ox, ovx, used);

    aos_bytes := N * size_of(Particle);
    print("AoS:      % particles = % bytes = % lines of 64 B (% of 128 B); % of % bytes per element useful (% percent)\n",
        N, aos_bytes, lines(aos_bytes, 64), lines(aos_bytes, 128), used, size_of(Particle), formatFloat(used * 100.0 / size_of(Particle), trailing_width = 1));
    soa_bytes := N * used;
    print("SoA:      x[] and vx[] = % bytes = % lines of 64 B (% of 128 B); % of % bytes useful\n",
        soa_bytes, lines(soa_bytes, 64), lines(soa_bytes, 128), used, used);
    hot_bytes := N * size_of(Hot);
    print("hot/cold: Hot is % bytes: % bytes = % lines of 64 B (% of 128 B); % of % bytes useful (% percent)\n",
        size_of(Hot), hot_bytes, lines(hot_bytes, 64), lines(hot_bytes, 128), used, size_of(Hot), formatFloat(used * 100.0 / size_of(Hot), trailing_width = 1));
    print("one element's x and vx share a line in AoS: % (64 B lines), % (128 B lines)\n",
        ox / 64 == (ovx + 3) / 64, ox / 128 == (ovx + 3) / 128);

    // The same data in three layouts.
    aos := NewArray(N, Particle);
    soa := make_soa(N);
    hot := NewArray(N, Hot);
    cold := NewArray(N, Cold);
    for i: 0..N-1 {
        x  := cast(float32) (i % 1024);
        vx := cast(float32) (i % 7) - 3;
        aos[i].x, aos[i].vx = x, vx;
        soa.x[i], soa.vx[i] = x, vx;
        hot[i].x, hot[i].vx = x, vx;
        aos[i].id, soa.id[i], cold[i].id = xx i, xx i, xx i;
    }

    for step: 1..10 {
        for * aos       it.x += it.vx * DT;     // touches every 64-byte element
        for i: 0..N-1   soa.x[i] += soa.vx[i] * DT;
        for * hot       it.x += it.vx * DT;     // touches 24 bytes per element
    }

    agree := true;
    sum: float64;
    for i: 0..N-1 {
        if aos[i].x != soa.x[i] || aos[i].x != hot[i].x agree = false;
        sum += aos[i].x;
    }
    print("after 10 steps all three layouts agree: % (sum of x = %)\n", agree, sum);
}
