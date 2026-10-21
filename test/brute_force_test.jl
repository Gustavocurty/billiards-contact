@testset "Força bruta com raio" begin
    cue = Ball(Vec2(0.0, 0.0), Vec2(0.0, 0.0), 18.0)
    direction = Vec2(1.0, 0.0)
    only = Ball(Vec2(100.0, 0.0), Vec2(0.0, 0.0), 18.0)
    single = find_contact_bruteforce([cue, only], 1, direction)
    @test single !== nothing
    @test single.ball_index == 2
    @test single.distance ≈ 64.0 atol = 1e-9
    @test single.point ≈ Vec2(64.0, 0.0) atol = 1e-9
    @test distance(single.point, only.position) ≈ 36.0 atol = 1e-9

    far = Ball(Vec2(220.0, 0.0), Vec2(0.0, 0.0), 18.0)
    side = Ball(Vec2(100.0, 80.0), Vec2(0.0, 0.0), 18.0)
    behind = Ball(Vec2(-80.0, 0.0), Vec2(0.0, 0.0), 18.0)
    several = find_contact_bruteforce([cue, far, only, side, behind], 1, direction)
    @test several !== nothing
    @test several.ball_index == 3

    none = find_contact_bruteforce([cue, side, behind], 1, direction)
    @test none === nothing
end
