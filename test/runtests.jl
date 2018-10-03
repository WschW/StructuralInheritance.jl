using Test
include("../deps/build.jl")

#NOTE: @testset will not work for testing this.

## TEST BASIC STRUCTURAL INHERITENCE ##

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

# exception thrown when inherited class uses same names
  @test_throws Any StructuralInheritance.@protostruct struct C <: A
      FA::Int
  end

  @test_throws Any StructuralInheritance.@protostruct struct D <: A
      FB
  end

  # exception thrown trying to inherit from a concrete class not defined
  # by @protostruct
  @test_throws Any StructuralInheritance.@protostruct struct E <: Int
      B
  end

  @test_throws Any StructuralInheritance.@protostruct struct E <: Int
      B
  end

  #inheritence from any abstract class
  StructuralInheritance.@protostruct struct F <: Real
      B
  end

  @test F(3).B == 3


#TODO: TEST MODULE SANITIZATION FACILITY


#TODO: TEST parametric inheritence

#TODO: TEST interactions between module sanitization and parametric inheritence
