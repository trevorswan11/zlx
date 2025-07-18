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

## [0.4.3]
- Rewrote type builtins to better use dsa library
- Fixed an issue with a memory leak and memory corruption in certain scopes
- Added `raw` builtin that combines `detype` and `deref` to continuously retrieve the raw underlying data
- Fixed documentation formatting issue.

## [0.4.4]
- Fixed fs.append to append to the end of the file instead of overwriting the current contents
- Single file compression is now fully streamed and works in chunks
    - Archiving functions and decompression will not support this behavior as it requires a redesign of the compression system

## [0.5.0]
- Added support for `cat` and `diff` tools through zlx
- Switched to zig's standard library implementation for compression algorithms
    - While it was cool to have my own implementations, it was very slow for what I want to use this project for :(

## [0.6.0]
- Updated README to reflect recent changes in project tooling
- Variables can now be declared uninitialized without a type specifier
- Fixed an issue where the system input would read a return cartridge, preventing string comparison and operations
- Fixed an issue where `csv.write` would attempt to handle too much and would violate its own internal assumptions
- Fixed an issue where the format function would fail to include the first format specifier
- Created `zip` function that takes in multiple arrays and returns a single array with each entry having `[[arr1[i], arr2[i + 1], etc...], ...]`
- Added `sqlite3` as a dependency to enable the `sqlite` as a builtin module
- The zlx-syntax vscode extension has been updated to include the `zip` builtin and `sqlite` module
- Switched to zig's `zlib` compression algorithm
- Removed a lot of code repetition in builtin module and type handlers
    - This has normalized error messages generated by improper calls to these modules/types
- Stripped down array module to just be `slice` and `join`
    - The `array_list` type should be used for operations that used to be found in the `array` module
- Removed `raylib` as a dependency and deleted `plotting` branch
    - Writing a cross platform plotting library is beyond the scope of this project
    - I cannot develop the main branch and march towards release 1.0.0 while working on plotting, and it's just really not something I'm interested in
- Created threading library which can be accessed through the `thread` standard library struct
    - ZLX is not thread-safe, and I will not be changing it to act in a thread-safe manner
    - This module throws foot guns at you, have fun!
    
## [0.6.1]
- Added log_base to math
- You can now type the name of important standard library structs to see a list of bound method names (not full signature)
- `fs.ls` and `fs.lsa` now work with 0 args, defaulting to the "." directory
- Updated reserved identifier map to include recent module additions