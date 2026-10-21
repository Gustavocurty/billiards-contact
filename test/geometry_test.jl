@testset "Geometria do círculo" begin
    @test distance(Vec2(0.0, 0.0), Vec2(3.0, 4.0)) ≈ 5.0

    valid, s, point = ray_circle_hit(Vec2(0.0, 0.0), Vec2(1.0, 0.0), Vec2(10.0, 0.0), 2.0)
    @test valid
    @test s ≈ 8.0 atol = 1e-12
    @test point ≈ Vec2(8.0, 0.0) atol = 1e-12
    @test distance(point, Vec2(10.0, 0.0)) ≈ 2.0 atol = 1e-12

    missed, _, _ = ray_circle_hit(Vec2(0.0, 0.0), Vec2(1.0, 0.0), Vec2(10.0, 5.0), 2.0)
    @test !missed

    behind, s_behind, _ = ray_circle_hit(Vec2(0.0, 0.0), Vec2(1.0, 0.0), Vec2(-10.0, 0.0), 2.0)
    @test !behind
    @test s_behind < 0

    tangent, s_t, point_t = ray_circle_hit(Vec2(0.0, 0.0), Vec2(1.0, 0.0), Vec2(200.0, 36.0), 36.0)
    @test tangent
    @test s_t ≈ 200.0 atol = 1e-8
    @test abs(s_derivative(0.0, s_t, Vec2(0.0, 0.0), Vec2(200.0, 36.0))) === NaN || !isfinite(s_derivative(0.0, s_t, Vec2(0.0, 0.0), Vec2(200.0, 36.0)))
end
