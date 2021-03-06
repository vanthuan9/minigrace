#pragma ExtendedLineups
#pragma noTypeChecks
dialect "none"
import "standardGrace" as sg

import "ast" as ast
import "xmodule" as xmodule
import "io" as io

inherit sg.methods

// Copied from Dialect2
// data structure to hold cached type assignments

// Checker error

def CheckerFailure is public = Exception.refine "CheckerFailure"

var methodtypes := [ ]
// visitor to convert a type expression to a string
def typeVisitor: ast.AstVisitor = object {
    inherit ast.baseVisitor
    var literalCount := 1
    method visitTypeLiteral(lit) {
        io.error.write"\n 25 visiting Type Literal"
        for (lit.methods) do { meth →
            var mtstr := "{literalCount} "
            for (meth.signature) do { part →
                mtstr := mtstr ++ part.name
                if (part.params.size > 0) then {
                    mtstr := mtstr ++ "("
                    for (part.params.indices) do { pnr →
                        var p := part.params.at(pnr)
                        if (p.dtype != false) then {
                            mtstr := mtstr ++ p.toGrace(1)
                        } else {
                            // if parameter type not listed, give it type Unknown
                            if(p.wildcard) then {
                                mtstr := mtstr ++ "_"
                            } else {
                                mtstr := mtstr ++ p.value
                            }
                            mtstr := mtstr ++ ":" ++ ast.unknownType.value
                            if (false != p.generics) then {
                                mtstr := mtstr ++ "⟦"
                                for (1..(p.generics.size - 1)) do {ix →
                                    mtstr := mtstr ++ p.generics.at(ix).toGrace(1) ++ ", "
                                }
                                mtstr := mtstr ++ p.generics.last.toGrace(1) ++ "⟧"
                            }
                        }
                        if (pnr < part.params.size) then {
                            mtstr := mtstr ++ ", "
                        }
                    }
                    mtstr := mtstr ++ ")"
                }
            }
            if (meth.rtype != false) then {
                mtstr := mtstr ++ " → " ++ meth.rtype.toGrace(1)
            }
            methodtypes.push(mtstr)
        }
        io.error.write "methodtypes of {lit} is {methodtypes}"
        return false
    }
    method visitOp(op) {
        if ((op.value=="&") || (op.value=="|")) then {
            def leftkind = op.left.kind
            def rightkind = op.right.kind
            if ((leftkind=="identifier") || (leftkind=="member")) then {
                var typeIdent := op.left.toGrace(0)
                methodtypes.push("{op.value} {typeIdent}")
            } elseif { leftkind=="typeliteral" } then {
                literalCount := literalCount + 1
                methodtypes.push("{op.value} {literalCount}")
                visitTypeLiteral(op.left)
            } elseif { leftkind=="op" } then {
                visitOp(op.left)
            }
            if ((rightkind=="identifier") || (rightkind=="member")) then {
                var typeIdent := op.right.toGrace(0)
                methodtypes.push("{op.value} {typeIdent}")
            } elseif { rightkind=="typeliteral" } then {
                literalCount := literalCount + 1
                methodtypes.push("{op.value} {literalCount}")
                visitTypeLiteral(op.right)
            } elseif { rightkind=="op" } then {
                visitOp(op.right)
            }
        }
        return false
    }
}

// convert type expression to string for debugging
method dtypeToString(dtype) {
    if (false == dtype) then {
        "Unknown"
    } elseif {dtype.kind == "typeliteral"} then {
        methodtypes := []
        dtype.accept(typeVisitor)
        methodtypes.at(1)
    } else {
        dtype.value
    }
}




// The cached type assignments.
def cache: Dictionary = emptyDictionary
// cache holding confidential as well as public types
def allCache: Dictionary = emptyDictionary

// Scope represents stack of scopes using stackOfKind

type StackOfKind⟦V⟧ = {
    stack → List⟦Dictionary⟧
    at (name : String) put (value:V) → Done

    addToTopAt(name : String) put (value : V) → Done
    find (name : String) butIfMissing (bl: Function0⟦V⟧) → V
    findAtTop (name : String) butIfMissing (bl: Function0⟦V⟧) → V
}

class stackOfKind⟦V⟧(kind : String) → StackOfKind⟦V⟧ is confidential {
    def stack: List⟦Dictionary⟧ is public = list[emptyDictionary]
    // add <name,value> to current scope
    method at (name : String) put (value:V) → Done {
        stack.last.at(name) put(value)
    }

    //adds to the first layer of the scope
    method addToTopAt(name : String) put (value:V) → Done {
        stack.first.at(name) put(value)
    }

    // Find name in stack of current scopes & return its value
    // If not there perform action in bl
    method find (name : String) butIfMissing (bl: Function0⟦V⟧) → V {
        var i: Number := stack.size
        while { i > 0 } do {
            var found: Boolean := true
            def val = stack.at(i).at(name) ifAbsent {
                found := false
            }
            if(found) then {
                return val
            }

            i := i - 1
        }

        return bl.apply
    }

    //specifically used to find types saved in the first level of the scope
    method findAtTop (name : String) butIfMissing (bl: Function0⟦V⟧) → V {
        var found: Boolean := true
        def val = stack.at(1).at(name) ifAbsent {
            found := false
        }
        if(found) then {
            return val
        } else {
            return bl.apply
        }
    }

    method asString → String is override {
        var out: String := ""

        for(stack) do { dict:Dictionary⟦String, Object⟧ →
            out := "{out}\ndict⟬"

            dict.keysAndValuesDo { key:String, value:Object →
                out := "{out}\n  {key}::{value}"
            }
            out := "{out}\n⟭"
        }
        out
    }
}

type Scope = {
    // keep track of each kind of expression separately
    variables → StackOfKind⟦ObjectType⟧
    methods → StackOfKind⟦MethodType⟧
    types → StackOfKind⟦ObjectType⟧
    // number of items on stack
    size → Number
    // Enter new scope to execute block bl and then delete afterwards
    // returns value of bl
    enter⟦V⟧(bl: Function0⟦V⟧) → V
}

// scope consists of stacks of scopes for each of variables, methods, & types
def scope: Scope is public = object {
    // keep track of each kind of expression separately
    def variables is public = stackOfKind ("variable")
    def methods is public = stackOfKind ⟦MethodType⟧("method")
    def types is public = stackOfKind ⟦ObjectType⟧("type")

    // number of items on stack
    method size → Number {
        variables.stack.size
    }

    // Enter new scope to execute block bl and then delete afterwards
    // returns value of bl
    method enter⟦V⟧ (bl:Function0⟦V⟧) → V {
        variables.stack.push (sg.emptyDictionary)
        methods.stack.push (sg.emptyDictionary)
        types.stack.push (sg.emptyDictionary)

        def result: V = bl.apply

        variables.stack.pop
        methods.stack.pop
        types.stack.pop

        result
    }

    method asString → String is override {
        "scope<{size}>"
    }
}

// check the type of node and insert into cache only
method checkTypes (node: AstNode) → Done {
    io.error.write "\n233: checking types of {node.nameString}"
    cache.at (node) ifAbsent {
        io.error.write "\n235: {node.nameString} not in cache"
        node.accept (astVisitor)
    }
}

// check type of node, put in cache & then return type
method typeOf (node: AstNode) → ObjectType {
    checkTypes (node)
    cache.at (node) ifAbsent {
        CheckerFailure.raise "cannot type non-expression {node}" with (node)
    }
}

method inheritableTypeOf (node: AstNode) → ObjectType {
    allCache.at (node) ifAbsent {
        CheckerFailure.raise "cannot find confidential type of {node}" with (node)
    }
}


type AstNode = { kind → String }

// Create a pattern for matching kind
class aPatternMatchingNode (kind : String) → Pattern {
    inherit outer.BasicPattern.new

    method match (obj : Object) → MatchResult | false {
        match (obj)
          case { node : AstNode →
            if (kind == node.kind) then {
                SuccessfulMatch.new (node, outer.emptySequence)
            } else {
                false
            }
        } case { _ → false }
    }
}

// Same as Pattern??
//type Matcher = {
//    match(obj: AstNode) → MatchResult | false
//}

// A pattern that matches if parameter satisfies predicate
class booleanPattern (predicate: Function1⟦AstNode⟧) → Pattern {
    inherit BasicPattern.new
    method match (obj: AstNode) → MatchResult | false{
        if (predicate.apply (obj)) then {
            SuccessfulMatch.new (obj, outer.emptySequence)
        } else {
            false
        }
    }
}

// patterns for built-in AST Nodes
def If: Pattern is public = aPatternMatchingNode "if"
def BlockLiteral: Pattern is public = aPatternMatchingNode "block"
def MatchCase: Pattern is public = aPatternMatchingNode "matchcase"
def TryCatch: Pattern is public = aPatternMatchingNode "trycatch"
def Outer: Pattern is public = aPatternMatchingNode "outer"
def MethodSignature: Pattern is public = aPatternMatchingNode "methodtype"
def TypeLiteral: Pattern is public = aPatternMatchingNode "typeliteral"
def TypeDeclaration: Pattern is public = aPatternMatchingNode "typedec"
def TypeAnnotation: Pattern is public = aPatternMatchingNode "dtype"
def Member: Pattern is public = aPatternMatchingNode "member"
def Method: Pattern is public = aPatternMatchingNode "method"
def Parameter: Pattern is public = aPatternMatchingNode "parameter"
// matches anything that is a call
def Request: Pattern is public = booleanPattern { x → x.isCall }
def Class: Pattern is public = aPatternMatchingNode "class"
def ObjectLiteral: Pattern is public = aPatternMatchingNode "object"
def ArrayLiteral: Pattern is public = aPatternMatchingNode "array"
def Generic: Pattern is public = aPatternMatchingNode "generic"
def Identifier: Pattern is public = aPatternMatchingNode "identifier"
def OctetsLiteral: Pattern is public = aPatternMatchingNode "octets"
def StringLiteral: Pattern is public = aPatternMatchingNode "string"
def NumberLiteral: Pattern is public = aPatternMatchingNode "num"
def Operator: Pattern is public = aPatternMatchingNode "op"
def Bind: Pattern is public = aPatternMatchingNode "bind"
def Def: Pattern is public = aPatternMatchingNode "defdec"
def Var: Pattern is public = aPatternMatchingNode "vardec"
def Import: Pattern is public = aPatternMatchingNode "import"
def Dialect: Pattern is public = aPatternMatchingNode "dialect"
def Return: Pattern is public = aPatternMatchingNode "return"
def Inherit: Pattern is public = aPatternMatchingNode "inherit"
def Module: Pattern is public = aPatternMatchingNode "module"


// -------------------------------------------------------------------
// Type declarations for type representations to use for type checking
// -------------------------------------------------------------------

//This type is used for checking subtyping
type TypePair = {
    first → ObjectType
    second → ObjectType
    == (other:Object)→ Boolean
    asString → String
}

class typePair(first':ObjectType, second':ObjectType) → TypePair is confidential{
    method first → ObjectType {first'}

    method second → ObjectType {second'}

    method == (other:Object) → Boolean {
        (first == other.first) && (second == other.second)
    }

    method asString {"<{first'} , {second'}>"}
}

//This type is used for checking subtyping
type Answer = {
    ans → Boolean
    trials → List⟦TypePair⟧
    asString → String
}

class answerConstructor(ans':Boolean, trials':List⟦TypePair⟧) → Answer {
    method ans → Boolean {ans'}

    method trials → List⟦TypePair⟧ {trials'}

    method asString → String{"Answer is {ans'}\n Trials is {trials}"}
}

// Method signature information.
// isSpecialisation and restriction are used for type-checking
type MethodType = {
    // name of the method
    name → String
    // name of the method with number of parameters for each part
    nameString → String
    // parameters and their types for each part
    signature → List⟦MixPart⟧
    // return type
    returnType → ObjectType
    // Does it extend other
    isSpecialisationOf (trials : List⟦TypePair⟧, other : MethodType) → Answer
    // create restriction of method type using other
    restriction (other : MethodType) → MethodType
}

// type of a parameter
type Param = {
    name → String
    typeAnnotation → ObjectType
}

type ParamFactory = {
    withName (name' : String) ofType (type' : ObjectType) → Param
    ofType (type' : ObjectType) → Param
}

// Create parameter with given name' and type'
// if no name then use wildcard "_"
def aParam: ParamFactory = object {
    method withName(name': String) ofType(type' : ObjectType) → Param {
        object {
            def name : String is public = name'
            def typeAnnotation : ObjectType is public = type'

            def asString : String is public, override =
                "{name} : {typeAnnotation}"
        }
    }

    method ofType (type': ObjectType) → Param {
        withName("_") ofType(type')
    }
}

// MixPart is a "segment" of a method:
// Ex. for (param1) do (param2), for(param1) and do(param2) are separate "MixParts."
type MixPart = {
    name → String
    parameters → List⟦Param⟧
}

// create a mixpart with given name' and parameters'
class aMixPartWithName(name' : String)
        parameters(parameters' : List⟦Param⟧) → MixPart {
    def name : String is public = name'
    def parameters : List⟦Param⟧ is public = parameters'
}

type MethodTypeFactory = {
    signature (signature' : List⟦MixPart⟧)
            returnType (rType : ObjectType)→ MethodType
    member (name : String) ofType (rType : ObjectType) → MethodType
    fromGctLine (line : String, importName: String) → MethodType
    fromNode (node: AstNode) → MethodType
}

// factory for creating method types from various inputs
def aMethodType: MethodTypeFactory is public = object {
    // create method type from list of mixparts and return type
    method signature (signature' : List⟦MixPart⟧)
            returnType (rType : ObjectType) → MethodType {
        object {
            def signature : List⟦MixPart⟧ is public = signature'
            def returnType : ObjectType is public = rType

            var name : String is readable := ""
            var nameString : String is readable := ""
            var show : String := ""

            def fst: MixPart = signature.first

            if (fst.parameters.isEmpty) then {
                name := fst.name
                nameString := fst.name
                show := name
            } else {
                for (signature) do { part →
                    name := "{name}{part.name}()"
                    nameString := "{nameString}{part.name}({part.parameters.size})"
                    show := "{show}{part.name}("
                    var once: Boolean := false
                    for (part.parameters) do { param →
                        if (once) then {
                            show := "{show}, "
                        }
                        show := "{show}{param}"
                        once := true
                    }
                    show := "{show})"
                }

                name := name.substringFrom (1) to (name.size - 2)
            }

            show := "{show} → {returnType}"

            method hash → Number is override {name.hash}

            method == (other: MethodType) → Boolean {
                nameString == other.nameString
            }

            // Mask unknown fields in corresponding methods
            // Assume that the methods share a signature.
            method restriction (other : MethodType) → MethodType {
                def restrictParts: List⟦MixPart⟧ = list[]
                if (other.signature.size != signature.size) then {
                    return self
                }
                for (signature) and (other.signature)
                                        do {part: MixPart, part': MixPart →
                    if (part.name == part'.name) then {
                        def restrictParams: List⟦Param⟧ = list[]
                        if (part.parameters.size != part'.parameters.size) then {
                              io.error.write ("Programmer error: part {part.name} has {part.parameters.size}" ++
                                    " while part {part'.name} has {part'.parameters.size}")}
                        for (part.parameters) and (part'.parameters)
                                                do { p: Param, p': Param →
                            def pt': ObjectType = p'.typeAnnotation

                            // Contravariant in parameter types.
                            if (pt'.isDynamic) then {
                                restrictParams.push (
                                    aParam.withName (p.name) ofType (anObjectType.dynamic))
                            } else {
                                restrictParams.push (p)
                            }
                        }
                        restrictParts.push (
                            aMixPartWithName (part.name) parameters (restrictParams))
                    } else {
                        restrictParts.push (part)
                    }
                }
                return aMethodType.signature (restrictParts) returnType (returnType)
            }

            // Determines if this method is a specialisation of the given one.
            method isSpecialisationOf (trials : List⟦TypePair⟧, other : MethodType) → Answer {

                if (self.isMe (other)) then {
                    return answerConstructor(true, trials)
                }

                if (nameString != other.nameString) then {
                    return answerConstructor(false, trials)
                }

                if (other.signature.size != signature.size) then {
                    return answerConstructor(false, trials)
                }

                for (signature) and (other.signature)
                                            do { part: MixPart, part': MixPart →
                    if (part.name != part'.name) then {
                        return answerConstructor(false, trials)
                    }

                    if (part.parameters.size != part'.parameters.size) then {
                        return answerConstructor(false, trials)
                    }

                    for (part.parameters) and (part'.parameters)
                                                    do { p: Param, p': Param →
                        def pt: ObjectType = p.typeAnnotation
                        def pt': ObjectType = p'.typeAnnotation

                        // Contravariant in parameter types.
                        def paramSubtyping : Answer = pt'.isSubtypeHelper(trials, pt)

                        if (paramSubtyping.ans.not) then {
                            return paramSubtyping
                        }
                    }
                }
                return returnType.isSubtypeHelper (trials, other.returnType)
            }

            def asString : String is public, override = show
        }
    }

    // Create method type with no parameters, but returning rType
    method member (name : String) ofType (rType : ObjectType) → MethodType {
        signature(list[aMixPartWithName (name) parameters (list[])]) returnType (rType)
    }

    // Parses a methodtype line from a gct file into a MethodType object.
    // Lines will always be formatted like this:
    //  1 methname(param : ParamType)part(param : ParamType) → ReturnType
    // The number at the beginning is ignored here, since it is handled
    // down in the Imports rule.
    method fromGctLine (line : String, importName : String) → MethodType {
        //TODO: Generics are currently skipped over and ignored entirely.
        // string specifying method being imported
        var mstr: String
        var fst: Number
        var lst: Number
        def parts: List⟦MixPart⟧ = list[]
        var ret: String

        //Declare an identifier node that will be used when saving the type
        //of method parameter and method return, so we only retrieve the actual
        //type defintion of the param or ret type when we need to type check.
        var ident : Identifier

        //Check if line starts with a number. ie: 2 methName -> ReturnType
        mstr := if (line.at(1).startsWithLetter) then {
            line
        } else {
            line.substringFrom (line.indexOf (" ") + 1) to (line.size)
        }

        //Retrieves the parts of the method
        fst := 1
        var par: Number := mstr.indexOf ("(") startingAt (fst)
        lst := par - 1

        //Collect the part definition if our method is not a member
        if (par > 0) then {
            //Iterates through each part
            while {par > 0} do {
                //Collect the signature part name
                var partName: String := mstr.substringFrom (fst) to (lst)
                // io.error.write "partName: {partName}"

                var partParams: List⟦Param⟧ := list[]
                fst := lst + 2
                lst := fst
                var multiple: Boolean := true

                //Iterates through all the parameters in this part
                while {multiple} do {
                    while {mstr.at (lst) != ":"} do {
                        lst := lst + 1
                    }

                    //Collect parameter name
                    var paramName: String := mstr.substringFrom(fst)to(lst - 1)
                    io.error.write "paramName: {paramName}"
                    fst := lst + 1
                    while {(mstr.at (lst) != ")") && (mstr.at (lst) != ",") && (mstr.at(lst) != "⟦")} do {
                        lst := lst + 1
                    }

                    //Collect parameter declared type.
                    var paramType: String := mstr.substringFrom(fst)to(lst - 1)

                    //Since any imported type that is not a prelude type will be
                    //saved as 'importName.typeName' in the types scope, we need
                    //to prepend 'importName' to places in a method signature
                    //that reference these types
                    if(anObjectType.preludeTypes.contains(paramType).not) then {
                        paramType := "{importName}.{paramType}"
                    }

                    //Checke if there are additional method parts
                    io.error.write "paramType = {paramType}"
                    if (mstr.at (lst) == ",") then {
                        fst := lst + 2
                        lst := fst
                    } else {
                        multiple := false
                    }

                    //Add this parameter to the parameter list, dtype of ident
                    //can be set to false because it is never used
                    ident := ast.identifierNode.new("{paramType}", false)
                    partParams.push(aParam.withName(paramName)
                                      ofType(anObjectType.definedByNode(ident)))
                }
                //Return from while-loop with the full part definition
                par := mstr.indexOf ("(") startingAt (lst)
                fst := lst + 1
                lst := par - 1
                parts.add (aMixPartWithName (partName) parameters (partParams))
            }
        } else { //This method is a member, the partName is the method's name
            var partName : String := mstr.substringFrom (fst)
                                                    to (mstr.indexOf(" →") - 1)
            // io.error.write "partName = {partName}"
            parts.add (aMixPartWithName (partName) parameters (list[]))
        }

        fst := mstr.indexOf ("→ ") startingAt (1) + 2
        if (fst < 1) then {
            io.error.write "no arrow in method type {mstr}"
        }

        //Collect the declared type that this method returns
        ret := mstr.substringFrom (fst) to (mstr.size)

        //Since any imported type that is not a prelude type will be saved as
        //'importName.typeName' in the types scope, we need to prepend
        //'importName'to places in a method signature that reference these types
        if(anObjectType.preludeTypes.contains(ret).not) then {
            ret := "{importName}.{ret}"
        }
        // io.error.write "ret = {ret}"

        //Construct the ObjectType of the return type, dtype of ident can be
        //set to false because it is never used
        ident := ast.identifierNode.new (ret, false)
        def rType: ObjectType = anObjectType.definedByNode(ident)
        // io.error.write "rType = {rType}"
        aMethodType.signature (parts) returnType (rType)
    }
    // if node is a method, class, method signature,
    // def, or var, create appropriate method type
    method fromNode (node: AstNode) → MethodType {
        match (node) case { meth : Method | Class | MethodSignature →
            io.error.write "\n573: node matched as method: {meth}"

            def signature: List⟦MixPart⟧ = list[]

            for (meth.signature) do { part:AstNode →
                def params: List⟦Param⟧ = list[]

                for (part.params) do { param: AstNode → // not of type Param??
                    params.push (aParam.withName (param.value)
                        ofType (anObjectType.definedByNode (param.dtype)))
                }

                signature.push (aMixPartWithName (part.name) parameters (params))
            }

            def rType: AstNode = match (meth)
                case { m : Method | Class → m.dtype}
                case { m : MethodSignature → meth.rtype}

            return signature (signature)
                returnType (anObjectType.definedByNode (rType))
        } case { defd : Def | Var →
            io.error.write "\n574: defd: {defd}"
            io.error.write "\n575: defd.dtype {defd.dtype}"
            def signature: List⟦MixPart⟧ =
                    list[aMixPartWithName (defd.name.value) parameters (list[])]
            def dtype: ObjectType = if (defd.dtype == false) then {
                anObjectType.dynamic
            } else {
                anObjectType.definedByNode (defd.dtype)
            }
            return signature (signature) returnType (dtype)
        } case { _ →
            Exception.raise "unrecognised method node" with(node)
        }
    }
}


// Object type information.

def noSuchMethod: outer.Pattern = object {
    inherit BasicPattern.new

    method match(obj : Object) {
        if(self.isMe(obj)) then {
            SuccessfulMatch.new(self, list[])
        } else {
            FailedMatch.new(obj)
        }
    }
}

def noSuchType: outer.Pattern = object {
    inherit BasicPattern.new

    method match(obj : Object) {
        if(self.isMe(obj)) then {
            SuccessfulMatch.new(self, list[])
        } else {
            FailedMatch.new(obj)
        }
    }
}


// represents the type of an expression as a collection of method types
type ObjectType = {
    methods → Set⟦MethodType⟧
    getMethod (name : String) → MethodType | noSuchMethod
    resolve → ObjectType
    isResolved → Boolean
    isDynamic → Boolean
    == (other:ObjectType) → Boolean
    isSubtypeOf (other : ObjectType) → Boolean
    isSubtypeHelper (trials : List⟦TypePair⟧, other : ObjectType) → Answer
    restriction (other : ObjectType) → ObjectType
    isConsistentSubtypeOf (other : ObjectType) → Boolean
    getVariantTypes → List⟦ObjectType⟧
    setVariantTypes(newVariantTypes:List⟦ObjectType⟧) → Done
    | (other : ObjectType) → ObjectType
    & (other : ObjectType) → ObjectType
}

// methods to create an object type from various inputs
type ObjectTypeFactory = {
    definedByNode (node : AstNode) → ObjectType
    fromMethods (methods' : Set⟦MethodType⟧) → ObjectType
    fromMethods (methods' : Set⟦MethodType⟧) withName (name : String) → ObjectType
    fromDType (dtype) → ObjectType
    fromIdentifier(ident : Identifier) → ObjectType
    fromBlock (block) → ObjectType
    fromBlockBody (body) → ObjectType
    dynamic → ObjectType
    bottom → ObjectType
    blockTaking (params : List⟦Parameter⟧) returning (rType : ObjectType) → ObjectType
    blockReturning (rType : ObjectType) → ObjectType
    preludeTypes → Set⟦String⟧
    base → ObjectType
    doneType → ObjectType
    pattern → ObjectType
    iterator → ObjectType
    boolean → ObjectType
    number → ObjectType
    string → ObjectType
    listTp → ObjectType
    set → ObjectType
    sequence → ObjectType
    dictionary → ObjectType
    point → ObjectType
    binding → ObjectType
    collection → ObjectType
    enumerable → ObjectType
}

def anObjectType: ObjectTypeFactory is public = object {

    //Version of ObjectType that allows for lazy-implementation of type checking
    //Holds the AstNode that can be resolved to the real ObjectType
    class definedByNode (node: AstNode) -> ObjectType{

        method methods -> Set⟦MethodType⟧ { resolve.methods }

        method getMethod (name : String) → MethodType | noSuchMethod {
            resolve.getMethod(name)
        }

        //Process the AstNode to get its ObjectType
        method resolve -> ObjectType { fromDType(node) }

        //an ObjectType is unexpanded if it still holds an AstNode
        def isResolved : Boolean is public = false

        def isDynamic : Boolean is public = false

        method == (other:ObjectType) → Boolean { resolve == other.resolve}

        method isSubtypeOf (other : ObjectType) -> Boolean {
            resolve.isSubtypeOf(other.resolve)
        }

        method isSubtypeHelper(trials:List⟦TypePair⟧, other:ObjectType) → Answer {
            resolve.isSubtypeHelper(trials, other.resolve)
        }

        method restriction (other : ObjectType) → ObjectType {
            resolve.restriction(other.resolve)
        }

        method isConsistentSubtypeOf (other : ObjectType) → Boolean{
            resolve.isConsistentSubtypeOf(other.resolve)
        }

        method getVariantTypes → List⟦ObjectType⟧ { resolve.getVariantTypes }

        method setVariantTypes(newVariantTypes:List⟦ObjectType⟧) → Done {
            resolve.setVariantTypes(newVariantTypes)
        }

        method | (other : ObjectType) → ObjectType { resolve | (other.resolve) }

        method & (other : ObjectType) → ObjectType { resolve & (other.resolve) }

        method asString → String is override {
            match(node) case { (false) →
                "Unknown"
            } case { typeLiteral : TypeLiteral →
                "UnresolvedTypeLiteral"
            } case { op : Operator →
                "{definedByNode(op.left)}{op.value}{definedByNode(op.right)}"
            } case { ident : Identifier →
                "{ident.value}"
            } case { generic : Generic →
                "{generic.value.value}"
            } case { member : Member →
                "{member.receiver.nameString}.{member.value}"
            } case { _ →
                ProgrammingError.raise ("No case in method 'asString' of the" ++
                    "class definedByNode for node of kind {node.kind}") with(node)
            }
        }
    }


    method fromMethods (methods' : Set⟦MethodType⟧) → ObjectType {
        object {
            // List of variant types (A | B | ... )
            var variantTypes: List⟦ObjectType⟧ := list[]

            def methods : Set⟦MethodType⟧ is public = (if (base == dynamic)
                then { emptySet } else { emptySet.addAll(base.methods) }).addAll(methods')

            method getMethod(name : String) → MethodType | noSuchMethod {
                for(methods) do { meth →
                    if(meth.nameString == name) then {
                        return meth
                    }
                }
                return noSuchMethod
            }

            method resolve -> ObjectType { self }

            def isResolved : Boolean is public = true

            def isDynamic : Boolean is public = false

            //TODO: not sure we trust this. May have to refine == in the future
            method == (other:ObjectType) → Boolean { self.isMe(other) }

            //Check if 'self', which is the ObjectType calling this method, is
            //a subtype of 'other'
            method isSubtypeOf(other : ObjectType) → Boolean {
                def helperResult : Answer = self.isSubtypeHelper(emptyList, other.resolve)
                //io.error.write("\n751 The trials from subtyping were: {helperResult.trials}")

                helperResult.ans
            }

            //Make confidential
            //helper method for subtyping a pair of non-variant types
            method isNonvariantSubtypeOf(trials': List⟦TypePair⟧,
                                                  other:ObjectType) → Answer {
                def selfOtherPair : TypePair = typePair(self, other)

                //if trials already contains selfOtherPair, we can assume self <: other
                if(trials'.contains(selfOtherPair) || self.isMe(other)) then{
                    return answerConstructor(true, trials')
                } else{
                    var trials : List⟦TypePair⟧ := trials'
                    trials.add(selfOtherPair)

                    //for each method in other, check that there is a corresponding
                    //method in self
                    for (other.methods) doWithContinue { otherMeth, continue→
                        for (self.methods) do { selfMeth→
                            def isSpec: Answer =
                                  selfMeth.isSpecialisationOf(trials, otherMeth)
                            trials := isSpec.trials

                            if (isSpec.ans) then { continue.apply }
                        }
                        //io.error.write "\n885: didn't find {otherMeth} in {self}"
                        io.error.write "\n other methods: {other.methods}"
                        io.error.write "\n self methods: {self.methods}"

                        //fails to find corresponding method
                        return answerConstructor(false, trials)
                    }
                    return answerConstructor(true, trials)
                }
            }

            //helper method for subtyping a pair of ObjectTypes
            //
            //Param trials - Holds pairs of previously subtype-checked ObjectTypes
            //          Prevents infinite subtype checking of self-referential types
            //Param other - The ObjectType that self is checked against
            method isSubtypeHelper(trials:List⟦TypePair⟧, other':ObjectType) → Answer {
                def other : ObjectType = other'.resolve
                if(self.isMe(other)) then {
                    return answerConstructor(true, trials)
                }

                if(other.isDynamic) then {
                    return answerConstructor(true,trials)
                }

                if(other == anObjectType.doneType) then {
                    return answerConstructor(true, trials)
                } elseif{self == anObjectType.doneType} then {
                    return answerConstructor(false, trials)
                }

                var helperResult : Answer := answerConstructor(false, trials)

                // Divides subtyping into 4 cases
                if(self.getVariantTypes.size == 0) then {
                    if (other.getVariantTypes.size == 0) then {
                        //Neither self nor other are variant types
                        return self.isNonvariantSubtypeOf(trials, other)
                    } else {
                        //self is not a variant type; other is
                        for (other.getVariantTypes) do {t:ObjectType →
                            helperResult := self.isNonvariantSubtypeOf(trials, t)
                            if (helperResult.ans) then{
                                return helperResult
                            }
                        }
                        return helperResult
                    }
                } else {
                    if (other.getVariantTypes.size == 0) then {
                        //self is a variant type; other is not
                        for (self.getVariantTypes) do {t:ObjectType →
                            helperResult := t.isNonvariantSubtypeOf(trials, other)
                            if (helperResult.ans.not) then {
                                return helperResult
                            }
                        }
                        return helperResult
                    } else {
                        //Both self and other are variant types
                        for (self.getVariantTypes) do {t:ObjectType →
                            helperResult := t.isSubtypeHelper(helperResult.trials, other)
                            if (helperResult.ans.not) then {
                                return helperResult
                            }
                        }
                        return helperResult
                    }
                }
            }

            method restriction(other : ObjectType) → ObjectType {
                if (other.isDynamic) then { return dynamic}
                def restrictTypes:Set⟦ObjectType⟧ = emptySet
                // Restrict matching methods
                for(methods) doWithContinue { meth, continue →
                  // Forget restricting if it is a type
                  if (asString.substringFrom (1) to (7) != "Pattern") then {
                    for(other.methods) do { meth' →
                      if(meth.name == meth'.name) then {
                        restrictTypes.add(meth.restriction(meth'))
                        continue.apply
                      }
                    }
                  }
                  restrictTypes.add(meth)
                }
                return object {
                  //Joe - not sure how to handle restrict; probably wants to keep the types
                  //Maybe check if they share same type name and keep those?
                  inherit anObjectType.fromMethods(restrictTypes)

                  method asString → String is override {
                    "{outer}|{other}"
                  }
                }
            }

            // Consistent-subtyping:
            // If self restrict other is a subtype of other restrict self.
            method isConsistentSubtypeOf(other : ObjectType) → Boolean {
                return self.isSubtypeOf(other.resolve)

                //TODO: Fix restriction() so that it handles variant types
                //def selfRestType = self.restriction(other)
                //def otherRestType = other.restriction(self)
                //io.error.write "self's restricted type is {selfRestType}"
                //io.error.write "other's restricted type is {otherRestType}"

                //return selfRestType.isSubtypeOf(otherRestType)  //  FIX!!!
                //true
            }

            method getVariantTypes → List⟦ObjectType⟧ { variantTypes }

            method setVariantTypes(newVariantTypes:List⟦ObjectType⟧) → Done {
                variantTypes := newVariantTypes
            }

            // Variant
            // Construct a variant type from two object types.
            // Note: variant types can only be created by this constructor.
            method |(other' : ObjectType) → ObjectType {
                def other : ObjectType = other'.resolve
                if(self == other) then { return self }
                if(other.isDynamic) then { return dynamic }

                def combine: Set⟦MethodType⟧ = emptySet

                // Variant types of the new object.
                var newVariantTypes := list[]

                // If self is a variant type, add its variant types
                // to the new object type's variant types.
                // If self is not a variant type, add itself to the
                // new object type's variant types.
                if (self.getVariantTypes.size != 0) then {
                  newVariantTypes := newVariantTypes ++ self.getVariantTypes
                } else {
                  newVariantTypes.push(self)
                }

                // If other is a variant type, add its variant types
                // to the new object type's variant types.
                // If other is not a variant type, add itself to the
                // new object types's variant types.
                if (other.getVariantTypes.size != 0) then {
                  newVariantTypes := newVariantTypes ++ other.getVariantTypes
                } else {
                  newVariantTypes.push(other)
                }

                return object {
                    //Joe - save types in common | ignore
                    inherit anObjectType.fromMethods(combine)

                    // Set the new object type's variant types to equal
                    // the new variant types.
                    self.setVariantTypes(newVariantTypes)

                    method asString → String is override {
                        "{outer} | {other}"
                    }

                }
            }

            method &(other' : ObjectType) → ObjectType {
                def other : ObjectType = other'.resolve

                if(self == other) then { return self }
                if(other.isDynamic) then {
                    return dynamic
                }

                //components from performing &-operator on variant types
                def components:List⟦ObjectType⟧ = emptyList

                if(self.getVariantTypes.size == 0) then {
                    if (other.getVariantTypes.size == 0) then {
                        //Neither self nor other are variant types
                        return self.andHelper(other)
                    } else {
                        //self is not a variant type; other is
                        for (other.getVariantTypes) do {t:ObjectType →
                            components.add(self.andHelper(t))
                        }
                    }
                } else {
                    if (other.getVariantTypes.size == 0) then {
                        //self is a variant type; other is not
                        for (self.getVariantTypes) do {t:ObjectType →
                            components.add(other.andHelper(t))
                        }
                    } else {
                        //Both self and other are variant types
                        for (self.getVariantTypes) do {t:ObjectType →
                            components.add(t&(other))
                        }
                    }
                }
                //Helper method does not work with Done
                astVisitor.fromObjectTypeList(components)
            }

            //Make confidential
            method andHelper(other: ObjectType) → ObjectType {
                def combine: Set⟦ObjectType⟧ = emptySet
                def twice = emptySet

                // Produce union between two object types.
                for(methods) doWithContinue { meth, continue →
                    for(other.methods) do { meth':MethodType →
                        if(meth.nameString == meth'.nameString) then {
                            if(meth.isSpecialisationOf(emptyList,meth').ans) then {
                                combine.add(meth)
                            } elseif{meth'.isSpecialisationOf(emptyList,meth).ans} then {
                                combine.add(meth')
                            } else {
                                // TODO: Perhaps generate lub of two types?
                                TypeError.raise("cannot produce union of " ++
                                    "incompatible types '{self}' and '{other}' because of {meth'}")
                            }

                            twice.add(meth.name)

                            continue.apply
                        }
                    }
                    combine.add(meth)
                }

                for(other.methods) do { meth →
                    if(twice.contains(meth.name).not) then {
                        combine.add(meth)
                    }
                }

                def selfToPrint: ObjectType = self

                object {
                    //Joe - comeback and write checking for types of same name using subtyping
                    inherit anObjectType.fromMethods(combine)

                    //method asString → String is override {
                    //    "\{{self.methods}\} & {other}"
                    //}

                    method asString → String is override {
                        "{selfToPrint} & {other}"
                    }
                }
            }

            method asString → String is override {
                if(methods.size == base.methods.size) then { return "Object" }

                var out: String := "\{ "

                for(methods) do { mtype: MethodType →
                    if(base.methods.contains(mtype).not) then {
                        out := "{out}\n    {mtype}; "
                    }
                }

                return "{out}\n  \}"
            }
        }
    }

    method fromMethods(methods' : Set⟦MethodType⟧)
                                          withName(name : String) → ObjectType {
        object {
            inherit fromMethods(methods')

            method asString → String is override {
                if(methods.size == base.methods.size) then { return "Object" }

                var out: String := name

                for(methods') do { mtype: MethodType →
                    out := "{out}\{ "
                    if(base.methods.contains(mtype).not) then {
                        out := "{out}\n    {mtype}; "
                    }
                    out := "{out}\n  \}"
                }

                return "{out}"
            }

        }
    }

    //takes an AstNode and returns its corresponding ObjectType
    method fromDType(dtype: AstNode) → ObjectType {
        match(dtype) case { (false) →
            dynamic
        } case { typeDec : TypeDeclaration →
            ProgrammingError.raise "Types cannot be declared inside other types or objects"
        } case { typeLiteral : TypeLiteral →
            def meths : Set⟦MethodType⟧ = emptySet

            //collect MethodTypes
            for(typeLiteral.methods) do { mType : AstNode →
                meths.add(aMethodType.fromNode(mType))
            }

            anObjectType.fromMethods(meths)

        } case { op: Operator →
            // Operator takes care of type expressions: Ex. A & B, A | C
            // What type of operator (& or |)?
            var opValue: String := op.value

            // Left side of operator
            var left: AstNode := op.left
            var leftType: ObjectType := fromDType(left)

            // Right side of operator
            var right: AstNode := op.right
            var rightType: ObjectType := fromDType(right)

            match(opValue) case { "&" →
              leftType & rightType
            } case { "|" →
              leftType | rightType
            } case { _ →
              ProgrammingError.raise("Expected '&' or '|', got {opValue}") with(op)
            }

        } case { ident : Identifier →
            def oType : ObjectType = scope.types.findAtTop(ident.value)
                butIfMissing{ScopingError.raise("Failed to find {ident.value}")}

            //If the type we are referencing is unexpanded, then expand it and
            //update its entry in the type scope
            if(oType.isResolved) then{
                return oType
            } else {
                def resolvedOType : ObjectType = oType.resolve
                scope.types.addToTopAt(ident.value) put (resolvedOType)
                return resolvedOType
            }

        } case { generic : Generic →
            //should we raise an error or return dynamic if not found in scope?
            scope.types.findAtTop(generic.value.value)
                butIfMissing{ScopingError.raise("Failed to find {generic.value.value}")}

        } case { member : Member →
            def receiverName : String = member.receiver.nameString
            def memberCall : String = "{receiverName}.{member.value}"
            //all members processed here are references to types, so we can ignore
            //these receivers since types are always at the top level of the scope
            if((receiverName == "self") || (receiverName == "module()object")) then {
                scope.types.findAtTop (member.value) butIfMissing {
                    ScopingError.raise("Failed to find {memberCall}")
                }
            } else {
                scope.types.findAtTop(memberCall) butIfMissing {
                    ScopingError.raise("Failed to find {memberCall}")
                }
            }

        } case { str : StringLiteral →
            anObjectType.string

        } case { num : NumberLiteral →
            anObjectType.number

        } case { _ →
            ProgrammingError.raise "No case for node of kind {dtype.kind}" with(dtype)
        }
    }

    //Find ObjectType corresponding to the identifier in the scope
    method fromIdentifier(ident : Identifier) → ObjectType {
        io.error.write "\n1249 looking for {ident.value} inside {scope.types}"
        scope.types.find(ident.value) butIfMissing { dynamic }
    }

    method fromBlock(block: AstNode) → ObjectType {
        def bType = typeOf(block)

        if(bType.isDynamic) then { return dynamic }

        def numParams: Number = block.params.size
        def applyName: String = if (numParams == 0) then {
            "apply"
        } else {
            "apply({numParams})"
        }
        def apply: MethodType = bType.getMethod(applyName)

        match(apply) case { (noSuchMethod) →
            def strip = {x → x.nameString}
            TypeError.raise ("1000: the expression `{stripNewLines(block.toGrace(0))}` of " ++
                "type '{bType}' does not satisfy the type 'Block'") with(block)
        } case { meth : MethodType →
            return meth.returnType
        }
    }

    method fromBlockBody(body: Sequence⟦AstNode⟧) → ObjectType {
        if(body.size == 0) then {
            anObjectType.doneType
        } else {
            typeOf(body.last)
        }
    }

    method dynamic → ObjectType {
        object {
            def methods: Set⟦MethodType⟧ is public = sg.emptySet

            method getMethod(_ : String) → noSuchMethod { noSuchMethod }

            method resolve -> ObjectType { self }

            def isResolved : Boolean is public = true

            def isDynamic : Boolean is public = true

            method ==(other:ObjectType) → Boolean{self.isMe(other)}

            method isSubtypeOf(_ : ObjectType) → Boolean { true }

            method isSubtypeHelper (_ : List⟦TypePair⟧, _ : ObjectType) → Answer {
                answerConstructor(true , emptyList)
            }

            method restriction(_ : ObjectType) → dynamic { dynamic }

            method isConsistentSubtypeOf(_ : ObjectType) → Boolean { true }

            method getVariantTypes → List⟦ObjectType⟧ { emptyList }

            method setVariantTypes(newVariantTypes:List⟦ObjectType⟧) → Done { }

            method |(_ : ObjectType) → dynamic { dynamic }

            method &(_ : ObjectType) → dynamic { dynamic }

            def asString : String is public, override = "Unknown"

        }
    }

    method bottom → ObjectType {
        object {
            inherit dynamic
            def isDynamic : Boolean is public, override = false
            def asString : String is public, override = "Bottom"
        }
    }

    method blockTaking(params : List⟦Parameter⟧)
            returning(rType : ObjectType) → ObjectType {
        def signature = list[aMixPartWithName("apply") parameters(params)]
        def meths: Set⟦MethodType⟧ = emptySet
        meths.add(aMethodType.signature(signature) returnType(rType))

        //Joe - Is there anytime where we want to save the internal types?
        //when a block has name??
        //when the last statement is an object or a typeDec?
        //In here we don't get the astNode; look at returnType?
        fromMethods(meths) withName("Block")
    }

    method blockReturning(rType : ObjectType) → ObjectType {
        blockTaking(list[]) returning(rType)
    }

    // add method to oType.  Only use this variant if method is parameterless
    method addTo (oType : ObjectType) name (name' : String)
            returns (rType : ObjectType) → Done is confidential {
        def signature = list[aMixPartWithName(name') parameters(list[])]
        oType.methods.add (aMethodType.signature(signature) returnType(rType))
    }

    // add method to oType.  Only use this variant if one part with one or more
    // parameters
    method addTo (oType : ObjectType) name (name' : String)
            params (ptypes : List⟦ObjectType⟧) returns (rType : ObjectType)
            → Done is confidential {
        def parameters = list[]
        for(ptypes) do { ptype →
            parameters.push(aParam.ofType(ptype))
        }

        def signature = list[aMixPartWithName(name') parameters (parameters)]

        oType.methods.add (aMethodType.signature(signature) returnType (rType))
    }

    // add method to oType.  Only use this variant for method with one part
    // and exactly one parameter
    method addTo (oType : ObjectType) name (name' : String)
            param(ptype : ObjectType) returns (rType : ObjectType)
            → Done is confidential {
        def parameters = list[aParam.ofType(ptype)]

        def signature = list[aMixPartWithName(name') parameters(parameters)]

        oType.methods.add (aMethodType.signature(signature) returnType(rType))
    }

    // add method to oType.  Only use if more than one part.
    method addTo (oType: ObjectType) names (name: List⟦String⟧)
         parts(p: List⟦List⟦ObjectType⟧ ⟧) returns (rType: ObjectType) → Done
                                    is confidential{
         def parts: List⟦List⟦Param⟧⟧ = list[]
         var nameString: String := ""
         for (p) do { part: List⟦ObjectType⟧ →
             def parameters: List⟦Param⟧ = list[]
             for (part) do {ptype: ObjectType →
                 parameters.push(aParam.ofType(ptype))
             }
             parts.push(parameters)
         }

         def signature: List⟦MixPart⟧ = list[]
         for (1 .. name.size) do {i →
             signature.push(aMixPartWithName (name.at(i)) parameters (parts.at(i)))
         }
         oType.methods.add (aMethodType.signature (signature) returnType (rType))
    }


    method extend(this : ObjectType) with(that : ObjectType)
            → Done is confidential {
        this.methods.addAll(that.methods)
    }

    // TODO: Make sure get everything from standardGrace and
    // StandardPrelude
    var base : ObjectType is readable := dynamic
    def doneType : ObjectType is public = fromMethods(sg.emptySet) withName("Done")
    base := fromMethods(sg.emptySet) withName("Object")

    //Used for type-checking imports; please update when additional types are added
    def preludeTypes: Set⟦String⟧ is public = ["Pattern", "Iterator", "Boolean", "Number",
                                    "String", "List", "Set", "Sequence",
                                    "Dictionary", "Point", "Binding",
                                    "Collection", "Enumerable", "Range"]

    def pattern : ObjectType is public = fromMethods(sg.emptySet) withName("Pattern")
    def iterator : ObjectType is public = fromMethods(sg.emptySet) withName("Iterator")
    def boolean : ObjectType is public = fromMethods(sg.emptySet) withName("Boolean")
    def number : ObjectType is public = fromMethods(sg.emptySet) withName("Number")
    def string : ObjectType is public = fromMethods(sg.emptySet) withName("String")
    def listTp : ObjectType is public = fromMethods(sg.emptySet) withName("List")
    def set : ObjectType is public = fromMethods(sg.emptySet) withName("Set")
    def sequence : ObjectType is public = fromMethods(sg.emptySet) withName("Sequence")
    def dictionary : ObjectType is public = fromMethods(sg.emptySet) withName("Dictionary")
    def point : ObjectType is public = fromMethods(sg.emptySet) withName("Point")
    def binding : ObjectType is public = fromMethods(sg.emptySet) withName("Binding")
    def collection : ObjectType is public = fromMethods(sg.emptySet) withName("Collection")
    def enumerable : ObjectType is public = fromMethods(sg.emptySet) withName("Enumerable")
    def rangeTp : ObjectType is public = fromMethods(sg.emptySet) withName("Range")
    def prelude: ObjectType is public = fromMethods(sg.emptySet) withName("Prelude")
    def boolBlock: ObjectType is public = fromMethods(sg.emptySet) withName("BoolBlock")
    def doneBlock: ObjectType is public = fromMethods(sg.emptySet) withName("DoneBlock")
    def dynamicDoneBlock: ObjectType is public = fromMethods(sg.emptySet) withName("DynamicDoneBlock")

//    addTo (base) name ("==") param(base) returns(boolean)
    addTo (base) name ("≠") param(base) returns(boolean)
    addTo (base) name ("hash") returns(number)
//    addTo (base) name ("match") returns(dynamic)
    addTo (base) name ("asString") returns(string)
    addTo (base) name ("basicAsString") returns(string)
    addTo (base) name ("asDebugString") returns(string)
//    addTo (base) name ("debugValue") returns(string)
//    addTo (base) name ("debugIterator") returns(iterator)
    addTo (base) name ("::") returns(binding)
    addTo (base) name ("list") param(collection) returns(listTp)

    extend (pattern) with (base)
    addTo (pattern) name ("match") param (base) returns (dynamic)
    addTo (pattern) name ("|") param (pattern) returns (pattern)
    addTo (pattern) name("&") param (pattern) returns (pattern)

    extend (iterator) with (base)
    addTo (iterator) name ("hasNext") returns (boolean)
    addTo (iterator) name ("next") returns (dynamic)

    def shortCircuit: ObjectType =
        blockTaking (list[aParam.ofType(blockReturning(dynamic))]) returning (base)
    extend (boolean) with(base)
    addTo (boolean) name("&&") param(boolean) returns(boolean)
    addTo (boolean) name("||") param(boolean) returns(boolean)
    addTo (boolean) name("prefix!") returns(boolean)
    addTo (boolean) name("not") returns(boolean)
    addTo (boolean) name("andAlso") param(shortCircuit) returns(dynamic)
    addTo (boolean) name("orElse") param(shortCircuit) returns(dynamic)

    extend (number) with(base)
    addTo (number) name("+") param(number) returns(number)
    addTo (number) name("*") param(number) returns(number)
    addTo (number) name("-") param(number) returns(number)
    addTo (number) name("/") param(number) returns(number)
    addTo (number) name("^") param(number) returns(number)
    addTo (number) name("%") param(number) returns(number)
    addTo (number) name("@") param(number) returns(point)
    addTo (number) name("hashcode") returns(string)
    addTo (number) name("++") param(base) returns(string)
    addTo (number) name("<") param(number) returns(boolean)
    addTo (number) name(">") param(number) returns(boolean)
    addTo (number) name("<=") param(number) returns(boolean)
    addTo (number) name("≤") param(number) returns(boolean)
    addTo (number) name(">=") param(number) returns(boolean)
    addTo (number) name("≥") param(number) returns(boolean)
    addTo (number) name("..") param(number) returns(listTp)
    addTo (number) name("asInteger32") returns(number)
    addTo (number) name("prefix-") returns(number)
    addTo (number) name("inBase") param(number) returns(number)
    addTo (number) name("truncated") returns(number)
    addTo (number) name("rounded") returns(number)
    addTo (number) name("prefix<") returns(pattern)
    addTo (number) name("prefix>") returns(pattern)
    addTo (number) name("abs") returns(number)

    def ifAbsentBlock: ObjectType = blockTaking (list[]) returning (dynamic)
    def stringDoBlock: ObjectType = blockTaking (list[aParam.ofType(string)])
            returning(doneType)
    def stringKeysValuesDoBlock: ObjectType =
        blockTaking (list[aParam.ofType(number), aParam.ofType(string)])
           returning (doneType)
    extend (string) with(base)
    addTo (string) name("*") param(number) returns(string)
    addTo (string) name("&") param(pattern) returns(pattern)
    addTo (string) name("++") param(base) returns(string)
    addTo (string) name(">") param(string) returns(boolean)
    addTo (string) name(">=") param(string) returns(boolean)
    addTo (string) name("<") param(string) returns(boolean)
    addTo (string) name("<=") param(string) returns(boolean)
    addTo (string) name("≤") param(string) returns(boolean)
    addTo (string) name("≥") param(string) returns(boolean)
    addTo (string) name("at") param(number) returns(string)
    addTo (string) name("asLower") returns(string)
    addTo (string) name("asNumber") returns(number)
    addTo (string) name("asUpper") returns(string)
    addTo (string) name("capitalized") returns(string)
    addTo (string) name("compare") param(string) returns(boolean)
    addTo (string) name("contains") param(string) returns(boolean)
    addTo (string) name("encode") returns(string)
    addTo (string) name("endsWith") param(string) returns(boolean)
    addTo (string) name ("indexOf") param(string) returns (number)
    addTo(string) names (list["indexOf","startingAt"])
           parts(list [ list[string], list[number] ]) returns (number)
//    addTo(string) names(["indexOf","startingAt","ifAbsent"])
//           parts([ [string], [number],[ifAbsentBlock] ]) returns(number | dynamic)
//    addTo(string) names(["indexOf","startingAt","ifAbsent"])
//           parts([ [string], [number],[ifAbsentBlock] ]) returns(number | dynamic)
    addTo (string) name ("lastIndexOf") param(string) returns(number)
    addTo (string) names (list["lastIndexOf","startingAt"])
           parts(list[ list[string], list[number] ]) returns (number)
//    addTo(string) names(["lastIndexOf","ifAbsent"]) parts([ [string], [ifAbsentBlock] ]) returns(number | dynamic)
//    addTo(string) names(["lastIndexOf","startingAt","ifAbsent"]) parts([ [string], [number],[ifAbsentBlock] ]) returns(number | dynamic)
    addTo(string) name ("indices") returns(listTp)
    addTo(string) name("isEmpty") returns(boolean)
    addTo(string) name("iterator") returns(base)
    addTo(string) name("lastIndexOf") param(string) returns(number)
//    addTo(string) name("lastIndexOf()ifAbsent") params(string, ifAbsentBlock) returns(number | dynamic)
//    addTo(string) name("lastIndexOf()startingAt()ifAbsent") params(string, ifAbsentBlock) returns(number | dynamic)
    addTo(string) name("ord") returns(number)
    addTo(string) names(list["replace","with"]) parts(list[ list[string], list[string] ]) returns(string)
    addTo(string) name("size") returns(number)
    addTo(string) name("startsWith") param(string) returns(boolean)
    addTo(string) name("startsWithDigit") returns(boolean)
    addTo(string) name("startsWithLetter") returns(boolean)
    addTo(string) name("startsWithPeriod") returns(boolean)
    addTo(string) name("startsWithSpace") returns(boolean)
    addTo(string) names(list["substringFrom","size"])
        parts(list[ list[number], list[number] ]) returns(string)
    addTo(string) names(list["substringFrom","to"])
        parts(list[ list[number], list[number] ]) returns(string)
    addTo(string) name("_escape") returns(string)
    addTo(string) name("trim") returns(string)
    addTo(string) name("do") param(stringDoBlock) returns (doneType)
    addTo(string) name("size") returns(number)
    addTo(string) name("iter") returns(iterator)

    extend(point) with(base)
    addTo(point) name("x") returns(number)
    addTo(point) name("y") returns(number)
    addTo(point) name("distanceTo") param(point) returns(number)
    addTo(point) name("+") param(point) returns(point)
    addTo(point) name("-") param(point) returns(point)
    addTo(point) name("*") param(point) returns(point)
    addTo(point) name("/") param(point) returns(point)
    addTo(point) name("length") returns(number)

    def fold: ObjectType = blockTaking(list[aParam.ofType(dynamic), aParam.ofType(dynamic)])
        returning (dynamic)
    extend (listTp) with (base)
    addTo (listTp) name("at") param(number) returns(dynamic)
    addTo(listTp) names(list["at","put"]) parts(list[ list[number], list[dynamic] ]) returns(doneType)
    addTo(listTp) name("push") param(dynamic) returns(doneType)
    addTo(listTp) name("add") param(dynamic) returns(listTp)
    addTo(listTp) name("addFirst") param(dynamic) returns(listTp)   // need to add varparams
    addTo(listTp) name("addLast") param(dynamic) returns(listTp)
    addTo(listTp) name("addAll") param(listTp) returns(listTp)
    addTo(listTp) name("pop") returns(dynamic)
    addTo(listTp) name("size") returns(number)
    addTo(listTp) name("iter") returns(iterator)
    addTo(listTp) name("iterator") returns(iterator)
    addTo(listTp) name("contains") param(dynamic) returns(boolean)
    addTo(listTp) name("indexOf") param(dynamic) returns(number)
    addTo(listTp) name("indices") returns(listTp)
    addTo(listTp) name("first") returns(dynamic)
    addTo(listTp) name("last") returns(dynamic)
    addTo(listTp) name("prepended") param(dynamic) returns(listTp)
    addTo(listTp) name("++") param(listTp) returns (listTp)
    addTo(listTp) name("reduce") params(list[dynamic, fold]) returns (dynamic)
    addTo(listTp) name("reversed") returns(dynamic)
    addTo(listTp) name("removeFirst") returns(dynamic)
    addTo(listTp) name("removeLast") returns(dynamic)
    addTo(listTp) name("removeAt") param(number) returns(dynamic)
    addTo(listTp) name("remove") param(dynamic) returns(listTp)
    addTo(listTp) name("removeAll") param(listTp) returns(listTp)
    addTo(listTp) name("copy") returns(listTp)
    addTo(listTp) name("sort") returns(listTp)
    addTo(listTp) name("reverse") returns(listTp)


    extend(binding) with(base)
    addTo(binding) name("key") returns(dynamic)
    addTo(binding) name("value") returns(dynamic)

    addTo(boolBlock) name("apply") returns(boolean)
    addTo(doneBlock) name("apply") returns(doneType)


    addTo (prelude) name("print") param(base) returns(doneType)
    addTo (prelude) names(list["while", "do"]) parts(list[list[boolBlock], list[doneBlock] ]) returns(doneType)
    addTo (prelude) names(list["for", "do"]) parts(list[list[listTp], list[dynamicDoneBlock] ]) returns(doneType)

    scope.types.at("Unknown") put(dynamic)
    scope.types.at("Done") put(doneType)
    scope.types.at("Object") put(base)
    scope.types.at("Pattern") put(pattern)
    scope.types.at("Boolean") put(boolean)
    scope.types.at("Number") put(number)
    scope.types.at("String") put(string)
    scope.types.at("List") put(listTp)
    scope.types.at("Set") put(set)
    scope.types.at("Sequence") put(sequence)
    scope.types.at("Dictionary") put(dictionary)
    scope.types.at("Point") put(point)
    scope.types.at("Binding") put(binding)
    scope.types.at("Range") put(rangeTp)

    addVar("Unknown") ofType(pattern)
    addVar("Dynamic") ofType(pattern)
    addVar("Done") ofType(pattern)
    addVar("Object") ofType(pattern)
    addVar("Pattern") ofType(pattern)
    addVar("Boolean") ofType(pattern)
    addVar("Number") ofType(pattern)
    addVar("String") ofType(pattern)
    addVar("List") ofType(pattern)
    addVar("Set") ofType(pattern)
    addVar("Sequence") ofType(pattern)
    addVar("Dictionary") ofType(pattern)
    addVar("Point") ofType(pattern)
    addVar("Binding") ofType(pattern)
    addVar("Range") ofType(pattern)

    addVar("done") ofType(self.doneType)
    addVar("true") ofType(boolean)
    addVar("false") ofType(boolean)
    addVar("prelude") ofType (prelude)
}

// Adds name to variables and as parameterless method (really def, not var!)
method addVar (name : String) ofType (oType : ObjectType) → Done is confidential {
    scope.variables.at (name) put (oType)
    scope.methods.at (name) put (aMethodType.member(name) ofType(oType))
}

// Exceptions while type-checking.
def ObjectError: outer.ExceptionKind = TypeError.refine("ObjectError")

// Class declaration.
def ClassError: outer.ExceptionKind = TypeError.refine("Class TypeError")

def MethodError = TypeError.refine("Method TypeError")

// Def and var declarations.
def DefError: outer.ExceptionKind = TypeError.refine("Def TypeError")

// Scoping error declaration
def ScopingError: outer.ExceptionKind = TypeError.refine("ScopingError")

// type of part of method request
type RequestPart = {
   args → List⟦AstNode⟧
   args:=(a: List⟦AstNode⟧) → Done
}

type RequestPartFactory = {
   new → RequestPart
   request(name: String) withArgs(argList) scope (s) → RequestPart
   request(rPart) withArgs (sx) → RequestPart
}

// Check if the signature and parameters of a request match
// the declaration, return the type of the result
method check(req : Request)
        against(meth : MethodType) → ObjectType is confidential {
    def name: String = meth.name   // CHANGE TO NAMESTRING

    for(meth.signature) and(req.parts) do { sigPart: MixPart, reqPart: RequestPart →
        def params: List⟦Param⟧ = sigPart.parameters
        def args: Collection⟦AstNode⟧   = reqPart.args

        def pSize: Number = params.size
        def aSize: Number = args.size

        if(aSize != pSize) then {
            def which: String = if(aSize > pSize) then { "many" } else { "few" }
            def where: Number = if(aSize > pSize) then {
                args.at(pSize + 1)
            } else {
            // Can we get beyond the final argument?
                req.value
            }

            outer.RequestError
                .raise("too {which} arguments to method part " ++
                    "'{sigPart.name}', expected {pSize} but got {aSize}")
                    with(where)
        }

        for (params) and (args) do { param: Param, arg: AstNode →
            def pType: ObjectType = param.typeAnnotation
            def aType: ObjectType = typeOf(arg)
            io.error.write ("\n1631 Checking {arg} of type {aType} is subtype of {pType}"++
                "\nwhile checking {req} against {meth}")
            if (aType.isConsistentSubtypeOf (pType).not) then {
                outer.RequestError.raise("the expression " ++
                    "`{stripNewLines(arg.toGrace(0))}` of type '{aType}' does not " ++
                    "satisfy the type of parameter '{param}' in the " ++
                    "method '{name}'") with(arg)
            }
        }
    }
    meth.returnType
}

// Throw error only if type of node is not consistent subtype of eType
method check (node: AstNode) matches(eType : ObjectType)
        inMethod (name : String) → Done is confidential {
    def aType: ObjectType = typeOf(node)
    if (aType.isConsistentSubtypeOf (eType).not) then {
        MethodError.raise("the method '{name}' declares a result of " ++
            "type '{eType}', but returns an expression of type " ++
            "'{aType}'") with (node)
    }
}

// break of input string into list of strings as divided by separator
method split(input : String, separator : String) → List⟦String⟧ {
    var start: Number := 1
    var end: Number := 1
    var output: List⟦ List⟦String⟧ ⟧ := list[]
    while {end < input.size} do {
        if (input.at(end) == separator) then {
            var cand := input.substringFrom(start)to(end-1)
            if (cand.size > 0) then {
                output.push(cand)
            }
            start := end + 1
        }
        end := end + 1
    }
    output.push(input.substringFrom(start)to(end))
    return output
}

// Pair of public and confidential types of an expression
// Generating objects
type PublicConfidential = {
    publicType → ObjectType
    inheritableType → ObjectType | false
}

// Returns pair of public and confidential type of expression that can be
// inherited from
class pubConf(pType: ObjectType,cType: ObjectType ) → PublicConfidential{
    method publicType → ObjectType {pType}
    method inheritableType → ObjectType {cType}
    method asString → String {
        "confidential type is {cType}\npublic type is {pType}"
    }
}


// Static type checker visitor
// methods return false if goes no further recursively
def astVisitor: ast.AstVisitor is public= object {
    inherit ast.baseVisitor

    // Default behavior serving as placeholder only for cases not yet implemented
    method checkMatch(node: AstNode) → Boolean {
        io.error.write "1436: checkMatch in astVisitor"
        true
    }

    // type-check if statement
    method visitIf (ifnode: If) → Boolean {
        def cond: AstNode = ifnode.value
        if (typeOf (cond).isConsistentSubtypeOf (anObjectType.boolean).not) then {
            outer.RequestError.raise("1366: the expression `{stripNewLines(cond.toGrace(0))}` does not " ++
                "satisfy the type 'Boolean' for an 'if' condition'") with (cond)
        }

        def thenType: ObjectType = anObjectType.fromBlock(ifnode.thenblock)

        def hasElse: Boolean = ifnode.elseblock.body.size > 0
        def elseType: ObjectType = if (hasElse) then {
            anObjectType.fromBlock(ifnode.elseblock)
        } else {
            anObjectType.doneType
        }

        // type of expression is whichever branch has largest type.
        // If incompatible return variant formed by the two types
        def ifType: ObjectType = if (hasElse) then {
            if (thenType.isConsistentSubtypeOf (elseType)) then {
                elseType
            } elseif {elseType.isConsistentSubtypeOf(thenType)} then {
                thenType
            } else {
                thenType | elseType
            }
        } else {
            anObjectType.doneType
        }

        // save type in cache
        cache.at (ifnode) put (ifType)
        false
    }

    // Type check block.  Fails if don't give types to block parameters
    // Should it?
    // params are identifier nodes.
    method visitBlock (block: AstNode) → Boolean {
        // Raises exception if block parameters not given types
        for (block.params) do {p→
            if (((p.kind == "identifier") || {p.wildcard.not}) && {p.decType.value=="Unknown"}) then {
                CheckerFailure.raise("no type given to declaration"
                    ++ " of parameter '{p.value}'") with (p)
            }
        }

        def body = sequence(block.body)
        var retType: ObjectType

        scope.enter {
            for(block.params) do { param →
                // Isn't param always a string?Special cases when using match
                // where pattern is string literal or number
                // I'm not sure this is right.  Doesn't seem like anything should be added
                // for literals!
                match (param)
                  case { _ : StringLiteral | NumberLiteral→
                    //scope.variables.at(param.value)
                    //    put(anObjectType.fromDType(param))
              //} case { _ : NumberLiteral →
                    //scope.variables.at(param.value)
                    //    put(anObjectType.fromDType(param))
                } case { _ →
                    io.error.write("\n1517: {param.value} has {param.dtype}")
                    scope.variables.at(param.value)
                                      put(anObjectType.fromDType(param.dtype))
                }
            }


            collectTypes(body)

            for(body) do { stmt: AstNode →
                checkTypes(stmt)
            }

            retType := anObjectType.fromBlockBody(body)
        }
        // At this point, know block type checks.

        // Now compute type of block and put in cache
        def parameters = list[]
        for(block.params) do { param: AstNode →
            match (param)
              case { _:StringLiteral →
                parameters.push(aParam.withName(param.value)
                                    ofType(anObjectType.fromDType(param)))
            } case { _:NumberLiteral →
                parameters.push(aParam.withName(param.value)
                                    ofType(anObjectType.fromDType(param)))
            } case { _ →
                parameters.push(aParam.withName(param.value)
                                    ofType(anObjectType.fromDType(param.dtype)))
            }
        }

        def blockType: ObjectType = anObjectType.blockTaking(parameters)
            returning(retType)

        cache.at (block) put (blockType)
        io.error.write "block has type {blockType}"
        false
    }

    method visitMatchCase (node: MatchCase) → Boolean {
        def matchee = node.value
        var matcheeType: ObjectType := typeOf(matchee)
        //Note: currently only one matchee is supported
        var paramTypesList: List⟦ObjectType⟧ := emptyList
        var returnTypesList: List⟦ObjectType⟧ := emptyList
        var paramType: ObjectType
        var returnType: ObjectType

        //goes through each case{} and accumulates its parameter and return types
        for(node.cases) do{block →

          if(block.params.size != 1) then{
            outer.RequestError.raise("1518: The case you are matching to, " ++
              "{stripNewLines(block.toGrace(0))}, has more than one argument "++
              "on the left side. This is not currently supported.") with (matchee)
          }

          //If param is a general case(ie. n:Number), accumulate its type to
          //paramTypesList; ignore if it is a specific case(ie. 47)
          def blockParam : Parameter = block.params.at(1)
          match (blockParam.dtype)
            case{ s:StringLiteral →
              io.error.write"\n Got StringLiteral"
          } case{ n:NumberLiteral →
              io.error.write"\n Got NumberLiteral"
          } case{ t:true →
              io.error.write"\n Got BooleanLiteral"
          } case{ f:false →
              io.error.write"\n Got BooleanLiteral"
          } case{ _ →
              def typeOfParam = anObjectType.fromDType(blockParam.decType)

              if (paramTypesList.contains(typeOfParam).not) then {
                  paramTypesList.add(typeOfParam)
              }
          }

          //Return type collection
          def blockReturnType : ObjectType = anObjectType.fromBlock(block)
          if (returnTypesList.contains(blockReturnType).not) then {
            returnTypesList.add(blockReturnType)
          }
        }

        //io.error.write("\n\nThe paramTypesList contains {paramTypesList}\n")
        //io.error.write("\n\nThe returnTypesList contains {returnTypesList}\n")

        paramType := fromObjectTypeList(paramTypesList)
        returnType := fromObjectTypeList(returnTypesList)

        io.error.write "\nparamType now equals: {paramType}"
        io.error.write "\nreturnType now equals: {returnType}"

        if (matcheeType.isSubtypeOf(paramType).not) then {
          outer.TypeError.raise("1519: the matchee `{stripNewLines(matchee.toGrace(0))}`"++
            " of type {matcheeType} does not " ++
            "match the type(s) {paramTypesList} of the case(s)") with (matchee)
        }

        cache.at(node) put (returnType)

        false
    }

    //Takes a non-empty list of objectTypes and combines them into a variant type
    method fromObjectTypeList(oList : List⟦ObjectType⟧)→ObjectType{
      var varType: ObjectType := oList.at(1)
      var index:Number := 2
      while{index<=oList.size}do{

        //Combine types that are subsets of one-another
        if (varType.isSubtypeOf (oList.at(index))) then {
            varType := oList.at(index)
        } elseif {oList.at(index).isSubtypeOf(varType).not} then {
            varType := varType | oList.at(index)
        }

        index := index +1
      }
      varType

    }



    // not implemented yet
    method visitTryCatch (node) → Boolean {
        io.error.write "\n1544: TryCatch visit not implemented yet\n"
        checkMatch (node)
    }

//    method visitMethodType (node) → Boolean {
//        io.error.write "\n1549: visiting method type {node} not implemented\n"
//
//        runRules (node)
//
//        node.parametersDo { param →
//            runRules (parameterFromNode(param))
//        }
//
//        return false
//    }

//    method visitType (node) → Boolean {
//        io.error.write "\n1561: visiting type {node} (not implemented)\n"
//        checkMatch (node)
////        io.error.write "432: done visiting type {node}"
//    }

    method visitMethod (meth: AstNode) → Boolean {
        io.error.write "\n1567: Visiting method {meth}\n"

        // ensure all parameters have known types and provide return type
        for (meth.signature) do {s: AstNode →
            for (s.params) do {p: AstNode →
                if ((p.kind == "identifier") && {p.wildcard.not} && {p.decType.value=="Unknown"}) then {
                    CheckerFailure.raise("no type given to declaration"
                        ++ " of parameter '{p.value}'") with (p)
                }
            }
        }
        if (meth.decType.value=="Unknown") then {
            CheckerFailure.raise ("no return type given to declaration"
                ++ " of method '{meth.value.value}'") with (meth.value)
        }

        // meth.value is Identifier Node
        def name: String = meth.value.value
        def mType: MethodType = aMethodType.fromNode(meth)
        def returnType: ObjectType = mType.returnType

        io.error.write "\n1585: Entering scope for {meth}\n"
        scope.enter {
            for(meth.signature) do { part: AstNode →
                for(part.params) do { param: AstNode →
                    scope.variables.at(param.value)
                        put(anObjectType.fromDType(param.dtype))
                }
            }

            collectTypes((meth.body))
            io.error.write "\n1595: collected types for {list(meth.body)}\n"

            for(meth.body) do { stmt: AstNode →
                checkTypes(stmt)

                // Write visitor to make sure return statements have right type
                stmt.accept(object {
                    inherit ast.baseVisitor

                    method visitReturn(ret) → Boolean is override {
                        check (ret.value) matches (returnType) inMethod (name)
                        // note sure why record returnType?
                        cache.at(ret) put (returnType)
                        return false
                    }

                    method visitMethod(node) → Boolean is override {
                        false
                    }
                })
            }

            if(meth.body.size == 0) then {
                if(anObjectType.doneType.isConsistentSubtypeOf(returnType).not) then {
                    MethodError.raise("the method '{name}' declares a " ++
                        "result of type '{returnType}', but has no body") with (meth)
                }
            } else {
                def lastNode: AstNode = meth.body.last
                if (Return.match(lastNode).not) then {
                    def lastType = typeOf(lastNode)
                    if(lastType.isConsistentSubtypeOf(returnType).not) then {
                        MethodError.raise("the method '{name}' declares a " ++
                            "result of type '{returnType}', but returns an " ++
                            "expression of type '{lastType}'") with (lastNode)
                    }
                }
                io.error.write ("\n2048 type of lastNode in method {meth.nameString}" ++
                                                    " is {lastNode.kind}")
                if (lastNode.kind == "object") then {
                    visitObject(lastNode)
                    def confidType: ObjectType = allCache.at(lastNode)
                    allCache.at(meth.nameString) put (confidType)
                    io.error.write "\n2053 confidType is {confidType} for {meth.nameString}"
                }
            }
        }

        // if method is just a member name then can record w/variables
        if (isMember(mType)) then {
            scope.variables.at(name) put(returnType)
        }

        // always record it as a method
        scope.methods.at(name) put(mType)

        cache.at(meth) put (anObjectType.doneType)
        false

    }

    method visitCall (req) → Boolean {
        def rec: AstNode = req.receiver

        io.error.write "\n1673: visitCall's call is: {rec.nameString}.{req.nameString}"
        //io.error.write "\nTypes scope at visitCall is : {scope.types}"\
        //io.error.write "\nVariable scope at visitCall is : {scope.variables}"

        var tempDef := scope.variables.find("$elf") butIfMissing{anObjectType.dynamic}
        //io.error.write "\nCache at visitCall is: {cache}"

        // receiver type
        def rType: ObjectType = if(rec.isIdentifier &&
            {(rec.nameString == "self") || (rec.nameString =="module()object")}) then {
            io.error.write "\n1675: looking for type of self"
            scope.variables.find("$elf") butIfMissing {
                Exception.raise "type of self missing" with(rec)
            }
        } else {
            io.error.write "\n2085 rec.kind = {rec.kind}"
            typeOf(rec)
        }
        //io.error.write "\n1680: type of receiver {rec} is {typeOf(rec)}"
        //io.error.write "\n1681: rType is {rType}"

        def callType: ObjectType = if (rType.isDynamic) then {
            io.error.write "rType: {rType} is dynamic}"
            anObjectType.dynamic
        } else {
            //Since we can't have a method or a type with the same name. A call
            //on a name can be searched in both method and type lists
            //Just have to assume that the programmer used nonconflicting names- Joe

            var name: String := req.nameString
            if (name.contains "$object(") then {
                req.parts.removeLast
                name := req.nameString
            }
            def completeCall : String = "{req.receiver.nameString}.{req.nameString}"
            io.error.write "\n2154: {completeCall}"
            io.error.write "\n2155: {req.nameString}"
            io.error.write "\nrequest on {name}"

            io.error.write "\n2000: rType.methods is: {rType.methods}"
            match(rType.getMethod(name))
              case { (noSuchMethod) →
                io.error.write "\n2001: got to case noSuchMethod"
                io.error.write "\n2002: scope here is {scope.types}"
                scope.types.findAtTop(completeCall) butIfMissing {
                    //Joe - possibly come back and change error msg maybe
                    //less informative, but less confusing msg

                    outer.RequestError.raise("no such method or type'{name}' in " ++
                        "`{stripNewLines(rec.toGrace(0))}` of type\n" ++
                        "    '{rType}' \nin type \n  '{rType.methods}'")
                            with(req)
                }
            } case { meth : MethodType →
                io.error.write "\nchecking request {req} against {meth}"
                check(req) against(meth)
            }
        }
        io.error.write "\n1701: callType: {callType}"
        cache.at(req) put (callType)
        true  // request to continue on arguments
    }

    // returns false so don't recurse into object
    method visitObject (obj :AstNode) → Boolean {
        def pcType: PublicConfidential = scope.enter {
            processBody (list (obj.value), obj.superclass)
        }
        cache.at(obj) put (pcType.publicType)
        allCache.at(obj) put (pcType.inheritableType)
        io.error.write "\n1971: *** Visited object {obj}"
        io.error.write (pcType.asString)
        io.error.write "\n2153: Scope at end is: {scope.methods}"
        false
    }

    //Process dialects and import statements
    //TODO: handle dialects
    method visitModule (node: AstNode) → Boolean {  // added kim
        io.error.write "\n1698: visiting module {node}"

        def importNodes: List⟦AstNode⟧ = emptyList
        def bodyNodes: List⟦AstNode⟧ = list(node.value)

        //goes through the body of the module and processes imports
        for (bodyNodes) do{ nd : AstNode →
            match (nd)
              case {imp: Import →
                //visitimport processes the import and puts its type on
                //the variable scope and method scope
                visitImport(imp)
                importNodes.add(nd)
          //} case {dialect}
            } case {_:Object → }//do nothing
        }

        //removes import statements from the body of the module
        for(importNodes) do{nd : AstNode →
            bodyNodes.remove(nd)
        }

        def withoutImport : AstNode = ast.moduleNode.body(bodyNodes)
                                named (node.nameString) scope (node.scope)
        io.error.write "\n2186 Types scope before collecing types is {scope.types}"
        collectTypes (list (withoutImport.body))
        io.error.write "\n2186 Types scope after collecing types is {scope.types}"

        visitObject (withoutImport)
    }

    // array literals represent collections (should fix to be lineups)
    method visitArray (lineUpLiteral) → Boolean {
        io.error.write "\n1704: visiting array {lineUpLiteral}"
        cache.at (lineUpLiteral) put (anObjectType.collection)
        false
    }

    // members are treated like calls
    method visitMember (node: AstNode) → Boolean {
        visitCall (node)
    }

    method visitGeneric (node: AstNode) → Boolean {
        io.error.write "\n1715: visiting generic {node} (not implemented)"
        checkMatch (node)
    }

    // look up identifier type in scope
    method visitIdentifier (ident: AstNode) → Boolean {
        //io.error.write "\nvisitIdentifier scope.variables processing node
        //    {ident} is {scope.variables}"
        def idType: ObjectType = match(ident.value)
          case { "outer" →
            outerAt(scope.size)
        } case { _ →
            scope.variables.find(ident.value) butIfMissing { anObjectType.dynamic }
        }
        cache.at (ident) put (idType)
        true

    }

    method visitTypeDec(node: TypeDeclaration) → Boolean {
        cache.at(node) put (anObjectType.fromDType(node.value))
        false
    }

    // Fix later
    method visitOctets (node: AstNode) → Boolean {
        io.error.write "\n1736: visiting Octets {node} (not implemented)"
        false
    }

    // type of string is String
    // Why do these return true?  Nothing to recurse on.
    method visitString (node: AstNode) → Boolean {
        cache.at (node) put (anObjectType.string)
        true
    }

    // type of number is Number
    method visitNum (node: AstNode) → Boolean {
        cache.at (node) put (anObjectType.number)
        true
    }

    // If the op is & or |, evaluate it
    // Otherwise treat it as a call
    method visitOp (node: AstNode) → Boolean {
        io.error.write"\n2283 type checking op"
        if(node.value == "&") then {
            cache.at(node) put (typeOf(node.left) & typeOf(node.right))
        } elseif {node.value == "|"} then {
            cache.at(node) put (typeOf(node.left) | typeOf(node.right))
        } else {
            visitCall(node)
        }
        false
    }

    method visitTypeLiteral(node: TypeLiteral) → Boolean {
        cache.at(node) put(anObjectType.fromDType(node))
        true
    }

    method visitBind (bind: AstNode) → Boolean {
        io.error.write "\n 1758: Visit Bind"
        def dest: AstNode = bind.dest

        match (dest) case { _ : Member →
            var nm: String := dest.nameString
            if (! nm.endsWith ":=(1)") then {
                nm := nm ++ ":=(1)"
            }
            // rec.memb
            def rec: AstNode = dest.in

            // Type of receiver
            def rType: ObjectType = if(Identifier.match(rec) && {rec.value == "self"}) then {
                scope.variables.find("$elf") butIfMissing {
                    Exception.raise "type of self missing" with(rec)
                }
            } else {
                typeOf(rec)
            }

            if (rType.isDynamic) then {
                anObjectType.dynamic
            } else {

                match(rType.getMethod(nm))
                  case { (noSuchMethod) →
                    outer.RequestError.raise("no such method '{nm}' in " ++
                        "`{stripNewLines(rec.toGrace(0))}` of type '{rType}'") with (bind)
                } case { meth : MethodType →
                    def req = ast.callNode.new(dest,
                        list [ast.callWithPart.new(dest.value, list [bind.value])])
                    check(req) against(meth)
                }
            }

        } case { _ →
            def dType: ObjectType = typeOf(dest)

            def value: AstNode = bind.value
            def vType: ObjectType = typeOf(value)

            if(vType.isConsistentSubtypeOf(dType).not) then {
                DefError.raise("the expression `{stripNewLines(value.toGrace(0))}` of type " ++
                    "'{vType}' does not satisfy the type '{dType}' of " ++
                    "`{stripNewLines(dest.toGrace(0))}`") with (value)
            }
        }
        cache.at (bind) put (anObjectType.doneType)
        false
    }


    // handles both defs and var declarations
    method visitDefDec (defd: AstNode) → Boolean {
        if (defd.decType.value=="Unknown") then {
            var typ: String := "def"
            if (Var.match(defd)) then { typ := "var" }
            CheckerFailure.raise("no type given to declaration"
                ++ " of {typ} '{defd.name.value}'") with (defd.name)
        }
        var defType: ObjectType := anObjectType.fromDType(defd.dtype)
        io.error.write "\n1820: defType is {defType}"
        def value = defd.value

        if(value != false) then {
            def vType: ObjectType = typeOf(value)
            // infer type if definition w/out type
            if(defType.isDynamic && (defd.kind == "defdec")) then {
                defType := vType
            }
            if(vType.isConsistentSubtypeOf(defType).not) then {
                DefError.raise("the expression `{stripNewLines(value.toGrace(0))}` of type " ++
                    "'{vType}' does not have type {defd.kind} " ++
                    "annotation '{defType}'") with (value)
            }
        }

        def name: String = defd.nameString
        scope.variables.at(name) put(defType)
        if (defd.isReadable) then {
            scope.methods.at(name) put(aMethodType.member(name) ofType(defType))
        }
        if (defd.isWritable) then {
            def name' = name ++ ":=(1)"
            def param = aParam.withName(name) ofType(defType)
            def sig = list[aMixPartWithName(name') parameters(list[param])]
            scope.methods.at(name')
                put(aMethodType.signature(sig) returnType(anObjectType.doneType))
        }
        cache.at (defd) put (anObjectType.doneType)
        false
    }

    // Handle variable declaration like definition
    method visitVarDec (node: AstNode) → Boolean {
        visitDefDec (node)
    }

    // Grab information from gct file
    //Move processImport back into visitImport
    method visitImport (imp: AstNode) → Boolean {
        io.error.write "\n1861: visiting import {imp}"
        // headers of sections of gct form keys
        // Associated values are lines beneath the header
        def gct: Dictionary⟦String, List⟦String⟧⟧ = xmodule.parseGCT(imp.path)
        def impName : String = imp.nameString
        io.error.write("\n1953 gct is {gct}")
        io.error.write("\n1954 keys are {gct.keys}\n")

        // Define a list of types that we have yet to resolve. All public types
        // are placed in this list at the start.
        //Comment about publicImpType
        def unresolvedTypes: List⟦String⟧ = list[]
        def publicImpTypes : List⟦String⟧ = list[]
        if (gct.containsKey("types")) then {
            for(gct.at("types")) do { typ →
                if (typ.startsWith("$")) then {
                    publicImpTypes.push(typ)
                }
                unresolvedTypes.push(typ)
            }
        }

        // Collect the type definition associated with each type
        def typeDefs : Dictionary⟦String, List⟦String⟧⟧ = emptyDictionary
        gct.keys.do { key : String →
            //example key: 'methodtypes-of:MyType:'
            if (key.startsWith("methodtypes-of:")) then {
                //gets the name of the type
                def typeName: String = split(key, ":").at(2)

                typeDefs.at(typeName) put(gct.at(key))
            }
        }

        //Loops until all imported types are resolved and stored in the types scope
        while{unresolvedTypes.size > 0} do {
            //To resolve its given type, importHelper recursively resolves other
            //unresolved types that its given type's type definition depends on.
            importHelper(unresolvedTypes.at(1), impName, unresolvedTypes,
                                                                      typeDefs)
        }

        //retrieves the names of public methods from imported module
        def importMethods : Set⟦MethodType⟧ = emptySet

        def importedMethodTypes: List⟦String⟧ = gct.at("publicMethodTypes")
                                                          ifAbsent { emptyList }

        //construct the MethodType corressponding to each method name
        for (importedMethodTypes) do { methSig : String →
            //if the method name begins with a '$', then it is a method that
            //returns an object corresponding to a public module that was
            //imported by our own import. We have already constructed the type
            //that this '$nickname' method returns in the while-do above. Since
            //that type is the type of an import and is not from a type-dec,
            //we want to remove it from our types scope after we've used it to
            //construct this '$nickname' method.
            def retName : String = methSig.substringFrom(methSig.indexOf("→") + 2)
            if (retName.startsWith("$")) then {
                def withoutDollar : String = retName.substringFrom(2)
                def mixPart : MixPart = aMixPartWithName(withoutDollar)
                                                          parameters(emptyList)

                def retType : ObjectType =
                    scope.types.findAtTop("{impName}.{retName}")
                        butIfMissing { Exception.raise
                            ("\nCannot find type " ++
                                "{impName}.{retName}. It is not defined in the " ++
                                "{impName} GCT file. Likely a problem with " ++
                                "writing the GCT file.")}

                importMethods.add(aMethodType.signature(list[mixPart])
                                                          returnType (retType))

                //remove the type belonging to '$nickname' from the types scope
                scope.types.stack.at(1).removeKey("{impName}.{retName}")
            } else {
                importMethods.add(aMethodType.fromGctLine(methSig, impName))
            }
        }

        // Create the ObjectType and MethodType of import
        def impOType: ObjectType = anObjectType.fromMethods(importMethods)
        def sig: List⟦MixPart⟧ = list[aMixPartWithName(impName)
                                                  parameters (emptyList)]
        def impMType: MethodType = aMethodType.signature(sig) returnType (impOType)

        // Store import in scopes and cache
        scope.variables.at(impName) put(impOType)
        scope.methods.at(impName) put(impMType)
        cache.at(imp) put (impOType)
        io.error.write"\n2421: ObjectType of the import {impName} is: {impOType}"
        false
    }

    //Resolve the imported type,'typeName', and store it in the types scope
    //
    //Param typeName - name of the imported type to be resolved
    //      impName  - nickname of the imported file containing 'typeName'
    //      unresolvedTypes - list of unresolved types
    //      typeDefs - maps all imported types from 'impName' to their type
    //                 definitions
    method importHelper(typeName : String, impName : String,
                        unresolvedTypes : List⟦String⟧,
                        typeDefs : Dictionary⟦String, List⟦String⟧⟧) → Done {

        if (typeDefs.containsKey(typeName).not) then {
            Exception.raise ("\nCannot find type {typeName}. It is not " ++
                "defined in the {impName} GCT file. Likely a problem with " ++
                "writing the GCT file.")
        }
        io.error.write "\n 2413: looking for {typeName} defined as {typeDefs.at(typeName)}"

        //Holds the type literals that make up 'typeName'
        def typeLiterals: Dictionary⟦String,ObjectType⟧ = emptyDictionary

        //Holds all methods belonging to 'typeName'
        def typeMeths: Set⟦MethodType⟧ = emptySet

        def typeDef : List⟦String⟧ = typeDefs.at(typeName)

        //populates typeLiterals with all the type literals declared in the type
        while {(typeDef.size > 0) && {typeDef.at(1).startsWithDigit}} do {
            def methPrefix : String = split(typeDef.at(1), " ").at(1)

            if (typeLiterals.containsKey(methPrefix).not) then {
                typeLiterals.at(methPrefix)
                                        put (anObjectType.fromMethods(emptySet))
            }
            typeLiterals.at(methPrefix).methods.add(
                          aMethodType.fromGctLine(typeDef.removeFirst, impName))
        }

        //*******************************************************
        //At this point in the method, typeDef only contains the
        //lines that come after the type literal definitions
        //*******************************************************

        //This will hold the resulting ObjectType of the type being evaluated
        def myType : ObjectType = if (typeDef.size == 0) then {
            //type is defined by a type literal
            if (typeLiterals.size == 0) then {
                anObjectType.fromMethods(emptySet)
            } else {
                typeLiterals.values.first
            }
        } else {
            def fstLine : String = typeDef.at(1)
            if ((fstLine.at(1) == "&") || {fstLine.at(1) == "|"}) then {
                //type is defined by operations on other types
                importOpHelper(typeDef, typeLiterals, typeName, impName,
                                                      unresolvedTypes, typeDefs)
            } elseif {anObjectType.preludeTypes.contains(fstLine)} then {
                //type is defined by a prelude type
                scope.types.findAtTop("{fstLine}") butIfMissing{
                    Exception.raise ("\nCannot find type {fstLine}. "++
                        "Likely a problem with writing the GCT file.")
                }
            } else {
                //type is defined by an imported type
                if (unresolvedTypes.contains(fstLine)) then {
                    importHelper(fstLine, impName, unresolvedTypes, typeDefs)
                }
                scope.types.findAtTop("{impName}.{fstLine}") butIfMissing{
                    Exception.raise ("\nCannot find type {impName}.{fstLine}."++
                        " Likely a problem with writing the GCT file.")
                }
            }
        }

        io.error.write ("\nThe type {impName}.{typeName} was put in the scope as" ++
                                      " {impName}.{typeName}::{myType}")

        io.error.write "\n2483 trying to remove {typeName} from {unresolvedTypes}"
        unresolvedTypes.remove(typeName)
        scope.types.at("{impName}.{typeName}") put (myType)
    }

    //recursively parse pre-ordered type definitions from GCT file
    //
    //Param list - the list of strings from the GCT file that represents the pre-order
    //                traversal of the AstNode tree
    //Param typeLits - Holds all the pre-processed type literals from the type definition
    //                    mapped to digits as temporary type names
    //The other parameters are just so this method can recursively call importHelper
    method importOpHelper (typeDef : List⟦String⟧,
                typeLits : Dictionary⟦String,ObjectType⟧, typeName : String,
                impName : String, unresolvedTypes : List⟦String⟧,
                typeDefs : Dictionary⟦String, List⟦String⟧⟧) → ObjectType {

        io.error.write("\nCalled importOpHelper on {typeName} with the " ++
                                                          "typeDef of {list}")
        def elt : String = typeDef.removeFirst
        //elt is an op, and what comes after it is its left side and right side
        if (elt == "&") then {
            def leftSide  : ObjectType = importOpHelper(typeDef, typeLits, elt,
                                            impName, unresolvedTypes, typeDefs)
            def rightSide : ObjectType = importOpHelper(typeDef, typeLits, elt,
                                            impName, unresolvedTypes, typeDefs)
            leftSide & rightSide
        } elseif {elt == "|"} then {
            def leftSide  : ObjectType = importOpHelper(typeDef, typeLits, elt,
                                            impName, unresolvedTypes, typeDefs)
            def rightSide : ObjectType = importOpHelper(typeDef, typeLits, elt,
                                            impName, unresolvedTypes, typeDefs)
            leftSide | rightSide
        //elt refers to an already-processed type literal
        } elseif {elt.startsWithDigit} then {
            typeLits.at(elt)
        //elt is an identifier, which must be resolved then found in the scope
        } else {
            if (unresolvedTypes.contains(elt)) then {
                importHelper (elt, impName, unresolvedTypes, typeDefs)
            }
            io.error.write ("\n2470 scope before search in import is" ++
                                                            "{scope.types}")
            scope.types.findAtTop("{impName}.{elt}") butIfMissing {
                                  ScopingError.raise("Could not " ++
                                        "find type {elt} from import in scope")
            }
        }
    }

    method visitReturn (node: AstNode) → Boolean {
        cache.at(node) put (typeOf(node.value))
        false
    }

    method visitInherits (node: AstNode) → Boolean {
        io.error.write "\n1999: visit inherits with {node} which has kind {node.kind}"
        io.error.write "\n1999: visit inherits with {node} which has receiver {node.value.receiver}"
        io.error.write "\n1999: visit inherits with {node} which has parts {node.value.parts.removeLast}"
        cache.at(node) put (typeOf(node.value))
        io.error.write "\n2000 has type {typeOf(node.value)}"
        false
    }


    // Not done
    // Should be treated like import, but at top level
    // Add to base type
    method visitDialect (node: AstNode) → Boolean {
        io.error.write "\n1919: visiting dialect {node}"
        checkMatch (node)
    }

}


// DEBUG: Outer not handled correctly yet

method outerAt(i : Number) → ObjectType is confidential {
    // Required to cope with not knowing the prelude.
    if(i <= 1) then {
        return anObjectType.dynamic
    }
    io.error.write "processing outer"

    def vStack: List⟦Dictionary⟧ = scope.variables.stack

    def curr: ObjectType = vStack.at(i)

    //Joe-how does an ObjectType have an 'at' method
    return curr.at("outer") ifAbsent {
        def prev: ObjectType = outerAt(i - 1)

        def mStack: List⟦Dictionary⟧ = scope.methods

        def vars: Dictionary = vStack.at(i - 1)
        def meths: Set⟦MethodType⟧ = mStack.at(i - 1).values

        //Joe - maybe do outer.types
        def oType: ObjectType = anObjectType.fromMethods(meths)
        def mType: MethodType = aMethodType.member("outer") ofType(oType)

        curr.at("outer") put(oType)
        mStack.at(i).at("outer") put(mType)

        oType
    }
}


// Typing methods.
// Type check body of object definition
method processBody (body : List⟦AstNode⟧, superclass: AstNode | false)
                                                → ObjectType is confidential {
    io.error.write "\n1958: superclass: {superclass}\n"

    var inheritedMethods: Set⟦MethodType⟧ := emptySet
    def hasInherits = false ≠ superclass
    io.error.write "\n1965: hasInherits is {hasInherits}\n"
    var publicSuperType: ObjectType := anObjectType.base
    def superType: ObjectType = if(hasInherits) then {
        def inheriting: AstNode = superclass
//        inheriting.accept(object {
//            inherit ast.baseVisitor

//            def illegal = ["self", "super"]

//            method visitIdentifier(ident) {
//                if(illegal.contains(ident.value)) then {
//                    ObjectError.raise("reference to '{ident.value}' " ++
//                        "in inheritance clause") with (ident)
//                }
//                true
//            }
//        })
        io.error.write "\nGT1981: checking types of inheriting = {inheriting}\n"
        var name: String := inheriting.value.nameString
        if (name.contains "$object(") then {
            inheriting.value.parts.removeLast
            name := inheriting.value.nameString
        }

        def inheritedType: ObjectType = allCache.at(name)
        inheritedMethods := inheritedType.methods
        publicSuperType := typeOf(inheriting.value)
        io.error.write "\n2641: public super type: {publicSuperType}"

        inheritedType
    } else {
        anObjectType.base
    }
    io.error.write "\n1989: superType is {superType}\n"
    scope.variables.at("super") put(superType)

    // If the super type is dynamic, then we can't know anything about the
    // self type.  TODO We actually can, because an object cannot have two
    // methods with the same name.

    // Type including all confidential features
    var internalType: ObjectType

    // Type including only public features
    def publicType: ObjectType = if(superType.isDynamic) then {
        scope.variables.at("$elf") put(superType)
        superType
    } else {
        // Collect the method types to add the two self types.
        def isParam: Param = aParam.withName("other") ofType (anObjectType.base)
        def part: MixPart = aMixPartWithName("isMe")parameters(list[isParam])

        // add isMe method as confidential
        def isMeMeth: MethodType = aMethodType.signature(list[part]) returnType(anObjectType.boolean)

        def publicMethods: Set⟦MethodType⟧ = publicSuperType.methods.copy
        def allMethods: Set⟦MethodType⟧ = superType.methods.copy
        allMethods.add(isMeMeth)

        // collect embedded types in these dictionaries
        def publicTypes: Dictionary⟦String,ObjectType⟧ = emptyDictionary
        def allTypes: Dictionary⟦String,ObjectType⟧ = emptyDictionary

        // gather types for all methods in object
        // TODO: Worry about overriding with refined signature
        for(body) do { stmt: AstNode →
            io.error.write "\n2009: processing {stmt}"
            match(stmt) case { meth : Method →
                def mType: MethodType = aMethodType.fromNode(meth)
                checkOverride(mType,allMethods,publicMethods)
                allMethods.add(mType)
                if(isPublic(meth)) then {
                    publicMethods.add(mType)
                }

                scope.methods.at(meth.nameString) put(mType)

                //A method that is a Member has no parameter and is identical to
                //a variable, so we also store it inside the variables scope
                if(isMember(mType)) then {
                    scope.variables.at(mType.name) put(mType.returnType)
                }

            } case { defd : Def | Var →
                def mType: MethodType = aMethodType.fromNode(defd)
                allMethods.add(mType)

                //create method to access def/var
                if(defd.isReadable) then {
                    publicMethods.add(mType)
                }

                //update scope with reference to def/var
                scope.methods.at(mType.name) put(mType)
                scope.variables.at(mType.name) put(mType.returnType)

                //constructs setter method for writable vars
                if(defd.isWritable) then {
                    def name': String = defd.nameString ++ ":=" //(1)"  ?? is name right?
                    def dType: ObjectType = anObjectType.fromDType(defd.dtype)
                    def param: Param = aParam.withName(defd.nameString) ofType(dType)
                    def sig: List⟦MixPart⟧ = list[aMixPartWithName(name') parameters(list[param])]

                    def aType: MethodType = aMethodType.signature(sig) returnType(anObjectType.doneType)
                    scope.methods.at(name') put(aType)
                    allMethods.add(aType)
                    publicMethods.add(aType)
                }

            } case { td : TypeDeclaration →
                //Now does nothing if given type declaration; might make this raise an error later
            } case { _ → io.error.write"\n2617 ignored {stmt}"}
        }

        internalType := anObjectType.fromMethods(allMethods)
        scope.variables.at("$elf") put (internalType)

        anObjectType.fromMethods(publicMethods)
    }

    scope.variables.at("self") put(publicType)
    io.error.write "\n2744: Type of self is {publicType}"

    // Type-check the object body.
    def indices: Collection⟦Number⟧ = if(hasInherits) then {
        2..body.size
    } else {
        body.indices
    }

    for(indices) do { i: Number →
        io.error.write "\n2070: checking index {i} at line {body.at(i).line}"
        checkTypes(body.at(i))
        io.error.write "\n2072: finished index {i}\n"
    }

    io.error.write "\n 2674 types scope is: {scope.types}"
    io.error.write "\n 2675 methods scope is: {scope.methods}"
    pubConf(publicType,internalType)
}

method checkOverride(mType: MethodType, allMethods: Set⟦MethodType⟧,
                                        publicMethods: Set⟦MethodType⟧) → Done {
    def oldMethType: MethodType = allMethods.find{m:MethodType →
        mType.nameString == m.nameString
    } ifNone {return}

    if(mType.isSpecialisationOf(emptyList, oldMethType).ans.not) then {
        MethodError.raise ("Type of overriding method {mType} is not"
            ++ " a specialization of existing method {oldMethType}") with (mType)
    }
}



def TypeDeclarationError = TypeError.refine "TypeDeclarationError"

// The first pass over a body, collecting all type declarations so that they can
// reference one another declaratively.
method collectTypes(nodes : Collection⟦AstNode⟧) → Done is confidential {
    def names: List⟦String⟧ = list[]

    for(nodes) do { node →
        match(node) case { td : TypeDeclaration →
            io.error.write"\nmatched as typeDec"
            if(names.contains(td.nameString)) then {
                TypeDeclarationError.raise("the type {td.nameString} uses " ++
                    "the same name as another type in the same scope") with(td)
            }

            names.push(td.nameString)
            scope.types.at(td.nameString)
                                    put(anObjectType.definedByNode (td.value))
        } case { _ →
        }
    }
    // io.error.write "1881: done collecting types"
}


// Determines if a node is publicly available.
method isPublic(node : Method | Def | Var) → Boolean is confidential {
    match(node) case { _ : Method →
        for(node.annotations) do { ann →
            if(ann.value == "confidential") then {
                return false
            }
        }

        true
    } case { _ →
        for(node.annotations) do { ann →
            if((ann.value == "public") || (ann.value == "readable")) then {
                return true
            }
        }

        false
    }
}


// Determines if a method will be accessed as a member.
method isMember(mType : MethodType) → Boolean is confidential {
    (mType.signature.size == 1) && {
        mType.signature.first.parameters.size == 0
    }
}


// Helper methods.

// For loop with break.
method for(a) doWithBreak(bl) → Done {
    for(a) do { e →
        bl.apply(e, {
            return
        })
    }
}

// For loop with continue.
method for(a) doWithContinue(bl) → Done {
    for(a) do { e →
        continue'(e, bl)
    }
}

method continue'(e, bl) → Done is confidential {
    bl.apply(e, { return })
}


// Replace newline characters with spaces. This is a
// workaround for issue #116 on the gracelang/minigrace
// git repo. The result of certain astNodes.toGrace(0)
// is a string containing newlines, and error messages
// containing these strings get cut off at the first
// newline character, resulting in an unhelpful error
// message.
method stripNewLines(str) → String is confidential {
    str.replace("\n")with(" ")
}

//class parameterFromNode (node) → Parameter is confidential {
//    inherit ast.identifierNode.new (node.name, node.dtype)
//    method kind { "parameter" }
//}

def thisDialect is public = object {
    method astChecker (moduleObj) { moduleObj.accept(astVisitor) }
}
