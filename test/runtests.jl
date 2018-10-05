using Test

#NOTE: @testset will not work for testing this.
using StructuralInheritance
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

  StructuralInheritance.@protostruct struct G <: B
      FE::Float32
      FF
  end

  @test fieldnames(G) == (:FA,:FB,:FC,:FD,:FE,:FF) #Test names of fields and order
  @test fieldtype.(G,[1,2,3,4,5,6]) == [Int,Any,Float32,Any,Float32,Any]
  @test G <: ProtoG && G <: ProtoB && G <: ProtoA


#TEST MODULE SANITIZATION FACILITY
module MA
  using StructuralInheritance
  @protostruct struct A
    MA_FA::Int
  end
  @protostruct struct B <: A
    A::A
  end
end

@test_broken @protostruct struct H <: MA.B
  C::A
end

@test_broken fieldnames(H) == (:MA_FA,:A,:C)
@test_broken fieldtype.(H,[1,2,3]) == [Int,MA.A,A]

#TODO: TEST parametric inheritence

#TODO: TEST interactions between module sanitization and parametric inheritence
