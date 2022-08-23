## Contributing Guideline

🎉 First off, thanks for taking the time to contribute! 🎉

This project adheres to the Contributor Covenant code of conduct. By participating, you are expected to respect it.

If you are interested in contributing to the code you should begin by reading the [Plugin Development Guide.](https://docs.konghq.com/gateway/2.8.x/plugin-development/). It will make you familiar with the structure of a plugin, and introduce you to [`pongo`](https://github.com/Kong/kong-pongo), the plugin development environment for Kong.

Below you can find some guidelines to help you contribute.

### Where to report bugs?

Feel free to submit an issue on the GitHub repository, we would be grateful to hear about it! Please make sure that you include:

1. A summary of the issue
2. A list of steps to help reproduce the issue
3. The version of Kong that you encountered the issue with
4. Your Plugin configuration, or the parts that are relevant to your issue
5. If you wish, you are more than welcome to open a PR to fix the issue! See the open a PR section for more information on how to best do so.

### Where to submit improvement suggestions?

You can submit an issue for improvement suggestions. Try adding all the details that seem relevant to you.

You are also welcome to open a PR that implements your suggestions. 

### Open a Pull Request

Feel free to contribute fixes or minor features, we are happy to receive Pull
Requests!

When contributing, please follow the guidelines provided in this document. They
will cover topics such as the different Git branches we use, the commit history and commit messages.

Once you have read them, and you feel that you are ready to submit your Pull Request, be sure
to verify a few things:

- Your commit message is clear. I.E. no branches named update, fix, docs.
- Rebase your work on top of the base branch (seek help online on how to use
  `git rebase`. This is important to ensure your commit history is clean and
   linear)
- Branch was named using the guideline below.

If the above guidelines are respected, your Pull Request has all its chances
to be considered and will be reviewed by a maintainer.

If you are asked to update your patch by a reviewer, please do so! Remember:
**you are responsible for pushing your patch forward**. If you contributed it,
you are probably the one in need of it. You must be ready to apply changes
to it if necessary.

If your Pull Request was accepted and fixes a bug, adds functionality, or improves documentation, congratulations!
You are now an official contributor!

#### Git branches

Please follow the following naming scheme when creating a branch:

- `feat/foo-bar` for new features
- `fix/foo-bar` for bug fixes
- `tests/foo-bar` when the change concerns only the test suite
- `refactor/foo-bar` when refactoring code without any behavior change
- `style/foo-bar` when addressing some style issue
- `docs/foo-bar` for updates to the README.md, this file, or similar documents
  
If you don't have write access to the repository, feel free to fork.

<br>

Partially inspired by [official Kong Contribution Guide](https://github.com/Kong/kong/edit/master/CONTRIBUTING.md)