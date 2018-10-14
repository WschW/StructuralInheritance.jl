using Test

#NOTE: @testset will not work for testing this.
using StructuralInheritance
## TEST BASIC STRUCTURAL INHERITENCE ##

  StructuralInheritance.@protostruct struct A
     f_a::Int
     f_b
  end

  StructuralInheritance.@protostruct struct B <: A
      f_c::Float32
      f_d
  end

  @test fieldnames(B) == (:f_a,:f_b,:f_c,:f_d) #Test names of fields and order
  @test fieldtype.(B,[1,2,3,4]) == [Int,Any,Float32,Any]
  @test B <: ProtoB && B <: ProtoA

# exception thrown when inherited class uses same names
  @test_throws Any StructuralInheritance.@protostruct struct C <: A
      f_a::Int
  end

  @test_throws Any StructuralInheritance.@protostruct struct D <: A
      f_b
  end

  # exception thrown trying to inherit from a concrete class not defined
  # by @protostruct
  @test_throws Any StructuralInheritance.@protostruct struct E <: Int
      f_b
  end

  @test_throws Any StructuralInheritance.@protostruct struct E <: Int
      f_b
  end

  #inheritence from any abstract class
  StructuralInheritance.@protostruct struct F <: Real
      f_b
  end

  @test F(3).f_b == 3

  StructuralInheritance.@protostruct struct G <: B
      f_e::Float32
      f_f
  end

  @test fieldnames(G) == (:f_a,:f_b,:f_c,:f_d,:f_e,:f_f) #Test names of fields and order
  @test fieldtype.(G,[1,2,3,4,5,6]) == [Int,Any,Float32,Any,Float32,Any]
  @test G <: ProtoG && G <: ProtoB && G <: ProtoA


#TEST MODULE SANITIZATION FACILITY
module MA
  using Main.StructuralInheritance
  @protostruct struct A
    f_a_MA::Int
  end
  @protostruct struct B <: A
    f_a::A
  end
end

@protostruct struct H <: MA.B
  f_c::A
end

@protostruct struct H_2 <: MA.B
  f_c::MA.A
end

@test fieldnames(H_2) == (:f_a_MA,:f_a,:f_c)
@test fieldtype.(H_2,[1,2,3]) == [Int,MA.A,MA.A]

@test fieldnames(H) == (:f_a_MA,:f_a,:f_c)
@test fieldtype.(H,[1,2,3]) == [Int,MA.A,A]

@test StructuralInheritance.@protostruct(struct I <: A
    f_c::Float32
    f_d
end,"ProtoType") == ProtoTypeI

@test StructuralInheritance.@protostruct(struct J
    f_c::Float32
    f_d
end,"ProtoType") == ProtoTypeJ

@test_throws Any StructuralInheritance.@protostruct(struct K
    f_c::Float32
    f_d
end,"") == ProtoTypeK

#TEST PARAMETRIC INHERITENCE
module M_paramfields
    using Main.StructuralInheritance
    using Test
    @test @protostruct(struct A
        f_a::Core.Main.Base.Array{Float16,3}
    end) == ProtoA

    @test @protostruct(struct B <: A
        f_b::Complex{Float64}
    end) == ProtoB

    @test @protostruct(struct C <: B
        field_c::Array{Float32,4}
    end) == ProtoC

    @test fieldnames(C) == (:f_a,:f_b,:field_c)
    @test fieldtype.(C,[1,2,3]) == [Array{Float16,3},Complex{Float64},Array{Float32,4}]
end



@test StructuralInheritance.@protostruct(struct K{T}
    f_a::T
end) == ProtoK

@test fieldtype(K{Int},1) == Int
@test fieldnames(K) == (:f_a,)


@test @protostruct(struct L{T} <: K{T}
    f_b::T
end) == ProtoL

@test fieldnames(L) == (:f_a,:f_b)
@test fieldtype.(L{Real},[1,2]) == [Real,Real]

@test @protostruct(struct N{R} <: K{R}
    f_b::R
end) == ProtoN


@test fieldnames(N) == (:f_a,:f_b)
@test fieldtype.(N{Complex},[1,2]) == [Complex,Complex]


@protostruct mutable struct BB
        f_a::Int
end

@protostruct mutable struct CC{A,BA} <: BB
    f_b::A
    f_c::BA
end


@test_broken @protostruct mutable struct DD{C,D} <: CC{D,Complex}
    f_d::C
end

@test_broken @protostruct mutable struct O <: MA.DD{Int,Real}
    f_e::Complex
end == ProtoO

#@test_broken @test fieldnames(O) == (:f_a,:f_b,:f_c,:f_d,:f_e)
#@test_broken @test fieldtype.(O,[1,2,3,4,5]) == [Int,Real,Complex,Int,Complex]

module M_literal_func
    using Main.StructuralInheritance
    f(x) = Int
    f(x::Array) = length(x) == 2 ? Complex : Array
    @macroexpand @protostruct struct P
        f1::f(2)
        f2::f([])
        f3::f([1,2])
    end
end

@protostruct struct Q <: M_literal_func.P
    f4::Real
end

@test fieldnames(Q) == (:f1,:f2,:f3,:f4)
@test_broken fieldtype.(Q,[1,2,3,4]) == [Int,Array,Complex,Real]
