# CONTRIBUTING.md

## Welcome
Thank you for your interest in contributing to KGSM! This project aims to simplify game server management on GNU/Linux systems with a lightweight and extensible design. Contributions are welcome, whether you're fixing a bug, adding a feature, or improving documentation.

## How to Contribute
1. **Fork** the repository and clone it to your local machine.
2. Create a new branch for your changes: `git checkout -b feature-or-fix-name`.
3. Make your changes following the [coding standards](#coding-standards).
4. Commit your changes: `git commit -m "Brief description of your changes"`.
5. Push to your fork: `git push origin feature-or-fix-name`.
6. Open a pull request with a description of your changes.

## Key Areas for Contribution

### Game Server Blueprints
The most valuable contribution is adding support for new game servers:
- **Native Blueprints**: Add `.bp` files for games with native Linux server support
- **Container Blueprints**: With KGSM 2.0, you can contribute `docker-compose.yml` files for containerized game servers
- Use the existing blueprints in the `blueprints/default` directory as templates
- Follow the guidelines in `docs/blueprints.md`

### Game Server Overrides
For games that need custom install/update/version logic, contribute module-based overrides:
- Create a directory `overrides/{blueprint_name}/` containing numbered module files (e.g., `05-version.sh`, `06-download.sh`, `07-deploy.sh`)
- Each override module is a copy of the corresponding default module in `templates/manage.native.d/` with only the necessary functions modified
- Only modules 03–11 may be overridden
- All functions from the default module must be preserved in the override
- See `docs/overrides.md` for full details and real-world examples

### System Compatibility
- Test KGSM on different Linux distributions and report compatibility
- Add support for alternative system components:
  - Process management systems (alternatives to systemd)
  - Firewall configurations (alternatives to ufw)
  - Enhanced event data and monitoring capabilities

### Testing and Bug Reports
- Test KGSM on your Linux distribution and report any compatibility issues
- Report bugs using the issue templates on GitHub
- Verify fixes and new features work across different environments

### Documentation
- Improve guides, tutorials, and examples
- Translate documentation to other languages
- Add diagrams or screenshots to clarify complex concepts

## Using GitHub Issue Templates
The project includes several issue templates for different types of contributions:
- Bug Report
- Feature Request
- New Game Server
- Documentation Improvement

Please use these templates when creating new issues as they help provide the necessary information.

## Coding Standards
KGSM uses an `.editorconfig` file to maintain consistent coding styles across different editors. Please ensure your editor respects the following settings:
- Indent style: Spaces
- Indent size: 2
- End of line: LF
- Charset: UTF-8
- Trim trailing whitespace: True
- Insert final newline: True

For shell scripts, follow these additional guidelines:
- Bash is the primary shell variant.
- Adhere to constructs supported by `shellcheck` where possible.

## Reporting Issues and Requesting Features
When submitting an issue, please include:
- The KGSM version you’re using.
- Your operating system and versions of Bash and systemd (if applicable).
- Steps to reproduce the issue.

For suggesting new game server support, use the **New Game Server** issue template, ensuring:
- The server has native Linux support.
- Relevant details like Steam App ID or official download links are provided.

## Testing Contributions
KGSM now has a testing framework in the `tests/` directory. Contributors are encouraged to:
- Add tests for new features or bug fixes
- Run the existing test suite before submitting PRs: `./tests/run.sh`
- Manually verify their changes with various configurations
- Test on multiple Linux distributions if possible

## Community and Communication
If you have questions or need help, feel free to:
- Open a discussion or issue on GitHub.
- Join the project’s community (add a link if applicable).

## License
By contributing to KGSM, you agree that your contributions will be licensed under the GNU General Public License v3.0 (GPL-3).

