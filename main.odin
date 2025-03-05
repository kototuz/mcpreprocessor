package main

import "core:fmt"
import "core:os"
import "core:strings"
import lex "core:odin/tokenizer"

Token :: struct {
    kind: Token_Kind,
    data: string
}

Token_Kind :: enum {
    EOF,
    Ident,
    Command,
    Keyword_Fn,
    Keyword_End,
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

    // Skip spaces
    for strings.is_space(rune(data[cursor])) {
        cursor += 1
        if cursor >= len(data) { return nil }
    }

    token_len: uint = 1
    token := Token{data=data[cursor:]}
    switch (data[cursor]) {
    case '@':
        cursor += 1
        token.data = token.data[1:]
        for is_alpha(token.data[token_len]) {
            token_len += 1
        }
        token.data = token.data[:token_len]
        if strings.compare(token.data, "fn") == 0 {
            token.kind = .Keyword_Fn
        } else if strings.compare(token.data, "end") == 0 {
            token.kind = .Keyword_End
        } else {
            fmt.eprintf("ERROR: Unknown keyword '%v'\n", token.data)
            return nil
        }

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

is_alpha :: proc(b: byte) -> bool {
    switch (b) {
    case 'a'..='z', 'A'..='Z': return true
    case: return false
    }
}

skip_whitespace :: proc() -> bool {
    if cursor >= len(data) { return true }
    for strings.is_space(rune(data[cursor])) {
        cursor += 1
        if cursor >= len(data) { return true }
    }
    return false
}

expect_fn_keyword_or_eof :: proc() -> Maybe(Token_Kind) {
    if skip_whitespace() { return .EOF }
    if !expect_keyword("fn") { return nil }
    return .Keyword_Fn
}

expect_ident :: proc() -> (res: Maybe(string)) {
    if skip_whitespace() {
        fmt.println("ERROR: Identifier was expected but reached the file end")
        return nil
    }

    end: uint = cursor
    for !strings.is_space(rune(data[end])) {
        if !is_alpha(data[end]) {
            fmt.eprintln("ERROR: Identifier was expected")
            return nil
        }
        end += 1
    }

    res = data[cursor:end]
    cursor = end
    return res
}

expect_keyword :: proc(keyword: string) -> bool {
    if skip_whitespace() {
        fmt.eprintf("ERROR: Keyword '%v' was expected\n", keyword)
        return false
    }

    if data[cursor] != '@' {
        fmt.eprintf("ERROR: Keyword '%v' was expected\n", keyword)
        return false
    }

    cursor += 1
    end: uint = cursor
    for is_alpha(data[end]) { end += 1 }
    if strings.compare(data[cursor:end], keyword) != 0 {
        fmt.eprintf("ERROR: Keyword '%v' was expected\n", keyword)
        return false
    }

    cursor = end
    return true
}

expect_cmd_or_end :: proc() -> Maybe(Token) {
    if skip_whitespace() {
        fmt.eprintln("ERROR: Command or '@end' was expected")
        return nil
    }

    token: Token
    if data[cursor] == '@' {
        if !expect_keyword("end") { return nil }
        token.kind = .Keyword_End
    } else {
        end: uint = cursor
        for data[end] != '\n' && data[end] != 0x0 {
            end += 1
        }
        token.kind = .Command
        token.data = data[cursor:end]
        cursor = end
    }

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

SOURCE_FILE_PATH :: "example"
main :: proc() {
    //if len(os.args) != 2 {
    //    fmt.printf("usage: %v <source_file>\n", os.args[0])
    //    return
    //}

    if !lexer_init(SOURCE_FILE_PATH) { return }
    defer lexer_deinit()

    for {
        {
            tk, ok := expect_fn_keyword_or_eof().(Token_Kind)
            if !ok || tk == .EOF { return }
        }

        fn_name, ok := expect_ident().(string)
        if !ok { return }
        fmt.println("Function:", fn_name)

        for {
            token, ok := expect_cmd_or_end().(Token)
            if !ok { return }
            if token.kind == .Keyword_End { break }
            fmt.printf("Command: [%v]\n", token.data)
        }
    }

    //token, ok := lexer_next().(Token)
    //if !ok { return }
    //if token.kind != .Ident {
    //    fmt.eprintln("ERROR: Function name was expected")
    //    return
    //}
    //
    //for {
    //    fn_filename := strings.concatenate({token.data, ".mcfunction"})
    //    defer delete(fn_filename)
    //
    //    fn_file, err := os.open(fn_filename, os.O_WRONLY | os.O_CREATE, os.S_IRWXU)
    //    if err != nil {
    //        fmt.eprintf("ERROR: Could not open file '%v': %v\n", fn_filename, err)
    //        return
    //    }
    //    defer os.close(fn_file)
    //
    //    for {
    //        token, ok = lexer_next().(Token)
    //        if !ok { return }
    //        if token.kind != .Command { break }
    //        if !write_string(fn_file, token.data) { return }
    //        if !write_string(fn_file, "\n") { return }
    //    }
    //}
}
