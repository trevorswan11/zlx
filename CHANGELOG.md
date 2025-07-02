# Change Log

All notably significant or outstanding changes to the zlx language will be documented in this file. Most changes will not be reflected here, as most language information can be found in the documentation.

## [0.1.0]
- Initial Release!
    - Fully functional scripting language fit for basic tasks
    - Binaries built for most major platforms... with a zlx script!
- 16-star milestone on project after initial reddit post, thank you all for the support!

## [0.1.1]
- Added ascii code support
- Added support for escape characters in strings
    - Multiline strings have been changed from triple quotes (""") to triple backticks (```)
- Updated syntax extension and docs to reflect these changes

## [0.2.0]
- "_" can now be used as an identifier to discard
    - It cannot be used after the keywords 'const' or 'let'
- Made the 'typeof' prefix operator more clear, now returns a pair
    - The 'first' field is a broad type descriptor (e.g. any)
    - The 'second' field is a narrower representation of the type, aligned with the interpreters inferred or explicit type (e.g. number)
- Added star star (**) operator that behaves like the same operator in python. It can be used for exponentiation
    - This is a binary operator
- Compound assignment now works on more types with more consistent behavior
- Modularized reused helpers for builtin modules
- Fixed inconsistent casing in some builtin functions
- Resolved inconsistent formatting in verbose output dumping
- Added enums!
    - Declared using the "enum" keyword
    - Simply represent an object of numbers starting from 0 and increasing for every entry
    - Can be used in match statements and expressions!
- Added stat module!
    - Full suite of statistical functions with some working on numbers and others on arrays
    - Linear regression analysis works, but more complex analysis functions may be implemented in the future 

## [0.2.1]
- Fixed corrupt memory bug in the graph module preventing edge checking

## [0.3.0]
- Removed byte limit on file reading, now adapts to the size of the file
- Restructured function pointers for builtin modules to remove redundancy in function params
- Added linear algebra module!
    - Matrix multiplication, normalization, determination, and more
    - Vector operations and 2D/3D space behavior
    - Derived from std_structs, using "size", "str", and "items" for inferred function calls and representation
- Partially fixed issue where scoped variables memory would leak out of their scope while being unaccessible by an environment
    - Small performance hit due to arena allocation management, but only by a few millis
    - This is still an issue with for and while loops, and should be handled at some point
- Updated error message in builtin module helper
- format builtin now inherently converts values to their printable representation
    - In other words, format now accepts std instance arguments
- Enforced argument count being 0 for almost all builtin functions and modules
    - This will be enforced in future modules

## [0.4.0]
- Added tooling to the program
    - Builtin hex-dumping option similar to `xxd`
    - Builtin file compression using huffman encoding
    - Both can be accessed through command line arguments. See the `README` for details!

## [0.4.1]
- Fixed Compression algorithm to work deterministically, eliminated bug when decompressing data
    - Shifted to more manual memory styles for the encoding table as hashmaps are not consistent across runs

## [0.4.2]
- Folders can now be compressed into archives, which have the `.zacx` file extension by default
- The compression command line arg dynamically dispatches to creating an archive if necessary
    - This does not work the other way around, and does not work at all for decompression due to safety checks