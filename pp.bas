''
'' Token buffer preprocessing
'' --------------------------
''
'' ppComments() removes TK_COMMENTs, for easier parsing later. It can assign
'' their text to other tokens (tkSetComment()) if comments should be preserved
'' for later.
''
'' ppDividers() merges empty lines (i.e. multiple TK_EOLs) into TK_DIVIDERs,
'' for nicer output formatting later. It can be nice to preserve the
'' block/section/paragraph layout of the input, and still trim down unnecessary
'' newlines.
''
''
'' CPP directive parsing, #if evaluation, macro expansion
'' ------------------------------------------------------
''
'' ppDirectives1() merges PP directives into TK_PP* tokens, except that #define
'' bodies and #if expressions are not yet parsed, but only enclosed in TK_BEGIN
'' and TK_END tokens. This basic identification of PP directives is enough for
'' an #include detection pre-parsing step.
''
'' ppDirectives2() goes through all #defines and finishes the parsing job by
'' parsing the #define bodies into ASTs and removing the TK_BEGIN/END parts.
'' This allows for token replacements in #define bodies before this step.
''
'' ppEval() goes through the token buffer almost like a C preprocessor would do.
'' It keeps track of #defines and #undefs and expands macro calls for "precious"
'' macros. It also expands macros inside #if conditions, then parses them as
'' expressions, evaluates them, and solves out #if blocks, preserving only the
'' #if/#else paths, depending on whether the expression evaluated to TRUE/FALSE.
''
'' ppAddSym() can be used to register symbols as initially "defined" or
'' "undefined". This helps evaluating #if defined() or #ifdef checks for symbols
'' that aren't #define'd in code. If an #if block can't be solved out because of
'' an unknown symbol, an error will be shown.
''
'' ppExpandSym() can be used to mark symbols as "precious", telling ppEval()
'' that it should try to do macro expansion for it, if a corresponding #define
'' is found. ppMacro*() can be used to register initial #defines.
''

#include once "fbfrog.bi"

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
		case TK_COMMENT

		case TK_EOL, TK_EOF
			exit do

		case TK_PPINCLUDE, TK_PPDEFINE, TK_PPIF, TK_PPELSEIF, _
		     TK_PPELSE, TK_PPENDIF, TK_PPUNDEF, TK_DIVIDER
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

private sub hStripAllComments( )
	dim as integer x = any
	x = 0
	while( tkGet( x ) <> TK_EOF )
		if( tkGet( x ) = TK_COMMENT ) then
			tkRemove( x, x )
			x -= 1
		end if
		x += 1
	wend
end sub

private function hFindClosingParen( byval x as integer ) as integer
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
		x = tkSkipCommentEol( x )

		select case( tkGet( x ) )
		case opening
			level += 1

		case closing
			if( level = 0 ) then
				exit do
			end if

			level -= 1

		case TK_EOF
			x -= 1
			exit do

		case TK_PPINCLUDE, TK_PPDEFINE, TK_PPIF, TK_PPELSEIF, _
		     TK_PPELSE, TK_PPENDIF, TK_PPUNDEF, TK_DIVIDER
			x = tkSkipCommentEol( x, -1 )
			exit do

		end select
	loop

	function = x
end function

private function hSkipStatement( byval x as integer ) as integer
	var begin = x

	do
		select case( tkGet( x ) )
		case TK_EOF
			exit do

		'' ';' (statement separator)
		case TK_SEMI
			x = tkSkipCommentEol( x )
			exit do

		'' '}': usually indicates end of statement, unless we're trying
		'' to skip a '}' itself
		case TK_RBRACE
			if( x > begin ) then
				exit do
			end if

		case TK_PPINCLUDE, TK_PPDEFINE, TK_PPIF, TK_PPELSEIF, _
		     TK_PPELSE, TK_PPENDIF, TK_PPUNDEF, TK_DIVIDER
			'' Reached high-level token after having seen normals?
			if( x > begin ) then
				exit do
			end if

		case TK_LPAREN, TK_LBRACKET, TK_LBRACE
			x = hFindClosingParen( x )
		end select

		x = tkSkipCommentEol( x )
	loop

	assert( x > begin )
	function = x
end function

private function ppComment( byval x as integer ) as integer
	dim as integer y = any, at_bol = any, at_eol = any

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
		if( tkCount( TK_EOL, x + 1, tkSkipCommentEol( x ) ) >= 2 ) then
			hAccumTkComment( tkSkipComment( x ), x )
		else
			'' Comment above multiple statements,
			'' that aren't separated by empty lines?
			y = hSkipStatement( x )
			if( (y < hSkipStatement( y )) and _
			    (tkCount( TK_EOL, tkSkipCommentEol( y, -1 ) + 1, y - 1 ) < 2) ) then
				hAccumTkComment( tkSkipComment( x ), x )
			else
				'' Comment above single statement
				hAccumTkComment( tkSkipCommentEol( x ), x )
			end if
		end if
	elseif( at_bol ) then
		hAccumTkComment( tkSkipComment( x ), x )
	elseif( at_eol ) then
		hAccumTkComment( tkSkipComment( x, -1 ), x )
	else
		hAccumTkComment( tkSkipComment( x ), x )
	end if

	tkRemove( x, x )
	x -= 1

	function = x
end function

sub ppComments( )
	dim as integer x = any

	'' TODO
	hStripAllComments( )

	x = 0
	do
		select case( tkGet( x ) )
		case TK_EOF
			exit do

		case TK_COMMENT
			x = ppComment( x )

		end select

		x += 1
	loop
end sub

''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

'' Merge empty lines into TK_DIVIDER, assuming we're starting at BOL.
private function ppDivider( byval x as integer ) as integer
	var begin = x

	'' Count empty lines in a row
	var lines = 0
	do
		select case( tkGet( x ) )
		case TK_EOL
			lines += 1

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

	var eol2 = tkSkipComment( x, -1 )
	var eol1 = tkSkipComment( eol2 - 1, -1 )
	var blockcomment = tkCollectComments( eol1 + 1, eol2 )

	var comment = tkCollectComments( begin, eol1 )
	tkRemove( begin, x - 1 )
	tkInsert( begin, TK_DIVIDER, blockcomment )
	tkSetComment( begin, comment )
	x = begin

	function = x
end function

sub ppDividers( )
	var x = 0
	while( tkGet( x ) <> TK_EOF )
		var old = x

		x = ppDivider( old )
		if( x >= 0 ) then
			continue while
		end if

		'' Skip to next BOL
		x = old
		do
			select case( tkGet( x ) )
			case TK_EOF
				exit do
			case TK_EOL
				x += 1
				exit do
			end select

			x += 1
		loop
	wend
end sub

''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

private function ppSkipToEOL( byval x as integer ) as integer
	do
		select case( tkGet( x ) )
		case TK_EOL, TK_EOF
			exit do
		end select

		x += 1
	loop

	function = x
end function

''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

function hNumberLiteral( byval x as integer ) as ASTNODE ptr
	dim as ASTNODE ptr n

	select case( tkGet( x ) )
	case TK_DECNUM
		n = astNewCONST( vallng( *tkGetText( x ) ), 0, TYPE_LONGINT )
	case TK_HEXNUM
		n = astNewCONST( vallng( "&h" + *tkGetText( x ) ), 0, TYPE_LONGINT )
		n->attrib or= ASTATTRIB_HEX
	case TK_OCTNUM
		n = astNewCONST( vallng( "&o" + *tkGetText( x ) ), 0, TYPE_LONGINT )
		n->attrib or= ASTATTRIB_OCT
	case TK_DECFLOAT
		n = astNewCONST( 0, val( *tkGetText( x ) ), TYPE_DOUBLE )
	case else
		assert( FALSE )
	end select

	function = n
end function

type PPOPINFO
	level		as integer
	is_leftassoc	as integer
end type

'' C PP operator precedence (higher value = higher precedence)
dim shared as PPOPINFO ppopinfo(ASTOP_IIF to ASTOP_UNARYPLUS) = _
{ _
	( 2, FALSE), _ '' ASTOP_IIF
	( 3, TRUE ), _ '' ASTOP_LOGOR
	( 4, TRUE ), _ '' ASTOP_LOGAND
	( 5, TRUE ), _ '' ASTOP_BITOR
	( 6, TRUE ), _ '' ASTOP_BITXOR
	( 7, TRUE ), _ '' ASTOP_BITAND
	( 8, TRUE ), _ '' ASTOP_EQ
	( 8, TRUE ), _ '' ASTOP_NE
	( 9, TRUE ), _ '' ASTOP_LT
	( 9, TRUE ), _ '' ASTOP_LE
	( 9, TRUE ), _ '' ASTOP_GT
	( 9, TRUE ), _ '' ASTOP_GE
	(10, TRUE ), _ '' ASTOP_SHL
	(10, TRUE ), _ '' ASTOP_SHR
	(11, TRUE ), _ '' ASTOP_ADD
	(11, TRUE ), _ '' ASTOP_SUB
	(12, TRUE ), _ '' ASTOP_MUL
	(12, TRUE ), _ '' ASTOP_DIV
	(12, TRUE ), _ '' ASTOP_MOD
	(13, TRUE ), _ '' ASTOP_LOGNOT
	(13, TRUE ), _ '' ASTOP_BITNOT
	(13, TRUE ), _ '' ASTOP_NEGATE
	(13, TRUE )  _ '' ASTOP_UNARYPLUS
}

'' C PP expression parser based on precedence climbing
private function ppExpression _
	( _
		byref x as integer, _
		byval level as integer = 0 _
	) as ASTNODE ptr

	'' Unary prefix operators
	var op = -1
	select case( tkGet( x ) )
	case TK_EXCL  : op = ASTOP_LOGNOT    '' !
	case TK_TILDE : op = ASTOP_BITNOT    '' ~
	case TK_MINUS : op = ASTOP_NEGATE    '' -
	case TK_PLUS  : op = ASTOP_UNARYPLUS '' +
	end select

	dim as ASTNODE ptr a
	if( op >= 0 ) then
		var uopx = x
		x += 1
		a = astNewUOP( op, ppExpression( x, ppopinfo(op).level ) )
		a->location = *tkGetLocation( uopx )
	else
		'' Atoms
		select case( tkGet( x ) )
		'' '(' Expression ')'
		case TK_LPAREN
			'' '('
			x += 1

			'' Expression
			a = ppExpression( x )

			'' ')'
			tkExpect( x, TK_RPAREN )
			x += 1

		'' Number literals
		case TK_OCTNUM, TK_DECNUM, TK_HEXNUM, TK_DECFLOAT
			a = hNumberLiteral( x )
			a->location = *tkGetLocation( x )
			x += 1

		'' Identifier
		case TK_ID
			'' Accepting identifiers as atoms to allow more PP
			'' expressions to be parsed, such as
			''    defined FOO && FOO == 123
			'' without having to expand FOO.
			a = astNew( ASTCLASS_ID, tkGetText( x ) )
			a->location = *tkGetLocation( x )
			x += 1

		'' DEFINED '(' Identifier ')'
		case KW_DEFINED
			var definedx = x
			x += 1

			'' '('
			var have_parens = FALSE
			if( tkGet( x ) = TK_LPAREN ) then
				have_parens = TRUE
				x += 1
			end if

			'' Identifier
			tkExpect( x, TK_ID )
			a = astNew( ASTCLASS_ID, tkGetText( x ) )
			a->location = *tkGetLocation( x )
			x += 1

			if( have_parens ) then
				'' ')'
				tkExpect( x, TK_RPAREN )
				x += 1
			end if

			a = astNewUOP( ASTOP_DEFINED, a )
			a->location = *tkGetLocation( definedx )

		case else
			tkOopsExpected( x, "number literal or '(...)' (atom expression)" )
		end select
	end if

	'' Infix operators
	do
		select case as const( tkGet( x ) )
		case TK_QUEST    : op = ASTOP_IIF    '' ? (a ? b : c)
		case TK_PIPEPIPE : op = ASTOP_LOGOR  '' ||
		case TK_AMPAMP   : op = ASTOP_LOGAND '' &&
		case TK_PIPE     : op = ASTOP_BITOR  '' |
		case TK_CIRC     : op = ASTOP_BITXOR '' ^
		case TK_AMP      : op = ASTOP_BITAND '' &
		case TK_EQEQ     : op = ASTOP_EQ     '' ==
		case TK_EXCLEQ   : op = ASTOP_NE     '' !=
		case TK_LT       : op = ASTOP_LT     '' <
		case TK_LTEQ     : op = ASTOP_LE     '' <=
		case TK_GT       : op = ASTOP_GT     '' >
		case TK_GTEQ     : op = ASTOP_GE     '' >=
		case TK_LTLT     : op = ASTOP_SHL    '' <<
		case TK_GTGT     : op = ASTOP_SHR    '' >>
		case TK_PLUS     : op = ASTOP_ADD    '' +
		case TK_MINUS    : op = ASTOP_SUB    '' -
		case TK_STAR     : op = ASTOP_MUL    '' *
		case TK_SLASH    : op = ASTOP_DIV    '' /
		case TK_PERCENT  : op = ASTOP_MOD    '' %
		case else        : exit do
		end select

		'' Higher/same level means process now (takes precedence),
		'' lower level means we're done and the parent call will
		'' continue. The first call will start with level 0.
		var oplevel = ppopinfo(op).level
		if( oplevel < level ) then
			exit do
		end if
		if( ppopinfo(op).is_leftassoc ) then
			oplevel += 1
		end if

		'' operator
		var bopx = x
		x += 1

		'' rhs
		var b = ppExpression( x, oplevel )

		'' Handle ?: special case
		if( op = ASTCLASS_IIF ) then
			'' ':'?
			tkExpect( x, TK_COLON )
			x += 1

			var c = ppExpression( x, oplevel )

			a = astNewIIF( a, b, c )
		else
			a = astNewBOP( op, a, b )
		end if
		a->location = *tkGetLocation( bopx )
	loop

	function = a
end function

''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

private function ppDirective( byval x as integer ) as integer
	var begin = x

	'' '#'
	tkExpect( x, TK_HASH )
	x += 1

	var tk = tkGet( x )

	select case( tk )
	'' DEFINE Identifier ['(' ParameterList ')'] Body Eol
	case KW_DEFINE
		x += 1

		'' Identifier?
		tkExpect( x, TK_ID )
		var t = astNew( ASTCLASS_PPDEFINE, tkGetText( x ) )
		t->paramcount = -1
		x += 1

		'' '(' following directly, no spaces in between?
		if( (tkGet( x ) = TK_LPAREN) and (not tkGetBehindSpace( x )) ) then
			x += 1
			t->paramcount = 0

			'' List of macro parameters:
			'' Identifier (',' Identifier)*
			do
				'' macro parameter's Identifier
				if( tkGet( x ) <> TK_ID ) then
					exit do
				end if
				astAppend( t, astNew( ASTCLASS_MACROPARAM, tkGetText( x ) ) )
				t->paramcount += 1
				x += 1

				'' ','?
				if( tkGet( x ) <> TK_COMMA ) then
					exit do
				end if
				x += 1
			loop

			'' ')'?
			tkExpect( x, TK_RPAREN )
			x += 1
		end if

		tkFold( begin, x, TK_PPDEFINE, , t )
		x = begin + 1

		'' Enclose body tokens in TK_BEGIN/END
		tkInsert( x, TK_BEGIN )
		x += 1
		x = ppSkipToEOL( x )
		tkInsert( x, TK_END )
		x += 1

	case KW_INCLUDE
		x += 1

		'' "filename"
		tkExpect( x, TK_STRING )

		tkFold( begin, x, TK_PPINCLUDE, tkGetText( x ) )
		x = begin + 1

	case KW_IF, KW_ELIF
		tkFold( begin, x, iif( tk = KW_IF, TK_PPIF, TK_PPELSEIF ) )
		x = begin + 1

		'' Enclose #if condition expression tokens in TK_BEGIN/END
		tkInsert( x, TK_BEGIN )
		x += 1
		var exprbegin = x
		x = ppSkipToEOL( x )
		if( x = exprbegin ) then
			tkOopsExpected( x, "#if condition" )
		end if
		tkInsert( x, TK_END )
		x += 1

	case KW_IFDEF, KW_IFNDEF
		x += 1

		'' Identifier?
		tkExpect( x, TK_ID )

		'' Build up "[!]defined id" expression
		var expr = astNew( ASTCLASS_ID, tkGetText( x ) )
		expr->location = *tkGetLocation( x )
		expr = astNewUOP( ASTOP_DEFINED, expr )
		expr->location = *tkGetLocation( x - 1 )
		expr->location.column += 2  '' ifdef -> def, ifndef -> ndef
		expr->location.length = 3
		if( tk = KW_IFNDEF ) then
			expr->location.column += 1  '' ndef -> def
			expr = astNewUOP( ASTOP_LOGNOT, expr )
			expr->location = *tkGetLocation( x - 1 )
			expr->location.column += 2  '' ifndef -> n
			expr->location.length = 1
		end if

		tkFold( begin, x, TK_PPIF, , expr )
		x = begin + 1

	case KW_ELSE, KW_ENDIF
		tkFold( begin, x, iif( tk = KW_ELSE, TK_PPELSE, TK_PPENDIF ) )
		x = begin + 1

	case KW_UNDEF
		x += 1

		'' Identifier?
		tkExpect( x, TK_ID )

		tkFold( begin, x, TK_PPUNDEF, tkGetText( x ) )
		x = begin + 1

	case else
		tkOops( x, "unknown PP directive" )
	end select

	'' EOL?
	select case( tkGet( x ) )
	case TK_EOL
		tkRemove( x, x )

	case TK_EOF

	case else
		tkOopsExpected( x, "EOL behind PP directive" )
	end select

	function = x
end function

sub ppDirectives1( )
	var x = 0
	do
		select case( tkGet( x ) )
		case TK_EOF
			exit do

		'' '#'
		case TK_HASH
			'' At BOL?
			select case( tkGet( tkSkipComment( x, -1 ) ) )
			case TK_EOL, TK_EOF, TK_END, TK_DIVIDER, _
			     TK_PPINCLUDE, TK_PPDEFINE, TK_PPIF, TK_PPELSEIF, _
			     TK_PPELSE, TK_PPENDIF, TK_PPUNDEF
				x = ppDirective( x )
			case else
				'' Skip to next line
				x = ppSkipToEOL( x ) + 1
			end select

		case TK_PPINCLUDE, TK_PPDEFINE, TK_PPIF, TK_PPELSEIF, _
		     TK_PPELSE, TK_PPENDIF, TK_PPUNDEF, TK_DIVIDER
			x += 1

		case else
			'' Skip to next line
			x = ppSkipToEOL( x ) + 1
		end select
	loop
end sub

''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
''
'' Example of recording the body of a #define:
''
''      #define m(a, b) a foo #b a##b a##foo
''                     |------- body ------|
''
'' This sequence of macro body nodes will be created:
''
''      param 0
''      tk TK_ID "foo"
''      param 1 (stringify)
''      param 0 (merge right)
''      param 1 (merge left)
''      param 0 (merge right)
''      tk TK_ID "foo" (merge left)
''
namespace record
	dim shared as ASTNODE ptr macro
	dim shared as integer x, stringify, merge
end namespace

private sub hTakeMergeAttrib( byval n as ASTNODE ptr )
	if( record.merge ) then
		n->attrib or= ASTATTRIB_MERGEWITHPREV
		record.merge = FALSE
	end if
end sub

'' Used for uninteresting tokens
private sub hRecordToken( )
	var n = astNewTK( tkGet( record.x ), tkGetText( record.x ) )
	hTakeMergeAttrib( n )
	astAppend( record.macro->expr, n )
end sub

'' Used when a 'param' or '#param' was found in the macro body.
private sub hRecordParam _
	( _
		byval id as zstring ptr, _
		byval paramindex as integer, _
		byval stringify as integer _
	)

	var n = astNewMACROPARAM( id, paramindex )

	if( stringify ) then
		n->attrib or= ASTATTRIB_STRINGIFY
	end if
	hTakeMergeAttrib( n )

	astAppend( record.macro->expr, n )

end sub

private sub hRecordMerge( )
	'' The next token/param (if any) will recieve the '##' merge attribute
	record.merge = TRUE
end sub

private function hLookupMacroParam( byval id as zstring ptr ) as integer
	var index = 0
	var param = record.macro->head
	while( param )
		assert( param->class = ASTCLASS_MACROPARAM )
		if( *param->text = *id ) then
			return index
		end if
		index += 1
		param = param->next
	wend
	function = -1
end function

private sub hRecordBody( )
	do
		select case( tkGet( record.x ) )
		case TK_END
			exit do

		'' '\'?
		case TK_BACKSLASH
			var xbackslash = record.x
			record.x += 1

			'' Check for escaped EOL, solve them out
			'' '\' [Space] EOL
			if( tkGet( record.x ) = TK_EOL ) then
				'' Remove the escaped EOL
				tkRemove( xbackslash, record.x )
				record.x = xbackslash - 1
			else
				record.x = xbackslash
				hRecordToken( )
			end if

		case TK_ID
			'' Is it one of the #define's parameters?
			var id = tkGetText( record.x )
			var paramindex = hLookupMacroParam( id )
			if( paramindex >= 0 ) then
				hRecordParam( id, paramindex, FALSE )
			else
				hRecordToken( )
			end if

		'' '#'?
		case TK_HASH
			'' '#param'?
			if( tkGet( record.x + 1 ) = TK_ID ) then
				'' Is it one of the #define's parameters?
				var id = tkGetText( record.x + 1 )
				var paramindex = hLookupMacroParam( id )
				if( paramindex >= 0 ) then
					'' '#'
					record.x += 1

					hRecordParam( id, paramindex, TRUE )
				else
					'' '#'
					hRecordToken( )
					record.x += 1

					hRecordToken( )
				end if
			else
				'' '#'
				hRecordToken( )
			end if

		'' '##'?
		case TK_HASHHASH
			hRecordMerge( )

		case else
			hRecordToken( )
		end select

		record.x += 1
	loop
end sub

sub ppDirectives2( )
	var x = 0
	do
		select case( tkGet( x ) )
		case TK_EOF
			exit do

		case TK_PPDEFINE
			var t = tkGetAst( x )
			assert( t->class = ASTCLASS_PPDEFINE )
			x += 1

			'' BEGIN
			assert( tkGet( x ) = TK_BEGIN )
			var begin = x
			x += 1

			'' Parse macro body
			assert( t->expr = NULL )
			t->expr = astNew( ASTCLASS_MACROBODY )
			record.macro = t
			record.x = x
			record.stringify = FALSE
			record.merge = FALSE
			hRecordBody( )
			x = record.x

			'' END
			assert( tkGet( x ) = TK_END )
			tkRemove( begin, x )
			x = begin

		case else
			x += 1
		end select
	loop
end sub

''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

const MAXARGS = 128
dim shared as integer argbegin(0 to MAXARGS-1), argend(0 to MAXARGS-1)

private function hMacroCall _
	( _
		byval macro as ASTNODE ptr, _
		byval x as integer _
	) as integer

	var args = 0
	var begin = x

	'' ID
	assert( tkGet( x ) = TK_ID )
	x += 1

	'' Not just "#define m"?
	if( macro->paramcount >= 0 ) then
		'' '('?
		if( tkGet( x ) <> TK_LPAREN ) then
			return FALSE
		end if
		x += 1

		'' Not just "#define m()"?
		if( macro->paramcount > 0 ) then
			'' For each arg...
			do
				if( args = MAXARGS ) then
					tkOops( x, "macro call arg buffer too small, MAXARGS=" & MAXARGS )
				end if

				argbegin(args) = x

				'' For each token that's part of this arg...
				var level = 0
				do
					select case( tkGet( x ) )
					case TK_LPAREN
						level += 1
					case TK_RPAREN
						if( level <= 0 ) then
							exit do
						end if
						level -= 1
					case TK_COMMA
						if( level <= 0 ) then
							exit do
						end if
					case TK_EOF
						tkOopsExpected( x, "')' to close macro call argument list" )
					end select
					x += 1
				loop

				argend(args) = x - 1
				args += 1

				'' ','?
				if( tkGet( x ) <> TK_COMMA ) then
					exit do
				end if
				x += 1
			loop

			'' As many args as params?
			if( args <> macro->paramcount ) then
				dim s as string
				if( args > macro->paramcount ) then
					s = "too many"
				else
					s = "not enough"
				end if
				s += " arguments for '" + *macro->text + "' macro call: "
				s &= args & " given, " & macro->paramcount & " needed"
				tkOops( x, s )
			end if
		end if

		'' ')'?
		tkExpect( x, TK_RPAREN )
		x += 1
	end if

	var bodybegin = x

	'' Not an empty #define?
	if( macro->expr ) then
		'' Insert the macro body behind the call
		assert( macro->expr->class = ASTCLASS_MACROBODY )

		var child = macro->expr->head
		while( child )
			var y = x

			select case( child->class )
			case ASTCLASS_TK
				tkInsert( x, child->tk, child->text )
				x += 1

			case ASTCLASS_MACROPARAM
				var arg = child->paramindex
				assert( (arg >= 0) and (arg < args) )

				if( child->attrib and ASTATTRIB_STRINGIFY ) then
					'' Turn the arg's tokens into a string and insert it as string literal
					tkInsert( x, TK_STRING, tkManyToCText( argbegin(arg), argend(arg) ) )
					x += 1
				else
					'' Copy the arg's tokens into the body
					tkCopy( x, argbegin(arg), argend(arg) )
					x += argend(arg) - argbegin(arg) + 1
				end if

			case else
				assert( FALSE )
			end select

			if( child->attrib and ASTATTRIB_MERGEWITHPREV ) then
				'' Not the first token? (it wouldn't have a previous token to merge with)
				if( bodybegin < y ) then
					'' Assuming every token >= TK_ID is mergable (i.e. an identifier or keyword)
					if( (tkGet( y - 1 ) >= TK_ID) and _
					    (tkGet( y     ) >= TK_ID) ) then
						tkInsert( x, TK_ID, *tkGetIdOrKw( y - 1 ) + *tkGetIdOrKw( y ) )
						x += 1
						tkRemove( y - 1, y )
						x -= 2
					else
						print tkDumpOne( y - 1 )
						print tkDumpOne( y )
						oops( "cannot merge these two tokens when expanding macro '" & *macro->text & "'" )
					end if
				end if
			end if

			child = child->next
		wend
	end if

	'' Then remove the call tokens
	tkRemove( begin, bodybegin - 1 )
	x -= (bodybegin - 1) - begin + 1

	function = TRUE
end function

''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

enum
	COND_UNKNOWN = 0
	COND_TRUE
	COND_FALSE
end enum

namespace eval
	'' Lists of known symbols etc. Initial symbols can be added before
	'' ppEval(), then it will use and adjust the lists while parsing.
	dim shared knownsyms     as ASTNODE ptr  '' symbols known to be defined or undefined
	dim shared knownsymhash  as THASH
	dim shared expandsyms    as ASTNODE ptr  '' precious symbols: registered for macro expansion
	dim shared expandsymhash as THASH
	dim shared macros        as ASTNODE ptr  '' known #defines for use by expansion
end namespace

sub ppEvalInit( )
	eval.knownsyms = astNew( ASTCLASS_GROUP )
	hashInit( @eval.knownsymhash, 4 )
	eval.expandsyms = astNew( ASTCLASS_GROUP )
	hashInit( @eval.expandsymhash, 4 )
	eval.macros = astNew( ASTCLASS_GROUP )
end sub

private function hSymExists _
	( _
		byval group as ASTNODE ptr, _
		byval id as zstring ptr _
	) as integer

	var child = group->head
	while( child )
		if( *child->text = *id ) then
			return TRUE
		end if
		child = child->next
	wend

	function = FALSE
end function

private sub hAddKnownSym( byval id as zstring ptr, byval is_defined as integer )
	var n = astNewID( id )
	astAppend( eval.knownsyms, n )
	hashAddOverwrite( @eval.knownsymhash, n->text, cptr( any ptr, is_defined ) )
end sub

private function hLookupKnownSym( byval id as zstring ptr ) as integer
	var item = hashLookup( @eval.knownsymhash, id, hashHash( id ) )
	if( item->s ) then
		function = iif( item->data, COND_TRUE, COND_FALSE )
	else
		function = COND_UNKNOWN
	end if
end function

sub ppAddSym( byval id as zstring ptr, byval is_defined as integer )
	if( hSymExists( eval.knownsyms, id ) ) then
		oops( "ppAddSym( """ & *id & """, " & iif( is_defined, "TRUE", "FALSE" ) & " ) called, but already exists" )
	end if
	hAddKnownSym( id, is_defined )
end sub

'' Check whether the given id is a precious symbol
private function hLookupExpandSym( byval id as zstring ptr ) as integer
	function = (hashLookup( @eval.expandsymhash, id, hashHash( id ) )->s <> NULL)
end function

sub ppExpandSym( byval id as zstring ptr )
	if( hSymExists( eval.expandsyms, id ) ) then
		oops( "ppExpandSym( """ & *id & """ ) called, but already exists" )
	end if
	var n = astNewID( id )
	astAppend( eval.expandsyms, n )
	hashAddOverwrite( @eval.expandsymhash, n->text, NULL )
end sub

private function hLookupMacro( byval id as zstring ptr ) as ASTNODE ptr
	var child = eval.macros->head
	while( child )
		if( *child->text = *id ) then
			return child
		end if
		child = child->next
	wend
	function = NULL
end function

private sub hAddMacro( byval macro as ASTNODE ptr )
	var existing = hLookupMacro( macro->text )
	if( existing ) then
		if( astIsEqualDecl( macro, existing ) = FALSE ) then
			print "1st #define:"
			astDump( existing )
			print "2nd #define:"
			astDump( macro )
			oops( "conflicting #define for " + *macro->text )
		end if
		exit sub
	end if
	astAppend( eval.macros, macro )
end sub

private sub hUndefMacro( byval id as zstring ptr )
	var macro = hLookupMacro( id )
	if( macro ) then
		astRemoveChild( eval.macros, macro )
	end if
end sub

sub ppMacroBegin( byval id as zstring ptr, byval paramcount as integer )
	assert( paramcount >= -1 )
	ppAddSym( id, TRUE )
	ppExpandSym( id )
	var macro = astNew( ASTCLASS_PPDEFINE, id )
	macro->paramcount = paramcount
	macro->expr = astNew( ASTCLASS_MACROBODY )
	astAppend( eval.macros, macro )
end sub

sub ppMacroToken( byval tk as integer, byval text as zstring ptr )
	var macro = eval.macros->tail
	astAppend( macro->expr, astNewTK( tk, text ) )
end sub

sub ppMacroParam( byval index as integer )
	var macro = eval.macros->tail
	assert( macro->paramcount > 0 )
	assert( (index >= 0) and (index < macro->paramcount) )
	astAppend( macro->expr, astNewMACROPARAM( NULL, index ) )
end sub

''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

private function hMaybeExpandId( byval x as integer ) as integer
	assert( tkGet( x ) = TK_ID )
	var id = tkGetText( x )

	if( hLookupExpandSym( id ) ) then
		var macro = hLookupMacro( id )
		if( macro ) then
			if( hMacroCall( macro, x ) ) then
				'' The macro call will be replaced with the body,
				'' the token at the TK_ID's position must be re-parsed.
				x -= 1
			end if
		end if
	end if

	function = x
end function

private sub hExpandInIfCondition( byval x as integer )
	assert( tkGet( x ) = TK_BEGIN )

	do
		x += 1

		select case( tkGet( x ) )
		case TK_END
			exit do

		'' DEFINED ['('] Identifier [')']
		case KW_DEFINED
			x += 1

			'' '('?
			var have_lparen = FALSE
			if( tkGet( x ) = TK_LPAREN ) then
				have_lparen = TRUE
				x += 1
			end if

			'' Identifier? (not doing any expansion here)
			if( tkGet( x ) = TK_ID ) then
				x += 1
			end if

			'' ')'?
			if( have_lparen ) then
				if( tkGet( x ) = TK_RPAREN ) then
					x += 1
				end if
			end if

			x -= 1

		'' Identifier (anything unrelated to DEFINED)
		case TK_ID
			x = hMaybeExpandId( x )

		end select
	loop
end sub

private function hParseIfCondition( byval x as integer ) as ASTNODE ptr
	'' BEGIN
	assert( tkGet( x ) = TK_BEGIN )
	var begin = x
	x += 1

	'' Try parsing an expression
	function = ppExpression( x )

	'' TK_END not reached after ppExpression()?
	if( tkGet( x ) <> TK_END ) then
		'' Then either no expression could be parsed at all,
		'' or it was followed by "junk" tokens...
		tkOops( begin, "couldn't parse #if condition expression" )
	end if

	'' END
	assert( tkGet( x ) = TK_END )
	'' Remove the TK_BEGIN/END and the expression tokens in between
	tkRemove( begin, x )
end function

private function hFold( byval n as ASTNODE ptr ) as ASTNODE ptr
	if( n = NULL ) then
		exit function
	end if

	n = astClone( n )
	function = n

	select case as const( n->class )
	case ASTCLASS_UOP
		n->l = hFold( n->l )

		if( n->op = ASTOP_DEFINED ) then
			'' defined() on known symbol?
			assert( n->l->class = ASTCLASS_ID )
			var cond = hLookupKnownSym( n->l->text )
			if( cond = COND_UNKNOWN ) then
				if( n->l->location.file ) then
					oopsLocation( @n->l->location, "unknown symbol, need more info" )
				end if
			else
				'' defined()    ->    1|0
				function = astNewCONST( iif( cond = COND_TRUE, 1, 0 ), 0, TYPE_LONG )
				astDelete( n )
			end if
		else
			if( (n->l->class = ASTCLASS_CONST) and _
			    (not typeIsFloat( n->l->dtype )) ) then
				var v1 = n->l->vali

				select case( n->op )
				case ASTOP_LOGNOT    : v1 = iif( v1, 0, 1 )
				case ASTOP_BITNOT    : v1 = not v1
				case ASTOP_NEGATE    : v1 = -v1
				case ASTOP_UNARYPLUS : '' nothing to do
				case else
					assert( FALSE )
				end select

				function = astNewCONST( v1, 0, TYPE_LONG )
				astDelete( n )
			end if
		end if

	case ASTCLASS_BOP
		n->l = hFold( n->l )
		n->r = hFold( n->r )

		if( (n->l->class = ASTCLASS_CONST) and _
		    (n->r->class = ASTCLASS_CONST) ) then
			if( (not typeIsFloat( n->l->dtype )) and _
			    (not typeIsFloat( n->r->dtype )) ) then
				var v1 = n->l->vali
				var v2 = n->r->vali

				select case as const( n->op )
				case ASTOP_LOGOR  : v1    = iif( v1 orelse  v2, 1, 0 )
				case ASTOP_LOGAND : v1    = iif( v1 andalso v2, 1, 0 )
				case ASTOP_BITOR  : v1  or= v2
				case ASTOP_BITXOR : v1 xor= v2
				case ASTOP_BITAND : v1 and= v2
				case ASTOP_EQ     : v1    = iif( v1 =  v2, 1, 0 )
				case ASTOP_NE     : v1    = iif( v1 <> v2, 1, 0 )
				case ASTOP_LT     : v1    = iif( v1 <  v2, 1, 0 )
				case ASTOP_LE     : v1    = iif( v1 <= v2, 1, 0 )
				case ASTOP_GT     : v1    = iif( v1 >  v2, 1, 0 )
				case ASTOP_GE     : v1    = iif( v1 >= v2, 1, 0 )
				case ASTOP_SHL    : v1 shl= v2
				case ASTOP_SHR    : v1 shr= v2
				case ASTOP_ADD    : v1   += v2
				case ASTOP_SUB    : v1   -= v2
				case ASTOP_MUL    : v1   *= v2
				case ASTOP_DIV    : v1   /= v2
				case ASTOP_MOD    : v1 mod= v2
				case else
					assert( FALSE )
				end select

				function = astNewCONST( v1, 0, TYPE_LONG )
				astDelete( n )
			end if

		'' Only the lhs is a CONST? Check for NOPs
		elseif( (n->l->class = ASTCLASS_CONST) and _
		        (n->r->class <> ASTCLASS_CONST) ) then

			if( typeIsFloat( n->l->dtype ) = FALSE ) then
				var v1 = n->l->vali

				select case( n->op )

				'' true  || x   = 1
				'' false || x   = x
				case ASTOP_LOGOR
					if( v1 ) then
						function = astNewCONST( 1, 0, TYPE_LONG )
					else
						function = astClone( n->r )
					end if
					astDelete( n )

				'' true  && x   = x
				'' false && x   = 0
				case ASTOP_LOGAND
					if( v1 ) then
						function = astClone( n->r )
					else
						function = astNewCONST( 0, 0, TYPE_LONG )
					end if
					astDelete( n )

				'' 0 | x = x
				'' 0 + x = x
				case ASTOP_BITOR, ASTOP_ADD
					if( v1 = 0 ) then
						function = astClone( n->r )
						astDelete( n )
					end if

				'' 0 &  x = 0
				'' 0 << x = 0
				'' 0 >> x = 0
				'' 0 /  x = 0
				'' 0 %  x = 0
				case ASTOP_BITAND, ASTOP_SHL, ASTOP_SHR, _
				     ASTOP_DIV, ASTOP_MOD
					if( v1 = 0 ) then
						function = astNewCONST( 0, 0, TYPE_LONG )
						astDelete( n )
					end if

				'' 0 * x = 0
				'' 1 * x = x
				case ASTOP_MUL
					select case( v1 )
					case 0
						function = astNewCONST( 0, 0, TYPE_LONG )
						astDelete( n )
					case 1
						function = astClone( n->r )
						astDelete( n )
					end select

				'' 0 - x = -x
				case ASTOP_SUB
					if( v1 = 0 ) then
						function = astNewUOP( ASTOP_NEGATE, astClone( n->r ) )
						astDelete( n )
					end if

				end select
			end if

		'' Only the rhs is a CONST? Check for NOPs
		elseif( (n->l->class <> ASTCLASS_CONST) and _
		        (n->r->class = ASTCLASS_CONST) ) then

			if( typeIsFloat( n->r->dtype ) = FALSE ) then
				var v2 = n->r->vali

				select case( n->op )

				'' x || true    = 1
				'' x || false   = x
				case ASTOP_LOGOR
					if( v2 ) then
						function = astNewCONST( 1, 0, TYPE_LONG )
					else
						function = astClone( n->l )
					end if
					astDelete( n )

				'' x && true    = x
				'' x && false   = 0
				case ASTOP_LOGAND
					if( v2 ) then
						function = astClone( n->l )
					else
						function = astNewCONST( 0, 0, TYPE_LONG )
					end if
					astDelete( n )

				'' x | 0 = x
				'' x + 0 = x
				'' x - 0 = x
				'' x << 0 = x
				'' x >> 0 = x
				case ASTOP_BITOR, ASTOP_ADD, ASTOP_SUB, _
				     ASTOP_SHL, ASTOP_SHR
					if( v2 = 0 ) then
						function = astClone( n->l )
						astDelete( n )
					end if

				'' x & 0 = 0
				case ASTOP_BITAND
					if( v2 = 0 ) then
						function = astNewCONST( 0, 0, TYPE_LONG )
						astDelete( n )
					end if

				'' x * 0 = 0
				'' x * 1 = x
				case ASTOP_MUL
					select case( v2 )
					case 0
						function = astNewCONST( 0, 0, TYPE_LONG )
						astDelete( n )
					case 1
						function = astClone( n->l )
						astDelete( n )
					end select

				end select
			end if
		end if

	case ASTCLASS_IIF
		n->expr = hFold( n->expr )
		n->l = hFold( n->l )
		n->r = hFold( n->r )

		if( (n->expr->class = ASTCLASS_CONST) and _
		    (not typeIsFloat( n->expr->dtype )) ) then
			if( n->expr->vali ) then
				function = astClone( n->l )
			else
				function = astClone( n->r )
			end if
			astDelete( n )
		end if

	end select
end function

private function hEvalIfCondition( byval x as integer ) as integer
	assert( (tkGet( x ) = TK_PPIF) or (tkGet( x ) = TK_PPELSEIF) )
	var xif = x
	var t = tkGetAst( x )

	'' No #if expression yet?
	if( t = NULL ) then
		x += 1

		'' Expand macros in the #if condition expression, before parsing
		'' it, but don't expand the "id" in "defined id".
		hExpandInIfCondition( x )

		t = hParseIfCondition( x )

		x = xif
	end if

	'' 1. Try to evaluate the condition
	t = hFold( t )

	'' 2. Check the condition
	if( (t->class <> ASTCLASS_CONST) or typeIsFloat( t->dtype ) ) then
		tkOops( x, "cannot evaluate #if condition, need more info" )
	end if

	function = (t->vali <> 0)
end function

type IFSTACKNODE
	saw_true	as integer
	saw_else	as integer
end type

const MAXIFBLOCKS = 128
dim shared ifstack(0 to MAXIFBLOCKS-1) as IFSTACKNODE

sub ppEval( )
	var x = 0
	var level = -1
	var skiplevel = MAXIFBLOCKS+1
	do
		select case( tkGet( x ) )
		case TK_EOF
			exit do

		case TK_PPIF
			if( level = MAXIFBLOCKS ) then
				tkOops( x, "#if stack too small, MAXIFBLOCKS=" & MAXIFBLOCKS )
			end if
			level += 1
			ifstack(level).saw_true = FALSE
			ifstack(level).saw_else = FALSE

			'' Not skipping? Then evaluate
			if( skiplevel = MAXIFBLOCKS+1 ) then
				if( hEvalIfCondition( x ) ) then
					'' #if TRUE, don't skip
					ifstack(level).saw_true = TRUE
				else
					'' #if FALSE, start skipping
					skiplevel = level
				end if
			end if

			tkRemove( x, x )
			x -= 1

		case TK_PPELSEIF
			if( level < 0 ) then
				tkOops( x, "#elseif without #if" )
			elseif( ifstack(level).saw_else ) then
				tkOops( x, "#elseif after #else" )
			end if

			'' Not skipping, or skipping due to previous #if/#elseif FALSE?
			'' Then evaluate the #elseif to check whether to continue skipping or not
			if( (skiplevel = MAXIFBLOCKS+1) or (skiplevel = level) ) then
				'' If there was a previous #if/#elseif TRUE on this level,
				'' then this #elseif must be skipped no matter what its condition is.
				if( ifstack(level).saw_true ) then
					'' Start/continue skipping
					skiplevel = level
				else
					if( hEvalIfCondition( x ) ) then
						'' #elseif TRUE, don't skip
						ifstack(level).saw_true = TRUE
						skiplevel = MAXIFBLOCKS+1
					else
						'' #elseif FALSE, start/continue skipping
						skiplevel = level
					end if
				end if
			end if

			tkRemove( x, x )
			x -= 1

		case TK_PPELSE
			if( level < 0 ) then
				tkOops( x, "#else without #if" )
			end if

			if( ifstack(level).saw_else ) then
				tkOops( x, "#else after #else" )
			end if
			ifstack(level).saw_else = TRUE

			'' Not skipping, or skipping due to previous #if/#elseif FALSE?
			'' Then check whether to skip this #else block or not.
			if( (skiplevel = MAXIFBLOCKS+1) or (skiplevel = level) ) then
				if( ifstack(level).saw_true ) then
					'' Previous #if/#elseif TRUE, skip #else
					skiplevel = level
				else
					'' Previous #if/#elseif FALSE, don't skip #else
					skiplevel = MAXIFBLOCKS+1
				end if
			end if

			tkRemove( x, x )
			x -= 1

		case TK_PPENDIF
			if( level < 0 ) then
				tkOops( x, "#endif without #if" )
			end if

			'' If skipping due to current level, then stop skipping.
			if( skiplevel = level ) then
				skiplevel = MAXIFBLOCKS+1
			end if

			tkRemove( x, x )
			x -= 1

			level -= 1

		case else
			'' Remove tokens if skipping
			if( skiplevel <> MAXIFBLOCKS+1 ) then
				tkRemove( x, x )
				x -= 1
			else
				select case( tkGet( x ) )
				case TK_PPDEFINE
					'' Register/overwrite as known defined symbol
					var t = tkGetAst( x )
					assert( t->class = ASTCLASS_PPDEFINE )
					hAddKnownSym( t->text, TRUE )

					'' Register #define for expansion if it's a precious symbol
					if( hLookupExpandSym( t->text ) ) then
						hAddMacro( astClone( t ) )
					end if

				case TK_PPUNDEF
					'' Register/overwrite as known undefined symbol
					var id = tkGetText( x )
					hAddKnownSym( id, FALSE )

					'' Forget previous #define if it's a precious symbol
					if( hLookupExpandSym( id ) ) then
						hUndefMacro( id )
					end if

				case TK_ID
					x = hMaybeExpandId( x )

				end select
			end if
		end select

		x += 1
	loop

	astDelete( eval.macros )
	hashEnd( @eval.expandsymhash )
	astDelete( eval.expandsyms )
	hashEnd( @eval.knownsymhash )
	astDelete( eval.knownsyms )
end sub

sub ppRemoveEOLs( )
	var x = 0
	do
		select case( tkGet( x ) )
		case TK_EOF
			exit do
		case TK_EOL
			tkRemove( x, x )
			x -= 1
		end select
		x += 1
	loop
end sub
