#pragma once

extern "C"

extern var1 as zstring * 100
extern var2(0 to 99) as byte

type UDT
	field1 as zstring * 100
	field2(0 to 99) as byte
end type

extern p1 as zstring ptr
extern p2 as byte ptr

end extern
