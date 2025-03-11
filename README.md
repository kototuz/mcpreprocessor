# mcpreprocessor

Like C preprocessor :)

## The main goal

The main goal is to make minecraft pack development easier by
automating some repeating processes (e.g. function creating)

## Demo

This code will be compiled into `.mcfunction` files

```
@fn main
    say hello world
    say Good morning
@end

@fn foo
    summon pig
    summon zombie
@end

@fn baz
    summon pig
    summon zombie
@end
```

> [!NOTE]
> The program doesn't check whether valid your code.
> It works just like macro

## Build

Just go to to the `src` directory and write `odin build .` or `odin run .`
