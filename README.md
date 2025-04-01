# mcpreprocessor

Like C preprocessor :)

## The main goal

The main goal is to make minecraft pack development easier by
automating some repeating processes (e.g. function creating)

## Demo

This code will be compiled into `.mcfunction` files

```
fn main {
    "say hello world"
    "say Good morning"
}

fn foo {
    "summon pig"
    "summon zombie"
}

fn baz {
    "summon pig"
    "summon zombie"
}
```

See more features in `example.mcp`

> [!NOTE]
> The program doesn't check whether valid your code.
> It works just like macro

## Build

Just go to to the `src` directory and write `odin build .` or `odin run .`
