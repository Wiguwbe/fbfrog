'' AST build up/helper functions

#include once "fbfrog.bi"

''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

dim shared as zstring ptr astnodename(0 to ...) => _
{ _
	_ '' Internal helper nodes
	@"group"     , _
	@"verblock"  , _
	@"veror"     , _
	@"verand"    , _
	@"divider"   , _
	@"scopeblock", _
	_
	_ '' Script helper nodes
	@"declaredefines", _
	@"declareversions", _
	@"declarebool"  , _
	@"select"       , _
	@"case"         , _
	@"caseelse"     , _
	@"endselect"    , _
	@"file"         , _
	@"dir"          , _
	@"noexpand"     , _
	@"removedefine" , _
	@"renametypedef", _
	@"renametag"    , _
	@"removematch"  , _
	@"inclib"       , _
	@"pragmaonce"   , _
	_
	_ '' Preprocessor directives
	@"#include", _
	@"#define" , _
	@"#if"     , _
	@"#elseif" , _
	@"#else"   , _
	@"#endif"  , _
	@"#error"  , _
	_
	_ '' Declarations/statements
	@"struct"     , _
	@"union"      , _
	@"enum"       , _
	@"typedef"    , _
	@"constant"   , _
	@"var"        , _
	@"externvar"  , _
	@"staticvar"  , _
	@"field"      , _
	@"enumconst"  , _
	@"proc"       , _
	@"param"      , _
	@"array"      , _
	@"externbegin", _
	@"externend"  , _
	_
	_ '' Expression atoms etc.
	@"macrobody" , _
	@"macroparam", _
	@"tk"        , _
	@"consti"    , _
	@"constf"    , _
	@"id"        , _
	@"tagid"     , _
	@"text"      , _
	@"string"    , _
	@"char"      , _
	@"type"      , _
	_
	_ '' BOPs
	@"C ||"   , _
	@"C &&"   , _
	@"orelse" , _
	@"andalso", _
	@"or"     , _
	@"xor"    , _
	@"and"    , _
	@"C ="    , _
	@"C <>"   , _
	@"C <"    , _
	@"C <="   , _
	@"C >"    , _
	@"C >="   , _
	@"="      , _
	@"<>"     , _
	@"<"      , _
	@"<="     , _
	@">"      , _
	@">="     , _
	@"shl"    , _
	@"shr"    , _
	@"+"      , _
	@"-"      , _
	@"*"      , _
	@"/"      , _
	@"mod"    , _
	@"[]"     , _
	@"."      , _
	@"->"     , _
	@"str +"  , _
	_
	_ '' UOPs
	@"C !"        , _
	@"not"        , _
	@"negate"     , _
	@"unary +"    , _
	@"C defined()", _
	@"defined()"  , _
	@"@"          , _
	@"deref"      , _
	@"#"          , _
	@"sizeof"     , _
	@"cast"       , _
	_
	_ '' Special expressions
	@"iif"       , _
	@"ppmerge"   , _
	@"call"      , _
	@"structinit", _
	@"arrayinit" , _
	@"dimension" , _
	@"sizeoftype" _
}

#assert ubound( astnodename ) = ASTCLASS__COUNT - 1

function astNew overload( byval class_ as integer ) as ASTNODE ptr
	dim as ASTNODE ptr n = callocate( sizeof( ASTNODE ) )
	n->class = class_
	function = n
end function

function astNew overload( byval class_ as integer, byval text as zstring ptr ) as ASTNODE ptr
	var n = astNew( class_ )
	n->text = strDuplicate( text )
	function = n
end function

function astNew overload( byval class_ as integer, byval c1 as ASTNODE ptr, byval c2 as ASTNODE ptr ) as ASTNODE ptr
	var n = astNew( class_ )
	astAppend( n, c1 )
	astAppend( n, c2 )
	function = n
end function

function astNewIncludeOnce( byval filename as zstring ptr ) as ASTNODE ptr
	var n = astNew( ASTCLASS_PPINCLUDE, filename )
	n->attrib or= ASTATTRIB_ONCE
	function = n
end function

function astNewPPDEFINE( byval id as zstring ptr ) as ASTNODE ptr
	var n = astNew( ASTCLASS_PPDEFINE, id )
	n->paramcount = -1
	function = n
end function

function astNewIIF( byval cond as ASTNODE ptr, byval l as ASTNODE ptr, byval r as ASTNODE ptr ) as ASTNODE ptr
	var n = astNew( ASTCLASS_IIF, l, r )
	n->expr = cond
	function = n
end function

function astNewGROUP overload( ) as ASTNODE ptr
	function = astNew( ASTCLASS_GROUP )
end function

function astNewGROUP overload( byval c1 as ASTNODE ptr, byval c2 as ASTNODE ptr ) as ASTNODE ptr
	var n = astNewGROUP( )
	astAppend( n, c1 )
	astAppend( n, c2 )
	function = n
end function

function astNewDEFINED( byval id as zstring ptr ) as ASTNODE ptr
	function = astNew( ASTCLASS_DEFINED, astNewID( id ) )
end function

function astCloneChildren( byval src as ASTNODE ptr ) as ASTNODE ptr
	var n = astNewGROUP( )
	var i = src->head
	while( i )
		astAppend( n, astClone( i ) )
		i = i->next
	wend
	function = n
end function

function astGroupContains( byval group as ASTNODE ptr, byval lookfor as ASTNODE ptr ) as integer
	var i = group->head
	while( i )
		if( astIsEqual( i, lookfor ) ) then
			return TRUE
		end if
		i = i->next
	wend
	function = FALSE
end function

function astGroupContainsAnyChildrenOf( byval l as ASTNODE ptr, byval r as ASTNODE ptr ) as integer
	var i = r->head
	while( i )
		if( astGroupContains( l, i ) ) then return TRUE
		i = i->next
	wend
end function

function astGroupContainsAllChildrenOf( byval l as ASTNODE ptr, byval r as ASTNODE ptr ) as integer
	var i = r->head
	while( i )
		if( astGroupContains( l, i ) = FALSE ) then exit function
		i = i->next
	wend
	function = TRUE
end function

private function astGroupsContainEqualChildren( byval l as ASTNODE ptr, byval r as ASTNODE ptr ) as integer
	function = astGroupContainsAllChildrenOf( l, r ) and astGroupContainsAllChildrenOf( r, l )
end function

function astUngroupOne( byval group as ASTNODE ptr ) as ASTNODE ptr
	assert( group->class = ASTCLASS_GROUP )
	assert( group->head )
	assert( group->head = group->tail )
	function = astClone( group->head )
	astDelete( group )
end function

function astNewCONSTI( byval i as longint, byval dtype as integer ) as ASTNODE ptr
	var n = astNew( ASTCLASS_CONSTI )
	n->dtype = dtype
	n->vali = i
	function = n
end function

function astNewCONSTF( byval f as double, byval dtype as integer ) as ASTNODE ptr
	var n = astNew( ASTCLASS_CONSTF )
	n->dtype = dtype
	n->valf = f
	function = n
end function

function astNewTK( byval x as integer ) as ASTNODE ptr
	var n = astTakeLoc( astNew( ASTCLASS_TK, tkGetText( x ) ), x )
	n->tk = tkGet( x )
	function = n
end function

function astTKMatchesPattern( byval tk as ASTNODE ptr, byval x as integer ) as integer
	assert( tk->class = ASTCLASS_TK )

	if( tk->tk <> tkGet( x ) ) then exit function

	var text = tkGetText( x )
	if( (tk->text <> NULL) <> (text <> NULL) ) then exit function
	if( text ) then
		if( *tk->text <> *text ) then exit function
	end if

	function = TRUE
end function

function astTakeLoc( byval n as ASTNODE ptr, byval x as integer ) as ASTNODE ptr
	n->location = *tkGetLocation( x )
	function = n
end function

sub astDelete( byval n as ASTNODE ptr )
	if( n = NULL ) then
		exit sub
	end if

	var i = n->head
	while( i )
		var nxt = i->next
		astDelete( i )
		i = nxt
	wend

	astDelete( n->expr )
	astDelete( n->array )
	deallocate( n->text )
	astDelete( n->subtype )
	deallocate( n )
end sub

#if __FB_DEBUG__
private function astIsChildOf _
	( _
		byval parent as ASTNODE ptr, _
		byval lookfor as ASTNODE ptr _
	) as integer

	var child = parent->head
	while( child )
		if( child = lookfor ) then
			return TRUE
		end if
		child = child->next
	wend

	function = FALSE
end function
#endif

sub astInsert _
	( _
		byval parent as ASTNODE ptr, _
		byval n as ASTNODE ptr, _
		byval ref as ASTNODE ptr, _
		byval unique as integer = FALSE _
	)

	if( n = NULL ) then exit sub

	assert( astIsChildOf( parent, n ) = FALSE )

	select case( n->class )
	'' If it's a GROUP, insert its children, and delete the GROUP itself
	case ASTCLASS_GROUP
		var i = n->head
		while( i )
			astInsert( parent, astClone( i ), ref, unique )
			i = i->next
		wend
		astDelete( n )
		exit sub
	end select

	'' If requested, don't insert if it already exists in the list
	if( unique ) then
		var i = parent->head
		while( i )
			if( astIsEqual( i, n ) ) then
				astDelete( n )
				exit sub
			end if
			i = i->next
		wend
	end if

	if( ref ) then
		assert( astIsChildOf( parent, ref ) )
		if( ref->prev ) then
			ref->prev->next = n
		else
			parent->head = n
		end if
		n->next = ref
		n->prev = ref->prev
		ref->prev = n
	else
		if( parent->tail ) then
			parent->tail->next = n
		else
			parent->head = n
		end if
		n->prev = parent->tail
		n->next = NULL
		parent->tail = n
	end if

end sub

sub astPrepend( byval parent as ASTNODE ptr, byval n as ASTNODE ptr )
	astInsert( parent, n, parent->head )
end sub

sub astAppend( byval parent as ASTNODE ptr, byval n as ASTNODE ptr )
	astInsert( parent, n, NULL )
end sub

function astRemove( byval parent as ASTNODE ptr, byval a as ASTNODE ptr ) as ASTNODE ptr
	assert( a )
	assert( astIsChildOf( parent, a ) )

	function = a->next

	if( a->prev ) then
		a->prev->next = a->next
	else
		assert( parent->head = a )
		parent->head = a->next
	end if

	if( a->next ) then
		a->next->prev = a->prev
	else
		assert( parent->tail = a )
		parent->tail = a->prev
	end if

	astDelete( a )
end function

sub astRemoveChildren( byval parent as ASTNODE ptr )
	while( parent->head )
		astRemove( parent, parent->head )
	wend
end sub

function astReplace _
	( _
		byval parent as ASTNODE ptr, _
		byval old as ASTNODE ptr, _
		byval n as ASTNODE ptr _
	) as ASTNODE ptr
	assert( old )
	astInsert( parent, n, old )
	function = astRemove( parent, old )
end function

sub astSetText( byval n as ASTNODE ptr, byval text as zstring ptr )
	deallocate( n->text )
	n->text = strDuplicate( text )
end sub

sub astRenameSymbol( byval n as ASTNODE ptr, byval newid as zstring ptr )
	assert( n->alias = NULL )
	n->alias = n->text
	n->text = strDuplicate( newid )
end sub

sub astSetType _
	( _
		byval n as ASTNODE ptr, _
		byval dtype as integer, _
		byval subtype as ASTNODE ptr _
	)

	astDelete( n->subtype )
	n->dtype = dtype
	n->subtype = astClone( subtype )

end sub

sub astSetComment( byval n as ASTNODE ptr, byval comment as zstring ptr )
	deallocate( n->comment )
	n->comment = strDuplicate( comment )
end sub

sub astAddComment( byval n as ASTNODE ptr, byval comment as zstring ptr )
	dim as string s

	if( len( *comment ) = 0 ) then
		exit sub
	end if

	if( n->comment ) then
		s = *n->comment + !"\n"
	end if

	s += *comment

	astSetComment( n, s )
end sub

'' astClone() but without children
function astCloneNode( byval n as ASTNODE ptr ) as ASTNODE ptr
	if( n = NULL ) then
		return NULL
	end if

	var c = astNew( n->class )
	c->attrib      = n->attrib

	c->text        = strDuplicate( n->text )
	c->comment     = strDuplicate( n->comment )
	c->alias       = strDuplicate( n->alias )

	c->dtype       = n->dtype
	c->subtype     = astClone( n->subtype )
	c->array       = astClone( n->array )
	c->bits        = astClone( n->bits )

	c->location    = n->location

	c->expr        = astClone( n->expr )

	select case( n->class )
	case ASTCLASS_CONSTI   : c->vali = n->vali
	case ASTCLASS_CONSTF   : c->valf = n->valf
	case ASTCLASS_TK       : c->tk = n->tk
	case ASTCLASS_PPDEFINE : c->paramcount = n->paramcount
	end select

	function = c
end function

function astClone( byval n as ASTNODE ptr ) as ASTNODE ptr
	var c = astCloneNode( n )
	if( c ) then
		var i = n->head
		while( i )
			astAppend( c, astClone( i ) )
			i = i->next
		wend
	end if
	function = c
end function

'' Check whether two ASTs represent equal declarations, i.e. most fields must be
'' equal, but some things may be different as long as it would still result in
'' compatible C/FB code.
'' For example, two procedures must have the same kind of parameters, but it
'' doesn't matter whether two CONSTI expressions both originally were
'' oct/hex/dec, as long as they're the same value.
function astIsEqual _
	( _
		byval a as ASTNODE ptr, _
		byval b as ASTNODE ptr, _
		byval options as integer _
	) as integer

	'' If one is NULL, both must be NULL
	if( (a = NULL) or (b = NULL) ) then
		return ((a = NULL) and (b = NULL))
	end if

	if( a->class <> b->class ) then exit function

	var check_callconv = FALSE
	if( options and ASTEQ_IGNOREHIDDENCALLCONV ) then
		'' Only check the callconv if not hidden on both sides
		var ahidden = ((a->attrib and ASTATTRIB_HIDECALLCONV) <> 0)
		var bhidden = ((b->attrib and ASTATTRIB_HIDECALLCONV) <> 0)
		check_callconv = (ahidden <> bhidden)
	end if

	if( check_callconv ) then
		if( (a->attrib and ASTATTRIB_CDECL) <> _
		    (b->attrib and ASTATTRIB_CDECL) ) then
			exit function
		end if

		if( (a->attrib and ASTATTRIB_STDCALL) <> _
		    (b->attrib and ASTATTRIB_STDCALL) ) then
			exit function
		end if
	end if

	if( (a->text <> NULL) <> (b->text <> NULL) ) then exit function
	if( a->text ) then
		var a_is_dummy = FALSE
		if( options and ASTEQ_IGNOREDUMMYIDSTRUCTS ) then
			select case( a->class )
			case ASTCLASS_STRUCT, ASTCLASS_UNION, ASTCLASS_ENUM
				'' If both sides have place holder ids, treat them as equal,
				'' without comparing the dummy ids any further.
				a_is_dummy = strStartsWith( *a->text, DUMMYID_PREFIX )

				'' If not both sides are dummy ids though, then they can't be equal anyways.
				if( a_is_dummy <> strStartsWith( *b->text, DUMMYID_PREFIX ) ) then exit function
			end select
		end if
		if( a_is_dummy = FALSE ) then
			if( *a->text <> *b->text ) then exit function
		end if
	end if

	if( (a->alias <> NULL) <> (b->alias <> NULL) ) then exit function
	if( a->alias ) then if( *a->alias <> *b->alias ) then exit function

	if( a->dtype <> b->dtype ) then exit function
	if( astIsEqual( a->subtype, b->subtype, options ) = FALSE ) then exit function
	if( astIsEqual( a->array, b->array, options ) = FALSE ) then exit function
	if( astIsEqual( a->bits, b->bits, options ) = FALSE ) then exit function

	if( astIsEqual( a->expr, b->expr, options ) = FALSE ) then exit function

	select case( a->class )
	case ASTCLASS_CONSTI
		if( a->vali <> b->vali ) then exit function

	case ASTCLASS_CONSTF
		const EPSILON_DBL as double = 2.2204460492503131e-016
		if( abs( a->valf - b->valf ) >= EPSILON_DBL ) then exit function

	case ASTCLASS_TK
		if( a->tk <> b->tk ) then exit function

	case ASTCLASS_PPDEFINE
		if( a->paramcount <> b->paramcount ) then exit function

	case ASTCLASS_STRUCT, ASTCLASS_UNION, ASTCLASS_ENUM
		if( options and ASTEQ_IGNOREFIELDS ) then
			return TRUE
		end if

	case ASTCLASS_VEROR, ASTCLASS_VERAND
		return astGroupsContainEqualChildren( a, b )
	end select

	'' Children
	a = a->head
	b = b->head
	while( (a <> NULL) and (b <> NULL) )
		if( astIsEqual( a, b, options ) = FALSE ) then
			exit function
		end if
		a = a->next
		b = b->next
	wend

	'' Both a's and b's last child must be reached at the same time
	function = ((a = NULL) and (b = NULL))
end function

sub astReport _
	( _
		byval n as ASTNODE ptr, _
		byval message as zstring ptr, _
		byval more_context as integer _
	)

	if( n->location.source ) then
		hReport( @n->location, message, more_context )
	else
		print *message
		print astDumpPrettyDecl( n )
	end if

end sub

sub astOops _
	( _
		byval n as ASTNODE ptr, _
		byval message as zstring ptr, _
		byval more_context as integer _
	)
	astReport( n, message, more_context )
	end 1
end sub

''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
'' AST dumping for pretty output and debugging

function astDumpPrettyDecl( byval n as ASTNODE ptr ) as string
	dim as string s

	if( n->text = NULL ) then
		s += "anonymous "
	end if

	select case( n->class )
	case ASTCLASS_CONSTANT  : s += "constant"
	case ASTCLASS_VAR       : s += "variable"
	case ASTCLASS_EXTERNVAR : s += "extern variable"
	case ASTCLASS_STATICVAR : s += "static variable"
	case ASTCLASS_PROC      : s += "function"
	case ASTCLASS_ENUMCONST : s += "enum constant"
	case else               : s += *astnodename(n->class)
	end select

	if( n->text ) then
		s += " " + strMakePrintable( *n->text )
	end if

	if( n->alias ) then
		s += " alias """ + strMakePrintable( *n->alias ) + """"
	end if

	if( n->class = ASTCLASS_PROC ) then
		s += "()"
	end if

	function = s
end function

function astDumpOne( byval n as ASTNODE ptr ) as string
	dim as string s

	if( n = NULL ) then
		return "<NULL>"
	end if

	#if 0
		s += "[" & hex( n ) & "] "
	#endif

	s += *astnodename(n->class)

	#macro checkAttrib( a )
		if( n->attrib and ASTATTRIB_##a ) then s += " " + lcase( #a, 1 )
	#endmacro
	checkAttrib( OCT )
	checkAttrib( HEX )
	checkAttrib( CDECL )
	checkAttrib( STDCALL )
	checkAttrib( HIDECALLCONV )
	checkAttrib( HIDECASEALIAS )
	checkAttrib( REPORTED )
	checkAttrib( NEEDRENAME )
	checkAttrib( POISONED )
	checkAttrib( DONTEMIT )
	checkAttrib( ONCE )
	checkAttrib( PACKED )
	checkAttrib( VARIADIC )

	if( n->class <> ASTCLASS_TK ) then
		if( n->text ) then
			s += " """ + strMakePrintable( *n->text ) + """"
		end if
		if( n->alias ) then
			s += " alias """ + strMakePrintable( *n->alias ) + """"
		end if
	end if

	select case( n->class )
	case ASTCLASS_CONSTI
		if( n->attrib and ASTATTRIB_OCT ) then
			s += " &o" + oct( n->vali )
		elseif( n->attrib and ASTATTRIB_HEX ) then
			s += " &h" + hex( n->vali )
		else
			s += " " + str( n->vali )
		end if
	case ASTCLASS_CONSTF
		s += " " + str( n->valf )
	case ASTCLASS_TK
		s += " " + tkDumpBasic( n->tk, n->text )
	end select

	if( n->dtype <> TYPE_NONE ) then
		s += " as " + emitType( n->dtype, NULL, TRUE )
	end if

	s += hDumpComment( n->comment )

	#if 0
		s += " " + hDumpLocation( @n->location )
	#endif

	function = s
end function

function astDumpInline( byval n as ASTNODE ptr ) as string
	var s = astDumpOne( n )
	var args = 0

	#macro more( arg )
		if( args = 0 ) then
			s += "("
		else
			s += ", "
		end if
		s += arg
		args += 1
	#endmacro

	if( n->subtype ) then
		more( "subtype=" + astDumpInline( n->subtype ) )
	end if
	if( n->array ) then
		more( "array=" + astDumpInline( n->array ) )
	end if
	if( n->expr ) then
		more( "expr=" + astDumpInline( n->expr ) )
	end if

	var child = n->head
	while( child )
		more( astDumpInline( child ) )
		child = child->next
	wend

	if( args > 0 ) then
		s += ")"
	end if

	function = s
end function

private sub hPrintIndentation( byval nestlevel as integer )
	for i as integer = 2 to nestlevel
		print "   ";
	next
end sub

sub astDump _
	( _
		byval n as ASTNODE ptr, _
		byval nestlevel as integer, _
		byref prefix as string _
	)

	nestlevel += 1

	if( n ) then
		hPrintIndentation( nestlevel )
		if( len( prefix ) > 0 ) then
			print prefix + ": ";
		end if
		print astDumpOne( n )

		#macro dumpField( field )
			if( n->field ) then
				astDump( n->field, nestlevel, #field )
			end if
		#endmacro

		dumpField( subtype )
		dumpField( array )
		dumpField( expr )

		var child = n->head
		while( child )
			astDump( child, nestlevel )
			child = child->next
		wend
	else
		hPrintIndentation( nestlevel )
		print "<NULL>"
	end if

	nestlevel -= 1
end sub
