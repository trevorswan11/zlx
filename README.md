# zlx [![Zig](https://img.shields.io/badge/zig-0.14.0-orange)](https://ziglang.org/) [![License](https://img.shields.io/github/license/trevorswan11/zlx)](LICENSE) [![Last commit](https://img.shields.io/github/last-commit/trevorswan11/zlx)](https://github.com/trevorswan11/zlx) [![Build](https://github.com/trevorswan11/zlx/actions/workflows/main.yml/badge.svg)](https://github.com/trevorswan11/zlx/actions/workflows/main.yml)

<p align="center">
  <img src="/resources/zlx-logo-v2.png" alt="zlx logo" width="250"/>
</p>

<p align="center">
  A lexical analyzer, parser, and interpreter written in Zig.
</p>

### Inspiration
The backbone of this project was made with the help of [tylerlaceby's](https://www.youtube.com/@tylerlaceby) lexer playlist on YouTube. It was created with the intent to further learn Zig and to tackle something I had little to no knowledge about: parsing! His full, short playlist can be found [here](https://www.youtube.com/playlist?list=PL_2VhOvlMk4XDeq2eOOSDQMrbZj9zIU_b) if you're interested. 

While I started this project with the intent to make the parser only, I ended up going much deeper and ended up building an interpreter. Ultimately, this project gave me a great understanding of Zig's strengths and weaknesses and taught me more about memory management in this language and in general. It was also a lot of fun!

## Getting Started
1. Clone the repository using `git clone --recursive https://github.com/trevorswan11/zlx`
2. Install [Zig](https://ziglang.org/) and include it in your system's path or somewhere else usable by your system
    - You can also build Zig from source following the instructions [here](https://github.com/ziglang/zig), but this is much more involved 
3. Build the binary with `zig build`. I used Zig 0.14.0, but other versions may work as well
    - The Zig language strives to be cross-platform, and all code written or used in this project is runnable on any platform  

## Building/Running the Program
- You can build the binary using `zig build` as mentioned above, but you can specify optimization targets if desired using these extra arguments
    - `-Doptimize=Debug`: This is the default and enables all checks
    - `-Doptimize=ReleaseFast`: Prioritize performance without safety checks
    - `-Doptimize=ReleaseSmall`: Prioritize small binary size over performance and safety
    - `-Doptimize=ReleaseSafe`: Balance between fast and small release modes 
- You can use the example language "tests" with `zig build run -- <run|dump|ast> examples/<filename> <time?> <-v?>`
    - `run` interprets the program, `dump` prints the syntax-highlighted file, and `ast` simply parses the program
    - `time` times the parser, interpreter, and program - this is an optional parameter
    - `-v` prints verbose output, showing an indented and formatted abstract syntax tree - also optional
- You can interpret your own input file by passing in the relative path as `zig build run -- run <path>`
- If you're pulling the executable from the `zig-out` directory, you can use the same arguments as explained above
    - The same applies for downloads from the `releases` tags
- Once native tests are written, you can run them with `zig build test`

## External Libraries
This project uses a single external library called [zig-regex](https://github.com/tiehuis/zig-regex), a simple regex library for Zig. While the `README` of this library mentions it is a work in progress, it met this projects needs perfectly. That being said, I hope to be able to make this a zero-dependency project when/if the Zig teams adds a Regex module to the standard library.

## Language Documentation
Documentation for the custom language (name TBD) will be written over time. The "standard library" has a few built-in functions that work out of the box, and also has built-in modules that must be imported to use their defined functions and constants. While documentation is a WIP, you can find the source code for these functions and modules in the `builtins` folder in the `src` directory.

## Naming Conventions
I’ve slightly altered some of the patterns used in tylerlaceby’s language, resulting in a syntax influenced by Go, Python, Rust, and more! The project itself will keep the name **zlx**, and I believe I’ll use a default file extension like `.zX`. This does not matter and will never be enforced since there’s no editor integration and the program can attempt to parse any file. By convention, all declarations should use `snake_case`, but I really don't care — do what you want.

## Disclaimers
- Zig is in its _very_ early stages at the time of writing this project, and it should be expected that behavior may break as the language matures
- This is a personal project, and will likely be put off to the side when I stop finding things to implement or get sick of writing documentation
    - If you find something glaringly wrong or would just like to contribute, feel free to open an issue or pull request!
- ChatGPT was used in some steps of the development process, specifically with help writing the example language 'tests' and with debugging some stubborn bugs. ChatGPT was also used to make the logo found at the top of this file!

## Acknowledgements
- Thank you to [tylerlaceby’s](https://www.youtube.com/@tylerlaceby) lexer playlist on YouTube, which was incredibly easy to understand and gave me a solid grasp of the building blocks needed to make a lexer and Pratt parser
- Thanks to this [article](https://matklad.github.io/2020/04/13/simple-but-powerful-pratt-parsing.html) by matklad, which helped me iron out some bugs and inconsistencies in binding powers
- If you are interested and unfamiliar with the Zig build process (which is really quite cool), I would recommend checking out this [video](https://youtu.be/jy7w_7JZYyw?si=7GtNPmn-OZtj9b7X)! [Zig SHOWTIME](https://www.youtube.com/@ZigSHOWTIME/featured) has been a great resource for me as I've learned the language!
