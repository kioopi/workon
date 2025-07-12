What i'm really trying to achieve here is the ability to have a simple file in the root
directory of a project that defines the files and applications I
need to work on that project.

And one ore more layouts that define how those resources should be arranged.

For example:

```yaml
resources:
  ide: code .
  terminal: alacrity .
  readme: README.md
  notes: nvim notes.md

  # URLs to open in browser
  web: "{{ NEXT_PUBLIC_SERVER_URL }}"
  admin: "{{ NEXT_PUBLIC_SERVER_URL }}/admin"
  process: overmind Procfile

layouts:
  desktop:
    - [ide]
    - [web, admin]
    - [terminal, readme, notes, process]

  mobile:
    - [ide]
    - [web]
    - [notes, process]

default_layout: default
```

If then run some executable, lets say `workon`, in the root directory of the project, or with the path to the project as an argument, it will read the `workon.yaml` file and

turn the resoures to parameters for pls-open and open clients in awesomewm on tags.
The layouts define wich resources go on which tag.

there is a program called awesome-client that might help

awesome-client 'require("awful.spawn").spawn("pls-open nvim $PROJECT_ROOT_DIR/notes.md", { tag = "3" })'

Do you understand the idea? Please think about this and let me know if you have any questions or suggestions. I would like to lean on reusing existing tools as much as possible and combine them rather than a big implementation.

What to you think? What have i missed? Are the problems i have not considered?
