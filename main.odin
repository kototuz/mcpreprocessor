package main

import "core:fmt"
import "core:os"
import "core:strings"

Token :: struct {
    kind: Token_Kind,
    data: string
}

Token_Kind :: enum {
    Ident,
    Command,
}

data:   string
cursor: uint = 0

lexer_init :: proc(filename: string) -> bool {
    bytes, err := os.read_entire_file_from_filename_or_err(filename)
    if err != nil {
        fmt.printf("ERROR: Could not load file '%v': %v\n", filename, err)
        return false
    }
    defer delete(bytes)

    data = strings.clone_from(bytes)

    return true
}

lexer_deinit :: proc() {
    delete(data)
}

lexer_next :: proc() -> Maybe(Token) {
    if cursor >= len(data) { return nil }

    for strings.is_space(rune(data[cursor])) {
        cursor += 1
        if cursor >= len(data) { return nil }
    }

    is_alpha :: proc(b: byte) -> bool {
        switch (b) {
        case 'a'..='z', 'A'..='Z': return true
        case: return false
        }
    }

    token_len: uint = 1
    token := Token{data=data[cursor:]}
    switch (data[cursor]) {
    case 'a'..='z', 'A'..='Z':
        token.kind = .Ident
        for is_alpha(token.data[token_len]) {
            token_len += 1
        }

    case '/':
        cursor += 1
        token.data = token.data[1:]
        token.kind = .Command
        for token.data[token_len] != '\n' && token.data[token_len] != 0x0 {
            token_len += 1
        }

    case:
        fmt.eprintln("ERROR: Invalid token")
        return nil
    }

    token.data = token.data[:token_len]
    cursor += token_len

    return token
}

write_string :: proc(f: os.Handle, str: string) -> bool {
    len, err := os.write_string(f, str)
    if err != nil {
        fmt.eprintf("ERROR: Could not write string to file: %v\n", err)
        return false
    }

    return true
}

main :: proc() {
    if len(os.args) != 2 {
        fmt.printf("Usage: %v <source_file>\n", os.args[0])
        return
    }

    if !lexer_init(os.args[1]) { return }
    defer lexer_deinit()

    token, ok := lexer_next().(Token)
    if !ok { return }
    if token.kind != .Ident {
        fmt.eprintln("ERROR: Function name was expected")
        return
    }

    for {
        fn_filename := strings.concatenate({token.data, ".mcfunction"})
        defer delete(fn_filename)

        fn_file, err := os.open(fn_filename, os.O_WRONLY | os.O_CREATE, os.S_IRWXU)
        if err != nil {
            fmt.eprintf("ERROR: Could not open file '%v': %v\n", fn_filename, err)
            return
        }
        defer os.close(fn_file)

        for {
            token, ok = lexer_next().(Token)
            if !ok { return }
            if token.kind != .Command { break }
            if !write_string(fn_file, token.data) { return }
            if !write_string(fn_file, "\n") { return }
        }
    }
}
