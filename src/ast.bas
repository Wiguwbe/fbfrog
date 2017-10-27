'' AST build up/helper functions

#include once "fbfrog.bi"
#include once "emit.bi"

'' Merge/expand dtype b into dtype a, overwriting a's base dtype, but preserving its ptrs/consts
'' This is useful for expanding typedefs into the context of another dtype.
function typeExpand(byval a as integer, byval b as integer) as integer
	var acount = typeGetPtrCount(a)
	var bcount = typeGetPtrCount(b)
	if acount + bcount > TYPEMAX_PTR then
		return TYPE_NONE
	end if
	if typeIsRef(a) and typeIsRef(b) then
		return TYPE_NONE
	end if
	return typeMultAddrOf(b, acount) or typeGetConst(a) or typeGetRef(a)
end function

function typeUnsetBaseConst(byval dtype as integer) as integer
	function = dtype and (not (1 shl (TYPEPOS_CONST + typeGetPtrCount(dtype))))
end function

function typeGetCLong(byval is_unsigned as integer, byval clong32 as integer) as integer
	if clong32 then
		'' C long => LONG (ok on Windows where C long is always 32bit)
		function = iif(is_unsigned, TYPE_ULONG, TYPE_LONG)
	else
		'' C long => CLONG
		function = iif(is_unsigned, TYPE_CULONG, TYPE_CLONG)
	end if
end function

dim shared datatypenames(0 to TYPE__COUNT-1) as zstring ptr => { _
	@"none"    , _
	@"any"     , _
	@"byte"    , _
	@"ubyte"   , _
	@"short"   , _
	@"ushort"  , _
	@"long"    , _
	@"ulong"   , _
	@"clong"   , _
	@"culong"  , _
	@"integer" , _
	@"uinteger", _
	@"longint" , _
	@"ulongint", _
	@"single"  , _
	@"double"  , _
	@"clongdouble", _
	@"udt"     , _
	@"proc"    , _
	@"zstring" , _
	@"wstring" , _
	@"wchar_t"   _
}

function typeDump(byval dtype as integer) as string
	dim s as string

	if typeIsRef(dtype) then
		s += "byref "
	end if

	var dt = typeGetDt(dtype)
	var ptrcount = typeGetPtrCount(dtype)

	if typeIsConstAt(dtype, ptrcount) then
		s += "const "
	end if

	s += *datatypenames(dt)

	for i as integer = (ptrcount - 1) to 0 step -1
		if typeIsConstAt(dtype, i) then
			s += " const"
		end if

		s += " ptr"
	next

	function = s
end function

''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

dim shared as zstring ptr astnodename(0 to ...) => _
{ _
	_ '' Internal helper nodes
	@"group"     , _
	@"verblock"  , _
	@"veror"     , _
	@"verand"    , _
	@"vernumcheck", _
	@"divider"   , _
	@"scopeblock", _
	@"unknown"   , _
	@"fbcode"    , _
	@"renamelist", _
	@"title"     , _
	_
	_ '' Script helper nodes
	@"declareversions", _
	@"declarebool"  , _
	@"selecttarget" , _
	@"selectversion", _
	@"selectdefine" , _
	@"case"         , _
	@"caseelse"     , _
	@"endselect"    , _
	@"option"       , _
	_
	_ '' Declarations/statements
	@"ppinclude", _
	@"ppdefine" , _
	@"ppif"     , _
	@"ppelseif" , _
	@"ppelse"   , _
	@"ppendif"  , _
	@"pragmaonce", _
	@"inclib"   , _
	@"undef"    , _
	@"struct"   , _
	@"union"    , _
	@"enum"     , _
	@"typedef"  , _
	@"const"    , _
	@"var"      , _
	@"field"    , _
	@"proc"     , _
	@"param"    , _
	@"macroparam" , _
	@"array"      , _
	@"externbegin", _
	@"externend"  , _
	@"return"   , _
	@"assign"   , _
	@"selfor"   , _
	@"selfxor"  , _
	@"selfand"  , _
	@"selfshl"  , _
	@"selfshr"  , _
	@"selfadd"  , _
	@"selfsub"  , _
	@"selfmul"  , _
	@"selfdiv"  , _
	@"selfmod"  , _
	@"ifblock"  , _
	@"ifpart"   , _
	@"elseifpart", _
	@"elsepart" , _
	@"dowhile"  , _
	@"while"    , _
	_
	_ '' Expression atoms etc.
	@"consti"    , _
	@"constf"    , _
	@"text"      , _
	@"string"    , _
	@"char"      , _
	@"datatype"  , _
	@"ellipsis"  , _
	_
	_ '' BOPs
	@"clogor" , _
	@"clogand", _
	@"logor" , _
	@"logand", _
	@"or"     , _
	@"xor"    , _
	@"and"    , _
	@"ccomma" , _
	@"cassign", _
	@"cselfor", _
	@"cselfxor", _
	@"cselfand", _
	@"cselfshl", _
	@"cselfshr", _
	@"cselfadd", _
	@"cselfsub", _
	@"cselfmul", _
	@"cselfdiv", _
	@"cselfmod", _
	@"ceq"    , _
	@"cne"    , _
	@"clt"    , _
	@"cle"    , _
	@"cgt"    , _
	@"cge"    , _
	@"eq"     , _
	@"ne"     , _
	@"lt"     , _
	@"le"     , _
	@"gt"     , _
	@"ge"     , _
	@"shl"    , _
	@"shr"    , _
	@"add"    , _
	@"sub"    , _
	@"mul"    , _
	@"div"    , _
	@"mod"    , _
	@"index"  , _
	@"member" , _
	@"memberderef", _
	@"strcat" , _
	_
	_ '' UOPs
	@"clognot"    , _
	@"not"        , _
	@"negate"     , _
	@"unaryplus"  , _
	@"cdefined"   , _
	@"defined"    , _
	@"addrof"     , _
	@"deref"      , _
	@"stringify"  , _
	@"sizeof"     , _
	@"cast"       , _
	_
	_ '' Special expressions
	@"iif"       , _
	@"ppmerge"   , _
	@"call"      , _
	@"structinit", _
	@"arrayinit" , _
	@"dimension"   _
}

#assert ubound(astnodename) = ASTCLASS__COUNT - 1

function astNew overload(byval class_ as integer) as AstNode ptr
	dim as AstNode ptr n = callocate(sizeof(AstNode))
	n->class = class_
	function = n
end function

function astNew overload(byval class_ as integer, byval text as zstring ptr) as AstNode ptr
	var n = astNew(class_)
	n->text = strDuplicate(text)
	function = n
end function

function astNew overload(byval class_ as integer, byval c1 as AstNode ptr, byval c2 as AstNode ptr) as AstNode ptr
	var n = astNew(class_)
	astAppend(n, c1)
	astAppend(n, c2)
	function = n
end function

function astNewPPDEFINE(byval id as zstring ptr) as AstNode ptr
	var n = astNew(ASTCLASS_PPDEFINE, id)
	n->paramcount = -1
	function = n
end function

function astNewIIF(byval cond as AstNode ptr, byval l as AstNode ptr, byval r as AstNode ptr) as AstNode ptr
	var n = astNew(ASTCLASS_IIF, l, r)
	n->expr = cond
	function = n
end function

function astNewGROUP overload() as AstNode ptr
	function = astNew(ASTCLASS_GROUP)
end function

function astNewGROUP overload(byval c1 as AstNode ptr, byval c2 as AstNode ptr) as AstNode ptr
	var n = astNewGROUP()
	astAppend(n, c1)
	astAppend(n, c2)
	function = n
end function

sub astBuildGroupAndAppend(byref group as AstNode ptr, byval n as AstNode ptr)
	if group = NULL then group = astNewGROUP()
	astAppend(group, n)
end sub

private function astBuildDEFINED(byval symbol as zstring ptr, byval negate as integer) as AstNode ptr
	var n = astNewDEFINED(symbol)
	if negate then n = astNew(ASTCLASS_NOT, n)
	function = n
end function

function astNewDEFINEDfb64(byval negate as integer) as AstNode ptr
	function = astBuildDEFINED("__FB_64BIT__", negate)
end function

function astNewDEFINEDfbarm(byval negate as integer) as AstNode ptr
	function = astBuildDEFINED("__FB_ARM__", negate)
end function

function astNewDEFINEDfbos(byval os as integer) as AstNode ptr
	function = astNewDEFINED(osinfo(os).fbdefine)
end function

function astNewOPTION(byval opt as integer, byval text1 as zstring ptr, byval text2 as zstring ptr) as AstNode ptr
	var n = astNew(ASTCLASS_OPTION, text1)
	astSetAlias(n, text2)
	n->opt = opt
	function = n
end function

#if __FB_DEBUG__
private function astGetIndexOf(byval parent as AstNode ptr, byval lookfor as AstNode ptr) as integer
	var index = 0
	var i = parent->head
	while i
		if i = lookfor then return index
		index += 1
		i = i->next
	wend
	function = -1
end function
#define astIsChildOf(parent, lookfor) (astGetIndexOf(parent, lookfor) >= 0)
#endif

sub astTakeChildren(byval d as AstNode ptr, byval s as AstNode ptr)
	assert(d->head = NULL)
	d->head = s->head
	d->tail = s->tail
	s->head = NULL
	s->tail = NULL
end sub

sub astTakeAndPrependChildren(byval d as AstNode ptr, byval s as AstNode ptr)
	if s->tail then
		if d->head then
			s->tail->next = d->head
			d->head->prev = s->tail
		else
			d->tail = s->tail
		end if
		d->head = s->head
		s->head = NULL
		s->tail = NULL
	end if
end sub

sub astTakeAndAppendChildSequence(byval d as AstNode ptr, byval s as AstNode ptr, byval first as AstNode ptr, byval last as AstNode ptr)
	assert(astGetIndexOf(s, first) <= astGetIndexOf(s, last))

	'' unlink from s
	if first->prev then
		first->prev->next = last->next
	else
		s->head = last->next
	end if
	if last->next then
		last->next->prev = first->prev
	else
		s->tail = first->prev
	end if
	first->prev = NULL
	last->next = NULL

	'' append to d
	if d->tail then
		first->prev = d->tail
		d->tail->next = first
	else
		d->head = first
	end if
	d->tail = last
end sub

function astCloneChildren(byval src as AstNode ptr) as AstNode ptr
	var n = astNewGROUP()
	var i = src->head
	while i
		astAppend(n, astClone(i))
		i = i->next
	wend
	function = n
end function

function astGroupContains(byval group as AstNode ptr, byval lookfor as AstNode ptr) as integer
	var i = group->head
	while i
		if astIsEqual(i, lookfor) then
			return TRUE
		end if
		i = i->next
	wend
	function = FALSE
end function

function astGroupContainsAnyChildrenOf(byval l as AstNode ptr, byval r as AstNode ptr) as integer
	var i = r->head
	while i
		if astGroupContains(l, i) then return TRUE
		i = i->next
	wend
end function

function astGroupContainsAllChildrenOf(byval l as AstNode ptr, byval r as AstNode ptr) as integer
	var i = r->head
	while i
		if astGroupContains(l, i) = FALSE then exit function
		i = i->next
	wend
	function = TRUE
end function

private function astGroupsContainEqualChildren(byval l as AstNode ptr, byval r as AstNode ptr) as integer
	function = astGroupContainsAllChildrenOf(l, r) and astGroupContainsAllChildrenOf(r, l)
end function

sub astDelete(byval n as AstNode ptr)
	if n = NULL then exit sub

	deallocate(n->text)
	deallocate(n->alias)
	deallocate(n->origid)
	astDelete(n->subtype)
	astDelete(n->array)
	astDelete(n->bits)
	astDelete(n->expr)

	var i = n->head
	while i
		var nxt = i->next
		astDelete(i)
		i = nxt
	wend

	deallocate(n)
end sub

'' Insert in front of ref, or append if ref = NULL
sub astInsert(byval parent as AstNode ptr, byval n as AstNode ptr, byval ref as AstNode ptr)
	if n = NULL then exit sub

	assert(astIsChildOf(parent, n) = FALSE)
	assert(iif(ref, astIsChildOf(parent, ref), TRUE))

	'' If it's a GROUP, insert its children, and delete the GROUP itself
	if n->class = ASTCLASS_GROUP then
		if n->head then
			'' Relink the GROUP's children, so they're added without being reallocated
			if ref then
				if ref->prev then
					ref->prev->next = n->head
					n->head->prev = ref->prev
				else
					parent->head = n->head
					assert(n->head->prev = NULL)
				end if
				n->tail->next = ref
				ref->prev = n->tail
			else
				if parent->tail then
					parent->tail->next = n->head
					n->head->prev = parent->tail
				else
					parent->head = n->head
					assert(n->head->prev = NULL)
				end if
				assert(n->tail->next = NULL)
				parent->tail = n->tail
			end if

			n->head = NULL
			n->tail = NULL
		end if

		astDelete(n)
		exit sub
	end if

	if ref then
		if ref->prev then
			ref->prev->next = n
			n->prev = ref->prev
		else
			parent->head = n
			assert(n->prev = NULL)
		end if
		n->next = ref
		ref->prev = n
	else
		if parent->tail then
			parent->tail->next = n
			n->prev = parent->tail
		else
			parent->head = n
			assert(n->prev = NULL)
		end if
		assert(n->next = NULL)
		parent->tail = n
	end if
end sub

sub astPrepend(byval parent as AstNode ptr, byval n as AstNode ptr)
	astInsert(parent, n, parent->head)
end sub

sub astAppend(byval parent as AstNode ptr, byval n as AstNode ptr)
	astInsert(parent, n, NULL)
end sub

sub astUnlink(byval parent as AstNode ptr, byval n as AstNode ptr)
	assert(astIsChildOf(parent, n))

	if n->prev then
		n->prev->next = n->next
	else
		assert(parent->head = n)
		parent->head = n->next
	end if

	if n->next then
		n->next->prev = n->prev
	else
		assert(parent->tail = n)
		parent->tail = n->prev
	end if

	n->prev = NULL
	n->next = NULL
end sub

function astRemove(byval parent as AstNode ptr, byval n as AstNode ptr) as AstNode ptr
	function = n->next
	astUnlink(parent, n)
	astDelete(n)
end function

sub astRemoveChildren(byval parent as AstNode ptr)
	while parent->head
		astRemove(parent, parent->head)
	wend
end sub

function astReplace _
	( _
		byval parent as AstNode ptr, _
		byval old as AstNode ptr, _
		byval n as AstNode ptr _
	) as AstNode ptr
	assert(old)
	astInsert(parent, n, old)
	function = astRemove(parent, old)
end function

sub astSetText(byval n as AstNode ptr, byval text as zstring ptr)
	deallocate(n->text)
	n->text = strDuplicate(text)
end sub

sub astSetAlias(byval n as AstNode ptr, byval alias_ as zstring ptr)
	deallocate(n->alias)
	n->alias = strDuplicate(alias_)
end sub

sub astRenameSymbol(byval n as AstNode ptr, byval newid as zstring ptr)
	if n->origid = NULL then
		n->origid = n->text
		if n->alias = NULL then
			n->alias = strDuplicate(n->origid)
		end if
	else
		deallocate(n->text)
	end if
	n->text = strDuplicate(newid)
end sub

sub astRenameSymbolWithoutSettingOrigId(byval n as AstNode ptr, byval newid as zstring ptr)
	if n->alias = NULL then
		n->alias = strDuplicate(n->text)
	else
		deallocate(n->text)
	end if
	n->text = strDuplicate(newid)
end sub

sub astTakeAliasFromId(byval dst as AstNode ptr, byval src as AstNode ptr)
	if dst->alias then deallocate(dst->alias)
	dst->alias = src->text
	src->text = NULL
end sub

sub astTakeOrigId(byval dst as AstNode ptr, byval src as AstNode ptr)
	if dst->origid then deallocate(dst->origid)
	dst->origid = src->origid
	src->origid = NULL
end sub

sub astTakeAliasAndOrigId(byval dst as AstNode ptr, byval src as AstNode ptr)
	if dst->alias then deallocate(dst->alias)
	dst->alias = src->alias
	src->alias = NULL
	astTakeOrigId(dst, src)
end sub

sub astCopyOrigId(byval dst as AstNode ptr, byval src as AstNode ptr)
	if dst->origid then deallocate(dst->origid)
	dst->origid = strDuplicate(src->origid)
end sub

sub astSetType(byval n as AstNode ptr, byval dtype as integer, byval subtype as AstNode ptr)
	astDelete(n->subtype)
	n->dtype = dtype
	n->subtype = astClone(subtype)
end sub

'' astClone() but without children
function astCloneNode(byval n as AstNode ptr) as AstNode ptr
	if n = NULL then return NULL

	var c = astNew(n->class)
	c->attrib      = n->attrib
	c->text        = strDuplicate(n->text)
	c->alias       = strDuplicate(n->alias)
	c->origid      = strDuplicate(n->origid)
	c->dtype       = n->dtype
	c->subtype     = astClone(n->subtype)
	c->array       = astClone(n->array)
	c->bits        = astClone(n->bits)
	c->expr        = astClone(n->expr)
	c->location    = n->location
	select case n->class
	case ASTCLASS_PPDEFINE : c->paramcount = n->paramcount
	case ASTCLASS_STRUCT, ASTCLASS_UNION : c->maxalign = n->maxalign
	case ASTCLASS_OPTION : c->opt = n->opt
	case ASTCLASS_VERBLOCK, ASTCLASS_PPIF, ASTCLASS_PPELSEIF
		c->apis = n->apis
	case ASTCLASS_VERNUMCHECK
		c->vernum = n->vernum
	end select

	function = c
end function

function astClone(byval n as AstNode ptr) as AstNode ptr
	var c = astCloneNode(n)
	if c then
		var i = n->head
		while i
			astAppend(c, astClone(i))
			i = i->next
		wend
	end if
	function = c
end function

function astContains(byval n as AstNode ptr, byval astclass as integer) as integer
	if n->class = astclass then return TRUE
	if n->subtype then if astContains(n->subtype, astclass) then return TRUE
	if n->array   then if astContains(n->array  , astclass) then return TRUE
	if n->bits    then if astContains(n->bits   , astclass) then return TRUE
	if n->expr    then if astContains(n->expr   , astclass) then return TRUE
	var i = n->head
	while i
		if astContains(i, astclass) then return TRUE
		i = i->next
	wend
	function = FALSE
end function

function astContainsCAssignments(byval n as AstNode ptr) as integer
	select case as const n->class
	case ASTCLASS_CASSIGN, _
	     ASTCLASS_CSELFOR, ASTCLASS_CSELFXOR, ASTCLASS_CSELFAND, _
	     ASTCLASS_CSELFSHL, ASTCLASS_CSELFSHR, _
	     ASTCLASS_CSELFADD, ASTCLASS_CSELFSUB, _
	     ASTCLASS_CSELFMUL, ASTCLASS_CSELFDIV, ASTCLASS_CSELFMOD
		return TRUE
	end select
	if n->subtype then if astContainsCAssignments(n->subtype) then return TRUE
	if n->array   then if astContainsCAssignments(n->array  ) then return TRUE
	if n->bits    then if astContainsCAssignments(n->bits   ) then return TRUE
	if n->expr    then if astContainsCAssignments(n->expr   ) then return TRUE
	var i = n->head
	while i
		if astContainsCAssignments(i) then return TRUE
		i = i->next
	wend
	function = FALSE
end function

function astHas1Child(byval n as AstNode ptr) as integer
	function = n->head andalso (n->head = n->tail)
end function

function astHasOnlyChild(byval n as AstNode ptr, byval astclass as integer) as integer
	function = astHas1Child(n) andalso (n->head->class = astclass)
end function

function astIsCodeBlock(byval n as AstNode ptr) as integer
	select case n->class
	case ASTCLASS_SCOPEBLOCK, ASTCLASS_IFBLOCK, ASTCLASS_DOWHILE, _
	     ASTCLASS_WHILE, ASTCLASS_STRUCT, ASTCLASS_UNION, ASTCLASS_ENUM
		function = TRUE
	case ASTCLASS_PROC
		function = (n->expr <> NULL)
	end select
end function

function astIsCodeScopeBlock(byval n as AstNode ptr) as integer
	select case n->class
	case ASTCLASS_SCOPEBLOCK, ASTCLASS_IFBLOCK, ASTCLASS_DOWHILE, ASTCLASS_WHILE
		function = TRUE
	end select
end function

function astIsScopeBlockWith1Stmt(byval n as AstNode ptr) as integer
	function = (n->class = ASTCLASS_SCOPEBLOCK) andalso _
	           astHas1Child(n) andalso (not astIsCodeBlock(n->head))
end function

function astIsMergableBlock(byval n as AstNode ptr) as integer
	select case n->class
	case ASTCLASS_STRUCT, ASTCLASS_UNION, ASTCLASS_ENUM, ASTCLASS_RENAMELIST
		function = TRUE
	end select
end function

function astIsCastTo(byval n as AstNode ptr, byval dtype as integer, byval subtype as AstNode ptr) as integer
	function = (n->class = ASTCLASS_CAST) andalso (n->dtype = dtype) andalso astIsEqual(n->subtype, subtype)
end function

''
'' Check whether two ASTs are "equal".
''
'' For the purposes of merging, the rules are somewhat relaxed: two procedure
'' declarations with different calling conventions can be treated as equal if
'' they're both covered by an Extern block, because then we won't emit the
'' calling convention explicitly anyways, and the declarations look exactly the
'' same.
''
'' For VEROR and VERAND nodes the order of children does not matter; we treat
'' them as equal either way.
''
function astIsEqual _
	( _
		byval a as AstNode ptr, _
		byval b as AstNode ptr, _
		byval is_merge as integer _
	) as integer

	if a = b then return TRUE
	if (a = NULL) or (b = NULL) then exit function

	if a->class <> b->class then exit function

	var aattrib = a->attrib
	var battrib = b->attrib

	if is_merge then
		'' If callconv is hidden on both sides, then ignore it
		if (aattrib and ASTATTRIB_HIDECALLCONV) and (battrib and ASTATTRIB_HIDECALLCONV) then
			aattrib and= not (ASTATTRIB_CDECL or ASTATTRIB_STDCALL)
			battrib and= not (ASTATTRIB_CDECL or ASTATTRIB_STDCALL)
		end if

		'' Other than that, we should ignore ASTATTRIB_HIDECALLCONV itself,
		'' allowing hFindCommonCallConvsOnMergedDecl() to handle cases where
		'' both sides have the same callconv but different hiding status.
		aattrib and= not ASTATTRIB_HIDECALLCONV
		battrib and= not ASTATTRIB_HIDECALLCONV

		'' Whether nodes are affected by -[no]string only matters during the CharStringPass;
		'' it doesn't matter for merging.
		aattrib and= not (ASTATTRIB_NOSTRING or ASTATTRIB_STRING)
		battrib and= not (ASTATTRIB_NOSTRING or ASTATTRIB_STRING)

		'' Ignore DLLIMPORT/STATIC on procedures for now, as we're not emitting it anyways
		if a->class = ASTCLASS_PROC then
			aattrib and= not (ASTATTRIB_DLLIMPORT or ASTATTRIB_STATIC)
			battrib and= not (ASTATTRIB_DLLIMPORT or ASTATTRIB_STATIC)
		end if
	end if

	'' Some attributes could perhaps always be ignored because they don't cause declarations to really be different.
	'' However, OCT/HEX attributes mustn't be ignored because otherwise number literals with the same digits but
	'' a different base could incorrectly compare equal.

	if aattrib <> battrib then exit function

	if (a->text <> NULL) <> (b->text <> NULL) then exit function
	if a->text then if *a->text <> *b->text then exit function

	if (a->alias <> NULL) <> (b->alias <> NULL) then exit function
	if a->alias then if *a->alias <> *b->alias then exit function

	if a->dtype <> b->dtype then exit function
	if astIsEqual(a->subtype, b->subtype, is_merge) = FALSE then exit function
	if astIsEqual(a->array, b->array, is_merge) = FALSE then exit function
	if astIsEqual(a->bits, b->bits, is_merge) = FALSE then exit function

	if astIsEqual(a->expr, b->expr, is_merge) = FALSE then exit function

	'' Only check location if not merging: for merging, the source location doesn't matter.
	'' We only use it before the merging step.
	if is_merge = FALSE then
		if a->location.source  <> b->location.source  then exit function
		if a->location.linenum <> b->location.linenum then exit function
	end if

	select case a->class
	case ASTCLASS_PPDEFINE
		if a->paramcount <> b->paramcount then exit function

	case ASTCLASS_STRUCT, ASTCLASS_UNION
		if a->maxalign <> b->maxalign then exit function

	case ASTCLASS_OPTION
		if a->opt <> b->opt then exit function

	case ASTCLASS_VERBLOCK, ASTCLASS_PPIF, ASTCLASS_PPELSEIF
		if a->apis.equals(b->apis) = FALSE then exit function

	case ASTCLASS_VEROR, ASTCLASS_VERAND
		return astGroupsContainEqualChildren(a, b)

	case ASTCLASS_VERNUMCHECK
		if a->vernum <> b->vernum then exit function
	end select

	if is_merge then
		if astIsMergableBlock(a) then
			return TRUE
		end if
	end if

	'' Children
	a = a->head
	b = b->head
	while (a <> NULL) and (b <> NULL)
		if astIsEqual(a, b, is_merge) = FALSE then
			exit function
		end if
		a = a->next
		b = b->next
	wend

	'' Both a's and b's last child must be reached at the same time
	function = ((a = NULL) and (b = NULL))
end function

function hGetFbNumberLiteralPrefix(byval attrib as integer) as string
	if attrib and ASTATTRIB_BIN then
		function = "&b"
	elseif attrib and ASTATTRIB_OCT then
		function = "&o"
	elseif attrib and ASTATTRIB_HEX then
		function = "&h"
	end if
end function

function astEvalConstiAsInt64(byval n as AstNode ptr) as longint
	assert(astIsCONSTI(n))
	function = vallng(hGetFbNumberLiteralPrefix(n->attrib) + *n->text)
end function

function astIsConst0(byval n as AstNode ptr) as integer
	if astIsCONSTI(n) then
		function = (astEvalConstiAsInt64(n) = 0)
	end if
end function

function astLookupMacroParam(byval macro as AstNode ptr, byval id as zstring ptr) as integer
	var index = 0

	assert(macro->class = ASTCLASS_PPDEFINE)

	var param = macro->head
	while param

		assert(param->class = ASTCLASS_MACROPARAM)
		if *param->text = *id then
			return index
		end if

		index += 1
		param = param->next
	wend

	function = -1
end function

function astGetMacroParamByNameIgnoreCase(byval macro as AstNode ptr, byval id as zstring ptr) as AstNode ptr
	assert(macro->class = ASTCLASS_PPDEFINE)

	var param = macro->head
	while param

		assert(param->class = ASTCLASS_MACROPARAM)
		if lcase(*param->text) = lcase(*id) then
			return param
		end if

		param = param->next
	wend

	function = NULL
end function

sub astVisit(byval n as AstNode ptr, byval callback as ASTVISITCALLBACK)
	if callback(n) = FALSE then
		exit sub
	end if

	if n->subtype then astVisit(n->subtype, callback)
	if n->array   then astVisit(n->array  , callback)
	if n->bits    then astVisit(n->bits   , callback)
	if n->expr    then astVisit(n->expr   , callback)

	var i = n->head
	while i
		astVisit(i, callback)
		i = i->next
	wend
end sub

function astCount(byval n as AstNode ptr) as integer
	var count = 1

	if n->subtype then count += astCount(n->subtype)
	if n->array   then count += astCount(n->array  )
	if n->bits    then count += astCount(n->bits   )
	if n->expr    then count += astCount(n->expr   )

	var i = n->head
	while i
		count += astCount(i)
		i = i->next
	wend

	function = count
end function

''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
'' AST dumping for pretty output and debugging

function astDumpPrettyClass(byval astclass as integer) as string
	select case astclass
	case ASTCLASS_PPDEFINE : function = "#define"
	case ASTCLASS_CONST : function = "constant"
	case ASTCLASS_VAR   : function = "variable"
	case ASTCLASS_PROC  : function = "procedure"
	case else           : function = *astnodename(astclass)
	end select
end function

function astDumpPrettyDecl(byval n as AstNode ptr, byval show_type as integer) as string
	dim as string s

	if n->text = NULL then
		s += "anonymous "
	end if

	s += astDumpPrettyClass(n->class)

	if n->text then
		s += " " + strMakePrintable(*n->text)
	end if

	if n->alias then
		s += " alias """ + strMakePrintable(*n->alias) + """"
	end if

	if n->class = ASTCLASS_PROC then
		s += "()"
	end if

	if show_type then
		if n->array then
			s += emitFbExpr(n->array)
		end if
		s += " as " + emitFbType(n->dtype, n->subtype)
	end if

	function = s
end function

function astDumpOne(byval n as AstNode ptr) as string
	dim as string s

	if n = NULL then
		return "<NULL>"
	end if

	's += "[" & hex(n) & "] "
	if (n->class >= 0) and (n->class < ASTCLASS__COUNT) then
		s += *astnodename(n->class)
	else
		s += "invalid astclass " & n->class
	end if

	#macro checkAttrib(a)
		if n->attrib and ASTATTRIB_##a then s += " " + lcase(#a, 1)
	#endmacro
	checkAttrib(LOCAL)
	checkAttrib(STATIC)
	checkAttrib(EXTERN)
	checkAttrib(OCT)
	checkAttrib(HEX)
	checkAttrib(CDECL)
	checkAttrib(STDCALL)
	checkAttrib(HIDECALLCONV)
	checkAttrib(POISONED)
	checkAttrib(PACKED)
	checkAttrib(VARIADIC)
	checkAttrib(PARENTHESIZEDMACROPARAM)
	checkAttrib(TAGID)
	checkAttrib(GENERATEDID)
	checkAttrib(DLLIMPORT)
	checkAttrib(ENUMCONST)
	checkAttrib(USED)
	checkAttrib(IFNDEFDECL)
	checkAttrib(NOSTRING)
	checkAttrib(STRING)

	select case n->class
	case ASTCLASS_OPTION
		s += " " + *tkInfoText(n->opt)
	case ASTCLASS_VERBLOCK, ASTCLASS_PPIF, ASTCLASS_PPELSEIF
		s += " apis=" + n->apis.dump()
	case ASTCLASS_VERNUMCHECK
		s += " vernum=" & n->vernum
	end select

	if n->text then
		s += " """ + strMakePrintable(*n->text) + """"
	end if
	if n->alias then
		s += " alias """ + strMakePrintable(*n->alias) + """"
	end if
	if n->origid then
		s += " origid """ + strMakePrintable(*n->origid) + """"
	end if

	if n->dtype <> TYPE_NONE then
		s += " as " + typeDump(n->dtype)
	end if

	function = s
end function

sub astDump _
	( _
		byval n as AstNode ptr, _
		byval nestlevel as integer, _
		byref prefix as string _
	)

	if n = NULL then
		print "<NULL>"
		exit sub
	end if

	nestlevel += 1

	var s = space((nestlevel - 1) * 3)
	if len(prefix) > 0 then
		s += prefix + ": "
	end if
	s += astDumpOne(n)
	print s

	#define dumpField(field) if n->field then astDump(n->field, nestlevel, #field)
	dumpField(subtype)
	dumpField(array)
	dumpField(bits)
	dumpField(expr)

	var child = n->head
	while child
		astDump(child, nestlevel)
		child = child->next
	wend

	nestlevel -= 1
end sub
