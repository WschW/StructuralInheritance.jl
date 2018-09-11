module StrucuralInheritence

#Stores prototype field definitions
const fieldBacking = Dict{Type,Vector{Any}}()
const constructorBacking = Dict{Type,Vector{Any}}()

#concrete -> prototype
#prototype -> prototype
const shadowMap = Dict{Type,Type}()

function abstracttype(name)
  basicForm = :(abstract type Replace end)
  dump(basicForm)
  basicForm.args[1] = name
  basicForm
end

function filtertofields(_quote)
  filter(x->typeof(x)==Symbol || (typeof(x) == Expr && x.head == :(::)),_quote.args)
end

function filtertoconstructors(_quote)
  filter(x -> (typeof(x) == Expr && x.head == :function),_quote.args)
end

function extractname(leaf)
  leaf.args[2]
end

function extractfields(leaf)
  filtertofields(leaf.args[3])
end

function protoname(oldName::Symbol)
  outName = Symbol("Proto",oldName)
  (:($oldName <: $outName),outName,outName)
end

function protoname(oldName::Expr)
  outName = deepcopy(oldName)
  if typeof(outName.args[2]) <: Symbol
    outName.args[2] = Symbol("Proto",outName.args[2])
    (outName,outName.args[2],outName.args[2])
  else
    outName.args[2].args[1] = Symbol("Proto",outName.args[2].args[1])
    (outName,outName.args[2],outName.args[2].args[1])
  end
end

"""
annotates module information to unanotated typed fields
"""
function sanitize(module_,fields)
    fields #TODO
end

macro proto(struct_)
  renamed,name,lightname = protoname(struct_)
  fields = extractfields(struct_)
  D1_struct = gensym()
  D1_module = gensym()
  D1_fields = gensym()
  prototypeDefinition = abstracttype(name) #Can't be evaluated until all checks are passed and we are in the calling module
  if typeof(name) <: Symbol #original definition does not inherit
    esc(quote
      $prototypeDefinition
      $D1_module = parentmodule($lightname)
      $D1_fields = StrucralInheritence.sanitize($D1_module,$fields)
      $struct_
    end)
  else

  end

end

"""
Calls the provided constructor of the supertype the strucure is inherited from.
"""
macro super(constructor,self::Symbol = gensym())
  val = gensym()
  fields = gensym()
  field = gensym()
  esc(quote
    $val = constructor
    $fields = fieldnames(typeof($val))
    $self = new()
    for $field = $fields
        setfield!($self,$field,getfield($val,$field))
    end
  end)
end

end
