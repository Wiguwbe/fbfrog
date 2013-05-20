'' C parsing passes

#include once "fbfrog.bi"

type PARSERSTUFF
	x		as integer
	pass		as integer

	tempidcount	as integer
end type

dim shared as PARSERSTUFF parse

enum
	DECL_VAR = 0
	DECL_EXTERNVAR
	DECL_STATICVAR
	DECL_FIELD
	DECL_PARAM
	DECL_TYPEDEF
end enum

declare function cStructCompound( ) as ASTNODE ptr
declare function cIdList _
	( _
		byval decl as integer, _
		byval basedtype as integer, _
		byval basesubtype as ASTNODE ptr _
	) as ASTNODE ptr
declare function cMultDecl( byval decl as integer ) as ASTNODE ptr

private function hMakeTempId( ) as string
	parse.tempidcount += 1
	function = "__fbfrog_AnonStruct" & parse.tempidcount
end function

''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

private function hSkipFromTo _
	( _
		byval x as integer, _
		byval fromtk as integer, _
		byval totk as integer, _
		byval delta as integer _
	) as integer

	dim as integer level = any

	assert( tkGet( x ) = fromtk )

	level = 0
	do
		x += delta

		assert( tkGet( x ) <> TK_EOF )

		select case( tkGet( x ) )
		case fromtk
			level += 1

		case totk
			if( level = 0 ) then
				exit do
			end if
			level -= 1

		end select
	loop

	function = x
end function

private function ppSkip( byval x as integer ) as integer
	dim as integer y = any

	do
		x += 1

		select case( tkGet( x ) )
		case TK_SPACE, TK_COMMENT

		case TK_BEGIN
			x = hSkipFromTo( x, TK_BEGIN, TK_END, 1 )

		'' Escaped EOLs don't end PP directives, though normal EOLs do
		'' '\' [Space] EOL
		case TK_BACKSLASH
			y = x

			do
				y += 1
			loop while( tkGet( y ) = TK_SPACE )

			if( tkGet( y ) <> TK_EOL ) then
				exit do
			end if
			x = y

		case else
			exit do
		end select
	loop

	function = x
end function

private function ppSkipToEOL( byval x as integer ) as integer
	do
		select case( tkGet( x ) )
		case TK_EOL, TK_EOF
			exit do
		end select

		x = ppSkip( x )
	loop

	function = x
end function

private function cSkip( byval x as integer ) as integer
	do
		x += 1

		select case( tkGet( x ) )
		case TK_SPACE, TK_COMMENT, TK_EOL

		case TK_BEGIN
			x = hSkipFromTo( x, TK_BEGIN, TK_END, 1 )

		case else
			exit do
		end select
	loop

	function = x
end function

private function cSkipRev( byval x as integer ) as integer
	do
		x -= 1

		select case( tkGet( x ) )
		case TK_SPACE, TK_COMMENT, TK_EOL

		case TK_END
			x = hSkipFromTo( x, TK_END, TK_BEGIN, -1 )

		case else
			exit do
		end select
	loop

	function = x
end function

private function cFindClosingParen( byval x as integer ) as integer
	dim as integer level = any, opening = any, closing = any

	opening = tkGet( x )
	level = 0
	select case( opening )
	case TK_LBRACE
		closing = TK_RBRACE
	case TK_LBRACKET
		closing = TK_RBRACKET
	case TK_LPAREN
		closing = TK_RPAREN
	case else
		return x
	end select

	do
		x = cSkip( x )

		select case( tkGet( x ) )
		case opening
			level += 1

		case closing
			if( level = 0 ) then
				exit do
			end if

			level -= 1

		case TK_EOF
			exit do

		case TK_AST, TK_DIVIDER
			exit do

		end select
	loop

	function = x
end function

function cSkipStatement( byval x as integer ) as integer
	do
		select case( tkGet( x ) )
		case TK_EOF
			exit do

		case TK_SEMI
			x = cSkip( x )
			exit do

		case TK_LPAREN, TK_LBRACKET, TK_LBRACE
			x = cFindClosingParen( x )

		case TK_AST, TK_DIVIDER
			exit do

		case else
			x = cSkip( x )
		end select
	loop

	function = x
end function

''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

private function hCollectComments _
	( _
		byval first as integer, _
		byval last as integer _
	) as string

	dim as string s
	dim as zstring ptr text = any

	'' Collect all comment text from a range of tokens and merge it into
	'' one string, which can be used
	for i as integer = first to last
		if( tkGet( i ) = TK_COMMENT ) then
			text = tkGetText( i )
		else
			text = tkGetComment( i )
		end if

		if( text ) then
			if( len( s ) > 0 ) then
				s += !"\n"
			end if
			s += *text
		end if
	next

	function = s
end function

private function hIsBeforeEol _
	( _
		byval x as integer, _
		byval delta as integer _
	) as integer

	function = TRUE

	'' Can we reach EOL before hitting any non-space token?
	do
		x += delta

		select case( tkGet( x ) )
		case TK_SPACE, TK_COMMENT

		case TK_EOL, TK_EOF
			exit do

		case TK_AST, TK_DIVIDER
			'' High-level tokens count as separate lines
			exit do

		case else
			function = FALSE
			exit do
		end select
	loop

end function

private sub hAccumComment( byval x as integer, byref comment as string )
	dim as zstring ptr s = any
	dim as string text

	if( len( comment ) = 0 ) then
		exit sub
	end if

	s = tkGetComment( x )
	if( s ) then
		text = *s + !"\n"
	end if

	text += comment

	tkSetComment( x, text )
end sub

private sub hAccumTkComment( byval x as integer, byval comment as integer )
	assert( tkGet( comment ) = TK_COMMENT )
	hAccumComment( x, *tkGetText( comment ) )
end sub

sub cAssignComments( )
	dim as integer x = any, y = any, at_bol = any, at_eol = any

	x = 0
	do
		select case( tkGet( x ) )
		case TK_EOF
			exit do

		case TK_COMMENT
			''
			'' int A; //FOO    -> assign FOO to ';', so it can be
			''                    picked up by the A vardecl
			''
			''  /*FOO*/ int A; -> assign FOO to 'int', ditto
			''
			'' //FOO           -> assign FOO to EOL, so it can be
			'' <empty line>       picked up by a TK_DIVIDER
			''
			'' //FOO           -> assign FOO to EOL, ditto
			'' int A;
			'' <empty line>
			''
			'' //FOO           -> comment belongs to both A and B,
			'' int A;             assign to EOL for a TK_DIVIDER
			'' int B;
			''
			'' int /*FOO*/ A;  -> assign FOO to 'int'
			''
			'' int             -> assign FOO to EOL
			'' //FOO
			'' A;

			at_bol = hIsBeforeEol( x, -1 )
			at_eol = hIsBeforeEol( x,  1 )

			if( at_bol and at_eol ) then
				'' Comment above empty line?
				if( tkCount( TK_EOL, x + 1, cSkip( x ) ) >= 2 ) then
					hAccumTkComment( tkSkipSpaceAndComments( x ), x )
				else
					'' Comment above multiple statements,
					'' that aren't separated by empty lines?
					y = cSkipStatement( x )
					if( (y < cSkipStatement( y )) and _
					    (tkCount( TK_EOL, cSkipRev( y ) + 1, y - 1 ) < 2) ) then
						hAccumTkComment( tkSkipSpaceAndComments( x ), x )
					else
						'' Comment above single statement
						hAccumTkComment( cSkip( x ), x )
					end if
				end if
			elseif( at_bol ) then
				hAccumTkComment( tkSkipSpaceAndComments( x ), x )
			elseif( at_eol ) then
				hAccumTkComment( tkSkipSpaceAndComments( x, -1 ), x )
			else
				hAccumTkComment( tkSkipSpaceAndComments( x ), x )
			end if

			tkRemove( x, x )
			x -= 1

		end select

		x += 1
	loop
end sub

''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

private function ppDirective( byval x as integer ) as integer
	dim as integer begin = any, tk = any, y = any
	dim as ASTNODE ptr expr = any

	'' not at BOL?
	y = tkSkipSpaceAndComments( x, -1 )
	select case( tkGet( y ) )
	case TK_EOL, TK_EOF
		return -1
	end select

	'' '#'
	if( tkGet( x ) <> TK_HASH ) then
		return -1
	end if
	x = ppSkip( x )

	begin = x
	expr = NULL

	tk = tkGet( x )
	select case( tk )
	'' DEFINE Identifier ['(' ParameterList ')'] Body Eol .
	case KW_DEFINE
		'' DEFINE
		x = ppSkip( x )

		'' Identifier?
		if( tkGet( x ) <> TK_ID ) then
			return -1
		end if
		expr = astNewPPDEFINE( tkGetText( x ) )
		x = ppSkip( x )

		tkRemove( begin, x - 1 )
		tkInsert( begin, TK_AST, , expr )
		begin += 1
		x = begin
		expr = NULL

		'' Parse body tokens, if any, and wrap them inside a BEGIN/END
		select case( tkGet( x ) )
		case TK_EOL, TK_EOF

		case else
			tkInsert( x, TK_BEGIN )
			x += 1

			x = ppSkipToEOL( x )

			tkInsert( x, TK_END )
			x += 1
		end select


''		'' If it's just a number literal, use a proper CONST expression
''		select case( tkGet( x ) )
''		case TK_DECNUM, TK_HEXNUM, TK_OCTNUM
''			select case( tkGet( ppSkip( x ) ) )
''			case TK_EOL, TK_EOF
''				select case( tkGet( x ) )
''				case TK_DECNUM
''					expr = astNewCONSTi( vallng( *tkGetText( x ) ) )
''				case TK_HEXNUM
''					expr = astNewCONSTi( vallng( "&h" + *tkGetText( x ) ) )
''				case TK_OCTNUM
''					expr = astNewCONSTi( vallng( "&o" + *tkGetText( x ) ) )
''				end select
''			end select
''		end select
''
''		'' Otherwise, if there are any tokens, fall back to a TEXT
''		'' expression, that may have to be translated manually
''		if( expr = NULL ) then
''			select case( tkGet( x ) )
''			case TK_EOL, TK_EOF
''
''			case else
''				y = ppSkipToEOL( x )
''				expr = astNewTEXT( tkToText( x, y ) )
''				x = y
''			end select
''		end if
''
''		expr = astNewPPDEFINE( text, expr )

	case KW_INCLUDE
		'' INCLUDE
		x = ppSkip( x )

		'' "..."
		if( tkGet( x ) <> TK_STRING ) then
			return -1
		end if
		expr = astNewPPINCLUDE( tkGetText( x ) )
		x = ppSkip( x )

	case KW_IFDEF, KW_IFNDEF
		x = ppSkip( x )

		'' Identifier?
		if( tkGet( x ) <> TK_ID ) then
			return -1
		end if
		expr = astNewID( tkGetText( x ) )
		x = ppSkip( x )

		expr = astNewDEFINED( expr )
		if( tk = KW_IFNDEF ) then
			expr = astNewLOGICNOT( expr )
		end if
		expr = astNewPPIF( expr )

	case KW_ELSE, KW_ENDIF
		x = ppSkip( x )

		if( tk = KW_ELSE ) then
			expr = astNewPPELSE( )
		else
			expr = astNewPPENDIF( )
		end if

	case else
		return -1
	end select

	'' EOL?
	select case( tkGet( x ) )
	case TK_EOL
		x = ppSkip( x )

	case TK_EOF

	case else
		return -1
	end select

	if( expr ) then
		tkRemove( begin, x - 1 )
		tkInsert( begin, TK_AST, , expr )
		begin += 1
		x = begin
	end if

	function = x
end function

private function ppUnknownDirective( byval x as integer ) as integer
	dim as integer begin = any, y = any
	dim as ASTNODE ptr expr = any

	begin = x

	'' not at BOL?
	y = tkSkipSpaceAndComments( x, -1 )
	select case( tkGet( y ) )
	case TK_EOL, TK_EOF
		return -1
	end select

	'' '#'
	if( tkGet( x ) <> TK_HASH ) then
		return -1
	end if
	x = ppSkip( x )

	y = ppSkipToEOL( x )
	expr = astNewPPUNKNOWN( tkToText( x, y ) )
	x = y

	'' EOL? (could also be EOF)
	if( tkGet( x ) = TK_EOL ) then
		x = ppSkip( x )
	end if

	tkRemove( begin, x - 1 )
	tkInsert( begin, TK_AST, , expr )
	begin += 1
	x = begin

	function = x
end function

'' Merge empty lines into TK_DIVIDER. We can assume to start at BOL,
'' as cPPDirectives() effectively parses one line after another.
private function ppDivider( byval x as integer ) as integer
	dim as integer lines = any, begin = any, eol1 = any, eol2 = any
	dim as string comment, blockcomment

	begin = x

	'' Count empty lines in a row
	lines = 0
	do
		select case( tkGet( x ) )
		case TK_EOL
			lines += 1

		case TK_SPACE

		case else
			exit do
		end select

		x += 1
	loop

	if( lines < 1 ) then
		return -1
	end if

	''  ...code...
	''
	''  //foo
	''
	''  //bar
	''  ...code...
	''
	'' "foo" is the comment associated with TK_DIVIDER, "bar" the one
	'' associated with the following block of code, stored as TK_DIVIDER's
	'' text.

	eol2 = tkSkipSpaceAndComments( x, -1 )
	eol1 = tkSkipSpaceAndComments( eol2 - 1, -1 )
	blockcomment = hCollectComments( eol1 + 1, eol2 )

	comment = hCollectComments( begin, eol1 )
	tkRemove( begin, x - 1 )
	tkInsert( begin, TK_DIVIDER, blockcomment )
	tkSetComment( begin, comment )
	x = cSkip( begin )

	function = x
end function

sub cPPDirectives( )
	dim as integer x = any, old = any

	x = ppSkip( -1 )
	while( tkGet( x ) <> TK_EOF )
		old = x

		x = ppDirective( old )
		if( x >= 0 ) then
			continue while
		end if

		x = ppUnknownDirective( old )
		if( x >= 0 ) then
			continue while
		end if

		x = ppDivider( old )
		if( x >= 0 ) then
			continue while
		end if

		'' Skip to next line
		x = ppSkip( ppSkipToEOL( old ) )
	wend
end sub

''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

private function cSimpleToken( ) as ASTNODE ptr
	dim as ASTNODE ptr t = any

	select case( tkGet( parse.x ) )
	case TK_SEMI
		'' Cannot just return NULL, because we need to indicate success,
		'' so a NOP node is needed...
		t = astNew( ASTCLASS_NOP )
		parse.x = cSkip( parse.x )

	case TK_AST
		'' Any pre-existing high-level tokens (things transformed by
		'' previous parsing, such as PP directives, or anything inserted
		'' by presets) need to be recognized as "valid constructs" too.
		t = astClone( tkGetAst( parse.x ) )
		parse.x = cSkip( parse.x )

	case TK_DIVIDER
		'' (ditto)
		t = astNew( ASTCLASS_DIVIDER )
		parse.x = cSkip( parse.x )

	case else
		t = NULL
	end select

	function = t
end function

private function hMergeUnknown( ) as ASTNODE ptr
	dim as integer begin = any

	function = NULL

	if( (parse.pass = 1) or (tkIsPoisoned( parse.x ) = FALSE) ) then
		exit function
	end if

	begin = parse.x
	do
		parse.x += 1
	loop while( tkIsPoisoned( parse.x ) )

	function = astNewUNKNOWN( tkToText( begin, parse.x - 1 ) )
end function

private sub cUnknown( )
	dim as integer begin = any

	'' This should only be called during the 1st pass
	assert( parse.pass = 1 )

	begin = parse.x
	parse.x = cSkipStatement( parse.x )
	tkSetPoisoned( begin, parse.x - 1 )
end sub

'' (MultDecl{Field} | StructCompound)*
private function cStructBody( ) as ASTNODE ptr
	dim as ASTNODE ptr group = any, t = any
	dim as integer old = any

	group = astNew( ASTCLASS_GROUP )

	do
		select case( tkGet( parse.x ) )
		case TK_RBRACE, TK_EOF
			exit do
		end select

		old = parse.x

		t = hMergeUnknown( )
		if( t = NULL ) then
			parse.x = old
			t = cStructCompound( )
			if( t = NULL ) then
				parse.x = old
				t = cMultDecl( DECL_FIELD )
				if( t = NULL ) then
					parse.x = old
					t = cSimpleToken( )
					if( t = NULL ) then
						parse.x = old
						cUnknown( )
					end if
				end if
			end if
		end if

		if( t ) then
			astAddChild( group, t )
		end if
	loop

	function = group
end function

'' [TYPEDEF] {STRUCT|UNION} [Identifier] '{' StructBody '}' [MultDecl] ';'
private function cStructCompound( ) as ASTNODE ptr
	dim as ASTNODE ptr struct = any, subtype = any, group = any, t = any
	dim as integer head = any, is_typedef = any
	dim as string id

	function = NULL
	head = parse.x
	is_typedef = FALSE

	'' TYPEDEF?
	if( tkGet( parse.x ) = KW_TYPEDEF ) then
		parse.x = cSkip( parse.x )
		is_typedef = TRUE
	end if

	'' {STRUCT|UNION}
	select case( tkGet( parse.x ) )
	case KW_STRUCT, KW_UNION

	case else
		exit function
	end select
	parse.x = cSkip( parse.x )

	'' [Identifier]
	if( tkGet( parse.x ) = TK_ID ) then
		id = *tkGetText( parse.x )
		parse.x = cSkip( parse.x )
	elseif( is_typedef ) then
		'' If it's a typedef with anonymous struct block, we need to
		'' make up an id for it, for use in the base type of the
		'' typedef MultDecl. If it turns out to be just a single
		'' typedef, we can still solve it out later.
		id = hMakeTempId( )
	end if

	'' '{'
	if( tkGet( parse.x ) <> TK_LBRACE ) then
		exit function
	end if
	parse.x = cSkip( parse.x )

	struct = astNew( ASTCLASS_STRUCT )
	astSetId( struct, id )
	astAddComment( struct, hCollectComments( head, parse.x - 1 ) )

	astAddChild( struct, cStructBody( ) )

	'' '}'
	if( tkGet( parse.x ) <> TK_RBRACE ) then
		astDelete( struct )
		exit function
	end if
	parse.x = cSkip( parse.x )

	if( is_typedef ) then
		subtype = astNewID( id )
		t = cIdList( DECL_TYPEDEF, TYPE_UDT, subtype )
		astDelete( subtype )

		if( t = NULL ) then
			astDelete( struct )
			exit function
		end if

		group = astNew( ASTCLASS_GROUP )
		astAddChild( group, struct )
		astAddChild( group, t )
	else
		'' ';'
		if( tkGet( parse.x ) <> TK_SEMI ) then
			astDelete( struct )
			exit function
		end if
		parse.x = cSkip( parse.x )

		group = struct
	end if

	function = group
end function

''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

''
'' Declaration base type parsing
''
'' The base type is the data type part of a variable/procedure/typedef/parameter
'' declaration that is at the front, in front of the identifier list.
'' '*' chars indicating pointers belong to the identifier, not the type.
''
''    int a, b, c;
''    ^^^
''
''    struct UDT const *p, **pp;
''    ^^^^^^^^^^^^^^^^
''
'' Besides the base type there can be modifiers such as "signed", "unsigned",
'' "const", "short", "long". They can be used together with some base types,
'' for example "short int a;", or alone: "short a;". Modifiers can appear in
'' front of the base type or behind it, in any order. Some modifiers are
'' incompatible to each-other, such as "signed" and "unsigned", or "short" and
'' "long". There may only be 1 "short", and only 1 or 2 "long"s.
''
''    short int a;
''    unsigned a;
''    const int unsigned a;
''    long const a;
''    long long int a;
''    const const unsigned long const long const int const unsigned a;
''
'' Returns TRUE/FALSE to indicate success/failure. The type is returned through
'' the byref parameters.
''
private function cBaseType _
	( _
		byref dtype as integer, _
		byref subtype as ASTNODE ptr, _
		byval decl as integer _
	) as integer

	dim as integer sign = any, signedmods = any, unsignedmods = any
	dim as integer constmods = any, shortmods = any, longmods = any
	dim as integer basetypex = any, basetypetk = any

	dtype = TYPE_NONE
	subtype = NULL
	function = FALSE

	signedmods = 0
	unsignedmods = 0
	constmods = 0
	shortmods = 0
	longmods = 0
	basetypex = -1
	basetypetk = -1

	''
	'' 1. Parse base type and all modifiers, and count them
	''

	do
		select case as const( tkGet( parse.x ) )
		case KW_SIGNED
			signedmods += 1

		case KW_UNSIGNED
			unsignedmods += 1

		case KW_CONST
			constmods += 1

		case KW_SHORT
			shortmods += 1

		case KW_LONG
			longmods += 1

		case else
			'' Only one base type is allowed
			if( basetypex >= 0 ) then
				exit do
			end if

			select case as const( tkGet( parse.x ) )
			case KW_ENUM, KW_STRUCT, KW_UNION
				'' {ENUM|STRUCT|UNION}
				parse.x = cSkip( parse.x )

				'' Identifier
				if( tkGet( parse.x ) <> TK_ID ) then
					exit function
				end if
				basetypex = parse.x

			case TK_ID
				''
				'' Disambiguation needed:
				''    signed foo;       // foo = var id
				''    signed foo, bar;  // foo = var id, bar = var id
				''    signed foo(void); // foo = function id
				''    signed foo[1];    // foo = array id
				'' vs.
				''    signed foo bar;   // foo = typedef, bar = var id
				''    signed foo *bar;  // ditto
				''    signed foo (*bar)(void);  // ditto
				''    signed foo const bar;  // ditto
				''
				'' Checking for this is only needed if there
				'' already were tokens that belong to the type
				'' in front of the TK_ID, e.g. "signed" or
				'' "long", but not "const" which cannot be given
				'' alone in place of a type.
				''
				'' If a type is expected, and a TK_ID appears
				'' as first token, then it just must be part of
				'' the type, afterall something like
				''    foo;
				'' isn't allowed; it has to be at least
				''    mytype foo;
				''
				'' For parameters the identifier can be omitted
				'' optionally, disambiguation is impossible
				'' based on syntax only:
				''    void f(unsigned myint);
				'' vs.
				''    typedef int myint;
				''    void f(unsigned myint);
				'' To be safe, we should always assume it's the
				'' identifier
				''

				'' Already saw modifiers that themselves would
				'' be enough to form the type?
				if( signedmods or unsignedmods or _
				    longmods or shortmods ) then
					select case( tkGet( cSkip( parse.x ) ) )
					case TK_ID
						'' Another id must follow for params,
						'' otherwise it's ambigious
						if( decl = DECL_PARAM ) then
							exit function
						end if

					case TK_SEMI, TK_COMMA, TK_LBRACKET
						exit do

					case TK_LPAREN
						if( tkGet( cSkip( cSkip( parse.x ) ) ) <> TK_STAR ) then
							exit do
						end if
					end select
				end if

				'' Treat the TK_ID as the type (a typedef)
				basetypex = parse.x

			case KW_VOID, KW_CHAR, KW_FLOAT, KW_DOUBLE, KW_INT
				basetypex = parse.x

			case else
				exit do
			end select
		end select

		parse.x = cSkip( parse.x )
	loop

	''
	'' 2. Refuse invalid modifier combinations etc.
	''

	if( basetypex >= 0 ) then
		basetypetk = tkGet( basetypex )
	end if

	'' Can't have both SIGNED and UNSIGNED
	if( (signedmods > 0) and (unsignedmods > 0) ) then
		exit function
	end if

	'' Neither both SHORT and LONG
	if( (shortmods > 0) and (longmods > 0) ) then
		exit function
	end if

	'' Max. 1 SHORT allowed, and 1 or 2 LONGs
	if( (shortmods > 1) or (longmods > 2) ) then
		exit function
	end if

	select case( basetypetk )
	case TK_ID, KW_VOID, KW_FLOAT, KW_DOUBLE
		'' No SIGNED|UNSIGNED|SHORT|LONG for UDTs/floats/void
		'' (cannot be translated to FB)
		if( signedmods or unsignedmods or shortmods or longmods ) then
			exit function
		end if

		select case( basetypetk )
		case TK_ID
			dtype = TYPE_UDT
			subtype = astNewID( tkGetText( basetypex ) )
		case KW_VOID
			dtype = TYPE_ANY
		case KW_FLOAT
			dtype = TYPE_SINGLE
		case KW_DOUBLE
			dtype = TYPE_DOUBLE
		case else
			assert( FALSE )
		end select

	case KW_CHAR
		'' No SHORT|LONG CHAR allowed
		if( shortmods or longmods ) then
			exit function
		end if

		'' SIGNED|UNSIGNED CHAR becomes BYTE|UBYTE,
		'' but plain CHAR probably means ZSTRING
		if( signedmods > 0 ) then
			dtype = TYPE_BYTE
		elseif( unsignedmods > 0 ) then
			dtype = TYPE_UBYTE
		else
			dtype = TYPE_ZSTRING
		end if

	case else
		'' Base type is "int" (either explicitly given, or implied
		'' because no other base type was given). Any modifiers are
		'' just added on top of that.
		if( shortmods = 1 ) then
			dtype = iif( unsignedmods > 0, TYPE_USHORT, TYPE_SHORT )
		elseif( longmods = 1 ) then
			'' TODO: How to handle translation of longs (32bit vs. 64bit)?
			exit function
		elseif( longmods = 2 ) then
			dtype = iif( unsignedmods > 0, TYPE_ULONGINT, TYPE_LONGINT )
		elseif( basetypetk = KW_INT ) then
			'' Explicit "int" base type and no modifiers
			dtype = iif( unsignedmods > 0, TYPE_ULONG, TYPE_LONG )
		elseif( unsignedmods > 0 ) then
			'' UNSIGNED only
			dtype = TYPE_ULONG
		elseif( signedmods > 0 ) then
			'' SIGNED only
			dtype = TYPE_LONG
		else
			'' No modifiers and no explicit "int" either
			exit function
		end if

	end select

	'' Any CONSTs on the base type are merged into one
	''    const int a;
	''    const int const a;
	''          int const a;
	''    const const int const const a;
	'' It's all the same...
	if( constmods > 0 ) then
		dtype = typeSetIsConst( dtype )
	end if

	function = TRUE
end function

'' ParamDecl = '...' | MultDecl{Param}
private function cParamDecl( ) as ASTNODE ptr
	dim as ASTNODE ptr t = any

	'' '...'?
	if( tkGet( parse.x ) = TK_ELLIPSIS ) then
		t = astNew( ASTCLASS_PARAM )
		astAddComment( t, hCollectComments( parse.x, cSkip( parse.x ) - 1 ) )
		parse.x = cSkip( parse.x )
	else
		t = cMultDecl( DECL_PARAM )
	end if

	function = t
end function

'' ParamDeclList = ParamDecl (',' ParamDecl)*
private function cParamDeclList( ) as ASTNODE ptr
	dim as ASTNODE ptr group = any, t = any

	function = NULL
	group = astNew( ASTCLASS_GROUP )

	do
		t = cParamDecl( )
		if( t = NULL ) then
			astDelete( group )
			exit function
		end if

		astAddChild( group, t )

		'' ','?
		if( tkGet( parse.x ) <> TK_COMMA ) then
			exit do
		end if
		parse.x = cSkip( parse.x )
	loop

	function = group
end function

''
'' Declarator =
''    '*'*
''    { [Identifier] | '(' Declarator ')' }
''    { '(' ParamList ')' | '[' ArrayElements ']' }
''
'' This needs to parse things like:
''    i            for example, as part of: int i;
''    i[10]        array: int i[10];
''    <nothing>    anonymous parameter: int f(int);
''    ()           extra parentheses on anonymous parameter: int f(int ());
''    ***p         int ***p;
''    (*p)(void)   function pointer: void (*p)(void);
''    (((i)))      extra parentheses around identifier: int (((i)));
''    *(*(pp))     ditto
''    (*f(void))(void)    function returning a function pointer:
''                            void (*f(void))(void);
''    (*p[10])(void)      array of function pointers: void (*p[10])(void);
''
private function cDeclarator _
	( _
		byval decl as integer, _
		byval basedtype as integer, _
		byval basesubtype as ASTNODE ptr, _
		byref procptrdtype as integer _
	) as ASTNODE ptr

	dim as ASTNODE ptr proc = any, t = any, params = any
	dim as integer begin = any, astclass = any, elements = any
	dim as integer dtype = any, innerprocptrdtype = any
	dim as string id

	function = NULL
	begin = parse.x
	dtype = basedtype
	innerprocptrdtype = TYPE_PROC
	procptrdtype = TYPE_PROC
	elements = 0

	'' Pointers: ('*')*
	while( tkGet( parse.x ) = TK_STAR )
		procptrdtype = typeAddrOf( procptrdtype )
		dtype = typeAddrOf( dtype )
		parse.x = cSkip( parse.x )

		'' (CONST)*
		while( tkGet( parse.x ) = KW_CONST )
			procptrdtype = typeSetIsConst( procptrdtype )
			dtype = typeSetIsConst( dtype )
			parse.x = cSkip( parse.x )
		wend
	wend

	if( tkGet( parse.x ) = TK_LPAREN ) then
		'' '('
		parse.x = cSkip( parse.x )

		t = cDeclarator( decl, dtype, basesubtype, innerprocptrdtype )
		if( t = NULL ) then
			exit function
		end if

		'' ')'
		if( tkGet( parse.x ) <> TK_RPAREN ) then
			astDelete( t )
			exit function
		end if
		parse.x = cSkip( parse.x )
	else
		if( tkGet( parse.x ) = TK_ID ) then
			id = *tkGetText( parse.x )
			parse.x = cSkip( parse.x )
		else
			'' An identifier must exist, except for parameters
			if( decl <> DECL_PARAM ) then
				exit function
			end if
		end if

		select case( decl )
		case DECL_VAR, DECL_EXTERNVAR, DECL_STATICVAR
			astclass = ASTCLASS_VAR
		case DECL_FIELD
			astclass = ASTCLASS_FIELD
		case DECL_PARAM
			astclass = ASTCLASS_PARAM
		case DECL_TYPEDEF
			astclass = ASTCLASS_TYPEDEF
		case else
			assert( FALSE )
		end select

		t = astNew( astclass )

		select case( decl )
		case DECL_EXTERNVAR
			t->attrib or= ASTATTRIB_EXTERN
		case DECL_STATICVAR
			t->attrib or= ASTATTRIB_STATIC
		end select

		astSetId( t, id )
		astSetType( t, dtype, basesubtype )
		astAddComment( t, hCollectComments( begin, parse.x - 1 ) )
	end if

	select case( tkGet( parse.x ) )
	'' '[' ArrayElements ']'
	case TK_LBRACKET
		parse.x = cSkip( parse.x )

		'' Simple number?
		if( tkGet( parse.x ) <> TK_DECNUM ) then
			astDelete( t )
			exit function
		end if
		elements = valint( *tkGetText( parse.x ) )
		parse.x = cSkip( parse.x )

		'' ']'
		if( tkGet( parse.x ) <> TK_RBRACKET ) then
			astDelete( t )
			exit function
		end if
		parse.x = cSkip( parse.x )

	'' '(' ParamList ')'
	case TK_LPAREN
		parse.x = cSkip( parse.x )

		'' Parameters turn a vardecl/fielddecl into a procdecl,
		'' unless they're for a procptr type.
		if( innerprocptrdtype <> TYPE_PROC ) then
			'' There were '()'s above and the recursive
			'' cDeclarator() call found pointers/CONSTs,
			'' these parameters are for a function pointer.
			proc = astNew( ASTCLASS_PROC )

			'' The function pointer's result type is the
			'' base type plus any pointers up to this level.
			astSetType( proc, dtype, basesubtype )

			'' The declared symbol's type is the function
			'' pointer plus additional pointers if any
			astDelete( t->subtype )
			t->dtype = innerprocptrdtype
			t->subtype = proc
		else
			'' A plain symbol, not a pointer, becomes a function
			select case( t->class )
			case ASTCLASS_VAR, ASTCLASS_FIELD
				t->class = ASTCLASS_PROC
			end select
			proc = t
		end if

		'' Just '(void)'?
		if( (tkGet( parse.x ) = KW_VOID) and (tkGet( cSkip( parse.x ) ) = TK_RPAREN) ) then
			'' VOID
			parse.x = cSkip( parse.x )
		'' Not just '()'?
		elseif( tkGet( parse.x ) <> TK_RPAREN ) then
			params = cParamDeclList( )
			if( params = NULL ) then
				astDelete( t )
				exit function
			end if
			astAddChild( proc, params )
		end if

		'' ')'
		if( tkGet( parse.x ) <> TK_RPAREN ) then
			astDelete( t )
			exit function
		end if
		parse.x = cSkip( parse.x )
	end select

	function = t
end function

'' IdList = Declarator (',' Declarator)* [';']
private function cIdList _
	( _
		byval decl as integer, _
		byval basedtype as integer, _
		byval basesubtype as ASTNODE ptr _
	) as ASTNODE ptr

	dim as ASTNODE ptr group = any, t = any

	function = NULL
	group = astNew( ASTCLASS_GROUP )

	'' ... (',' ...)*
	do
		t = cDeclarator( decl, basedtype, basesubtype, 0 )
		if( t = NULL ) then
			astDelete( group )
			exit function
		end if

		astAddChild( group, t )

		'' Everything can have a comma and more identifiers,
		'' except for parameters.
		if( decl = DECL_PARAM ) then
			exit do
		end if

		'' ','?
		if( tkGet( parse.x ) <> TK_COMMA ) then
			exit do
		end if
		parse.x = cSkip( parse.x )
	loop

	'' Everything except parameters must end with a ';'
	if( decl <> DECL_PARAM ) then
		'' ';'
		if( tkGet( parse.x ) <> TK_SEMI ) then
			astDelete( group )
			exit function
		end if
		parse.x = cSkip( parse.x )
	end if

	function = group
end function

''
'' Generic 'type *a, **b;' parsing, used for vars/fields/protos/params/typedefs
'' ("multiple declaration" syntax)
''    int i;
''    int a, b, c;
''    int *a, ***b, c;
''    int f(void);
''    int (*procptr)(void);
''
'' MultDecl = BaseType IdList
''
private function cMultDecl( byval decl as integer ) as ASTNODE ptr
	dim as integer dtype = any, typebegin = any, typeend = any
	dim as ASTNODE ptr subtype = any

	function = NULL

	'' BaseType
	typebegin = parse.x
	if( cBaseType( dtype, subtype, decl ) = FALSE ) then
		exit function
	end if
	typeend = parse.x

	function = cIdList( decl, dtype, subtype )
	astDelete( subtype )
end function

'' Global variable/procedure declarations
''    [EXTERN|STATIC] MultDecl
private function cGlobalDecl( ) as ASTNODE ptr
	dim as integer decl = any

	select case( tkGet( parse.x ) )
	case KW_EXTERN, KW_STATIC
		if( tkGet( parse.x ) = KW_EXTERN ) then
			decl = DECL_EXTERNVAR
		else
			decl = DECL_STATICVAR
		end if
		parse.x = cSkip( parse.x )
	case else
		decl = DECL_VAR
	end select

	function = cMultDecl( decl )
end function

'' Typedefs
''    TYPEDEF MultDecl
private function cTypedef( ) as ASTNODE ptr
	function = NULL

	'' TYPEDEF?
	if( tkGet( parse.x ) <> KW_TYPEDEF ) then
		exit function
	end if
	parse.x = cSkip( parse.x )

	function = cMultDecl( DECL_TYPEDEF )
end function

private function hToplevel( ) as ASTNODE ptr
	dim as integer old = any
	dim as ASTNODE ptr group = any, t = any

	group = astNew( ASTCLASS_GROUP )
	parse.x = cSkip( -1 )

	while( tkGet( parse.x ) <> TK_EOF )
		old = parse.x

		t = hMergeUnknown( )
		if( t = NULL ) then
			parse.x = old
			t = cStructCompound( )
			if( t = NULL ) then
				parse.x = old
				t = cGlobalDecl( )
				if( t = NULL ) then
					parse.x = old
					t = cTypedef( )
					if( t = NULL ) then
						parse.x = old
						t = cSimpleToken( )
						if( t = NULL ) then
							parse.x = old
							cUnknown( )
						end if
					end if
				end if
			end if
		end if

		if( t ) then
			astAddChild( group, t )
		end if
	wend

	function = group
end function

function cToplevel( ) as ASTNODE ptr
	'' 1st pass to identify constructs & set marks correspondingly
	parse.pass = 1
	parse.tempidcount = 0
	astDelete( hToplevel( ) )

	'' 2nd pass to build up AST
	parse.pass = 2
	parse.tempidcount = 0
	function = hToplevel( )
end function
