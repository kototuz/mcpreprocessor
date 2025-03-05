package main

import "core:fmt"
import "core:os"
import "core:strings"

expect_token_kind :: proc(tok: Token, k: Token_Kind) -> bool {
    if tok.kind != k {
        default_error_handler(tok.pos, "'%v' was expected, but found '%v'", to_string(k), to_string(tok.kind))
        return false
    }

    return true
}

write_string :: proc(f: os.Handle, str: string) -> bool {
    _, err := os.write_string(f, str)
    if err != nil {
        fmt.eprintf("ERROR: Could not write string to file: %v\n", err)
        return false
    }
    return true
}

main :: proc() {
    output_path := "."

    if len(os.args) == 3 {
        output_path = os.args[2]
    } else if len(os.args) < 2 {
        fmt.eprintf("usage: %v <source_file> [<output_path>]\n", os.args[0])
        os.exit(1)
    }

    bytes, err := os.read_entire_file_or_err(os.args[1])
    if err != nil {
        fmt.eprintf("ERROR: Could not load file '%v': %v\n", os.args[1], err)
        os.exit(1)
    }

    file_src := strings.clone_from_bytes(bytes)
    delete(bytes)

    tokenizer: Tokenizer
    init(&tokenizer, file_src, "test")

    filename := strings.builder_make()
    defer strings.builder_destroy(&filename)
    for {
        token := scan(&tokenizer)
        if token.kind == .EOF { break }

        if !expect_token_kind(token, .Fn) { os.exit(1) }
        token = scan(&tokenizer)
        if !expect_token_kind(token, .Ident) { os.exit(1) }

        // Build output file path
        strings.builder_reset(&filename)
        strings.write_string(&filename, output_path)
        strings.write_byte(&filename, '/')
        strings.write_string(&filename, token.text)
        strings.write_string(&filename, ".mcfunction")

        // Create .mcfunction file
        fn_file, err := os.open(strings.to_string(filename), os.O_CREATE | os.O_WRONLY, os.S_IRUSR | os.S_IWUSR)
        if err != nil {
            fmt.eprintf("ERROR: Could not create file '%v': %v\n", strings.to_string(filename), err)
            os.exit(1)
        }
        defer os.close(fn_file)

        for {
            token = scan(&tokenizer, true)
            if token.kind == .Command {
                if !write_string(fn_file, token.text) { os.exit(1) }
                if !write_string(fn_file, "\n") { os.exit(1) }
            } else {
                if !expect_token_kind(token, .End) { os.exit(1) }
                break
            }
        }
    }
}
