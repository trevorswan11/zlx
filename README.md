# zlx [![Zig](https://img.shields.io/badge/zig-0.14.0-orange)](https://ziglang.org/) [![License](https://img.shields.io/github/license/trevorswan11/zlx)](LICENSE) [![Last commit](https://img.shields.io/github/last-commit/trevorswan11/zlx)](https://github.com/trevorswan11/zlx) [![Build](https://github.com/trevorswan11/zlx/actions/workflows/main.yml/badge.svg)](https://github.com/trevorswan11/zlx/actions/workflows/main.yml)

<p align="center">
  <img src="/resources/zlx-logo-v2.png" alt="zlx logo" width="250"/>
</p>

<p align="center">
  A lexer, parser, language, and interpreter written in Zig.
</p>

### Inspiration
The backbone of this project was built with help from [tylerlaceby's](https://www.youtube.com/@tylerlaceby) lexer playlist on YouTube. I created this project to learn Zig and to tackle something I had little to no knowledge about: parsing! His short, focused playlist can be found [here](https://www.youtube.com/playlist?list=PL_2VhOvlMk4XDeq2eOOSDQMrbZj9zIU_b) if you're interested.

While I originally intended to just build the parser, I ended up going much deeper and built an interpreter. Ultimately, this project gave me a great understanding of Zig's strengths and weaknesses and taught me more about memory management in this language and in general. It was also a lot of fun!

## Getting Started
1. Clone the repository using `git clone --recursive https://github.com/trevorswan11/zlx`
2. Install [Zig](https://ziglang.org/) and add it to your system's `PATH`, or place it somewhere accessible
    - You can also build Zig from source following the instructions [here](https://github.com/ziglang/zig), but this is much more involved 
3. Build the binary with `zig build`. I used Zig 0.14.0, but other versions may also work
    - The Zig language strives to be cross-platform, and all code written or used in this project is runnable on any platform
4. If you would like the plotting suite, then checkout the `plotting` library and repeat the build process. This branch has CI tests for all platforms, but I have only personally tested it on windows

## Building/Running the Program
- You can build the binary using `zig build` as mentioned above, but you can specify optimization targets if desired using these extra arguments
    - `--release=fast`: Prioritize performance without safety checks
    - `--release=small`: Prioritize small binary size over performance and safety
    - `--release=safe`: Balance between fast and small release modes. This is the default when passing `--release` on its own
- You can use the example language "tests" with `zig build run -- <run|dump|ast> examples/<filename> <time?> <-v?>`
    - `run` interprets the program, `dump` prints the syntax-highlighted file, and `ast` simply parses the program
    - `time` times the parser, interpreter, and program - this is an optional parameter
    - `-v` prints verbose output, showing an indented and formatted abstract syntax tree - also optional
- To interpret your own input file, pass the relative path as `zig build run -- run <path>`
- If you're pulling the executable from the `zig-out` directory, you can use the same arguments as explained above
    - The same applies for downloads from the `releases` tags
- You can run the projects tests, which mimic the code found in the `examples` folder, with `zig build test`

## External Libraries
This project has three independent dependencies:
1.  [zig-regex](https://github.com/tiehuis/zig-regex), a simple regex library for Zig. While the `README` of this library mentions it is a work in progress, it met this project's needs perfectly. That being said, I hope to be able to make this a zero-dependency project if and when the Zig team adds a Regex module to the standard library. 
2. [zig-containers](https://github.com/trevorswan11/zig-containers) which drives the standard libraries builtin data structures.
3. [raylib-zig](https://github.com/Not-Nik/raylib-zig) which drives the plotting module through basic window creation. This is only linked during the build process if building from the plotting branch

## Syntax Highlighting
While you can edit the source code for any zlx file in any editor, you can download the [zlx-syntax](https://marketplace.visualstudio.com/items?itemName=kyoshi11.zlx-syntax) extension through vscode to get syntax highlighting! This is a large WIP, but will hopefully grow to show doc strings and support intellisense eventually!

## Language Documentation
Documentation for the language, officially called `zlx`, will be written and polished over time. You can find the language reference in the `doc` folder. The "standard library" has a few built-in functions that work out of the box, and also has built-in modules that must be imported to use their defined functions and constants. While documentation is a WIP, you can view their source code in the `builtins` folder in the `src` directory.

## Naming Conventions
I’ve slightly altered some of the patterns used in tylerlaceby’s language, resulting in a syntax influenced by Go, Python, Rust, and more! All files should be named with file extension `.zlx`, but this is never enforced and never will be enforced by the interpreter. By convention, all declarations should use `snake_case`, but I really don't care — do what you want.

## Disclaimers
- Zig is in its _very_ early stages at the time of writing this project, so you should expect that behavior may break as the language matures
- This is a personal project, and will likely be put off to the side when I stop finding things to implement or get sick of writing documentation
    - If you find something glaringly wrong or would just like to contribute, feel free to open an issue or pull request!
- ChatGPT was used during some parts of the development process, specifically with writing the example language 'tests', writing some redundant code/tests for the builtin modules, creating the outline for the documentation html page, and debugging some stubborn bugs. ChatGPT was also used to make the logo found at the top of this file!
- ChatGPT was used in the generation of the builtin standard library types, but not in the creation of the underlying dependency. I created the template `list.zig` and provided ChatGPT with it and the source code in the module to avoid the mindless repetition of linking the data structures to the interpreter
- While ChatGPT was used in the creation of the documentation outline, it was only used to write the basic documentation for some builtin modules

## Acknowledgements
- Thank you to [tylerlaceby’s](https://www.youtube.com/@tylerlaceby) lexer playlist on YouTube, which was incredibly easy to understand and gave me a solid grasp of the building blocks needed to make a lexer and Pratt parser
- Thanks to this [article](https://matklad.github.io/2020/04/13/simple-but-powerful-pratt-parsing.html) by matklad, which helped me iron out some bugs and inconsistencies in operator precedence/binding powers
- If you are interested and unfamiliar with the Zig build process (which is really quite cool), I would recommend checking out this [video](https://youtu.be/jy7w_7JZYyw?si=7GtNPmn-OZtj9b7X)! [Zig SHOWTIME](https://www.youtube.com/@ZigSHOWTIME/featured) has been a great resource for me as I've learned the language!
