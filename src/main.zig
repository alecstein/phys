const std = @import("std");
const math = std.math;

const g = 9.81;
const m_particle = 0.001;
const m_piston = 1.0;

var piston_x: f64 = 1;
var piston_v: f64 = 0;

// get time to hit ground
fn tGround(x: f64, v: f64) f64 {
    if (v >= 0) return math.inf(f64);
    return -x / v;
}

// get time to collide with piston
fn tPiston(x: f64, v: f64) f64 {
    const a = 0.5 * g;
    const b = v - piston_v;
    const c = x - piston_x;
    const disc = b * b - 4 * a * c;
    return (-b + math.sqrt(disc)) / (2 * a);
}

// compute velocities after elastic collision
fn elasticCol(m1: f64, v1: f64, m2: f64, v2: f64) struct { v1_prime: f64, v2_prime: f64 } {
    const v1_prime = (m1 - m2) * v1 / (m1 + m2) + 2 * m2 * v2 / (m1 + m2);
    const v2_prime = 2 * m1 * v1 / (m1 + m2) - (m1 - m2) * v2 / (m1 + m2);
    return .{ .v1_prime = v1_prime, .v2_prime = v2_prime };
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);

    var timer = try std.time.Timer.start();
    const t0 = timer.read();

    if (args.len < 3) return error.ExpectedArgument;
    const n = try std.fmt.parseInt(u32, args[1], 0);
    const max_time = try std.fmt.parseFloat(f64, args[2]);

    var particle_x = try allocator.alloc(f64, n);
    var particle_v = try allocator.alloc(f64, n);
    var time_to_ground = try allocator.alloc(f64, n);
    var time_to_piston = try allocator.alloc(f64, n);
    defer allocator.free(particle_x);
    defer allocator.free(particle_v);
    defer allocator.free(time_to_ground);
    defer allocator.free(time_to_piston);

    const vAvg: f64 = 0.5 * math.sqrt(2 * m_piston * g * piston_x / m_particle / @as(f64, @floatFromInt(n)));

    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.os.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rand = prng.random();

    for (0..n) |i| {
        particle_x[i] = piston_x * rand.float(f32);
        particle_v[i] = vAvg;
        time_to_ground[i] = tGround(particle_x[i], particle_v[i]);
        time_to_piston[i] = tPiston(particle_x[i], particle_v[i]);
    }

    // progress indicator
    var pct_done: u8 = 0;
    var progress = std.Progress{};
    const root_node = progress.start("Simulating", 100);
    defer root_node.end();

    var t: f64 = 0;
    var ct: usize = 0; // collision count

    std.debug.print("Particles: {d}\tWorldtime: {d}s\n", .{ n, max_time });

    while (t < max_time) {
        ct += 1;

        // update progress indicator
        const new_pct_done = @as(u8, @intFromFloat((t * 100) / max_time));
        if (new_pct_done > pct_done) {
            pct_done = new_pct_done;
            root_node.completeOne();
            progress.refresh();
        }

        // get the next interaction
        // this is always O(N) time, so there's no prettier way to do it
        var dt = math.inf(f64);
        var j: usize = undefined;
        var is_ground_col: bool = true;

        for (0..n) |i| {
            const trial_t_ground = time_to_ground[i];
            const trial_t_piston = time_to_piston[i];
            const trial_t = @min(trial_t_ground, trial_t_piston);
            if (trial_t < dt) {
                dt = trial_t;
                j = i;
                is_ground_col = trial_t_ground < trial_t_piston;
            }
        }

        // step forward in time
        for (0..n) |i| {
            particle_x[i] += particle_v[i] * dt;
            time_to_ground[i] -= dt;
        }
        piston_x += piston_v * dt - g * dt * dt / 2;
        piston_v -= g * dt;
        t += dt;

        if (is_ground_col) {
            // handle ground collision
            particle_v[j] = -particle_v[j];
            time_to_ground[j] = math.inf(f64);
            for (0..n) |i| {
                time_to_piston[i] -= dt;
            }
            time_to_piston[j] = tPiston(particle_x[j], particle_v[j]);
        } else {
            // handle piston collision
            const new_vs = elasticCol(m_particle, particle_v[j], m_piston, piston_v);
            particle_v[j] = new_vs.v1_prime;
            piston_v = new_vs.v2_prime;
            time_to_ground[j] = tGround(particle_x[j], particle_v[j]);
            for (0..n) |i| {
                time_to_piston[i] = tPiston(particle_x[i], particle_v[i]);
            }
        }
    }

    const t1 = timer.read();
    const dt = @as(f64, @floatFromInt(t1 - t0));

    std.debug.print("\nCollisions: {}\n", .{ct});
    std.debug.print("Time taken: {d:.2}s\n", .{dt / 1000000000.0});
}
