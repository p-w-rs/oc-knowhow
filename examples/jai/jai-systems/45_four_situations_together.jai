// The four situations in one program: a tiny game loop (2 levels, 3 frames each). Each piece of
// data is classified first (how long does it live? how much of it is there?) and then gets the
// allocator that matches:
//   data                      lives for         size              allocator
//   entity slots              the whole game    16, a constant    one NewArray at startup      (1)
//   tile grid                 one level         width x height    one exact block, level arena (1)
//   spawn points, level name  one level         known after load  level arena: a Flat_Pool     (2)
//   damage per entity         one frame         16, a constant    [16] s32 on the stack        (1)
//   in-range list, HUD text   one frame         varies            temp, reset every frame      (2)
//   entities                  until killed      one Entity        slots + free list + handles  (3)
//   chat messages             until pushed out  any length        default heap, freed singly   (4)
// The "in range" lists run in slot order, so they show the free list at work: in frame 2 of the
// caves, bat5 comes before slime4 because it took the slot bat3 left behind in frame 1.
// Why the slots live for the whole game: the generation counters live in the slots. A handle
// kept past its level (here: to a bat in the caves) is still rejected later because its slot
// kept counting. Slots re-created per level restart at generation 0, and the same old handle
// then matches a new entity (shown at the end).
// The level name lives in the arena: anything that needs it after reset() must copy it first
// (the unload line is built in temp before the reset). reset(*arena, overwrite_memory = true)
// stamps 0xcc over the old level so such a mistake shows up as garbage at once.
// Every allocator is wrapped in a counter, and the end checks that nothing is left behind.
// EXPECT: level caves (12x6): tiles 72 bytes in 1 block, 3 spawn points, level arena 176 bytes
// EXPECT:   frame 1: in range bat3 slime4, killed bat3, focus slime4
// EXPECT:   frame 2: in range bat5 slime4 bat6 slime7, killed slime4, focus died -> bat5
// EXPECT:   frame 3: in range bat5 bat6 slime7, killed bat5 bat6 slime7, focus died -> none
// EXPECT: unload caves: 1 entity still alive, arena 176 -> 0 bytes, temp peak in a frame 168 bytes
// EXPECT: level tower (6x16): tiles 96 bytes in 1 block, 2 spawn points, level arena 200 bytes
// EXPECT:   frame 1: in range slime9 slime10, killed none, focus slime9
// EXPECT:   frame 2: in range slime9 slime12 slime11 slime10, killed slime10, focus slime9
// EXPECT:   frame 3: in range slime9 slime12 slime11, killed slime12, focus slime9
// EXPECT: unload tower: 2 entities still alive, arena 200 -> 0 bytes, temp peak in a frame 160 bytes
// EXPECT: handle to bat2 from the caves, kept until now: rejected (its slot is at generation 4)
// EXPECT: the same handle against slots re-created for a new level: accepted, wrongly: true
// EXPECT: chat: 4 messages received, the last 3 kept, 1 freed when pushed out
// EXPECT: end: chat heap blocks 3 -> 0, entity slots 1 block -> 0, arena released, temp 0 bytes
#import "Basic";
#import "String";
#import "Math";
#import "Flat_Pool";

// ---- counting wrapper: live blocks per allocator
Tracked :: struct {
    live:    int;
    backing: Allocator;
}

tracked_proc :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, data: *void) -> *void {
    t := cast(*Tracked) data;
    if mode == .ALLOCATE || (mode == .RESIZE && !old_memory)  t.live += 1;
    if mode == .FREE && old_memory  t.live -= 1;
    return t.backing.proc(mode, size, old_size, old_memory, t.backing.data);
}

tracked :: (t: *Tracked) -> Allocator { return .{tracked_proc, t}; }

// ---- entities: fixed-size slots, free list, generational handles (situation 3, see example 43)
MAX_ENTITIES :: 16;
RANGE        :: 4;

Kind :: enum u8 { PLAYER; BAT; SLIME; }
KIND_NAMES   :: string.["player", "bat", "slime"];
KIND_HP      :: s32.[100, 6, 14];

Handle :: struct { index, generation: u32; }

Entity :: struct {
    kind: Kind;
    id:   s32;                  // serial number, for names
    hp:   s32;
    x, y: s32;
}

Slot :: struct {
    using entity: Entity;
    generation: u32;            // odd = alive
    next_free:  s32;
}

World :: struct {
    slots:     [] Slot;         // exact size, allocated once: never moves, never grows
    free_head: s32 = -1;
    used:      s32;
    alive:     int;
    next_id:   s32 = 1;
}

spawn :: (w: *World, e: Entity) -> Handle {
    index: s32;
    if w.free_head >= 0 { index = w.free_head; w.free_head = w.slots[index].next_free; }
    else { assert(w.used < w.slots.count, "more than % entities", w.slots.count); index = w.used; w.used += 1; }
    slot := *w.slots[index];
    slot.entity = e;
    slot.id = w.next_id;
    w.next_id += 1;
    slot.generation += 1;
    w.alive += 1;
    return .{cast(u32) index, slot.generation};
}

get :: (w: *World, h: Handle) -> *Entity {
    if h.index >= cast(u32) w.used || !(h.generation & 1)  return null;
    slot := *w.slots[h.index];
    if slot.generation != h.generation  return null;
    return *slot.entity;
}

kill :: (w: *World, index: s32) {
    slot := *w.slots[index];
    slot.generation += 1;
    slot.next_free = w.free_head;
    w.free_head = index;
    w.alive -= 1;
}

alive :: (w: *World, index: s32) -> bool { return (w.slots[index].generation & 1) == 1; }
handle_of :: (w: *World, index: s32) -> Handle { return .{cast(u32) index, w.slots[index].generation}; }
name_of :: (e: Entity) -> string { return tprint("%1%2", KIND_NAMES[e.kind], e.id); }   // temp

// ---- levels: loaded into the level arena (situations 1 and 2)
LEVEL_CAVES :: #string END
caves 12 6
bat 3 1
bat 4 4
slime 6 2
END

LEVEL_TOWER :: #string END
tower 6 16
slime 2 5
slime 3 9
END

Spawn :: struct { kind: Kind; x, y: s32; }

Level :: struct {
    name:          string;
    width, height: int;
    tiles:         [] u8;           // (1) size known from the header: one exact allocation
    spawns:        [..] Spawn;      // (2) count known only after parsing
}

next_line :: (rest: *string) -> string { _, line, after := split_from_left(rest.*, #char "\n"); rest.* = after; return line; }
next_word :: (rest: *string) -> string { _, word, after := split_from_left(rest.*, #char " ");  rest.* = after; return word; }

load_level :: (text: string) -> Level {    // allocates from context.allocator and never frees
    level: Level;
    rest := text;
    header := next_line(*rest);
    level.name   = copy_string(next_word(*header));
    level.width  = to_integer(next_word(*header));
    level.height = to_integer(next_word(*header));
    level.tiles  = NewArray(level.width * level.height, u8);
    while rest {
        line := next_line(*rest);
        if !line  continue;
        s: Spawn;
        s.kind = ifx next_word(*line) == "bat" then Kind.BAT else .SLIME;
        s.x = cast(s32) to_integer(next_word(*line));
        s.y = cast(s32) to_integer(next_word(*line));
        array_add(*level.spawns, s);
        level.tiles[s.y * level.width + s.x] = #char "S";
    }
    return level;
}

main :: () {
    game_heap := Tracked.{backing = context.allocator};
    chat_heap := Tracked.{backing = context.allocator};

    world: World;
    world.slots = NewArray(MAX_ENTITIES, Slot,, tracked(*game_heap));   // (1) the whole game
    slot_blocks := game_heap.live;

    arena: Flat_Pool;                                                     // (2) one level at a time
    chat: [3] string;                                                     // (4) the text lives on the heap
    received, pushed_out := 0, 0;
    CHAT_SCRIPT :: string.["gl hf", "bats!", "", "tower time", "", "brb"];   // one entry per frame

    kept: Handle;                       // a handle that outlives its level, on purpose
    kept_name: string;
    frame_number := 0;

    for level_text: string.[LEVEL_CAVES, LEVEL_TOWER] {
        level: Level;
        {
            push_allocator(flat_pool_allocator_proc, *arena);
            level = load_level(level_text);
        }
        arena_bytes := arena.current_point - arena.memory_base;
        print("level % (%x%): tiles % bytes in 1 block, % spawn points, level arena % bytes\n",
            level.name, level.width, level.height, level.tiles.count, level.spawns.count, arena_bytes);

        player := spawn(*world, .{kind = .PLAYER, hp = KIND_HP[Kind.PLAYER], x = cast(s32) level.width / 2, y = cast(s32) level.height / 2});
        for level.spawns  spawn(*world, .{kind = it.kind, hp = KIND_HP[it.kind], x = it.x, y = it.y});
        if !kept.generation { kept = handle_of(*world, 1); kept_name = copy_string(name_of(world.slots[1].entity),, tracked(*chat_heap)); }

        focus: Handle;                  // (3) whom the camera follows: may die at any moment
        temp_peak := 0;
        for frame: 1..3 {
            if frame == 2  for level.spawns  spawn(*world, .{kind = it.kind, hp = KIND_HP[it.kind], x = it.x, y = it.y + 1});

            damage: [MAX_ENTITIES] s32;                 // (1) frame lifetime, size known: stack
            in_range: [..] s32;                         // (2) frame lifetime, size unknown: temp
            in_range.allocator = temp;

            p := get(*world, player);
            for i: 0..world.used-1 {
                if !alive(*world, i) || world.slots[i].kind == .PLAYER  continue;
                d := abs(world.slots[i].x - p.x) + abs(world.slots[i].y - p.y);
                if d > RANGE  continue;
                damage[i] = cast(s32) (RANGE + 2 - d) * 2;   // closer = harder
                array_add(*in_range, i);
            }

            hud := String_Builder.{allocator = temp};
            print_to_builder(*hud, "  frame %: in range", frame);
            for in_range  print_to_builder(*hud, " %", name_of(world.slots[it].entity));
            print_to_builder(*hud, ", killed");
            killed := 0;
            for in_range {
                world.slots[it].hp -= damage[it];
                if world.slots[it].hp > 0  continue;
                print_to_builder(*hud, " %", name_of(world.slots[it].entity));
                kill(*world, it);
                killed += 1;
            }
            if !killed  print_to_builder(*hud, " none");

            if !get(*world, focus) {                    // never set, or the target died
                died := focus.generation != 0;
                focus = .{};
                for in_range  if alive(*world, it) { focus = handle_of(*world, it); break; }
                if died  print_to_builder(*hud, ", focus died ->");  else print_to_builder(*hud, ", focus");
                if get(*world, focus)  print_to_builder(*hud, " %", name_of(get(*world, focus)));
                else                   print_to_builder(*hud, " none");
            } else {
                print_to_builder(*hud, ", focus %", name_of(get(*world, focus)));
            }
            print("%\n", builder_to_string(*hud,, temp));

            message := CHAT_SCRIPT[frame_number];
            frame_number += 1;
            if message {
                received += 1;
                if chat[0] { free(chat[0],, tracked(*chat_heap)); pushed_out += 1; }
                chat[0], chat[1] = chat[1], chat[2];
                chat[2] = sprint("[%] %", frame_number, message,, tracked(*chat_heap));
            }

            temp_peak = max(temp_peak, context.temporary_storage.high_water_mark);
            reset_temporary_storage();                  // every temp allocation of this frame is gone
        }

        // Unload: kill what is left, then drop everything the level allocated in one call.
        left := world.alive - 1;
        for i: 0..world.used-1  if alive(*world, i)  kill(*world, i);
        line := tprint("unload %: % % still alive", level.name, left, ifx left == 1 then "entity" else "entities");
        reset(*arena, overwrite_memory = true);         // level.name and level.tiles are garbage now
        print("%, arena % -> % bytes, temp peak in a frame % bytes\n", line, arena_bytes, arena.current_point - arena.memory_base, temp_peak);
        reset_temporary_storage();
    }

    print("handle to % from the caves, kept until now: % (its slot is at generation %)\n",
        kept_name, ifx get(*world, kept) then "accepted" else "rejected", world.slots[kept.index].generation);
    free(kept_name,, tracked(*chat_heap));

    fresh: World;                       // the mistake: slots that are re-created for every level
    fresh.slots = NewArray(MAX_ENTITIES, Slot,, temp);
    for 1..4  spawn(*fresh, .{});
    print("the same handle against slots re-created for a new level: accepted, wrongly: %\n", get(*fresh, kept) != null);
    reset_temporary_storage();

    print("chat: % messages received, the last % kept, % freed when pushed out\n", received, received - pushed_out, pushed_out);

    chat_before := chat_heap.live;
    for chat  if it  free(it,, tracked(*chat_heap));
    free(world.slots.data,, tracked(*game_heap));
    fini(*arena);
    print("end: chat heap blocks % -> %, entity slots % block -> %, arena released, temp % bytes\n",
        chat_before, chat_heap.live, slot_blocks, game_heap.live, context.temporary_storage.total_bytes_occupied);
}
