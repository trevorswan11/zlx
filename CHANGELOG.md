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