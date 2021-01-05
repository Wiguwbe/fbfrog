#include "test"
#include "../../src/util-str.bi"

test(strIsValidSymbolId("") = false)
test(strIsValidSymbolId("_"))
test(strIsValidSymbolId("____"))
test(strIsValidSymbolId("_a"))
test(strIsValidSymbolId("_A"))
test(strIsValidSymbolId("_1"))
test(strIsValidSymbolId("1") = false)
test(strIsValidSymbolId("a"))
test(strIsValidSymbolId("A"))
test(strIsValidSymbolId("abcABC_123"))
