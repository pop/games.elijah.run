# games.elijah.run

A little blog I use for documenting gamedev.

## Building

Once you clone the repository, you can use the `Makefile` to build the site -- if that's your thing.

```
$ make build
$ make serve
```

The first command runs [Zola][zola] in a [podman][podman] container.
You can also follow Zola's [install instructions][zola-install] to install another way and run `zola build` or `zola serve` respectively.

[zola]: https://www.getzola.org
[podman]: https://podman.io/
[zola-install]: https://www.getzola.org/documentation/getting-started/installation/

## Release

A Github Action runs automatically when we merge to `main` which builds and publishes the website.
It may take a few minutes after the deploy workflow is done for the changes to be visible.

## License

This work is licensed under CC BY 4.0.
