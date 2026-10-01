@testset "Força bruta" begin
    cue = Ball(Vec2(0.0, 0.0), Vec2(1.0, 0.0), 0.0)
    only = Ball(Vec2(4.0, 2.0), Vec2(0.0, -1.0), 0.0)
    single = find_contact_bruteforce([cue, only], 1)
    @test single !== nothing
    @test single.ball_index == 2
    @test single.point ≈ Vec2(4.0, 0.0) atol = 1e-12
    @test single.distance ≈ 4.0 atol = 1e-12

    far = Ball(Vec2(10.0, 5.0), Vec2(0.0, -1.0), 0.0)
    near = Ball(Vec2(3.0, 4.0), Vec2(0.0, -1.0), 0.0)
    behind = Ball(Vec2(-4.0, 2.0), Vec2(0.0, -1.0), 0.0)
    parallel = Ball(Vec2(1.0, 1.0), Vec2(2.0, 0.0), 0.0)
    several = find_contact_bruteforce([cue, far, near, behind, parallel], 1)
    @test several !== nothing
    @test several.ball_index == 3
    @test several.point ≈ Vec2(3.0, 0.0) atol = 1e-12
    @test several.distance ≈ 3.0 atol = 1e-12

    none = find_contact_bruteforce([cue, behind, parallel], 1)
    @test none === nothing

    stopped = Ball(Vec2(0.0, 0.0), Vec2(0.0, 0.0), 0.0)
    @test find_contact_bruteforce([stopped, only], 1) === nothing
end
