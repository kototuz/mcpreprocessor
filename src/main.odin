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

Macro :: struct {
    tok_state: Tokenizer_State,
    params:    [dynamic]Macro_Param,
}

Macro_Param :: struct {
    name:  string,
    value: Tokenizer_State,
}

EXTENSION     :: ".mcfunction"

output_path:     string
path_builder:    strings.Builder
macro:           map[string]Macro
macro_params_stack: [dynamic][]Macro_Param
scopes:          [dynamic]Scope
tok_state_stack: [dynamic]Tokenizer_State

expect_token_kind :: proc(tok: Token, k: Token_Kind) -> bool {
    if tok.kind != k {
        default_error_handler(tok.pos, "'%v' was expected, but found '%v'", to_string(k), to_string(tok.kind))
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

find_param_by_name :: proc(params: []Macro_Param, name: string) -> (Tokenizer_State, bool) {
    for p in params {
        if p.name == name {
            return p.value, true
        }
    }
    return {}, false
}

// NOTE: Writes `newline` only if there is no something on the current line
write_newline :: proc(t: ^Tokenizer, f: os.Handle) {
    state := get_state(t^)
    defer set_state(t, state)
    curr_line := t.line_count

    token := scan(t)

    #partial switch token.kind {
    case .String:
    case .Lambda:
    case .Ident:
    case .Dollar:

    case .EOF: return

    case:
        fmt.fprintln(f)
        return
    }

    if token.pos.line != curr_line {
        fmt.fprintln(f)
    }
}

process_block :: proc(t: ^Tokenizer) -> bool {
    expect_token_kind(scan(t), .Open_Brace) or_return

    // Create .mcfunction file
    fn_file, err := os.open(strings.to_string(path_builder), os.O_CREATE | os.O_WRONLY | os.O_TRUNC, os.S_IRUSR | os.S_IWUSR)
    if err != nil {
        fmt.eprintf("ERROR: Could not create file '%v': %v\n", strings.to_string(path_builder), os.error_string(err))
        return false
    }
    defer os.close(fn_file)

    resize(&path_builder.buf, len(path_builder.buf) - len(EXTENSION))
    curr_path_len := len(path_builder.buf)

    // Append the block local scope
    append_nothing(&scopes)
    defer pop(&scopes)

    // Process block content
    loop: for {
        token := scan(t)
        #partial switch token.kind {
        case .String:
            // Write string consider double quotes
            for i := 1; i < len(token.text) - 1; {
                if token.text[i] == '\\' {
                    fmt.fprint(fn_file, rune(token.text[i+1]))
                    i += 2
                } else {
                    fmt.fprint(fn_file, rune(token.text[i]))
                    i += 1
                }
            }
            write_newline(t, fn_file)

        // Function declaration
        case .Fn:
            process_fn(t) or_return
            resize(&path_builder.buf, curr_path_len)

        case .Def:
            process_macro(t) or_return

        case .Undef:
            token = scan(t)
            expect_token_kind(token, .Ident) or_return
            m, ok := macro[token.text]
            if !ok {
                default_error_handler(token.pos, "macro '%v' is not defined", token.text)
                return false
            }
            delete(m.params)
            delete_key(&macro, token.text)

        // Macro parameter
        case .Dollar:
            if len(macro_params_stack) == 0 {
                default_error_handler(token.pos, "trying to get parameter outside of macro")
                return false
            }
            token = scan(t)
            expect_token_kind(token, .Ident) or_return
            m_params := macro_params_stack[len(macro_params_stack)-1]
            param_value, found := find_param_by_name(m_params[:], token.text)
            if !found {
                default_error_handler(token.pos, "parameter '%v' is not declared", token.text)
                return false
            }
            append(&tok_state_stack, get_state(t^))
            set_state(t, param_value)
            append(&macro_params_stack, []Macro_Param{})

        case .Lambda:
            scope := &scopes[len(scopes) - 1]
            path_append(scope.lambda_count)
            scope.lambda_count += 1
            lambda_call_name := path_builder.buf[len(output_path)+1 : len(path_builder.buf) - len(EXTENSION)]
            fmt.fprintf(fn_file, "%v ", string(lambda_call_name))
            process_block(t) or_return
            resize(&path_builder.buf, curr_path_len)
            write_newline(t, fn_file)

        // Macro
        case .Ident:
            expand_macro(t, token.text, token.pos) or_return

        case .EOF:
            if len(tok_state_stack) == 0 {
                error(t, t.offset, "Unclosed block")
                return false
            }
            set_state(t, pop(&tok_state_stack))
            write_newline(t, fn_file)
            pop(&macro_params_stack)

        case .Close_Brace:
            break loop

        case:
            default_error_handler(token.pos, "unexpected token '%v'", token.text)
            return false
        }
    }

    return true
}

scan_arg :: proc(t: ^Tokenizer) -> (state: Tokenizer_State, last: bool, ok: bool = true) {
    state = get_state(t^)
    token := scan(t)
    depth := 0
    for {
        #partial switch token.kind {
        case .Comma:
            if depth > 0 { break }
            last = false
            state.src = state.src[:token.pos.offset]
            return

        case .Open_Paren:
            depth += 1 

        case .Close_Paren:
            if depth > 0 { depth -= 1; break }
            last = true
            state.src = state.src[:token.pos.offset]
            return

        case .EOF:
            ok = false
            default_error_handler(token.pos, "unexpected end of file")
            return
        }

        token = scan(t)
    }
}

expand_macro :: proc(t: ^Tokenizer, macro_name: string, pos: Pos) -> bool {
    m, ok := &macro[macro_name]
    if !ok {
        default_error_handler(pos, "macro '%v' is not defined", macro_name)
        return false
    }

    token: Token
    if len(m.params) > 0 {
        if scan(t).kind != .Open_Paren {
            default_error_handler(token.pos, "macro '%v' is parametric, so you need to specify arguments", macro_name)
            return false
        }

        arg_count := 0
        for {
            arg_tok_state, is_last := scan_arg(t) or_return
            m.params[arg_count].value = arg_tok_state
            arg_count += 1
            if is_last { break }
        }

        if arg_count != len(m.params) {
            default_error_handler(token.pos, "expected %v arguments but found only %v", len(m.params), arg_count)
            return false
        }
    }

    append(&tok_state_stack, get_state(t^))
    set_state(t, m.tok_state)
    append(&macro_params_stack, m.params[:])

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

scan_until_end :: proc(t: ^Tokenizer) -> (state: Tokenizer_State, ok: bool) {
    state = get_state(t^)
    token := scan(t)
    for {
        if token.kind == .EOF {
            default_error_handler(token.pos, "unexpected end of file")
            ok = false
            return
        }

        if token.kind == .End {
            ok = true
            state.src = state.src[:token.pos.offset]
            return
        }

        token = scan(t)
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

    m := Macro{}

    // Save state to check macro parameters
    m.tok_state = get_state(t^)

    // Process macro parameter names if they are specified
    token = scan(t)
    if token.kind == .Open_Paren {
        loop: for {
            token = scan(t)
            if token.kind != .Ident {
                default_error_handler(token.pos, "parameter was expected but found '%v'", token.text)
                return false
            }

            append(&m.params, Macro_Param{name=token.text})

            token = scan(t)
            #partial switch token.kind {
            case .Comma:
            case .Close_Paren: break loop
            case:
                default_error_handler(token.pos, "unexpected token '%v'", token.text)
                return false
            }
        }
    } else {
        set_state(t, m.tok_state)
    }

    // Save the tokenizer state when it on the macro body source
    m.tok_state = scan_until_end(t) or_return

    macro[macro_name] = m

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
        fmt.eprintf("ERROR: Could not load file '%v': %v\n", os.args[1], os.error_string(err))
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

    macro = make(map[string]Macro)
    defer {
        for _, v in macro {
            delete(v.params)
        }
        delete(macro)
    }

    macro_params_stack = make([dynamic][]Macro_Param)
    defer delete(macro_params_stack)

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

    // TODO: Maybe we need to implement macro parameters and `macro undef`
    //       in the global scope, but i don't see the usage of this yet 
    loop: for {
        token := scan(&tokenizer)
        #partial switch token.kind {
        case .Fn:
            if !process_fn(&tokenizer) { print_macro_stacktrace_and_exit() }
            resize(&path_builder.buf, len(output_path))

        case .Def:
            if !process_macro(&tokenizer) { print_macro_stacktrace_and_exit() }

        case .Ident:
            if !expand_macro(&tokenizer, token.text, token.pos) { print_macro_stacktrace_and_exit() }

        case .EOF:
            if len(tok_state_stack) == 0 { break loop }
            set_state(&tokenizer, pop(&tok_state_stack))
            pop(&macro_params_stack)

        case:
            default_error_handler(token.pos, "unexpected token '%v'", token.text)
            print_macro_stacktrace_and_exit()
        }
    }
}
