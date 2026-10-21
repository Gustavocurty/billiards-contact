@testset "raio contra círculo" begin
    valid, s, point = ray_circle_hit(Vec2(0.0, 0.0), Vec2(1.0, 0.0), Vec2(10.0, 0.0), 2.0)
    @test valid
    @test s ≈ 8.0
    @test point ≈ Vec2(8.0, 0.0)

    missed, _, _ = ray_circle_hit(Vec2(0.0, 0.0), Vec2(1.0, 0.0), Vec2(10.0, 5.0), 2.0)
    @test !missed

    behind, _, _ = ray_circle_hit(Vec2(0.0, 0.0), Vec2(1.0, 0.0), Vec2(-10.0, 0.0), 2.0)
    @test !behind
end

@testset "mesa parada" begin
    balls = rack_balls(6)
    @test all(b -> b.velocity == Vec2(0.0, 0.0), balls)
    state = SimulationState(balls; live_shot = true, aim_angle = 0.0)
    initialize!(state)
    @test state.contact !== nothing
    @test state.contact.point[1] > balls[1].position[1]
    @test state.contact.point[2] ≈ 500.0 atol = 1e-6
    @test state.contact.point ≈ Vec2(524.0, 500.0) atol = 1e-6

    state.aim_angle = π / 2
    contact = locate_contact(state)
    @test contact === nothing || contact.point[2] > balls[1].position[2]
end

@testset "atrito, tacada e colisão" begin
    slowing = [Ball(Vec2(100.0, 100.0), Vec2(100.0, 0.0), 18.0)]
    advance_balls!(slowing, 0.1, 1000.0, 1000.0; friction = 140.0)
    @test slowing[1].velocity[1] ≈ 86.0 atol = 1e-8
    @test slowing[1].velocity[2] ≈ 0.0 atol = 1e-8

    stopped = [Ball(Vec2(100.0, 100.0), Vec2(5.0, 0.0), 18.0)]
    advance_balls!(stopped, 0.1, 1000.0, 1000.0; friction = 140.0)
    @test stopped[1].velocity == Vec2(0.0, 0.0)

    pair = [
        Ball(Vec2(100.0, 500.0), Vec2(300.0, 0.0), 18.0),
        Ball(Vec2(160.0, 500.0), Vec2(0.0, 0.0), 18.0),
    ]
    advance_balls!(pair, 0.1, 1000.0, 1000.0; collide = true)
    @test pair[1].velocity[1] ≈ 0.0 atol = 1e-6
    @test pair[2].velocity[1] ≈ 300.0 atol = 1e-6
    @test distance(pair[1].position, pair[2].position) > 36.0

    momentum_before = Vec2(40.0, -10.0)
    energy_balls = [
        Ball(Vec2(100.0, 200.0), Vec2(40.0, -10.0), 18.0),
        Ball(Vec2(140.0, 200.0), Vec2(0.0, 0.0), 18.0),
    ]
    function momentum_of(group)
        total = Vec2(0.0, 0.0)
        for ball in group
            total += ball.velocity
        end
        return total
    end
    function kinetic_of(group)
        total = 0.0
        for ball in group
            total += ball.velocity[1]^2 + ball.velocity[2]^2
        end
        return 0.5 * total
    end
    p0 = momentum_of(energy_balls)
    e0 = kinetic_of(energy_balls)
    advance_balls!(energy_balls, 0.2, 1000.0, 1000.0; friction = 0.0, collide = true)
    @test momentum_of(energy_balls) ≈ p0 atol = 1e-6
    @test kinetic_of(energy_balls) ≈ e0 atol = 1e-6
    @test p0 ≈ momentum_before atol = 1e-9

    state = SimulationState(rack_balls(2); live_shot = true, aim_angle = π / 2)
    @test strike!(state, 200.0)
    @test state.balls[1].velocity ≈ Vec2(0.0, 200.0) atol = 1e-8
    @test !strike!(state, 50.0)

    config = SimulationConfig(dt = 1 / 60, recalculation_interval = 1)
    speed_before = hypot(state.balls[1].velocity[1], state.balls[1].velocity[2])
    for _ in 1:30
        step!(state, config)
    end
    speed_after = hypot(state.balls[1].velocity[1], state.balls[1].velocity[2])
    @test speed_after < speed_before
    @test speed_after > 0.0

    bounced = [Ball(Vec2(990.0, 10.0), Vec2(100.0, -100.0), 0.0)]
    advance_balls!(bounced, 0.2, 1000.0, 1000.0)
    @test bounced[1].position ≈ Vec2(990.0, 10.0) atol = 1e-6
    @test bounced[1].velocity ≈ Vec2(-100.0, 100.0) atol = 1e-6
end
