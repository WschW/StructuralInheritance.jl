using Test
include("../deps/build.jl")


@testset "Direct Inheritence" begin
  StructuralInheritance.@protostruct struct A
     FA::Int
     FB
  end

  StructuralInheritance.@protostruct struct B <: A
      FC::Float32
      FD
  end

  @test fieldnames(B) == (:FA,:FB,:FC,:FD) #Test names of fields and order
  @test fieldtype.(B,[1,2,3,4]) == [Int,Any,Float32,Any]
  @test B <: ProtoB && B <: ProtoA

  @test_throws Any StructuralInheritance.@protostruct struct C <: A
      A::Int
  end

  @test_throws Any StructuralInheritance.@protostruct struct D <: A
      B
  end

  @test_throws Any StructuralInheritance.@protostruct struct E <: Int
      B
  end
end

@testset "Module Sanitization" begin

end

@testset "Parametric Inheritence" begin

end

@testset "Parametric Modules" begin

end
