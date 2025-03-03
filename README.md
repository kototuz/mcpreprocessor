# mcpreprocessor

## The main goal

The main goal is to make minecraft pack development easier by
automating some repeating processes (e.g. function creating)

## Current state

This is a basic snippet of what you can do right now:
This code will be processed into `.mcfunction` files

```
main
    /say hello world
    /say Good morning

foo
    /summon pig
    /summon zombie

baz
    /summon pig
    /summon zombie
```

## Build

Go to the project directory and run:

``` console
odin build .
```

or

``` console
odin run .
```
