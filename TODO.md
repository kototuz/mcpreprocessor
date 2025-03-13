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

- [ ] Expand macro in macro
