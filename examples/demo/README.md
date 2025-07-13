# Demo Project

This is a simple demo project to test WorkOn functionality.

## Testing WorkOn

From this directory, run:

```bash
../../bin/workon
```

This should open:
- VS Code editor
- This README file
- A terminal
- AwesomeWM documentation
- Example website
- Notes file in nvim

## Environment Variables

You can set `DEMO_URL` to override the default web resource:

```bash
export DEMO_URL="https://github.com"
../../bin/workon
```