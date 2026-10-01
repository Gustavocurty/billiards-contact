using Test
using BilliardsContact

@testset "BilliardsContact" begin
    include(joinpath(@__DIR__, "geometry_test.jl"))
    include(joinpath(@__DIR__, "brute_force_test.jl"))
    include(joinpath(@__DIR__, "tracking_test.jl"))
    include(joinpath(@__DIR__, "pool_test.jl"))
end
