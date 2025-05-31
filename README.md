# zlx
A lexical analyzer/parser written in zig.

## Inspiration
This project was made with the help of [tylerlaceby](https://www.youtube.com/@tylerlaceby)'s lexer playlist on YouTube. It was created with the intent to further learn Zig, and to tackle something that I had little to no knowledge about, parsing! His full, short playlist can be found [here](https://www.youtube.com/playlist?list=PL_2VhOvlMk4XDeq2eOOSDQMrbZj9zIU_b) if you are interested!

### Getting Started
1. Clone the repository using `git clone --recursive https://github.com/trevorswan11/zlx`
2. Install [Zig](https://ziglang.org/) and include it in your systems path or somewhere else useable by your system
3. Build the binary with `zig build`. I used Zig 0.14.0, but other versions may work as well

### Running the Program
- You can use the example language 'tests' using `zig build run -- examples/<filename>`
- You can parse your own input file by passing in the relative path as `zig build run -- <path>`
- You can also run some tests that I wrote by using `zig build test`
