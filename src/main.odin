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

Tokenizer_State :: struct {
    src:         string,
    ch:          rune,
    offset:      int,
    line_count:  int,
    read_offset: int,
    line_offset: int,
    insert_semicolon: bool,
}

EXTENSION     :: ".mcfunction"

output_path:     string
path_builder:    strings.Builder
macro:           map[string]Tokenizer_State // map[<macro-name>]<macro_body>
scopes:          [dynamic]Scope
tok_state_stack: [dynamic]Tokenizer_State

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

    // Append the block local scope
    append_nothing(&scopes)
    defer pop(&scopes)

    // Process block content
    // TODO: Macro declaration in blocks
    token := scan(t, true)
    loop: for {
        #partial switch token.kind {
        case .Command:
            write_string(fn_file, token.text) or_return
            write_string(fn_file, "\n") or_return

        // Function declaration
        case .At:
            process_fn(t) or_return
            resize(&path_builder.buf, curr_path_len)

        case .Lambda:
            scope := &scopes[len(scopes) - 1]
            path_append(scope.lambda_count)
            scope.lambda_count += 1
            lambda_call_name := path_builder.buf[len(output_path)+1 : len(path_builder.buf) - len(EXTENSION)]
            write_string(fn_file, string(lambda_call_name)) or_return
            write_string(fn_file, " ") or_return
            process_block(t) or_return
            curr_line := t.line_count
            token = scan(t, true)
            if token.kind != .Command || token.pos.line > curr_line { write_string(fn_file, "\n") or_return }
            resize(&path_builder.buf, curr_path_len)
            continue loop

        // Macro
        case .Mod:
            expand_macro(t) or_return

        case .EOF:
            if len(tok_state_stack) == 0 {
                error(t, t.offset, "Unclosed block")
                return false
            }
            set_state(t, pop(&tok_state_stack))

        case:
            expect_token_kind(token, .Close_Brace) or_return
            break loop
        }

        token = scan(t, true)
    }

    return true
}

expand_macro :: proc(t: ^Tokenizer) -> bool {
    token := scan(t)
    expect_token_kind(token, .Ident) or_return
    tok_state, ok := macro[token.text]
    if !ok {
        default_error_handler(token.pos, "macro '%v' is not defined", token.text)
        return false
    }

    append(&tok_state_stack, get_state(t^))
    set_state(t, tok_state)

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

scan_until_end :: proc(t: ^Tokenizer) -> (string, bool) {
    offset := t.offset

    for {
        if t.ch == -1 {
            error(t, t.offset, "'#end' was expected, but found 'EOF'")
            return "", false
        }

        if t.ch == '#' {
            offset_end := t.offset - 1
            advance_rune(t)
            lit := scan_identifier(t)
            if lit == "end" {
                return t.src[offset:offset_end], true
            }
        } else {
            advance_rune(t)
        }
    }
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

    // Get the tokenizer state in macro definition.
    // It is used to implement recursive macro expansion
    tok_state := get_state(t^)

    // Skip until newline to get the macro body start line
    for t.ch != '\n' { advance_rune(t) }

    // Scan the macro body
    macro_body := scan_until_end(t) or_return
    tok_state.src = macro_body

    tok_state.offset = 0
    tok_state.read_offset = 0
    tok_state.line_count -= 1
    tok_state.line_offset = 0

    macro[macro_name] = tok_state

    return true
}

get_state :: proc(t: Tokenizer) -> Tokenizer_State {
    return {
        ch = t.ch,
        offset = t.offset,
        read_offset = t.read_offset,
        line_offset = t.line_offset,
        line_count = t.line_count,
        insert_semicolon = t.insert_semicolon,
        src = t.src
    }
}

print_macro_stacktrace_and_exit :: proc() -> ! {
    for i := len(tok_state_stack)-1; i >= 0; i -= 1 {
        tok_state := tok_state_stack[i]
        column := tok_state.offset - tok_state.line_offset + 1
        fmt.eprintf("    expansion of macro in (%v:%v)\n", tok_state.line_count, column)
    }

    os.exit(1)
}

set_state :: proc(t: ^Tokenizer, s: Tokenizer_State) {
    t.ch = s.ch
    t.offset = s.offset
    t.read_offset = s.read_offset
    t.line_offset = s.line_offset
    t.insert_semicolon = s.insert_semicolon
    t.line_count = s.line_count
    t.src = s.src
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

    macro = make(map[string]Tokenizer_State)
    defer delete(macro)

    tok_state_stack = make([dynamic]Tokenizer_State)
    defer delete(tok_state_stack)

    scopes = make([dynamic]Scope)
    defer {
        for i in 0..<cap(scopes) {
            #no_bounds_check { delete(scopes[i].names) }
        }
        delete(scopes)
    }
    
    // Append global scope
    append_nothing(&scopes)

    loop: for {
        token := scan(&tokenizer)
        #partial switch token.kind {
        case .At:
            if !process_fn(&tokenizer) { print_macro_stacktrace_and_exit() }
            resize(&path_builder.buf, len(output_path))

        case .Def:
            if !process_macro(&tokenizer) { print_macro_stacktrace_and_exit() }

        case .Mod:
            if !expand_macro(&tokenizer) { print_macro_stacktrace_and_exit() }

        case .EOF:
            if len(tok_state_stack) == 0 { break loop }
            set_state(&tokenizer, pop(&tok_state_stack))

        case:
            default_error_handler(token.pos, "unexpected token '%v'", token.text)
            print_macro_stacktrace_and_exit()
        }
    }
}
