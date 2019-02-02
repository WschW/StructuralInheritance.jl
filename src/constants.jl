const FieldType = Union{Symbol,Expr}
const SymbolTuple = Tuple{Vararg{Symbol,N}} where {N}

#Stores prototype field definitions
const fieldBacking = IdDict{Type, Vector{FieldType}}()

#prototype -> self
#concrete -> prototype
const shadowMap = IdDict{Type,Type}()

#concrete -> prototype
const traitMap = IdDict{Type,Type}()

#store parametric type information
const parameterMap = IdDict{Type,Vector{FieldType}}()

const mutabilityMap = IdDict{Type,Bool}()
