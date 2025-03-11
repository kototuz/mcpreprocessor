package main

import "core:fmt"
import "core:os"
import "core:strings"

output_path:  string
path_builder: strings.Builder
macro:        map[string]string // map[<macro-name>]<macro_body>
fn_file_name: strings.Builder

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

// TODO: Check for redefinition of a function
process_fn :: proc(t: ^Tokenizer, parent_fn_name: string = "") -> bool {
    // Get name
    token := scan(t)
    expect_token_kind(token, .Ident) or_return
    expect_token_kind(scan(t), .Open_Brace) or_return

    { // Build .mcfunction file path
        strings.builder_reset(&path_builder)
        strings.write_string(&path_builder, output_path)
        strings.write_byte(&path_builder, '/')

        if len(parent_fn_name) > 0 {
            strings.write_string(&path_builder, parent_fn_name)
            strings.write_byte(&path_builder, '.')
            strings.write_byte(&fn_file_name, '.')
            strings.write_string(&fn_file_name, token.text)
        } else {
            strings.builder_reset(&fn_file_name)
            strings.write_string(&fn_file_name, token.text)
        }

        strings.write_string(&path_builder, token.text)
        strings.write_string(&path_builder, ".mcfunction")
    }

    // Create .mcfunction file
    fn_file, err := os.open(strings.to_string(path_builder), os.O_CREATE | os.O_WRONLY, os.S_IRUSR | os.S_IWUSR)
    if err != nil {
        fmt.eprintf("ERROR: Could not create file '%v': %v\n", strings.to_string(path_builder), err)
        return false
    }
    defer os.close(fn_file)

    // Process function body
    loop: for {
        token = scan(t, true)
        #partial switch token.kind {
        case .Command:
            write_string(fn_file, token.text) or_return
            write_string(fn_file, "\n") or_return

        case .At:
            curr_file_name_len := len(fn_file_name.buf)
            process_fn(t, strings.to_string(fn_file_name)) or_return
            resize(&fn_file_name.buf, curr_file_name_len)

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
        output_path = os.args[2]
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
    init(&tokenizer, file_src, "test")

    path_builder = strings.builder_make()
    defer strings.builder_destroy(&path_builder)

    fn_file_name = strings.builder_make()
    defer strings.builder_destroy(&fn_file_name)

    macro = make(map[string]string)
    defer delete(macro)

    for {
        token := scan(&tokenizer)
        if token.kind == .EOF { break }

        #partial switch token.kind {
        case .At:  if !process_fn(&tokenizer) { os.exit(1) }
        case .Def: if !process_macro(&tokenizer) { os.exit(1) }
        case:
            default_error_handler(token.pos, "uexpected token '%v'", token.text)
            os.exit(1)
        }
    }
}

// TODO: Support for comments
// TODO: Macro body processing
