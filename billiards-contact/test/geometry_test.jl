@testset "Geometria" begin
    @test distance(Vec2(0.0, 0.0), Vec2(3.0, 4.0)) ≈ 5.0

    cue = Ball(Vec2(0.0, 0.0), Vec2(1.0, 0.0), 0.0)
    crossing = Ball(Vec2(2.0, 2.0), Vec2(0.0, -1.0), 0.0)
    valid, s, τ, point = intersect_trajectories(cue, crossing)
    @test valid
    @test s ≈ 2.0 atol = 1e-12
    @test τ ≈ 2.0 atol = 1e-12
    @test point ≈ Vec2(2.0, 0.0) atol = 1e-12

    parallel = Ball(Vec2(0.0, 1.0), Vec2(2.0, 0.0), 0.0)
    valid_parallel, _, _, _ = intersect_trajectories(cue, parallel)
    @test !valid_parallel

    ahead = Ball(Vec2(5.0, 3.0), Vec2(0.0, -1.0), 0.0)
    valid_ahead, s_ahead, _, point_ahead = intersect_trajectories(cue, ahead)
    @test valid_ahead
    @test s_ahead > 0
    @test point_ahead ≈ Vec2(5.0, 0.0) atol = 1e-12

    behind = Ball(Vec2(-2.0, 1.0), Vec2(0.0, -1.0), 0.0)
    valid_behind, s_behind, _, _ = intersect_trajectories(cue, behind)
    @test !valid_behind
    @test s_behind < 0

    origin = Ball(Vec2(0.0, 1.0), Vec2(0.0, -1.0), 0.0)
    valid_origin, s_origin, _, point_origin = intersect_trajectories(cue, origin)
    @test valid_origin
    @test s_origin ≈ 0.0 atol = 1e-12
    @test point_origin ≈ Vec2(0.0, 0.0) atol = 1e-12
end
