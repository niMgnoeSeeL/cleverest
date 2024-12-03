# Commit Messages from WAFLGo dataset

## mujs

### BIC

#### Issue #65

**Commit:** 8c27b12

**Commit Always Reached by Cleverest with default mode:** Yes

**Commit Always Reached by Cleverest with MSGONLY mode:** Yes

**Commit Message Word Count:** 4

**Commit Message Character Count:** 41

**Commit Message:**
```
Fix leak in Function.prototype.toString.
```

#### Issue #141

**Commit:** 832e069

**Commit Always Reached by Cleverest with default mode:** Yes

**Commit Always Reached by Cleverest with MSGONLY mode:** Yes

**Commit Message Word Count:** 86

**Commit Message Character Count:** 618

**Commit Message:**
```
Support 4-byte UTF-8 sequences.

The following functions are no longer restricted to 16-bit integer values:

	String.fromCharCode()
	String.prototype.charCodeAt()

repr() will not escape SMP characters, as doing so would require conversion to
surrogate pairs, but will encode these characters as UTF-8. Unicode characters
in the BMP will still be escaped with \uXXXX as before.

JSON.stringify() only escapes control characters, so will represent all non-ASCII
characters as UTF-8.

We do no automatic conversions to/from surrogate pairs. Code that worked with
surrogate pairs should not be affected by these changes.
```

#### Issue #145

**Commit:** 4c7f6be

**Commit Always Reached by Cleverest with default mode:** Yes

**Commit Always Reached by Cleverest with MSGONLY mode:** Yes

**Commit Message Word Count:** 28

**Commit Message Character Count:** 187

**Commit Message:**
```
Issue #139: Parse integers with floats to support large numbers.

Add a js_strtol which parses integers with bases 2..36 using simple
double precision arithmetic with no overflow checks.
```

#### Issue #166

**Commit:** 3f71a1c

**Commit Always Reached by Cleverest with default mode:** Yes

**Commit Always Reached by Cleverest with MSGONLY mode:** Yes

**Commit Message Word Count:** 89

**Commit Message Character Count:** 537

**Commit Message:**
```
Fast path for "simple" arrays.

An array without holes and with only integer properties can be represented
with a "flat" array part that allows for O(1) property access.

If we ever add a non-integer property, create holes in the array,
the whole array is unpacked into a normal string-keyed object.

Also add fast integer indexing to be used on these arrays, before falling
back to converting the integer to a string property lookup.

Use JS_ARRAYLIMIT to restrict size of arrays to avoid integer overflows and out
of memory thrashing.
```
### FIX

#### Issue #65

**Commit:** 833f82c

**Commit Always Reached by Cleverest with default mode:** Yes

**Commit Always Reached by Cleverest with MSGONLY mode:** Yes

**Commit Message Word Count:** 8

**Commit Message Character Count:** 66

**Commit Message:**
```
Fix issue #65: Uninitialized name in Function.prototype function.
```

#### Issue #141

**Commit:** 6871e5b

**Commit Always Reached by Cleverest with default mode:** Yes

**Commit Always Reached by Cleverest with MSGONLY mode:** No

**Commit Message Word Count:** 9

**Commit Message Character Count:** 62

**Commit Message:**
```
Issue #141: Add missing end-of-string checks in regexp lexer.
```

#### Issue #145

**Commit:** f93d245

**Commit Always Reached by Cleverest with default mode:** Yes

**Commit Always Reached by Cleverest with MSGONLY mode:** No

**Commit Message Word Count:** 2

**Commit Message Character Count:** 14

**Commit Message:**
```
Fix js_strtol
```

#### Issue #166

**Commit:** 8b5ba20

**Commit Always Reached by Cleverest with default mode:** Yes

**Commit Always Reached by Cleverest with MSGONLY mode:** Yes

**Commit Message Word Count:** 20

**Commit Message Character Count:** 124

**Commit Message:**
```
Issue #166: Use special iterator for string and array indices.

Add a scratch buffer to js_State to hold temporary strings.
```
## libxml2

### BIC

#### Issue #535

**Commit:** 9a82b94

**Commit Always Reached by Cleverest with default mode:** Yes

**Commit Always Reached by Cleverest with MSGONLY mode:** Yes

**Commit Message Word Count:** 24

**Commit Message Character Count:** 175

**Commit Message:**
```
Introduce xmlNewSAXParserCtxt and htmlNewSAXParserCtxt

Add API functions to create a parser context with a custom SAX handler
without having to mess with ctxt->sax manually.
```

#### Issue #550

**Commit:** 7e3f469

**Commit Always Reached by Cleverest with default mode:** Yes

**Commit Always Reached by Cleverest with MSGONLY mode:** Yes

**Commit Message Word Count:** 40

**Commit Message Character Count:** 253

**Commit Message:**
```
entities: Use flags to store '<' check results

Instead of abusing the LSB of the "checked" member, store the result
of testing for occurrence of '<' character in "flags".

Also use the flags in xmlParseStringEntityRef instead of rescanning
every time.
```
### FIX

#### Issue #535

**Commit:** d0c3f01

**Commit Always Reached by Cleverest with default mode:** Yes

**Commit Always Reached by Cleverest with MSGONLY mode:** Yes

**Commit Message Word Count:** 57

**Commit Message Character Count:** 381

**Commit Message:**
```
parser: Fix old SAX1 parser with custom callbacks

For some reason, xmlCtxtUseOptionsInternal set the start and end element
SAX handlers to the internal DOM builder functions when XML_PARSE_SAX1
was specified. This means that custom SAX handlers could never work with
that flag because these functions would receive the wrong user data
argument and crash immediately.

Fixes #535.
```

#### Issue #550

**Commit:** 6273df6

**Commit Always Reached by Cleverest with default mode:** No

**Commit Always Reached by Cleverest with MSGONLY mode:** No

**Commit Message Word Count:** 57

**Commit Message Character Count:** 381

**Commit Message:**
```
xpath: Ignore entity ref nodes when computing node hash

XPath queries only work reliably if entities are substituted.
Nevertheless, it's possible to query a document with entity reference
nodes. xmllint even deletes entities when the `--dropdtd` option is
passed, resulting in dangling pointers, so it's best to skip entity
reference nodes to avoid a use-after-free.

Fixes #550.
```
## poppler

### BIC

#### Issue #1282

**Commit:** 3d35d20

**Commit Always Reached by Cleverest with default mode:** Yes

**Commit Always Reached by Cleverest with MSGONLY mode:** Yes

**Commit Message Word Count:** 30

**Commit Message Character Count:** 198

**Commit Message:**
```
Avoid cycles in PDF parsing

Mark objects being processed in Parser::makeStream() as being processed
and check the mark when entering this method to avoid processing
of the same object recursively.
```

#### Issue #1289

**Commit:** 3cae777

**Commit Always Reached by Cleverest with default mode:** No

**Commit Always Reached by Cleverest with MSGONLY mode:** No

**Commit Message Word Count:** 8

**Commit Message Character Count:** 50

**Commit Message:**
```
pdfunite: add fields to AcroForm dict

Bug #99141
```

#### Issue #1303

**Commit:** e674ca6

**Commit Always Reached by Cleverest with default mode:** No

**Commit Always Reached by Cleverest with MSGONLY mode:** No

**Commit Message Word Count:** 66

**Commit Message Character Count:** 398

**Commit Message:**
```
Create fallback fonts as needed.

If a PDF form field value uses a font that is not in the resources dictionary, a warning is logged and the field value is ignored/not displayed. It's unclear whether this behavior is strictly valid based on the PDF spec (since typically font references, even to base fonts, require a corresponding font dictionary) but Acrobat seems to display the content anyway.
```

#### Issue #1305

**Commit:** aaf2e80

**Commit Always Reached by Cleverest with default mode:** No

**Commit Always Reached by Cleverest with MSGONLY mode:** No

**Commit Message Word Count:** 46

**Commit Message Character Count:** 283

**Commit Message:**
```
Tweak the don't use Appearance stream if annot is typeHighlight

After playing hand editing files and opening them in Adobe Reader i
*think* the condition is "if the appearance stream has a ExtGState in
its Resources dict, then use the appearance stream, otherwise draw it
ourselves
```

#### Issue #1381

**Commit:** 245abad

**Commit Always Reached by Cleverest with default mode:** No

**Commit Always Reached by Cleverest with MSGONLY mode:** No

**Commit Message Word Count:** 44

**Commit Message Character Count:** 262

**Commit Message:**
```
Change Function::getToken return a GooString instead of a pointer

Makes the calling code simpler, also no need to check for null since the
function was never returning null anyway

Fixes a memory leak since some of the conditions were missing a delete
tok call
```
### FIX

#### Issue #1282

**Commit:** 4564a00

**Commit Always Reached by Cleverest with default mode:** Yes

**Commit Always Reached by Cleverest with MSGONLY mode:** Yes

**Commit Message Word Count:** 6

**Commit Message Character Count:** 36

**Commit Message:**
```
pdfunite: Fix crash on broken files
```

#### Issue #1289

**Commit:** efb6868

**Commit Always Reached by Cleverest with default mode:** Yes

**Commit Always Reached by Cleverest with MSGONLY mode:** No

**Commit Message Word Count:** 6

**Commit Message Character Count:** 42

**Commit Message:**
```
pdfunite: Don't crash in broken documents
```

#### Issue #1303

**Commit:** a4ca3a9

**Commit Always Reached by Cleverest with default mode:** No

**Commit Always Reached by Cleverest with MSGONLY mode:** No

**Commit Message Word Count:** 11

**Commit Message Character Count:** 67

**Commit Message:**
```
topIdx can't be negative

Fixes crash on broken files. Issue #1303
```

#### Issue #1305

**Commit:** 907d05a

**Commit Always Reached by Cleverest with default mode:** No

**Commit Always Reached by Cleverest with MSGONLY mode:** No

**Commit Message Word Count:** 18

**Commit Message Character Count:** 95

**Commit Message:**
```
Fix crash in file that wants to do huge transparency group

huge = 2147483016 x 2

Issue #1305
```

#### Issue #1381

**Commit:** 1be35ee

**Commit Always Reached by Cleverest with default mode:** No

**Commit Always Reached by Cleverest with MSGONLY mode:** No

**Commit Message Word Count:** 21

**Commit Message Character Count:** 137

**Commit Message:**
```
Fix stack overflow in PostScriptFunction::parseCode

By using a pointer instead of a variable things are on the heap.

Fixes issue #1381
```
