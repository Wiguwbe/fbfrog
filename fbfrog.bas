'' Main module, command line interface

#include once "fbfrog.bi"

dim shared frog as FROGSTUFF

private sub hPrintHelpAndExit( )
	print "fbfrog 1.0 (" + __DATE_ISO__ + "), FreeBASIC *.bi binding generator"
	print "usage: fbfrog *.h [options]"
	print "*.fbfrog input files are special and treated similar to @<file>."
	print "global options:"
	print "  @<file>          Read more command line arguments from that file."
	print "                   (will be expanded in place before other parsing)"
	print "  -nomerge         Don't preserve code from #includes"
	print "  -whitespace      Try to preserve comments and empty lines"
	print "  -noautoextern    Don't add Extern blocks"
	print "  -windowsms       Use Extern ""Windows-MS"" instead of Extern ""Windows"""
	print "  -noconstants     Don't try to turn #defines into constants"
	print "  -nonamefixup     Don't fix symbol identifier conflicts which happen"
	print "                   e.g. due to FB's keywords and/or case insensitivity"
	print "  -keepundefs      Don't default to removing #undefs and conflicting #defines"
	print "  -versiondefine <id>  Set identifier for version #define that may"
	print "                       be used by the generated binding."
	print "  -pragmaonce      Add #pragma once statements"
	print "  -incdir <path>   Add #include search directory"
	print "  -o <path/file>   Set output .bi file name, or just the output directory"
	print "  -v               Show verbose/debugging info"
	print "commands specific to binding version/target:"
	print "  -version <string>        Begin of version-specific arguments"
	print "                           (ends at next -version or EOL)"
	print "  -target dos|linux|win32  Begin of target-specific arguments (ditto)"
	print "  -inclib <name>           Add an #inclib ""<name>"" statement"
	print "  -define <id> [<body>]    Add pre-#define"
	print "  -undef <id>              Add pre-#undef"
	print "  -include <file>          Add pre-#include"
	print "  -noexpand <id>           Disable expansion of certain #define"
	print "  -removedefine <id>       Don't preserve certain #defines/#undefs"
	print "  -renametypedef <oldid> <newid>  Rename a typedef"
	print "  -renametag <oldid> <newid>      Rename a struct/union/enum"
	print "  -appendbi <file>                Append arbitrary FB code from <file> to the binding"
	print "  -removematch ""<C token(s)>""  Drop constructs containing the given C token(s)."
	print "                               This should be used to work-around parsing errors."
	end 1
end sub

private function hTurnArgsIntoString( byval argc as integer, byval argv as zstring ptr ptr ) as string
	dim s as string

	'' Even including argv[0] so it's visible in error messages
	'' (specially parsed in hParseArgs())
	for i as integer = 0 to argc-1
		var arg = *argv[i]

		'' If the argument contains special chars (white-space, ", '),
		'' enclose it in quotes as needed for lexLoadArgs().

		'' Contains '?
		if( instr( arg, "'" ) > 0 ) then
			'' Must enclose in "..." and escape included " or \ chars properly.
			'' This also works if " or whitespace are included too.

			'' Insert \\ for \ before inserting \" for ", so \" won't accidentally
			'' be turned into \\".
			arg = strReplace( arg, $"\", $"\\" )
			arg = strReplace( arg, """", $"\""" )
			arg = """" + arg + """"
		'' Contains no ', but " or white-space?
		elseif( instr( arg, any !""" \t\f\r\n\v" ) > 0 ) then
			'' Enclose in '...', so no escaping is needed.
			arg = "'" + arg + "'"
		end if

		if( len( s ) > 0 ) then
			s += " "
		end if
		s += arg
	next

	function = s
end function

private sub hLoadResponseFile _
	( _
		byval x as integer, _
		byref filename as string, _
		byval location as TKLOCATION ptr _
	)

	const MAX_FILES = 1024  '' Arbitrary limit to detect recursion
	static filecount as integer

	if( filecount > MAX_FILES ) then
		tkOops( x, "suspiciously many @response file expansions, recursion? (limit=" & MAX_FILES & ")" )
	end if

	'' Load the file content at the specified position
	lexLoadArgs( x, sourcebufferFromFile( filename, location ) )
	filecount += 1

end sub

'' Expand @file arguments in the tk buffer
private sub hExpandResponseFileArguments( )
	var x = 0
	while( tkGet( x ) <> TK_EOF )

		if( tkGet( x ) = TK_RESPONSEFILE ) then
			var filename = *tkGetText( x )

			'' Complain if argument was only '@'
			if( len( filename ) = 0 ) then
				tkOopsExpected( x, "file name directly behind @ (no spaces in between)" )
			end if

			'' If the @file argument comes from an @file,
			'' open it relative to the parent @file's dir.
			var location = tkGetLocation( x )
			if( location->source->is_file ) then
				filename = pathAddDiv( pathOnly( *location->source->name ) ) + filename
			end if

			'' Load the file content behind the @file token
			hLoadResponseFile( x + 1, filename, location )

			'' Remove the @file token (now that its location is no
			'' longer referenced), so it doesn't get in the way of
			'' hParseArgs().
			tkRemove( x, x )

			'' Re-check this position in case a new @file token was inserted right here
			x -= 1
		end if

		x += 1
	wend
end sub

private sub hLoadBuiltinResponseFile _
	( _
		byval x as integer, _
		byref id as string, _
		byval location as TKLOCATION ptr _
	)

	'' <exepath>/builtin/<id>.fbfrog.
	var builtinfile = hExePath( ) + "builtin" + PATHDIV + id + ".fbfrog"
	hLoadResponseFile( x, builtinfile, location )

	'' Must expand @files again in case the loaded built-in file contained any
	hExpandResponseFileArguments( )

end sub

private sub hExpectId( byval x as integer )
	tkExpect( x, TK_ID, "(valid symbol name)" )
end sub

private function hIsStringOrId( byval x as integer ) as integer
	function = (tkGet( x ) = TK_STRING) or (tkGet( x ) = TK_ID)
end function

private sub hExpectPath( byval x as integer )
	if( hIsStringOrId( x ) = FALSE ) then
		tkOopsExpected( x, "<path> argument" )
	end if
end sub

private function hPathRelativeToResponseFile( byval x as integer ) as string
	var path = *tkGetText( x )

	'' If the file/dir argument isn't an absolute path, and it came from an
	'' @file, open it relative to the @file's dir.
	if( pathIsAbsolute( path ) = FALSE ) then
		var location = tkGetLocation( x )
		if( location->source->is_file ) then
			path = pathAddDiv( pathOnly( *location->source->name ) ) + path
		end if
	end if

	function = path
end function

private sub hReadFileArg( byval result as ASTNODE ptr, byval x as integer )
	var path = hPathRelativeToResponseFile( x )

	'' File or directory?
	var n = astNew( ASTCLASS_FILE, path )
	if( hReadableDirExists( path ) ) then
		n->class = ASTCLASS_DIR
	end if

	astAppend( result, astTakeLoc( n, x ) )
end sub

enum
	BODY_TOPLEVEL = 0
	BODY_VERSION
	BODY_TARGET
end enum

private function hParseArgs( byref x as integer, byval body as integer ) as ASTNODE ptr
	var result = astNewGROUP( )

	if( body = BODY_TOPLEVEL ) then
		'' Skip argv[0]
		assert( tkGet( x ) <> TK_EOF )
		x += 1

		'' Load pre-#defines that are always used
		hLoadBuiltinResponseFile( x, "base", tkGetLocation( x - 1 ) )
	end if

	while( tkGet( x ) <> TK_EOF )
		var text = *tkGetText( x )

		select case( tkGet( x ) )
		case TK_OPTION
			select case( text )
			case "h", "?", "help", "-help", "-version"
				hPrintHelpAndExit( )

			case "nomerge"      : frog.nomerge      = TRUE
			case "whitespace"   : frog.whitespace   = TRUE
			case "noautoextern" : frog.noautoextern = TRUE
			case "windowsms"    : frog.windowsms    = TRUE
			case "noconstants"  : frog.noconstants  = TRUE
			case "nonamefixup"  : frog.nonamefixup  = TRUE
			case "keepundefs"   : frog.keepundefs   = TRUE
			case "pragmaonce"   : frog.pragmaonce   = TRUE
			case "v", "verbose", "-verbose" : frog.verbose = TRUE

			case "versiondefine"
				x += 1

				'' <id>
				hExpectId( x )
				frog.versiondefine = *tkGetText( x )

			case "incdir"
				x += 1

				'' <path>
				hExpectPath( x )
				astAppend( frog.incdirs, astTakeLoc( astNewTEXT( hPathRelativeToResponseFile( x ) ), x ) )

			case "o"
				x += 1

				'' <path>
				hExpectPath( x )
				frog.outname = hPathRelativeToResponseFile( x )

			'' -version <version id> ...
			case "version"
				'' Another -version is coming - end any current -version/-target blocks
				if( body <> BODY_TOPLEVEL ) then
					exit while
				end if
				var location1 = tkGetLocation( x )
				x += 1

				'' <version id>
				if( hIsStringOrId( x ) = FALSE ) then
					tkOopsExpected( x, "<version id> argument" )
				end if
				'' astNewCONSTI( vallng( nextarg ), TYPE_LONGINT )
				var id = astNew( ASTCLASS_STRING, tkGetText( x ) )
				var location2 = tkGetLocation( x )
				id->location = *location2
				x += 1

				var location = tkGetLocation( x )
				var n = astNewVERBLOCK( id, NULL, hParseArgs( x, BODY_VERSION ) )
				n->location = *location1
				n->location.length = location2->column + location2->length - location1->column
				astAppend( result, n )
				x -= 1

			'' -target <target-id> ...
			case "target"
				'' Another -target is coming - end any current -target block
				if( body = BODY_TARGET ) then
					exit while
				end if
				var location = *tkGetLocation( x )
				x += 1

				'' <target-id>
				var attrib = 0
				dim as string targetid
				if( tkGet( x ) = TK_ID ) then
					targetid = *tkGetText( x )
					select case( targetid )
					case "dos"   : attrib = ASTATTRIB_DOS
					case "linux" : attrib = ASTATTRIB_LINUX
					case "win32" : attrib = ASTATTRIB_WIN32
					end select
				end if
				if( attrib = 0 ) then
					tkOopsExpected( x, "one of dos|linux|win32" )
				end if
				var location2 = tkGetLocation( x )
				location.length = location2->column + location2->length - location.column
				x += 1

				hLoadBuiltinResponseFile( x, targetid, @location )

				var n = astNew( ASTCLASS_TARGETBLOCK, hParseArgs( x, BODY_TARGET ) )
				n->attrib or= attrib
				n->location = location
				astAppend( result, n )
				x -= 1

			'' -inclib <name>
			case "inclib"
				x += 1

				if( hIsStringOrId( x ) = FALSE ) then
					tkOopsExpected( x, "<name> argument" )
				end if
				astAppend( result, astTakeLoc( astNew( ASTCLASS_INCLIB, tkGetText( x ) ), x ) )

			'' -define <id> [<body>]
			case "define"
				x += 1

				'' <id>
				hExpectId( x )
				var n = astTakeLoc( astNewPPDEFINE( tkGetText( x ) ), x )

				'' [<body>]
				if( hIsStringOrId( x + 1 ) ) then
					x += 1
					n->expr = astTakeLoc( astNewTEXT( tkGetText( x ) ), x )
				end if

				astAppend( result, n )

			case "undef"
				x += 1

				'' <id>
				hExpectId( x )
				astAppend( result, astTakeLoc( astNew( ASTCLASS_PPUNDEF, tkGetText( x ) ), x ) )

			case "include"
				x += 1

				'' <file>
				hExpectPath( x )
				astAppend( result, astTakeLoc( astNew( ASTCLASS_PPINCLUDE, hPathRelativeToResponseFile( x ) ), x ) )

			case "noexpand"
				x += 1

				'' <id>
				hExpectId( x )
				astAppend( result, astTakeLoc( astNew( ASTCLASS_NOEXPAND, tkGetText( x ) ), x ) )

			case "removedefine"
				x += 1

				'' <id>
				hExpectId( x )
				astAppend( result, astTakeLoc( astNew( ASTCLASS_REMOVEDEFINE, tkGetText( x ) ), x ) )

			case "renametypedef", "renametag"
				x += 1

				dim as integer astclass
				select case( text )
				case "renametypedef" : astclass = ASTCLASS_RENAMETYPEDEF
				case "renametag"     : astclass = ASTCLASS_RENAMETAG
				case else            : assert( FALSE )
				end select

				'' <oldid>
				hExpectId( x )
				var n = astTakeLoc( astNew( astclass, tkGetText( x ) ), x )
				x += 1

				'' <newid>
				hExpectId( x )
				astSetComment( n, tkGetText( x ) )

				astAppend( result, n )

			case "removematch"
				x += 1

				'' <C tokens>
				if( (tkGet( x ) <> TK_ID) and (tkGet( x ) <> TK_STRING) ) then
					tkOopsExpected( x, "C tokens" )
				end if
				astAppend( result, astTakeLoc( astNew( ASTCLASS_REMOVEMATCH, tkGetText( x ) ), x ) )

			case "appendbi"
				x += 1

				'' <file>
				hExpectPath( x )
				astAppend( result, astTakeLoc( astNew( ASTCLASS_APPENDBI, hPathRelativeToResponseFile( x ) ), x ) )

			case else
				tkOops( x, "unknown command line option '" + text + "'" )
			end select

		case else
			select case( text )
			case "/?", "/h", "/help"
				hPrintHelpAndExit( )
			case else
				'' *.fbfrog file given (without @)? Treat as @file too
				if( pathExtOnly( text ) = "fbfrog" ) then
					hLoadResponseFile( x + 1, text, tkGetLocation( x ) )
					tkRemove( x, x )
					x -= 1

					'' Must expand @files again in case the loaded file contained any
					hExpandResponseFileArguments( )
				else
					hReadFileArg( result, x )
				end if
			end select
		end select

		x += 1
	wend

	function = result
end function

private sub hLexRemoveMatchPattern( byval n as ASTNODE ptr )
	tkInit( )

	lexLoadC( 0, sourcebufferFromZstring( "-removematch", n->text, @n->location ), FALSE )

	for x as integer = 0 to tkGetCount( )-1
		astAppend( n, astNewTK( x ) )
	next

	tkEnd( )
end sub

private sub hLexRemoveMatchPatterns( byval code as ASTNODE ptr )
	var i = code->head
	while( i )

		if( i->class = ASTCLASS_REMOVEMATCH ) then
			hLexRemoveMatchPattern( i )
		end if

		hLexRemoveMatchPatterns( i )

		i = i->next
	wend
end sub

private function hPatternMatchesHere _
	( _
		byval n as ASTNODE ptr, _
		byval x as integer, _
		byval last as integer _
	) as integer

	var tk = n->head
	while( (tk <> NULL) and (x <= last) )
		assert( tk->class = ASTCLASS_TK )

		if( astTKMatchesPattern( tk, x ) = FALSE ) then
			exit function
		end if

		tk = tk->next
		x += 1
	wend

	function = TRUE
end function

private function hConstructMatchesPattern _
	( _
		byval n as ASTNODE ptr, _
		byval first as integer, _
		byval last as integer _
	) as integer

	assert( n->class = ASTCLASS_REMOVEMATCH )

	'' Check whether the pattern exists in the construct:
	'' For each token in the construct, check whether the pattern starts
	'' there and if so whether it continues...
	for x as integer = first to last
		if( hPatternMatchesHere( n, x, last ) ) then
			return TRUE
		end if
	next

end function

private function hConstructMatchesAnyPattern _
	( _
		byval presetcode as ASTNODE ptr, _
		byval first as integer, _
		byval last as integer _
	) as integer

	var i = presetcode->head
	while( i )
		if( i->class = ASTCLASS_REMOVEMATCH ) then
			if( hConstructMatchesPattern( i, first, last ) ) then
				return TRUE
			end if
		end if
		i = i->next
	wend

end function

private sub hApplyRemoveMatchOptions( byval presetcode as ASTNODE ptr )
	var x = 0
	while( tkGet( x ) <> TK_EOF )
		var begin = x
		x = hFindConstructEnd( x )

		if( hConstructMatchesAnyPattern( presetcode, begin, x - 1 ) ) then
			tkRemove( begin, x - 1 )
			x = begin
		end if
	wend
end sub

private sub hApplyRenameTypedefOption _
	( _
		byval n as ASTNODE ptr, _
		byval ast as ASTNODE ptr, _
		byval renametypedef as ASTNODE ptr _
	)

	if( n->class = ASTCLASS_TYPEDEF ) then
		if( *n->text = *renametypedef->text ) then
			astReplaceSubtypes( ast, ASTCLASS_ID, renametypedef->text, ASTCLASS_ID, renametypedef->comment )
			astSetText( n, renametypedef->comment )
		end if
	end if

	var i = n->head
	while( i )
		hApplyRenameTypedefOption( i, ast, renametypedef )
		i = i->next
	wend

end sub

private sub hApplyRenameTagOption _
	( _
		byval n as ASTNODE ptr, _
		byval ast as ASTNODE ptr, _
		byval renametag as ASTNODE ptr _
	)

	select case( n->class )
	case ASTCLASS_STRUCT, ASTCLASS_UNION, ASTCLASS_ENUM
		if( *n->text = *renametag->text ) then
			astReplaceSubtypes( ast, ASTCLASS_TAGID, renametag->text, ASTCLASS_TAGID, renametag->comment )
			astSetText( n, renametag->comment )
		end if
	end select

	var i = n->head
	while( i )
		hApplyRenameTagOption( i, ast, renametag )
		i = i->next
	wend

end sub

private sub hApplyRenameTypedefOptions _
	( _
		byval presetcode as ASTNODE ptr, _
		byval ast as ASTNODE ptr _
	)

	var i = presetcode->head
	while( i )

		select case( i->class )
		case ASTCLASS_RENAMETYPEDEF
			hApplyRenameTypedefOption( ast, ast, i )
		case ASTCLASS_RENAMETAG
			hApplyRenameTagOption( ast, ast, i )
		end select

		i = i->next
	wend

end sub

private function frogWorkVersion _
	( _
		byval targetversion as ASTNODE ptr, _
		byval presetcode as ASTNODE ptr _
	) as ASTNODE ptr

	print "[" + astDumpPrettyVersion( targetversion ) + "]"

	var rootfiles = astNewGROUP( )
	scope
		var i = presetcode->head
		while( i )
			select case( i->class )
			case ASTCLASS_FILE
				'' Input files
				astCloneAppend( rootfiles, i )
			case ASTCLASS_DIR
				'' Input files from directories
				var n = hScanDirectory( *i->text, "*.h" )
				astSetLocationAndAlsoOnChildren( n, @i->location )
				astAppend( rootfiles, n )
			end select
			i = i->next
		wend
	end scope
	if( rootfiles->head = NULL ) then
		oops( "no input files" )
	end if

	'' The first .h file name seen will be used for the final .bi
	if( len( frog.defaultoutname ) = 0 ) then
		frog.defaultoutname = pathStripExt( *rootfiles->head->text ) + ".bi"
	end if

	tkInit( )

	cppInit( )

	scope
		'' Pre-#defines/#undefs are simply inserted at the top of the
		'' token buffer, so that cppMain() parses them like any other
		'' #define/#undef.

		var i = presetcode->head
		while( i )

			select case( i->class )
			case ASTCLASS_NOEXPAND
				cppNoExpandSym( i->text )

			case ASTCLASS_REMOVEDEFINE
				cppRemoveSym( i->text )

			case ASTCLASS_PPDEFINE, ASTCLASS_PPUNDEF, ASTCLASS_PPINCLUDE
				dim as string prettyname, s

				select case( i->class )
				case ASTCLASS_PPDEFINE
					cppRemoveSym( i->text )

					prettyname = "pre-#define"
					s = "#define " + *i->text
					if( i->expr ) then
						assert( i->expr->class = ASTCLASS_TEXT )
						s += " " + *i->expr->text
					end if
					s += !"\n"

				case ASTCLASS_PPUNDEF
					cppRemoveSym( i->text )
					prettyname = "pre-#undef"
					s = "#undef " + *i->text + !"\n"

				case ASTCLASS_PPINCLUDE
					prettyname = "pre-#include"
					s = "#include """ + *i->text + """" + !"\n"

				end select

				lexLoadC( tkGetCount( ), sourcebufferFromZstring( prettyname, s, @i->location ), FALSE )

			end select

			i = i->next
		wend
	end scope

	''
	'' Add toplevel file(s) behind current tokens (could be pre-#defines etc.)
	''
	'' Note: pre-#defines should appear before tokens from root files, such
	'' that the order of -define vs *.h command line arguments doesn't
	'' matter. The -include option can be used to have files #included in
	'' between pre-#defines.
	''
	scope
		var i = rootfiles->head
		while( i )

			if( tkGetCount( ) > 0 ) then
				'' Extra EOL to separate from previous tokens
				tkInsert( tkGetCount( ), TK_EOL )
			end if

			print space( frog.maxversionstrlen ) + "parsing: " + *i->text
			lexLoadC( tkGetCount( ), sourcebufferFromFile( i->text, @i->location ), frog.whitespace )

			if( tkGetCount( ) > 0 ) then
				'' EOL at EOF, if missing
				if( tkGet( tkGetCount( ) - 1 ) <> TK_EOL ) then
					tkInsert( tkGetCount( ), TK_EOL )
				end if
			end if

			i = i->next
		wend
	end scope

	cppMain( frog.whitespace, frog.nomerge )

	tkRemoveEOLs( )
	tkTurnCPPTokensIntoCIds( )

	hApplyRemoveMatchOptions( presetcode )

	'' Parse C constructs
	var ast = cFile( )

	tkEnd( )

	''
	'' Work on the AST
	''
	astMakeProcsDefaultToCdecl( ast )
	astTurnStructInitIntoArrayInit( ast )
	astCleanUpExpressions( ast )
	astSolveOutArrayTypedefs( ast, ast )
	astSolveOutProcTypedefs( ast, ast )
	astFixArrayParams( ast )
	astUnscopeDeclsNestedInStructs( ast )
	astMakeNestedUnnamedStructsFbCompatible( ast )
	if( frog.noconstants = FALSE ) then astTurnDefinesIntoConstants( ast )

	hApplyRenameTypedefOptions( presetcode, ast )
	astRemoveRedundantTypedefs( ast, ast )
	astNameAnonUdtsAfterFirstAliasTypedef( ast )
	astAddForwardDeclsForUndeclaredTagIds( ast )

	if( frog.nonamefixup = FALSE ) then astFixIds( ast )
	if( frog.noautoextern = FALSE ) then astAutoExtern( ast, frog.windowsms, frog.whitespace )

	assert( ast->class = ASTCLASS_GROUP )

	'' Add #include "crt/long.bi" to the binding, if it uses CLONG
	if( astUsesDtype( ast, TYPE_CLONGDOUBLE ) ) then
		astPrependMaybeWithDivider( ast, astNewIncludeOnce( "crt/longdouble.bi" ) )
	end if
	if( astUsesDtype( ast, TYPE_CLONG ) or astUsesDtype( ast, TYPE_CULONG ) ) then
		astPrependMaybeWithDivider( ast, astNewIncludeOnce( "crt/long.bi" ) )
	end if

	'' Prepend #inclibs
	scope
		var i = presetcode->tail
		while( i )
			if( i->class = ASTCLASS_INCLIB ) then
				astPrependMaybeWithDivider( ast, astClone( i ) )
			end if
			i = i->prev
		wend
	end scope

	'' Prepend #pragma once
	if( frog.pragmaonce ) then
		astPrependMaybeWithDivider( ast, astNew( ASTCLASS_PRAGMAONCE ) )
	end if

	'' Add the APPENDBI's, if any
	scope
		var i = presetcode->head
		while( i )
			if( i->class = ASTCLASS_APPENDBI ) then
				astAppend( ast, astNew( ASTCLASS_DIVIDER ) )
				astAppend( ast, astClone( i ) )
			end if
			i = i->next
		wend
	end scope

	astMergeDIVIDERs( ast )

	'' Put file's AST into a VERBLOCK, if a targetversion was given,
	'' in preparation for the astMergeVerblocks() call later
	ast = astWrapFileInVerblock( ast, targetversion )

	astDelete( presetcode )
	astDelete( rootfiles )
	function = ast
end function

private function hMakeDeclCountMessage( byval declcount as integer ) as string
	if( declcount = 1 ) then
		function = "1 declaration"
	else
		function = declcount & " declarations"
	end if
end function

''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

	if( __FB_ARGC__ <= 1 ) then
		hPrintHelpAndExit( )
	end if

	frog.versiondefine = "__VERSION__"
	frog.incdirs = astNewGROUP( )
	sourcebuffersInit( )
	fbkeywordsInit( )

	tkInit( )

	'' Load all command line arguments into the tk buffer
	lexLoadArgs( 0, sourcebufferFromZstring( "<command line>", _
			hTurnArgsIntoString( __FB_ARGC__, __FB_ARGV__ ), NULL ) )

	'' Load content of @files too
	hExpandResponseFileArguments( )

	'' Parse the command line arguments
	frog.code = hParseArgs( 0, BODY_TOPLEVEL )

	tkEnd( )

	'' Go through -removematch options and run lexLoadC() on the C token
	'' string that was given behind -removematch on the command line.
	'' This will write into the tk buffer so it must be done here before
	'' the main parsing process starts...
	hLexRemoveMatchPatterns( frog.code )

	var versions = astCollectVersions( frog.code )

	'' If no versions given, use a dummy, to hold the targets
	if( versions->head = NULL ) then
		astAppend( versions, astNew( ASTCLASS_DUMMYVERSION ) )
	end if

	'' Multiply version(s) with the targets, for example:
	''    versions: 1, 2
	''    targets: linux, win32
	''    result: 1.linux, 1.win32, 2.linux, 2.win32
	var targetversions = astNewGROUP( )
	scope
		var i = versions->head
		do
			astAppend( targetversions, astAddAttrib( astClone( i ), ASTATTRIB_DOS ) )
			astAppend( targetversions, astAddAttrib( astClone( i ), ASTATTRIB_LINUX ) )
			astAppend( targetversions, astAddAttrib( astClone( i ), ASTATTRIB_WIN32 ) )
			i = i->next
		loop while( i )
	end scope

	'' Find longest version string, for pretty output
	scope
		var i = targetversions->head
		do
			var s = astDumpPrettyVersion( i )
			if( frog.maxversionstrlen < len( s ) ) then
				frog.maxversionstrlen = len( s )
			end if
			i = i->next
		loop while( i )
		frog.maxversionstrlen += 3
	end scope

	'' Parse files for each version, using the options for that version
	scope
		var i = targetversions->head
		do
			i->expr = frogWorkVersion( i, astGet1VersionAndTargetOnly( frog.code, i ) )
			i = i->next
		loop while( i )
	end scope

	'' Merge version-specific ASTs into one
	dim as ASTNODE ptr final
	scope
		var i = targetversions->head
		do

			if( final = NULL ) then
				final = i->expr
			else
				final = astMergeVerblocks( final, i->expr )
			end if
			i->expr = NULL

			i = i->next
		loop while( i )
	end scope

	'' Turn VERBLOCKs into #ifs etc.
	astProcessVerblocksAndTargetblocks( final, versions, frog.versiondefine )

	'' Do auto-formatting if not preserving whitespace
	if( frog.whitespace = FALSE ) then
		astAutoAddDividers( final )
	end if

	'' Write out the .bi file
	if( len( frog.defaultoutname ) = 0 ) then
		frog.defaultoutname = "unknown.bi"
	end if
	if( len( frog.outname ) = 0 ) then
		frog.outname = frog.defaultoutname
	elseif( pathIsDir( frog.outname ) ) then
		frog.outname = pathAddDiv( frog.outname ) + pathStrip( frog.defaultoutname )
	end if
	print "emitting: " + frog.outname + " (" + hMakeDeclCountMessage( astCountDecls( final ) ) + ")"
	emitFile( frog.outname, final )

	astDelete( final )
	astDelete( versions )
	astDelete( targetversions )

	if( frog.verbose ) then
		astPrintStats( )
	end if
