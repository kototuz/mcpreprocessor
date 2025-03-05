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
