package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:slice"
import path "core:path/filepath"

Function_Name :: string
Scope :: struct {
    names:        [dynamic]Function_Name,
    lambda_count: uint
}

EXTENSION     :: ".mcfunction"

output_path:  string
path_builder: strings.Builder
macro:        map[string]string // map[<macro-name>]<macro_body>
scopes:       [dynamic]Scope

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

path_append_uint :: proc(v: uint) {
    if strings.builder_len(path_builder) > len(output_path) {
        strings.write_byte(&path_builder, '.')
        strings.write_uint(&path_builder, v)
        strings.write_string(&path_builder, EXTENSION)
    } else {
        strings.write_byte(&path_builder, path.SEPARATOR)
        strings.write_uint(&path_builder, v)
        strings.write_string(&path_builder, EXTENSION)
    }
}

path_append_str :: proc(str: string) {
    if strings.builder_len(path_builder) > len(output_path) {
        strings.write_byte(&path_builder, '.')
        strings.write_string(&path_builder, str)
        strings.write_string(&path_builder, EXTENSION)
    } else {
        strings.write_byte(&path_builder, path.SEPARATOR)
        strings.write_string(&path_builder, str)
        strings.write_string(&path_builder, EXTENSION)
    }
}

path_append :: proc{
    path_append_uint,
    path_append_str,
}

process_block :: proc(t: ^Tokenizer) -> bool {
    expect_token_kind(scan(t), .Open_Brace) or_return

    // Create .mcfunction file
    fn_file, err := os.open(strings.to_string(path_builder), os.O_CREATE | os.O_WRONLY, os.S_IRUSR | os.S_IWUSR)
    if err != nil {
        fmt.eprintf("ERROR: Could not create file '%v': %v\n", strings.to_string(path_builder), err)
        return false
    }
    defer os.close(fn_file)

    resize(&path_builder.buf, len(path_builder.buf) - len(EXTENSION))
    curr_path_len := len(path_builder.buf)

    // Append the function local scope
    append_nothing(&scopes)
    defer pop(&scopes)

    // Process block content
    loop: for {
        token := scan(t, true)
        #partial switch token.kind {
        case .Command:
            write_string(fn_file, token.text) or_return
            write_string(fn_file, "\n") or_return

        case .At:
            process_fn(t) or_return
            resize(&path_builder.buf, curr_path_len)

        case .Semicolon:
            write_string(fn_file, "\n") or_return

        case .Lambda:
            scope := &scopes[len(scopes) - 1]
            path_append(scope.lambda_count)
            scope.lambda_count += 1
            lambda_call_name := path_builder.buf[len(output_path)+1 : len(path_builder.buf) - len(EXTENSION)]
            write_string(fn_file, string(lambda_call_name)) or_return
            write_string(fn_file, " ") or_return
            process_block(t) or_return
            resize(&path_builder.buf, curr_path_len)

        case .Mod:
            token = scan(t)
            expect_token_kind(token, .Ident) or_return
            if !(token.text in macro) {
                default_error_handler(token.pos, "macro '%v' is not defined", token.text)
                return false
            }
            write_string(fn_file, macro[token.text]) or_return
            write_string(fn_file, "\n") or_return

        case:
            expect_token_kind(token, .Close_Brace) or_return
            break loop
        }
    }

    return true
}

process_fn :: proc(t: ^Tokenizer) -> bool {
    // Get name
    token := scan(t)
    expect_token_kind(token, .Ident) or_return

    // Check for function redefinition
    scope := &scopes[len(scopes)-1]
    if slice.contains(scope.names[:], token.text) {
        default_error_handler(token.pos, "redefinition of function '%v'", token.text)
        return false
    }

    // Append the function name to the scope
    append(&scope.names, token.text)

    path_append(token.text)
    process_block(t) or_return

    return true
}

process_macro :: proc(t: ^Tokenizer) -> bool {
    // Get macro name
    token := scan(t)
    expect_token_kind(token, .Ident) or_return
    macro_name := token.text

    // Check if macro already exists
    if macro_name in macro {
        default_error_handler(token.pos, "redefinition of macro '%v'", macro_name)
        return false
    }

    token = scan(t, true)
    if token.kind == .EOF {
        default_error_handler(token.pos, "unexpected EOF")
        return false
    }

    // Handle the case when the macro is empty
    if token.kind == .End {
        macro[macro_name] = ""
        return true
    }

    // Recognize the macro body
    macro_body_begin := t.offset - len(token.text)
    macro_body_end := t.offset
    for {
        token = scan(t, true)

        if token.kind == .EOF {
            default_error_handler(token.pos, "unexpected EOF")
            return false
        }

        if token.kind == .End {
            macro[macro_name] = t.src[macro_body_begin:macro_body_end]
            return true
        }

        macro_body_end = t.offset
    }
}

main :: proc() {
    if len(os.args) == 3 {
        output_path = path.clean(os.args[2])
    } else if len(os.args) < 2 {
        fmt.eprintf("usage: %v <source_file> [<output_path>]\n", os.args[0])
        os.exit(1)
    }

    // Load source file bytes
    bytes, err := os.read_entire_file_or_err(os.args[1])
    if err != nil {
        fmt.eprintf("ERROR: Could not load file '%v': %v\n", os.args[1], err)
        os.exit(1)
    }

    // Convert source file bytes -> string
    file_src := strings.clone_from_bytes(bytes)
    delete(bytes)

    tokenizer: Tokenizer
    init(&tokenizer, file_src, os.args[1])

    path_builder = strings.builder_make()
    defer strings.builder_destroy(&path_builder)
    strings.write_string(&path_builder, output_path)

    macro = make(map[string]string)
    defer delete(macro)

    scopes = make([dynamic]Scope)
    defer {
        for i in 0..<cap(scopes) {
            #no_bounds_check { delete(scopes[i].names) }
        }
        delete(scopes)
    }
    
    // Append global scope
    append_nothing(&scopes)

    for {
        token := scan(&tokenizer)
        if token.kind == .EOF { break }

        #partial switch token.kind {
        case .At:
            if !process_fn(&tokenizer) { os.exit(1) }
            resize(&path_builder.buf, len(output_path))

        case .Def:
            if !process_macro(&tokenizer) { os.exit(1) }

        case:
            default_error_handler(token.pos, "unexpected token '%v'", token.text)
            os.exit(1)
        }
    }
}
