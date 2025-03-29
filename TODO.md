- [X] Simple tokenizer
    - [X] Load file from command line
    - [X] Implement `next_token` that returns next one character
    - [X] Implement `next_token` that returns next word

- [X] Function parsing
    - [X] Token `command`
    - [X] Implement parsing for this syntax:
        ```
        <fn_name>
            <command>
            <command>
            ...

        <fn_name>
            <command>
            <command>
            ...
        ```

- [X] Better function declarations
    ```
    @fn <fn_name>
        <command>
        <command>
        ...
    @end
    ```

- [X] Macro
    - [X] New keyword `@macro`
    - [X] Macro table map[macro-name]macro-text
    - [X] Macro call syntax `#<macro-name>`

- [X] New syntax
    - [X] Function declarations
        ```
        @<function-name> {
        }
        ```
    - [X] Macro declarations
        ```
        #def <macro-name>
        #end
        ```

- [X] Nested function declarations

- [X] Check for function redefinitions

- [X] Lambda functions
    ```
    @main {
        function test:\
        #lambda {
            say Hello, world
        };
    }
    ```

- [X] Remove usage of ';'

- [X] Better macro expansion. Processing statements in the macro body
    HOW TO:
        Source stack. The macro expansion is just a push to a source stack.
        When the tokenizer meets `EOF` it pops source from the stack

- [X] Redesign the syntax
    ```
    def macro_a
        /say Hello, world
    end

    # main function
    fn main {
        @macro_a
        /say Ok
        /function test:\
        lambda {
            /say Something...
        } /with entity @s
    }
    ```

- [X] Macro declarations inside blocks

- [ ] Parametric macro

- [ ] Undef macro
